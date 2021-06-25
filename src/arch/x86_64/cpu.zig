const std = @import("std");
const CPU = @This();
const GDT = @import("gdt.zig").GDT;
const idt_module = @import("idt.zig");
const IDT = idt_module.IDT;
const Paging = @import("paging.zig");
const kpanic = @import("../../panic.zig").kpanic;
const print = @import("../../renderer.zig").print;

const Context = extern struct
{
    LAPIC_id: u8,
    reserved: [3]u8,
    kernel_stack: u64,
    user_stack: u64,
    gdt: GDT.PtrType,
    idt: IDT.PtrType,
    stack_isr: u64,
    stack_irq: u64,
    stack_timer_begin: u64,
    stack_timer: u64,
};

const TimerStackTop = extern struct
{
    context: u64,
    kernel_pml4: u64,
    padding: u64,
    reserved: u64,
};

var bsp = CPU.Context
{
    .LAPIC_id = 0,
    .reserved = [_]u8{0} ** 3,
    .kernel_stack = 0,
    .user_stack = 0,
    .gdt = undefined,
    .idt = undefined,
    .stack_irq = 0,
    .stack_isr = 0,
    .stack_timer = 0,
    .stack_timer_begin = 0,
};

const stack_isr_page_count = 1;
const stack_irq_page_count = 2;
const stack_timer_page_count = 2;

extern fn cpuid_get_LAPIC_id() u32;
extern fn cpu_set_gs_fs_base_MSRs(context: *CPU.Context) void;

fn allocate_stack(page_count: u64, clear: bool) u64
{
    if (Paging.request_pages(page_count)) |stack_page_result|
    {
        if (clear)
        {
            std.mem.set(u8, stack_page_result.ptr[0..stack_page_result.len], 0);
        }

        return @ptrToInt(stack_page_result.ptr) + stack_page_result.len;
    }
    else
    {
        kpanic("Pages for stack IRQ failed\n", .{});
    }
}

fn allocate(cpu: *CPU.Context) void
{
    var gdt_block = &GDT.gdt;
    var idt_block = &IDT.table;
    const gdt_block_address = @ptrToInt(gdt_block);
    const idt_block_address = @ptrToInt(idt_block);
    cpu.gdt = gdt_block;
    cpu.idt = idt_block;

    cpu.stack_isr = allocate_stack(stack_isr_page_count, false);
    cpu.stack_irq = allocate_stack(stack_irq_page_count, false);
    cpu.stack_timer = allocate_stack(stack_timer_page_count, true);
    cpu.stack_timer_begin = cpu.stack_timer - (stack_timer_page_count * Paging.page_size);
    cpu.stack_timer -= @sizeOf(TimerStackTop);
}

fn init(cpu: *CPU.Context) void
{
    allocate(cpu);
    @intToPtr(*TimerStackTop, cpu.stack_timer).kernel_pml4 = @ptrToInt(Paging.pml4);
    print("CPU allocated successfully!\n", .{});

    cpu.gdt.init();
    print("Selector: {any}\n", .{GDT.selector});
    const selector_index = GDT.selector[@enumToInt(GDT.SelectorIndex.tss)];
    const gdt_tss = @intToPtr(*@import("gdt.zig").TSS.Descriptor, cpu.gdt.descriptor.offset + selector_index);
    print("GDT TSS entry: {}\n", .{gdt_tss.*});
    print("GDT initialized successfully!\n", .{});
    cpu.gdt.set_tss_entry_ist(@enumToInt(IDT.IST.ISR), cpu.stack_isr);
    cpu.gdt.set_tss_entry_ist(@enumToInt(IDT.IST.IRQ), cpu.stack_irq);
    cpu.gdt.set_tss_entry_ist(@enumToInt(IDT.IST.timer), cpu.stack_timer);
    GDT.load_gdt(&cpu.gdt.descriptor, selector_index);
    print("GDT loaded successfully!\n", .{});

    cpu.idt.init();
    print("IDT initialized successfully!\n", .{});
    IDT.load_idt(&cpu.idt.descriptor);
    print("IDT loaded successfully!\n", .{});
}

fn init_common(cpu: *CPU.Context) void
{
    cpu_set_gs_fs_base_MSRs(cpu);
    init(cpu);
}

pub fn init_bsp() void
{
    bsp.LAPIC_id = @truncate(u8, cpuid_get_LAPIC_id());
    init_common(&bsp);
}
