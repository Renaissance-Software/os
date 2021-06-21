const std = @import("std");
const print = @import("renderer.zig").print;
const kpanic = @import("panic.zig").kpanic;

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

const SDT = struct
{
    const Header = extern struct
    {
        base: Base,
        revision: u8,
        checksum: u8,
        OEM_id: [6]u8,
        OEM_table_ID: [8]u8,
        OEM_revision: u32,
        creator_ID: u32,
        creator_revision: u32,

        const Base = extern struct
        {
            signature: [4]u8,
            length: u32,
        };

        fn find_table(self: *Header, signature: []const u8) ?*SDT.Header
        {
            const entry_count = (self.base.length - @sizeOf(Header)) / 8;
            const array_base = @intToPtr([*] align(1) *SDT.Header, @ptrToInt(self) + @sizeOf(Header));
            const entries = array_base[0..entry_count];
            for (entries) |entry|
            {
                if (std.mem.eql(u8, entry.base.signature[0..], signature))
                {
                    return entry;
                }
            }

            return null;
        }

        comptime
        {
            const sizeofbase = 8;
            if (@sizeOf(Base) != sizeofbase)
            {
                @compileError("Size of SDT header base is wrong");
            }
            const sizeofheader = 8 + 2 + 6 + 8 + 4 + 4 + 4;
            if (@sizeOf(Header) != sizeofheader)
            {
                @compileError("Size of SDT header is wrong");
            }
        }
    };
};

const MCFG = struct
{
    const Header = packed struct
    {
        sdt_header: SDT.Header,
        reserved: [8]u8,
    };
};

const MADT = struct
{
    const Header = packed struct
    {
        sdt_header: SDT.Header,
        LAPIC_address: u32,
        flags: u32,
    };
};

var rsdp2: *RSDP.Descriptor2 = undefined;
var xsdt: *SDT.Header = undefined;
var mcfg: *MCFG.Header = undefined;
var madt: *MADT.Header = undefined;

pub fn setup(rsdp_base_address: u64) void
{
    rsdp2 = @intToPtr(*RSDP.Descriptor2, rsdp_base_address);
    xsdt = @intToPtr(*SDT.Header, rsdp2.XSDT_address);
    print("XSDT address: {}\n", .{xsdt});
    mcfg = blk:
    {
        if (xsdt.find_table("MCFG")) |header|
        {
            break :blk @ptrCast(*MCFG.Header, header);
        }
        else
        {
            kpanic("MCFG header not found\n", .{});
        }
    };
    madt = blk:
    {
        if (xsdt.find_table("APIC")) |header|
        {
            break :blk @ptrCast(*MADT.Header, header);
        }
        else
        {
            kpanic("MADT header not found\n", .{});
        }
    };
    print("ACPI setup correctly\n", .{});
}
