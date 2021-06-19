pub fn halt_loop() noreturn
{
    while (true)
    {
        asm volatile("hlt");
    }
}

pub fn hlt() void
{
    asm volatile("hlt");
}
