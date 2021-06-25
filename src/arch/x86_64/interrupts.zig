const std = @import("std");
const gdt = @import("gdt.zig");
const GDT = gdt.GDT;
const Paging = @import("paging.zig");
const print = @import("../../renderer.zig").print;
const kpanic = @import("../../panic.zig").kpanic;
const range = @import("../../range.zig").range;
const ports = @import("intrinsics.zig");
const inb = ports.inb;
const outb = ports.outb;
const io_wait = ports.io_wait;
const PIT = @import("pit.zig");
const APIC = @import("apic.zig");
const IOAPIC = APIC.IOAPIC;
const IDT = @import("idt.zig").IDT;
const ISR = @import("isr.zig");
const PIC = @import("pic.zig");


pub fn setup() void
{
    //var i: u64 = 0;
    //inline for (range(IDT.Entry.count)) |interrupt_index|
    //{
        //raw_callbacks[interrupt_index] = make_handler(interrupt_index);
        //add_handler(interrupt_index, ISR.unhandled_interrupt, true, 0, 0);
    //}

    //add_handler(8, ISR.double_fault_handler, true, 0, 0);
    //add_handler(13, ISR.general_protection_fault_handler, true, 0, 0);
    //add_handler(14, ISR.page_fault_handler, true, 3, 1);

    PIT.init();
    print("PIT initialized successfully\n", .{});

    PIC.disable();
    print("PIC disabled successfully\n", .{});

    IOAPIC.init();
    print("IOAPIC initialized successfully\n", .{});

    IOAPIC.set_from_isrs();
    print("IOAPIC set from ISRs successfully\n", .{});
}
