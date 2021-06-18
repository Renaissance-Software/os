const std = @import("std");
const uefi = @import("uefi.zig");
const arch = @import("arch/x86_64/intrinsics.zig");
const PSF = @import("psf.zig");

const Point = extern struct
{
    x: u32,
    y: u32,
};

pub fn kernel_panic(comptime format: []const u8, args: anytype) noreturn
{
    var buffer: [16 * 1024]u8 = undefined;
    const formatted_buffer = std.fmt.bufPrint(buffer[0..], format, args) catch unreachable;
    panic(formatted_buffer, null);
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn
{
    print("Panic: {s}\n", .{message});

    arch.hlt();
}

const Renderer = struct
{
    frame: []u32,
    font: []u8,
    x: u32,
    y: u32,

    fn init(boot_data: *uefi.BootData) void
    {
        const framebuffer_pixel_type = u32;
        const framebuffer_len = boot_data.gop.size / @sizeOf(framebuffer_pixel_type);
        renderer = Renderer
        {
            .frame = @intToPtr([*]framebuffer_pixel_type, boot_data.gop.base)[0..framebuffer_len],
            .font = boot_data.font.buffer.ptr[0..boot_data.font.buffer.size / @sizeOf(u8)],
            .x = 0,
            .y = 0,
        };

        Renderer.character_size = boot_data.font.header.char_size;
        Renderer.width = boot_data.gop.width;
        Renderer.height = boot_data.gop.height;
        Renderer.pixels_per_scanline = boot_data.gop.pixels_per_scanline;

        const space_to_obviate = Renderer.character_size + (Renderer.height % Renderer.character_size);
        Renderer.line_limit = Renderer.height - space_to_obviate;

        renderer.clear(0xff000000);

        print("Renderer initialized successfully\n", .{});
    }

    fn render_char(self: *Renderer, ch: u8, xo: u32, yo: u32) void
    {
        var font_index = @as(u64, ch) * Renderer.character_size;

        const y_end = yo + character_height;
        const x_end = xo + character_width;

        var y = yo;

        while (y < y_end) :
            ({
                y += 1;
                font_index += 1;
            })
        {
            const font_byte = self.font[font_index];

            var x = xo;

            while (x < x_end) : (x += 1)
            {
                const shr = @intCast(u8, 0b10000000) >> @intCast(u3, (x - xo));

                if (font_byte & shr > 0)
                {
                    const framebuffer_index = x + (y * pixels_per_scanline);
                    self.frame[framebuffer_index] = 0xffffffff;
                }
            }
        }
    }

    fn handle_new_line(self: *Renderer) void
    {
        if (self.y + Renderer.character_size < Renderer.line_limit)
        {
            self.x = 0;
            self.y = self.y + Renderer.character_size;
        }
        else
        {
            self.scroll();
        }
    }

    fn putchar(self: *Renderer, ch: u8) void
    {
        switch (ch)
        {
            '\n' => 
            {
                self.handle_new_line();
            },
            else =>
            {
                self.render_char(ch, self.x, self.y);
                self.x += 8;
                if (self.x + 8 > Renderer.width)
                {
                    self.handle_new_line();
                }
            },
        }
    }

    fn scroll(self: *Renderer) void
    {
        const lines_to_be_skipped = Renderer.character_size;
        const lines_to_be_copied = Renderer.height - lines_to_be_skipped;
        const line_to_clear_offset = lines_to_be_copied * Renderer.pixels_per_scanline;
        const line_to_copy_offset = renderer.frame.len - line_to_clear_offset;
        var dst = renderer.frame[0..line_to_clear_offset];
        var src = renderer.frame[line_to_copy_offset .. renderer.frame.len];

        std.mem.copy(u32, dst, src);

        for (self.frame[line_to_clear_offset ..]) |*pixel|
        {
            pixel.* = 0x000000ff;
        }

        self.x = 0;
    }

    fn clear(self: *Renderer, color: u32) void
    {
        std.mem.set(u32, self.frame, color);
    }

    fn clear_well(self: *Renderer) void
    {
        //self.frame;
        const fb_size = self.frame.len;

        var vertical_line: u64 = 0;
        while (vertical_line < Renderer.height) : (vertical_line += 1)
        {
            const offset = vertical_line * Renderer.pixels_per_scanline;
            var slice = self.frame[offset .. offset + Renderer.pixels_per_scanline];

            for (slice) |*color, i|
            {
                color.* = 0x000000ff;
            }
        }

    }

    const character_height = 16;
    const character_width = 8;

    var pixels_per_scanline: u32 = undefined;
    var character_size: u8 = undefined;
    var line_limit: u32 = undefined;

    var width: u32 = undefined;
    var height: u32 = undefined;
};

fn print(comptime format: []const u8, args: anytype) void
{
    var buffer: [4096]u8 = undefined;
    const formatted_buffer = std.fmt.bufPrint(buffer[0..], format, args) catch unreachable;
    for (formatted_buffer) |ch|
    {
        renderer.putchar(ch);
    }
}

var renderer: Renderer = undefined;

var memory_size: u64 = 0;

const Memory = struct
{
    var size: u64 = 0;
    const page_size = 4096;

    const PageAllocator = struct
    {
        bitmap_ptr: [*]u8,
        bitmap_size: u64,
        free_memory: u64,
        used_memory: u64,

        fn new(bitmap_address: u64) PageAllocator
        {
            var page_allocator = PageAllocator
            {
                .bitmap_ptr = @intToPtr([*]u8, bitmap_address),
                .bitmap_size = size / page_size / 8 + 1,
                .free_memory = size,
                .used_memory = 0,
            };

            print("Page allocator bitmap size: {}\n", .{page_allocator.bitmap_size});

            std.mem.set(u8, page_allocator.bitmap_ptr[0..page_allocator.bitmap_size], 0);

            return page_allocator;
        }

        fn request_page(self: *PageAllocator) ?[]u8
        {
            const top = self.bitmap.len * 8;
            var index: u64 = 0;
            while (index < top) : (index += 1)
            {
                if (self.is_page_reserved(index))
                {
                    continue;
                }

                const page_address = index * 4096;
                self.reserve_page(page_address);
                var page = @intToPtr([*]u8, page_address)[0..4096];
                return page;
            }

            return null;
        }

        fn is_page_reserved(self: *PageAllocator, index: u64) bool
        {
            if (index > self.bitmap_size * 8)
            {
                return false;
            }

            const byte_index = index / 8;
            const bit_index: u3 = @intCast(u3, index % 8);
            const bit_indexer = @intCast(u8, 0b10000000) >> bit_index;

            return self.bitmap_ptr[byte_index] & bit_indexer > 0;
        }

        const SetPageReservedResult = enum(u8)
        {
            OutOfBounds,
            Reserved,
            NonReserved,
        };

        fn set_page_reserved(self: *PageAllocator, index: u64, value: bool) SetPageReservedResult
        {
            if (index > self.bitmap_size * 8)
            {
                return .OutOfBounds;
            }

            const byte_index = index / 8;
            const bit_index: u3 = @intCast(u3, index % 8);
            const bit_indexer = @intCast(u8, 0b10000000) >> bit_index;
            self.bitmap_ptr[byte_index] &= ~bit_indexer;

            if (value)
            {
                self.bitmap_ptr[byte_index] |= bit_indexer;
                return .Reserved;
            }

            return .NonReserved;
        }

        fn reserve_pages(self: *PageAllocator, address: u64, page_count: u64) void
        {
            const top_address = address + (page_count * page_size);
            var page_address: u64 = address;
            while (page_address < top_address) : (page_address += page_size)
            {
                self.reserve_page(page_address);
            }
        }

        fn free_pages(self: *PageAllocator, address: u64, page_count: u64) void
        {
            const top_address = address + (page_count * page_size);
            var page_address: u64 = address;
            while (page_address < top_address) : (page_address += page_size)
            {
                self.free_page(page_address);
            }
        }

        fn reserve_page(self: *PageAllocator, address: u64) void
        {
            const page_index = address / page_size;
            if (!self.is_page_reserved(page_index))
            {
                if (self.set_page_reserved(page_index, true) == .Reserved)
                {
                    self.free_memory -= page_size;
                    self.used_memory += page_size;
                }
            }
        }

        fn free_page(self: *PageAllocator, address: u64) void
        {
            const page_index = address / page_size;
            if (!self.is_page_reserved(index))
            {
                return;
            }

            self.set_page_reserved(index, false);
            self.free_memory += page_size;
            self.used_memory -= page_size;
        }
    };

    fn init(boot_data: *uefi.BootData) void
    {
        const map_entry_count = boot_data.memory.size / boot_data.memory.descriptor_size;
        print("Memory map size: {}\n", .{boot_data.memory.size});
        print("Map entry count: {}\n", .{map_entry_count});

        const memory_map = boot_data.memory.map[0..map_entry_count];
        var number_of_pages: u64 = 0;

        for (memory_map) |map_entry|
        {
            number_of_pages += map_entry.number_of_pages;
        }

        size = number_of_pages * page_size;

        print("Number of pages: {}\n", .{number_of_pages});
        print("Expected memory size: {}\n", .{size});

        var largest_free_memory_block: u64 = 0;
        var largest_free_memory_block_size: u64 = 0;

        for (memory_map) |map_entry|
        {
            if (map_entry.type == .ConventionalMemory)
            {
                if (map_entry.number_of_pages * page_size > largest_free_memory_block)
                {
                    largest_free_memory_block = map_entry.physical_start;
                    largest_free_memory_block_size = map_entry.number_of_pages * page_size;
                }
            }
        }

        print("Memory map size: {}\n", .{size});
        print("Largest block: 0x{x} at 0x{x}\n", .{largest_free_memory_block_size, largest_free_memory_block});

        var page_allocator = PageAllocator.new(largest_free_memory_block);
        print("Page allocator set up\n", .{});
        page_allocator.reserve_pages(largest_free_memory_block, page_allocator.bitmap_size / page_size + 1);
        print("Reserved pages for page allocator bitmap\n", .{});

        for (memory_map) |map_entry|
        {
            if (map_entry.type != .ConventionalMemory)
            {
                page_allocator.reserve_pages(map_entry.physical_start, map_entry.number_of_pages);
            }
        }

        print("Memory initialized successfully!\n", .{});
        print("Free RAM: {}\nUsed RAM: {}\nTotal RAM: {}\n", .{page_allocator.free_memory, page_allocator.used_memory, Memory.size});
    }
};

export fn _start(boot_data: *uefi.BootData) callconv(.C) noreturn
{
    Renderer.init(boot_data);
    Memory.init(boot_data);

    var i: u64 = 0;
    while (i < 100) : (i += 1)
    {
        print("Hello world: {}\n", .{i});
    }

    arch.hlt();
}
