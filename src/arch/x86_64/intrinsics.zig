pub fn hlt() noreturn
{
    while (true)
    {
        asm volatile("hlt");
    }
}
