const std = @import("std");
const Interrupts = @import("interrupts.zig");
const ISR = @import("isr.zig");

const ACPI = @import("../../acpi.zig");
const SDT = ACPI.SDT;
const print = @import("../../renderer.zig").print;
const kpanic = @import("../../panic.zig").kpanic;
const Paging = @import("paging.zig");

pub const MADT = struct
{
    const Extra = packed struct
    {
        LAPIC_address: u32,
        PCAT_COMPAT: u1,
        reserved: u31,
    };

    const Entry = packed struct
    {
        type: u8,
        length: u8,

        const Type = enum(u8)
        {
            LAPIC = 0,
            IOAPIC = 1,
            IOAPIC_ISO = 2,
            IOAPIC_NMIS = 3,
            LAPIC_NMI = 4,
            LAPIC_address_override = 5,
            IOSAPIC = 6,
            LSAPIC = 7,
            PlatformInterruptSources = 8,
            Lx2APIC = 9,
            Lx2APIC_NMI = 0xa,
            GICC = 0xb,
            GICD = 0xc,
            GCI_MSI_frame = 0xd,
            GICR = 0xe,
            GIC_ITS = 0xf,
        };
    };

    const LAPICEntry = packed struct
    {
        base: Entry,
        procesor_id: u8,
        LAPIC_id: u8,
        flags: u32,
    };

    const IOAPICEntry = packed struct
    {
        base: Entry,
        id: u8,
        reserved: u8,
        IOAPIC_address: u32,
        global_interrupt_base: u32,
    };

    const ISOEntry = packed struct
    {
        base: Entry,
        bus: u8,
        source: u8,
        global_interrupt: u32,
        flags: u16,
    };

    const NonMaskableInterruptEntry = packed struct
    {
        base: Entry,
        LAPIC_id: u8,
        flags: u16,
        lint: u8,
    };

    const LAPICAddressOverrideEntry = packed struct
    {
        base: Entry,
        reserved: u16,
        LAPIC_address: u64,
    };

    comptime
    {
        if (@sizeOf(MADT.Extra) != 8)
        {
            @compileError("MADT extra struct size is wrong");
        }
        if (@sizeOf(MADT.Entry) != 2)
        {
            @compileError("MADT entry struct size is wrong");
        }
    }

    pub fn init() void
    {
        const madt_length = ACPI.madt_header.length;
        print("MADT length: 0x{x}\n", .{madt_length});
        Paging.reserve_pages(@ptrToInt(ACPI.madt_header), (madt_length + 0x1000) / 0x1000 + 1);
        const madt_extra = @intToPtr(*MADT.Extra, @ptrToInt(ACPI.madt_header) + @sizeOf(SDT.Header));
        LAPIC.address = madt_extra.LAPIC_address;
        Paging.reserve_pages(LAPIC.address, 1);
        Paging.map(LAPIC.address, LAPIC.address);
        print("LAPIC address: 0x{x}\n", .{LAPIC.address});

        var madt_entry = @intToPtr(*MADT.Entry, @ptrToInt(madt_extra) + @sizeOf(MADT.Extra));
        const madt_end = @intToPtr(*MADT.Entry, @ptrToInt(ACPI.madt_header) + madt_length);

        while (@ptrToInt(madt_entry) < @ptrToInt(madt_end))
        {
            const madt_type = @intToEnum(MADT.Entry.Type, madt_entry.type);
            switch (madt_type)
            {
                .LAPIC =>
                {
                    const lapic = @ptrCast(*LAPICEntry, madt_entry);
                    print("LAPIC entry: {}\n", .{lapic});
                    LAPIC.count += 1;
                },
                .IOAPIC =>
                {
                    const ioapic = @ptrCast(*IOAPICEntry, madt_entry);
                    const ioapic_info = &IOAPIC.IOAPICInfo.info[IOAPIC.IOAPICInfo.count];
                    const address = ioapic.IOAPIC_address;
                    ioapic_info.address = address;
                    ioapic_info.global_interrupt_base = ioapic.global_interrupt_base;
                    Paging.reserve_pages(address, 1);
                    Paging.map(address, address);
                    print("IOAPIC entry: {}\n", .{ioapic});
                    IOAPIC.IOAPICInfo.count += 1;
                },
                .IOAPIC_ISO =>
                {
                    const iso = @ptrCast(*ISOEntry, madt_entry);
                    var iso_record = &IOAPIC.ISO.info[IOAPIC.ISO.count];
                    iso_record.source = iso.source;
                    iso_record.global_interrupt_base = iso.global_interrupt;
                    iso_record.flags = iso.flags;
                    print("ISO entry: {}\n", .{iso});
                    IOAPIC.ISO.count += 1;
                },
                .LAPIC_NMI =>
                {
                    const nmi = @ptrCast(*NonMaskableInterruptEntry, madt_entry);
                    print("NMI entry: {}\n", .{nmi});
                },
                .LAPIC_address_override =>
                {
                    const lapic_address_override = @ptrCast(*LAPICAddressOverrideEntry, madt_entry);
                    print("LAPIC address override entry: {}\n", .{lapic_address_override});
                },
                else => kpanic("not implemented: {}\n", .{madt_entry.type}),
            }

            madt_entry = @intToPtr(*MADT.Entry, @ptrToInt(madt_entry) + madt_entry.length);
        }
    }
};

