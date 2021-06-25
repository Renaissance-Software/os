const std = @import("std");
const range = @import("../../range.zig").range;
const GDT = @import("gdt.zig").GDT;

const ISR = @import("isr.zig");

const sched_call_vector = 0x31;
const syscall_vector = 0x32;
const ring_vector = 0x33;
const spurious_vector = 0xff;

pub const IDT = extern struct
{
    pub const PtrType = * align(0x1000)IDT;
    descriptor: Descriptor,
    entries: [Entry.count]Entry,

    pub fn init(self: PtrType) void
    {
        self.* = std.mem.zeroes(IDT);
        self.descriptor.limit = IDT.size;
        self.descriptor.address = @ptrToInt(&self.entries[0]);

        inline for (range(IDT.Entry.count)) |interrupt_index|
        {
            raw_callbacks[interrupt_index] = make_raw_callback(interrupt_index);
            add_handler(interrupt_index, ISR.unhandled_interrupt, true, 0, IST.none);

        }

        add_handler(8, ISR.double_fault_handler, true, 0, IST.ISR);
        add_handler(13, ISR.general_protection_fault_handler, true, 0, IST.ISR);
        add_handler(14, ISR.page_fault_handler, true, 3, IST.ISR);
    }

    pub extern fn load_idt(descriptor: *IDT.Descriptor) void;

    pub const IST = enum(u3)
    {
        none = 0,
        ISR = 1,
        IRQ = 2,
        timer = 3,
    };

    pub const Entry = packed struct
    {
        address_low: u16,
        selector: u16,
        ist: IST,
        space: u5 = 0,
        gate_type: GateType,
        storage: u1,
        privilege_level: u2,
        present: u1,
        address_mid: u16,
        address_high: u32,
        reserved: u32 = 0,

        pub const count = 256;

        const GateType = enum(u4)
        {
            undef = 0,
            call = 0xc,
            interrupt = 0xe,
            trap = 0xf,
        };

        pub fn new(handler: InterruptHandler, interrupt: bool, privilege_level: u2, ist: IST) IDT.Entry
        {
            const handler_address = @ptrToInt(handler);
            return IDT.Entry
            {
                .address_low = @truncate(u16, handler_address),
                .selector = GDT.selector[1] | privilege_level,
                .ist = .none,
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

    pub const Descriptor = extern struct
    {
        limit: u16,
        address: u64,
    };

    pub const InterruptHandler = fn() callconv(.Naked) void;
    const size = IDT.Entry.count * @sizeOf(IDT.Entry);
    pub var table: IDT align(0x1000) = blk:
    {
        @setEvalBranchQuota(10000);
        const result = std.mem.zeroes(IDT);
        break :blk result;
    };
};

var raw_callbacks: [IDT.Entry.count]IDT.InterruptHandler = undefined;

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

pub fn add_handler(index: u8, handler: ISR.Handler, interrupt: bool, privilege_level: u2, ist: IDT.IST) void
{
    IDT.table.entries[index] = IDT.Entry.new(raw_callbacks[index], interrupt, privilege_level, ist);
    ISR.handlers[index] = handler;
}

pub fn make_raw_callback(comptime interrupt_number: u8) IDT.InterruptHandler
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
