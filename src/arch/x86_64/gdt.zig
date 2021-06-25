const std = @import("std");
const print = @import("../../renderer.zig").print;
const range = @import("../../range.zig").range;

pub const GDT = extern struct
{
    pub const PtrType = * align(0x1000)GDT;

    descriptor: GDT.Descriptor,
    gdt_entries: [GDT.Entry.count]GDT.Entry,

    pub var gdt align(0x1000) = std.mem.zeroes(GDT);
    pub var tss_entries align(0x1000) = std.mem.zeroes([TSS.Entry.count]TSS.Entry);

    pub const SelectorIndex = enum(u8)
    {
        kernel_null = 0,
        kernel_code = 1,
        kernel_data = 2,
        user_null = 3,
        user_data = 4,
        user_code = 5,
        tss = 6,
    };

    pub const selector: [GDT.Entry.count - 1]u16 = blk:
    {
        var sel: [GDT.Entry.count - 1]u16 = undefined;
        var offset: u16 = 0;
        for (sel) |*writer|
        {
            writer.* = offset;
            offset += @sizeOf(GDT.Entry);
        }
        break :blk sel;
    };

    pub const Descriptor = extern struct
    {
        size: u16,
        offset: u64,
    };

    pub const Entry = extern struct
    {
        limit0: u16,
        base0: u16,
        base1: u8,
        access_byte: u8,
        limit1_flags: u8,
        base2: u8,

        pub const count = 8;

        fn set(self: *Entry, access: u8, flags: u8) void
        {
            self.limit0 = 0xffff; 
            self.access_byte = @enumToInt(GDT.Access.type) | @enumToInt(GDT.Access.present) | access;
            self.limit1_flags = @enumToInt(GDT.Flags.long_mode) | @enumToInt(GDT.Flags.page_granularity) | flags;
            print("Access: 0x{x}. Limit: 0x{x}\n", .{self.access_byte, self.limit1_flags});
        }
    };

    pub fn init(self: PtrType) void
    {
        const gdt_total_size = @sizeOf(GDT.Entry) * GDT.Entry.count;

        self.gdt_entries[@enumToInt(SelectorIndex.kernel_code)].set(@enumToInt(GDT.Access.executable), 0);
        self.gdt_entries[@enumToInt(SelectorIndex.kernel_data)].set(@enumToInt(GDT.Access.writable), 0);
        self.gdt_entries[@enumToInt(SelectorIndex.user_data)].set(@enumToInt(GDT.Access.dpl) | @enumToInt(GDT.Access.writable), 0);
        self.gdt_entries[@enumToInt(SelectorIndex.user_code)].set(@enumToInt(GDT.Access.dpl) | @enumToInt(GDT.Access.executable), 0);

        self.set_tss_descriptor(@enumToInt(SelectorIndex.tss));

        self.descriptor.size = gdt_total_size - 1;
        self.descriptor.offset = @ptrToInt(&self.gdt_entries[0]);
    }

    pub extern fn load_gdt(descriptor: *GDT.Descriptor, tss_offset: u16) void;

    fn set_tss_descriptor(self: PtrType, gdt_index: u64) void
    {
        var tss_index: u64 = 0;
        var tss_entry = &GDT.tss_entries[tss_index];
        tss_entry.* = std.mem.zeroInit(TSS.Entry, .{
            .io_map_base = 0xffff,
        });

        const tss_entry_addr = @ptrToInt(tss_entry);
        print("TSS entry address: 0x{x}\n", .{tss_entry_addr});
        const offset = @ptrToInt(&self.gdt_entries[gdt_index]) - @ptrToInt(&self.gdt_entries[0]);
        print("Offset: {}\n", .{offset});
        var tss_descriptor = @ptrCast(* align(1) TSS.Descriptor, &self.gdt_entries[gdt_index]);
        tss_descriptor.* = TSS.Descriptor
        {
            .segment_limit = @sizeOf(TSS.Entry) - 1,
            .base_low = @truncate(u16, tss_entry_addr),
            .base_mid = @truncate(u8, tss_entry_addr >> 16),
            .base_mid2 = @truncate(u8, tss_entry_addr >> 24),
            .base_high = @truncate(u32, tss_entry_addr >> 32),
            .access = 0b10000000 | 0b00001001,
            .flags = 0b00010000,
            .reserved = 0,
        };
    }

    pub fn set_tss_entry_ist(self: PtrType, ist_index: u64, stack: u64) void
    {
        const tss_index = 0;
        var tss_entry = &GDT.tss_entries[tss_index];
        const zero_base_ist_index = ist_index - 1;
        tss_entry.ist[zero_base_ist_index][0] = @truncate(u32, stack);
        tss_entry.ist[zero_base_ist_index][1] = @truncate(u32, stack >> 32);
    }
    
    pub fn set_tss_ring(self: PtrType, ring_index: u64, stack: u64) void
    {
        const tss_index = 0;
        var tss_entry = &self.tss_entries[tss_index];
        const stack_truncated = @truncate(u32, stack);
        const stack_truncated_shr = @truncate(u32, stack >> 32);
        print("Index: {}\n", .{ring_index});
        tss_entry.ist[(ring_index - 1) * 2 + 0] = stack_truncated;
        tss_entry.ist[(ring_index - 1) * 2 + 1] = stack_truncated_shr;
    }

    const Access = enum(u8)
    {
        writable = 0b00000010,
        executable = 0b00001000,
        type = 0b00010000,
        dpl = 0b01100000,
        present = 0b10000000,
    };

    const Flags = enum(u8)
    {
        long_mode = 0b00100000,
        page_granularity = 0b10000000,
    };
};

pub const TSS = extern struct
{
    pub const Entry = extern struct
    {
        reserved0: u32,
        rsp: [3][2]u32,
        reserved1: [2]u32,
        ist: [7][2]u32,
        reserved2: [2]u32,
        reserved3: u16,
        io_map_base: u16,

        pub const count = 1;
    };

    pub const Descriptor = extern struct
    {
        segment_limit: u16,
        base_low: u16,
        base_mid: u8,
        access: u8,
        flags: u8,
        base_mid2: u8,
        base_high: u32,
        reserved: u32,
    };

    comptime
    {
        if (@sizeOf(Descriptor) != 16)
        {
            @compileError("GDT descriptor size is wrong");
        }
    }
};
