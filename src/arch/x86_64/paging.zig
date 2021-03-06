const std = @import("std");
const uefi = @import("../../uefi.zig");
const root = @import("root");
const kpanic = @import("../../panic.zig").kpanic;
const APIC = @import("apic.zig");

pub var memory_size: u64 = 0;
pub const page_size = 0x1000;


const PageMapIndexer = extern struct
{
    PDP_i: u64,
    PD_i: u64,
    PT_i: u64,
    P_i: u64,
};

const PDE = struct
{
    const Bit = enum(u6)
    {
        present = 0,
        read_write = 1,
        user_super = 2,
        write_through = 3,
        cache_disabled = 4,
        accessed = 5,
        larger_pages = 7,
        custom0 = 9,
        custom1 = 10,
        custom2 = 11,
        nx = 63,
    };

    fn mask(pde: u64, bit: PDE.Bit, enabled: bool) u64
    {
        const bitmask: u64 = @intCast(u64, 1) << @enumToInt(bit);
        var result = (pde & ~bitmask);
        if (enabled)
        {
            result |= bitmask;
        }
        return result;
    }

    fn get_bit(pde: u64, pde_bit: PDE.Bit) bool
    {
        const bitmask: u64 = @intCast(u64, 1) << @enumToInt(pde_bit);
        return (pde & bitmask) > 0;
    }

    fn get_address(pde: u64) u64
    {
        return (pde & 0x000ffffffffff000) >> 12;
    }

    fn compute_address(pde: u64, address: u64) u64
    {
        const masked_address = address & 0x000000ffffffffff;

        return (pde & 0xfff0000000000fff) | (masked_address << 12);
    }

    const Type = u64;
};

pub const PageTable = extern struct 
{
    entries: [512]u64,
};

fn prepare_page_table(entry_index: u64, previous_page_table: * align (0x1000) PageTable) * align(0x1000) PageTable
{
    var pde = previous_page_table.entries[entry_index];
    const page_table: * align(0x1000) PageTable = blk:
    {
        if (!PDE.get_bit(pde, .present))
        {
            if (request_zero_page()) |page|
            {
                pde = PDE.compute_address(pde, @ptrToInt(page) >> 12);
                pde = PDE.mask(pde, .present, true);
                pde = PDE.mask(pde, .read_write, true);
                previous_page_table.entries[entry_index] = pde;
                break :blk @ptrCast(* align(0x1000) PageTable, page);
            }
            else
            {
                kpanic("Unable to get page for index {}\n", .{entry_index});
            }
        }
        else
        {
            const address = PDE.get_address(pde) << 12;
            break :blk @intToPtr(* align(0x1000) PageTable, address);
        }
    };

    return page_table;
}

pub var pml4: * align(0x1000) PageTable = undefined;

pub fn map(virtual: u64, physical: u64) void
{
    const pmi: PageMapIndexer = blk:
    {
        var va = virtual >> 12;
        const p_i = va & 0x1ff;
        va >>= 9;
        const pt_i = va & 0x1ff;
        va >>= 9;
        const pd_i = va & 0x1ff;
        va >>= 9;
        const pdp_i = va & 0x1ff;

        break :blk PageMapIndexer
        {
            .PDP_i = pdp_i,
            .PD_i = pd_i,
            .PT_i = pt_i,
            .P_i = p_i,
        };
    };

    const pdp = prepare_page_table(pmi.PDP_i, pml4);
    const pd = prepare_page_table(pmi.PD_i, pdp);
    const pt = prepare_page_table(pmi.PT_i, pd);

    var pde = pt.entries[pmi.P_i];
    pde = PDE.compute_address(pde, physical >> 12);
    pde = PDE.mask(pde, .present, true);
    pde = PDE.mask(pde, .read_write, true);
    pt.entries[pmi.P_i] = pde;
}

var bitmap: []u8 = undefined;
pub var free_memory: u64 = 0;
pub var used_memory: u64 = 0;

