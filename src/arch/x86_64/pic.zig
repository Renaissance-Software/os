const PIC = @This();
const x86_64 = @import("intrinsics.zig");
const outb = x86_64.outb;
const io_wait = x86_64.io_wait;
const inb = x86_64.inb;

const Data = struct
{
    command: u8,
    data: u8,
};

const PIC1 = Data { .command = 0x20, .data = 0x21 };
const PIC2 = Data { .command = 0xa0, .data = 0xa1 };
const EOI = 0x20;
const ICW1_init = 0x10;
const ICW1_ICW4 = 0x01;
const ICW4_8086 = 0x01;
const chipset_address_register = 0x22;
const chipset_data_register = 0x23;
const IMCR_register_address = 0x70;
const IMCR_8259_direct = 0x00;
const IMCR_VIA_APIC = 0x01;

pub fn disable() void
{
    outb(chipset_address_register, IMCR_register_address);
    io_wait();
    outb(chipset_data_register, IMCR_VIA_APIC);
    io_wait();
    outb(PIC1.data, 0xff);
    io_wait();
    outb(PIC2.data, 0xff);
}

pub fn remap() void
{
    var a1: u8 = undefined;
    var a2: u8 = undefined;

    a1 = inb(PIC1.data);
    io_wait();
    a2 = inb(PIC2.data);
    io_wait();

    outb(PIC1.command, ICW1_init |ICW1_ICW4);
    io_wait();
    outb(PIC2.command, ICW1_init |ICW1_ICW4);
    io_wait();

    outb(PIC1.data, 0x20);
    io_wait();
    outb(PIC2.data, 0x28);
    io_wait();

    outb(PIC1.data, 4);
    io_wait();
    outb(PIC2.data, 2);
    io_wait();

    outb(PIC1.data, ICW4_8086);
    io_wait();
    outb(PIC2.data, ICW4_8086);
    io_wait();

    outb(PIC1.data, a1);
    io_wait();
    outb(PIC2.data, a2);
}

fn mask() void
{
    outb(PIC.PIC1.data, 0b11111101);
    outb(PIC.PIC2.data, 0b11111111);
}
