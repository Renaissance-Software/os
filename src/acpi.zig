const std = @import("std");
const print = @import("renderer.zig").print;
const kpanic = @import("panic.zig").kpanic;
const APIC = @import("arch/x86_64/apic.zig");
const MADT = APIC.MADT;
const LAPIC = APIC.LAPIC;
const Paging = @import("arch/x86_64/paging.zig");

const RSDP = struct
{
    const Descriptor = packed struct
    {
        signature: [8]u8,
        checksum: u8,
        OEM_id: [6]u8,
        revision: u8,
        RSDT_address: u32,
    };

    const Descriptor2 = packed struct
    {
        descriptor1: Descriptor,
        length: u32,
        XSDT_address: u64,
        extended_checksum: u8,
        reserved: [3]u8,
    };
};

pub const SDT = struct
{
    pub const Header = extern struct
    {
        signature: [4]u8,
        length: u32,
        revision: u8,
        checksum: u8,
        OEM_id: [6]u8,
        OEM_table_ID: [8]u8,
        OEM_revision: u32,
        creator_ID: u32,
        creator_revision: u32,

        fn find_table(self: *Header, signature: []const u8) ?*SDT.Header
        {
            const entry_count = (self.length - @sizeOf(Header)) / 8;
            const array_base = @intToPtr([*] align(1) *SDT.Header, @ptrToInt(self) + @sizeOf(Header));
            const entries = array_base[0..entry_count];
            for (entries) |entry|
            {
                if (std.mem.eql(u8, entry.signature[0..], signature))
                {
                    return entry;
                }
            }

            return null;
        }

        comptime
        {
            const sizeofheader = 8 + 2 + 6 + 8 + 4 + 4 + 4;
            if (@sizeOf(Header) != sizeofheader)
            {
                @compileError("Size of SDT header is wrong");
            }
        }
    };
};

pub var rsdp2: *RSDP.Descriptor2 = undefined;
pub var xsdt_header: *SDT.Header = undefined;
pub var mcfg_header: *SDT.Header = undefined;
pub var madt_header: *SDT.Header = undefined;

pub fn setup(rsdp_base_address: u64) void
{
    rsdp2 = @intToPtr(*RSDP.Descriptor2, rsdp_base_address);
    xsdt_header = @intToPtr(*SDT.Header, rsdp2.XSDT_address);
    mcfg_header = blk:
    {
        if (xsdt_header.find_table("MCFG")) |header|
        {
            break :blk header;
        }
        else
        {
            kpanic("MCFG header not found\n", .{});
        }
    };
    madt_header = blk:
    {
        if (xsdt_header.find_table("APIC")) |header|
        {
            break :blk header;
        }
        else
        {
            kpanic("MADT header not found\n", .{});
        }
    };

    APIC.IOAPIC.io_apic_enable();
    MADT.init();
    LAPIC.init();
}
