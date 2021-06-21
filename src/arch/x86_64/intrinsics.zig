pub fn halt_loop() noreturn
{
    while (true)
    {
        asm volatile("hlt");
    }
}

pub fn hlt() callconv(.Naked) void
{
    asm volatile("hlt");
}

pub fn in(comptime T: type, port: u16) T
{
    return switch (T)
    {
        u8 => inb(port),
        else => @compileError("No in instruction for this type"),
    };
}

pub fn out(comptime T: type, port: u16, value: T) void
{
    switch (T)
    {
        u8 => outb(port, value),
        else => @compileError("No in instruction for this type"),
    }
}

pub fn inb(port: u16) u8
{
    return asm volatile("inb %[port], %[result]\n"
        : [result] "={al}" (->u8)
        : [port] "N{dx}" (port));
}

pub fn outb(port: u16, value: u8) void
{
    asm volatile("outb %[value], %[port]\n"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port));
}

pub fn io_wait() void
{
    outb(0x80, undefined);
}
