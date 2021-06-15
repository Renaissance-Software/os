const std = @import("std");
const uefi = @import("uefi.zig");
const arch = @import("arch/x86_64/intrinsics.zig");
const PSF = @import("psf.zig");

const Point = extern struct
{
    x: u32,
    y: u32,
};

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
        std.mem.copyBackwards(u32, self.frame[0..line_to_clear_offset], self.frame[lines_to_be_skipped * Renderer.pixels_per_scanline ..]);

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
    var mm_size: u64 = 0;
    const page_size = 4096;

    fn init(boot_data: *uefi.BootData) void
    {
        const map_entry_count = boot_data.memory.size / boot_data.memory.descriptor_size;
        print("Memory map size: {}\n", .{boot_data.memory.size});
        print("Map entry count: {}\n", .{map_entry_count});

        const memory_map = boot_data.memory.map[0..map_entry_count];

        for (memory_map) |map_entry|
        {
            mm_size += map_entry.number_of_pages * page_size;
        }

        print("Memory map size: {}\n", .{mm_size});
        print("Memory initialized successfully!\n", .{});
    }
};

export fn _start(boot_data: *uefi.BootData) callconv(.C) noreturn
{
    Renderer.init(boot_data);
    Memory.init(boot_data);

    arch.hlt();
}
