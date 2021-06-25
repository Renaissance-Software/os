const x86_64 = @import("intrinsics.zig");
const inb = x86_64.inb;
const outb = x86_64.outb;
const io_wait = x86_64.io_wait;

const PIT = @This();


const base_frequency = 1193182;
const max_divisor = 65535;
const default_divisor = max_divisor;
const port = 0x40;
var divisor: u64 = 0;

pub fn init() void
{
    set_divisor(default_divisor);
}

pub fn set_divisor(new_divisor: u64) void
{
    divisor = new_divisor;

    if (divisor > max_divisor)
    {
        divisor = max_divisor;
    }

    outb(port, @truncate(u8, divisor & 0xff));
    io_wait();
    outb(port, @truncate(u8, (divisor & 0xff00) >> 8));
}
