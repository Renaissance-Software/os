pub const magic = [2]u8{0x36, 0x04};

pub const Header = extern struct
{
    magic: [2]u8 = [2]u8{},
    mode: u8,
    char_size: u8,
};

pub const Buffer = extern struct
{
    ptr: [*]u8,
    size: u64,
};

pub const Font = extern struct
{
    header: *Header,
    buffer: *Buffer,
};
