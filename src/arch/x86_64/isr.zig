const ISR = @This();
const IDT = @import("idt.zig").IDT;
const GDT = @import("gdt.zig").GDT;
const print = @import("../../renderer.zig").print;
const kpanic = @import("../../panic.zig").kpanic;
pub const IRQ_start = 32;
pub const MAX = 256;
pub const Handler = fn (*InterruptFrame)void;

pub export var handlers: [IDT.Entry.count]Handler = undefined;

pub fn exists(index: u8) bool
{
    return handlers[index] != unhandled_interrupt;
}

pub const InterruptFrame = packed struct
{
    es: u64,
    ds: u64,
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    intnum: u64,
    ec: u64,
    rip: u64,
    cs: u64,
    eflags: u64,
    rsp: u64,
    ss: u64,
};

pub fn unhandled_interrupt(frame: *InterruptFrame) void
{
    print("Unhandled interrupt: {}", .{frame.intnum});
}

export fn interrupt_common() callconv(.Naked) void
{
    asm volatile (
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rbp
        \\push %%rsi
        \\push %%rdi
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\mov %%ds, %%rax
        \\push %%rax
        \\mov %%es, %%rax
        \\push %%rax
        \\mov %%rsp, %%rdi
        \\mov %[dsel], %%ax
        \\mov %%ax, %%es
        \\mov %%ax, %%ds
        \\call interrupt_handler
        \\pop %%rax
        \\mov %%rax, %%es
        \\pop %%rax
        \\mov %%rax, %%ds
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rbp
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        \\add $16, %%rsp // Pop error code and interrupt number
        \\iretq
        :
        : [dsel] "i" (GDT.selector[2])
    );
    unreachable;
}

export fn interrupt_handler(frame: u64) void
{
    const interrupt_frame = @intToPtr(*InterruptFrame, frame);
    interrupt_frame.intnum &= 0xff;
    if (interrupt_frame.intnum < ISR.handlers.len)
    {
        ISR.handlers[interrupt_frame.intnum](interrupt_frame);
    }
}


pub fn double_fault_handler(frame: *InterruptFrame) void
{
    kpanic("Double fault: {}", .{frame.*});
}

pub fn page_fault_handler(frame: *InterruptFrame) void
{
    kpanic("Page fault: {}", .{frame.*});
}

pub fn general_protection_fault_handler(frame: *InterruptFrame) void
{
    kpanic("General protection fault: {}", .{frame.*});
}
