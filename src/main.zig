const std = @import("std");
const uefi = @import("uefi.zig");
const x86_64 = @import("arch/x86_64/intrinsics.zig"); const PSF = @import("psf.zig");
const renderer_module = @import("renderer.zig");
const print = renderer_module.print;
const Renderer = renderer_module.Renderer;
const Paging = @import("arch/x86_64/paging.zig");
const GDT = @import("arch/x86_64/gdt.zig").GDT;
const Interrupts = @import("arch/x86_64/interrupts.zig");
const kpanic = @import("panic.zig").kpanic;
const ACPI = @import("acpi.zig");
const CPU = @import("arch/x86_64/cpu.zig");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn
{
    @setCold(true);
    print("Panic: {s}\n", .{message});

    while (true) {}
}

export fn kernel_main(boot_data: *uefi.BootData) callconv(.SysV) noreturn
{
    Renderer.init(boot_data);
    //GDT.init();
    Paging.init(boot_data);


    renderer_module.renderer.clear(0xff000000);
    print("Paging setup\nFree memory: {}.\nUsed memory: {}\n", .{Paging.free_memory, Paging.used_memory});

    ACPI.setup(boot_data.rsdp_address);
    print("ACPI setup correctly\n", .{});

    Interrupts.setup();
    print("Interrupts setup\n", .{});

    CPU.init_bsp();

    print("Kernel initialized successfully\n", .{});

    x86_64.halt_loop();
}
