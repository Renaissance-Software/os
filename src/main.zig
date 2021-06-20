const std = @import("std");
const uefi = @import("uefi.zig");
const x86_64 = @import("arch/x86_64/intrinsics.zig");
const PSF = @import("psf.zig");
const renderer_module = @import("renderer.zig");
const print = renderer_module.print;
const Renderer = renderer_module.Renderer;
const Paging = @import("arch/x86_64/paging.zig");
const PageAllocator = Paging.PageAllocator;
const PageTable = Paging.PageTable;
const GDT = @import("arch/x86_64/gdt.zig").GDT;
const Interrupts = @import("arch/x86_64/interrupts.zig");
const kpanic = @import("panic.zig").kpanic;

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn
{
    @setCold(true);
    print("Panic: {s}\n", .{message});

    while (true) {}
}

export fn kernel_main(boot_data: *uefi.BootData) callconv(.SysV) noreturn
{
    Renderer.init(boot_data);

    GDT.init();

    var page_allocator = PageAllocator.init(boot_data);

    if (page_allocator.request_zero_page()) |pml4_ptr|
    {
        const pml4_address = @ptrToInt(pml4_ptr);
        var page_manager = @ptrCast(* align(0x1000) PageTable, pml4_ptr);
        var page_address : u64 = 0;
        while (page_address < Paging.size) : (page_address += Paging.page_size)
        {
            page_manager.map(&page_allocator, page_address, page_address);
        }

        const fb_base = boot_data.gop.base;
        const fb_size = boot_data.gop.size + 0x1000;
        page_allocator.reserve_pages(fb_base, fb_size / Paging.page_size + 1);

        page_address = fb_base;
        const fb_top = fb_base + fb_size;
        while (page_address < fb_top) : (page_address += Paging.page_size)
        {
            page_manager.map(&page_allocator, page_address, page_address);
        }

        asm volatile("mov %[in], %%cr3" : : [in] "r" (pml4_address));
    }
    else
    {
        kpanic("unable to obtain pml4 page\n", .{});
    }

    renderer_module.renderer.clear(0xff000000);
    Interrupts.setup(&page_allocator);

    while (true)
    {
    }
}