pub const LAPIC = struct
{
    var address: u64 = 0;
    var count: u64 = 0;

    pub const trampoline_target: u64 = 0x8000;

    const RegisterOffset = enum(u16)
    {
        ID = 0x0020,
        version = 0x0030,
        task_priority = 0x0080,
        arbitration_priority = 0x0090,
        processor_priority = 0x00a0,
        eoi = 0x00b0,
        remote_read = 0x00c0,
        logical_destination = 0x00d0,
        destination_format = 0x00e0,
        spurious_int_vector = 0x00f0,
        in_service = 0x0100,
        trigger_mode = 0x0180,
        interrupt_request = 0x0200,
        error_status = 0x0280,
        cmci = 0x02f0,
        interrupt_command = 0x0300,
        LVT_timer = 0x0320,
        LVT_thermal_sensor = 0x0330,
        LVT_performance_monitor = 0x0340,
        LVT_lint0 = 0x0350,
        LVT_lint1 = 0x0360,
        LVT_error = 0x0370,
        initial_count = 0x0380,
        current_count = 0x0390,
        divide_config = 0x03e0,
    };

    pub fn init() void
    {
        const spurious_reg = LAPIC.get_register(.spurious_int_vector);
        LAPIC.set_register(.spurious_int_vector, spurious_reg | 0x100);
    }

    fn get_register(register_offset: RegisterOffset) u32
    {
        const result = @intToPtr(* volatile u32, LAPIC.address + @enumToInt(register_offset)).*;
        return result;
    }

    fn set_register(register_offset: RegisterOffset, value: u32) void
    {
        @intToPtr(* volatile u32, LAPIC.address + @enumToInt(register_offset)).* = value;
    }
};

