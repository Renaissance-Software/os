const std = @import("std");

pub const selector = .
{
    .selnull = @as(u16, 0x00),
    .code64 = @as(u16, 0x08),
    .data64 = @as(u16, 0x10),
    .usercode64 = @as(u16, 0x18 | 3),
    .userdata64 = @as(u16, 0x20 | 3),
    .tss = @as(u16, 0x28),
};

pub const GDT = extern struct
{
    kernel_null: Entry,
    kernel_code: Entry,
    kernel_data: Entry,
    user_null: Entry,
    user_code: Entry,
    user_data: Entry,

    pub const Descriptor = packed struct
    {
        size: u16,
        offset: u64,
    };

    pub const Entry = packed struct
    {
        limit0: u16,
        base0: u16,
        base1: u8,
        access_byte: u8,
        limit1_flags: u8,
        base2: u8,
    };

    export var descriptor: GDT.Descriptor = undefined;

    pub fn init() void
    {
        descriptor.size = @sizeOf(GDT) - 1;
        descriptor.offset = @ptrToInt(&GDT.default);
        load_gdt(&GDT.descriptor);
    }

    const default = GDT
    {
        .kernel_null = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0,
            .limit1_flags = 0,
            .base2 = 0,
        },
        .kernel_code = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0x9a,
            .limit1_flags = 0xa0,
            .base2 = 0,
        },
        .kernel_data = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0x92,
            .limit1_flags = 0xa0,
            .base2 = 0,
        },
        .user_null = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0,
            .limit1_flags = 0,
            .base2 = 0,
        },
        .user_code = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0x9a,
            .limit1_flags = 0xa0,
            .base2 = 0,
        },
        .user_data = Entry
        {
            .limit0 = 0,
            .base0 = 0,
            .base1 = 0,
            .access_byte = 0x92,
            .limit1_flags = 0xa0,
            .base2 = 0,
        },
    };
};

extern fn load_gdt(descriptor: *const GDT.Descriptor) void;

comptime 
{
    if (@sizeOf(GDT) != 8 * 6)
    {
        @compileError("GDT size is not correct");
    }
    if (@sizeOf(GDT.Descriptor) != 10)
    {
        @compileError("GDT size is not correct");
    }
}
