const std = @import("std");
const gdt = @import("gdt.zig");
const GDT = gdt.GDT;
const Paging = @import("paging.zig");
const PageAllocator = Paging.PageAllocator;
const print = @import("../../renderer.zig").print;
const kpanic = @import("../../panic.zig").kpanic;
const range = @import("range.zig").range;

const IDT = struct
{
    const Descriptor = packed struct
    {
        address_low: u16,
        selector: u16,
        ist: u3,
        space: u5 = 0,
        gate_type: GateType,
        storage: u1,
        privilege_level: u2,
        present: u1,
        address_mid: u16,
        address_high: u32,
        reserved: u32 = 0,

        const count = 256;

        const GateType = enum(u4)
        {
            undef = 0,
            call = 0xc,
            interrupt = 0xe,
            trap = 0xf,
        };

        fn new(handler: InterruptHandler, interrupt: bool, privilege_level: u2, ist: u3) IDT.Descriptor
        {
            const handler_address = @ptrToInt(handler);
            return IDT.Descriptor
            {
                .address_low = @truncate(u16, handler_address),
                .selector = gdt.selector.code64 | privilege_level,
                .ist = 0,
                .gate_type = if (interrupt) .interrupt else .trap,
                .storage = 0,
                .privilege_level = privilege_level,
                .present = 1,
                .address_mid = @truncate(u16, handler_address >> 16),
                .address_high = @truncate(u32, handler_address >> 32),
                .reserved = 0,
            };
        }
    };

    const Register = packed struct
    {
        limit: u16,
        address: u64,
    };


    const InterruptHandler = fn() callconv(.Naked) void;
    const size = IDT.Descriptor.count * @sizeOf(IDT.Descriptor);

    var register = std.mem.zeroes(IDT.Register);
    var table: [256]IDT.Descriptor = blk:
    {
        var _table: [256]IDT.Descriptor = undefined;
        std.mem.set(IDT.Descriptor, _table[0..], std.mem.zeroes(IDT.Descriptor));
        break :blk _table;
    };
};

var raw_callbacks: [IDT.table.len]IDT.InterruptHandler = undefined;

const ISR = struct
{
    const Handler = fn (*InterruptFrame)void;
    export var handlers: [IDT.table.len]Handler = undefined;
};

comptime
{
    const expected_size = 2 + 2 + 1 + 1 + 2 + 4 + 4;
    if (@sizeOf(IDT.Descriptor) != expected_size)
    {
        @compileError("IDT descriptor size is wrong");
    }
}

pub fn make_handler(comptime interrupt_number: u8) IDT.InterruptHandler
{
    return struct
    {
        fn function() callconv(.Naked) void
        {
            const error_code = if (comptime (!has_error_code(interrupt_number))) "push $0\n" else "";
            asm volatile (error_code ++ "push %[interrupt_number]\njmp interrupt_common\n"
                :
                : [interrupt_number] "i" (@as(u8, interrupt_number)));
            unreachable;
        }
    }.function;
}

pub fn add_handler(index: u8, handler: ISR.Handler, interrupt: bool, privilege_level: u2, ist: u3) void
{
    IDT.table[index] = IDT.Descriptor.new(raw_callbacks[index], interrupt, privilege_level, ist);
    ISR.handlers[index] = handler;
}

const InterruptFrame = packed struct
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

export fn interrupt_handler(frame: u64) void
{
    const interrupt_frame = @intToPtr(*InterruptFrame, frame);
    interrupt_frame.intnum &= 0xff;
    if (interrupt_frame.intnum < ISR.handlers.len)
    {
        ISR.handlers[interrupt_frame.intnum](interrupt_frame);
    }
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
        : [dsel] "i" (gdt.selector.data64)
    );
    unreachable;
}

fn has_error_code(interrupt_number: u64) bool
{
    return switch (interrupt_number)
    {
        0x00...0x07 => false,
        0x08 => true,
        0x09 => false,
        0x0a...0x0e => true,
        0x0f...0x010 => false,
        0x11 => true,
        0x12...0x14 => false,
        0x1e => true,
        else => false,
    };
}

fn unhandled_interrupt(frame: *InterruptFrame) void
{
    kpanic("Unhandled interrupt: {}", .{frame.intnum});
}

fn double_fault_handler(frame: *InterruptFrame) void
{
    kpanic("Double fault: {}", .{frame.*});
}

fn page_fault_handler(frame: *InterruptFrame) void
{
    kpanic("Page fault: {}", .{frame.*});
}

fn general_protection_fault_handler(frame: *InterruptFrame) void
{
    kpanic("General protection fault: {}", .{frame.*});
}

pub fn setup(page_allocator: *PageAllocator) void
{
    inline for (IDT.table) |*table_entry, interrupt_number|
    {
        raw_callbacks[interrupt_number] = make_handler(interrupt_number);
        add_handler(interrupt_number, unhandled_interrupt, true, 0, 0);
    }

    add_handler(8, double_fault_handler, false, 0, 0);
    add_handler(13, general_protection_fault_handler, false, 0, 0);
    add_handler(14, page_fault_handler, false, 0, 0);

    IDT.register.limit = IDT.size - 1;
    IDT.register.address = @ptrToInt(&IDT.table[0]);
    asm volatile("lidt (%[idtr_addr])" : : [idtr_addr] "r" (&IDT.register));
    asm volatile("sti");

    print("Interrupts setup\n", .{});
}