pub const IOAPIC = struct
{
    pub extern fn io_apic_enable() void;

    const IOAPICInfo = struct
    {
        const Info = struct
        {
            address: u64,
            global_interrupt_base: u32,
        };

        var info: [max]Info = std.mem.zeroes([max]Info);
        const max = 8;
        var count: u64 = 0;
        var max_interrupts: u64 = 0;
    };

    const ISO = struct
    {
        const Info = struct
        {
            global_interrupt_base: u32,
            flags: u16,
            source: u8,
        };

        const max = 16;
        var info: [max]ISO.Info = std.mem.zeroes([max]Info);
        var count: u64 = 0;
    };

    const RedirectionEntry = packed struct
    {
        vector: u8,
        delivery_mode: DeliveryMode,
        destination_mode: DestinationMode,
        delivery_status: DeliveryStatus,
        pin_polarity: PinPolarity,
        remote_irr: RemoteIRR,
        trigger_mode: TriggerMode,
        mask: Mask,
        destination: u8,

        const DeliveryMode = enum(u3)
        {
            fixed = 0b000,
            low_priority = 0b001,
            SMI = 0b010,
            NMI = 0b100,
            init = 0b101,
            extint = 0b111,
        };

        const DestinationMode = enum(u1)
        {
            physical = 0,
            logical = 1,
        };

        const DeliveryStatus = enum(u1)
        {
            idle = 0,
            pending = 1,
        };

        const PinPolarity = enum(u1)
        {
            high = 0,
            low = 1,
        };

        const RemoteIRR = enum(u1)
        {
            none = 0,
            inflight = 1,
        };

        const TriggerMode = enum(u1)
        {
            edge = 0,
            level = 1,
        };

        const Mask = enum(u1)
        {
            enable = 0,
            disable = 1,
        };

        const LowBits = enum(u5)
        {
            vector = 0,
            delivery_mode = 8,
            destination_mode = 11,
            delivery_status = 12,
            pin_polarity = 13,
            remote_irr = 14,
            trigger_mode = 15,
            mask = 16,
        };

        const HighBits = enum(u5)
        {
            destination = 24,
        };

        fn set(self: RedirectionEntry, address: u64, index: u32) void
        {
            const low: u32 =
                (self.vector << @enumToInt(LowBits.vector)) |
                (@intCast(u32, @enumToInt(self.delivery_mode)) << @enumToInt(LowBits.delivery_mode)) |
                (@intCast(u32, @enumToInt(self.destination_mode)) << @enumToInt(LowBits.destination_mode)) |
                (@intCast(u32, @enumToInt(self.delivery_status)) << @enumToInt(LowBits.delivery_status)) |
                (@intCast(u32, @enumToInt(self.pin_polarity)) << @enumToInt(LowBits.pin_polarity)) |
                (@intCast(u32, @enumToInt(self.remote_irr)) << @enumToInt(LowBits.remote_irr)) |
                (@intCast(u32, @enumToInt(self.trigger_mode)) << @enumToInt(LowBits.trigger_mode)) |
                (@intCast(u32, @enumToInt(self.mask)) << @enumToInt(LowBits.mask));
            const high: u32 = @intCast(u32, self.destination) << @enumToInt(HighBits.destination);

            Register.set(address, @enumToInt(Register.Offset.redirection_table) + 2 * index + 0, low);
            Register.set(address, @enumToInt(Register.Offset.redirection_table) + 2 * index + 1, high);
        }
    };

    const Register = struct
    {
        const Offset = enum(u8)
        {
            id = 0x00,
            version = 0x01,
            arbitration = 0x02,
            redirection_table = 0x10,
        };

        const select_offset = 0x00;
        const window_offset = 0x10;

        fn get(address: u64, register_offset: u32) u32
        {
            @intToPtr(* volatile u32, address + Register.select_offset).* = register_offset;
            const result = @intToPtr(* volatile u32, address + Register.window_offset).*;
            return result;
        }

        fn set(address: u64, register_offset: u32, value: u32) void
        {
            @intToPtr(* volatile u32, address + Register.select_offset).* = register_offset;
            @intToPtr(* volatile u32, address + Register.window_offset).* = value;
        }
    };

    pub fn init() void
    {
        var ioapic_index: u64 = 0;

        for (IOAPICInfo.info[0..IOAPICInfo.count]) |*ioapic|
        {
            const address = ioapic.address;
            IOAPICInfo.max_interrupts = ((IOAPIC.Register.get(address, @enumToInt(Register.Offset.version)) >> 16) & 0xff) + 1;
            const global_interrupt_base = ioapic.global_interrupt_base;

            if (IOAPICInfo.count != 1)
            {
                kpanic("IOAPIC count must be 1. Other counts are not implemented\n", .{});
            }

            for (IOAPIC.ISO.info[0..IOAPIC.ISO.count]) |iso|
            {
                const redirection_entry = RedirectionEntry
                {
                    .vector = iso.source + ISR.IRQ_start,
                    .delivery_mode = RedirectionEntry.DeliveryMode.fixed,
                    .destination_mode = RedirectionEntry.DestinationMode.physical,
                    .pin_polarity = if ((iso.flags & 0x03) == 0x03) RedirectionEntry.PinPolarity.low else RedirectionEntry.PinPolarity.high,
                    .trigger_mode = if ((iso.flags & 0x0c) == 0x0c) RedirectionEntry.TriggerMode.level else RedirectionEntry.TriggerMode.edge,
                    .mask = RedirectionEntry.Mask.enable,
                    .delivery_status = .idle,
                    .remote_irr = .none,
                    .destination = 0,
                };
                redirection_entry.set(address, iso.global_interrupt_base);
            }
        }
    }

    pub fn set_from_isrs() void
    {
        const ioapic_count = IOAPICInfo.count;

        for (IOAPICInfo.info[0..ioapic_count]) |ioapic|
        {
            const address = ioapic.address;
            var isr_index_big: u16 = ISR.IRQ_start;
second_loop:
            while (isr_index_big < ISR.MAX) : (isr_index_big += 1)
            {
                const isr_index = @truncate(u8, isr_index_big);
                if (!ISR.exists(isr_index))
                {
                    continue;
                }

                const ISO_count = IOAPIC.ISO.count;
                for (ISO.info[0..ISO_count]) |iso|
                {
                    if (iso.source + ISR.IRQ_start == isr_index)
                    {
                        continue :second_loop;
                    }
                }

                const redirection_entry = RedirectionEntry
                {
                    .vector = isr_index,
                    .delivery_mode = .low_priority,
                    .destination_mode = .physical,
                    .pin_polarity = .high,
                    .trigger_mode = .edge,
                    .mask = .enable,
                    .delivery_status = .idle,
                    .remote_irr = .none,
                    .destination = 0,
                };

                redirection_entry.set(address, isr_index - ISR.IRQ_start);
            }
        }
    }
};