pub fn init(boot_data: *uefi.BootData) void
{
    const map_entry_count = boot_data.memory.size / boot_data.memory.descriptor_size;

    const memory_map = boot_data.memory.map[0..map_entry_count];
    var number_of_pages: u64 = 0;

    for (memory_map) |map_entry|
    {
        number_of_pages += map_entry.number_of_pages;
    }

    memory_size = number_of_pages * page_size;

    var largest_free_memory_block: u64 = 0;
    var largest_free_memory_block_size: u64 = 0;

    for (memory_map) |map_entry|
    {
        if (map_entry.type == .ConventionalMemory)
        {
            if (map_entry.number_of_pages * page_size > largest_free_memory_block_size)
            {
                largest_free_memory_block = map_entry.physical_start;
                largest_free_memory_block_size = map_entry.number_of_pages * page_size;
            }
        }
    }

    bitmap = @intToPtr([*]u8, largest_free_memory_block)[0.. memory_size / page_size / 8 + 1];
    free_memory = memory_size;
    used_memory = 0;
    std.mem.set(u8, bitmap, 0);
    reserve_pages(largest_free_memory_block, bitmap.len / page_size + 1);

    for (memory_map) |map_entry|
    {
        if (map_entry.type != .ConventionalMemory)
        {
            reserve_pages(map_entry.physical_start, map_entry.number_of_pages);
        }
    }

    const kernel_start = boot_data.kernel_virtual_start;
    const kernel_end = boot_data.kernel_virtual_end;
    const kernel_size = kernel_end - kernel_start;
    const kernel_page_count = kernel_size / page_size + 1;
    reserve_pages(kernel_start, kernel_page_count);

    var kernel_virtual: u64 = kernel_start;
    var kernel_physical: u64 = boot_data.kernel_content;
    while (kernel_virtual < kernel_end) : ({kernel_virtual += page_size; kernel_physical += page_size; })
    {
        map(kernel_virtual, kernel_physical);
    }

    reserve_pages(APIC.LAPIC.trampoline_target, 1);

    asm volatile("mov %[in], %%cr3" : : [in] "r" (@ptrToInt(pml4)));
}

pub fn request_pages(page_count: u64) ?Result
{
    const top = bitmap.len * 8;
    var index: u64 = 0;

    outer_loop:
        while (index < top) : (index += 1)
    {
        var page_index: u64 = 0;
        while (page_index < page_count) : (page_index += 1)
        {
            if (is_page_reserved(index + page_index))
            {
                continue :outer_loop;
            }
        }

        const page = index * page_size;
        reserve_pages(page, page_count);

        return Result
        {
            .ptr = @intToPtr([*] align(0x1000) u8, page),
            .len = page_size * page_count,
        };
    }

    return null;
}

pub fn request_page() ?[*] align(0x1000) u8
{
    const top = bitmap.len * 8;
    var index: u64 = 0;

    while (index < top) : (index += 1)
    {
        if (is_page_reserved(index))
        {
            continue;
        }

        const page_address = index * 4096;
        reserve_page(page_address);
        var page = @intToPtr([*] align(0x1000) u8, page_address);
        return page;
    }

    return null;
}

pub fn request_zero_page() ?[*] align(0x1000) u8
{
    if (request_page()) |page|
    {
        std.mem.set(u8, page[0..page_size], 0);
        return page;
    }

    return null;
}

fn is_page_reserved(index: u64) bool
{
    if (index >= bitmap.len * 8)
    {
        return false;
    }

    const byte_index = index / 8;
    const bit_index = @intCast(u3, index % 8);
    const bit_indexer = @intCast(u8, 0b10000000) >> bit_index;

    return bitmap[byte_index] & bit_indexer > 0;
}

const SetPageReservedResult = enum(u8)
{
    OutOfBounds,
    Reserved,
    NonReserved,
};

fn set_page_reserved(index: u64, value: bool) SetPageReservedResult
{
    if (index >= bitmap.len * 8)
    {
        // @TODO: fix with anothe mapping algorithm
        //kpanic("Index out of bounds. Index: {}. Bytemap (*8): {}\n", .{index, self.bitmap.len * 8});
        return .OutOfBounds;
    }

    const byte_index = index / 8;
    const bit_index: u3 = @intCast(u3, index % 8);
    const bit_indexer = @intCast(u8, 0b10000000) >> bit_index;
    bitmap[byte_index] &= ~bit_indexer;

    if (value)
    {
        bitmap[byte_index] |= bit_indexer;
        return .Reserved;
    }

    return .NonReserved;
}

pub fn reserve_pages(address: u64, page_count: u64) void
{
    const top_address = address + (page_count * page_size);
    var page_address: u64 = address;
    while (page_address < top_address) : (page_address += page_size)
    {
        reserve_page(page_address);
    }
}

fn free_pages(address: u64, page_count: u64) void
{
    const top_address = address + (page_count * page_size);
    var page_address: u64 = address;
    while (page_address < top_address) : (page_address += page_size)
    {
        free_page(page_address);
    }
}

fn reserve_page(address: u64) void
{
    const page_index = address / page_size;
    if (!is_page_reserved(page_index))
    {
        switch (set_page_reserved(page_index, true))
        {
            .Reserved =>
            {
                free_memory -= page_size;
                used_memory += page_size;
            },
            else => {}
        }
    }
}

fn free_page(address: u64) void
{
    const page_index = address / page_size;
    if (!is_page_reserved(index))
    {
        return;
    }

    if (set_page_reserved(index, false) == .Unreserved)
    {
        free_memory += page_size;
        used_memory -= page_size;
    }
}

pub const Result = struct
{
    ptr: [*] align(0x1000) u8,
    len: u64,
};

pub fn round_up_page_size(n: u64) u64
{
    if (n % page_size == 0)
    {
        return n;
    }
    else
    {
        return n - (n % page_size) + page_size;
    }
}

pub fn nearest_page(n: u64) u64
{
    const result = round_up_page_size(n) / page_size;
    return result;
}
