OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

SECTIONS
{
    _virtual_base = 0xffffffff80000000;
    . = _virtual_base + 2M;
    _kernel_virtual_start = .;
    _kernel_physical_start = . - _virtual_base;

	.text ALIGN(0x1000) : AT(ADDR(.text) - _virtual_base)
	{
		*(.text)
	}
	.data ALIGN(0x1000) : AT(ADDR(.data) - _virtual_base)
	{
		*(.data)
	}
	.rodata ALIGN(0x1000): AT(ADDR(.rodata) - _virtual_base)
	{
		*(.rodata)
	}
    .bss ALIGN(0x1000): AT(ADDR(.bss) - _virtual_base)
    {
        *(COMMON)
        *(.bss)
    }
    .got ALIGN(0x1000): AT(ADDR(.got) - _virtual_base)
    {
        *(.got)
    }
    _kernel_virtual_end = .;
    _kernel_physical_end = . - _virtual_base;
}
