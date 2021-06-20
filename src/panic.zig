const std = @import("std");
const root = @import("root");
const panic = root.panic;

pub fn kpanic(comptime format: []const u8, args: anytype) noreturn
{
    var buffer: [16 * 1024]u8 = undefined;
    const formatted_buffer = std.fmt.bufPrint(buffer[0..], format, args) catch unreachable;
    panic(formatted_buffer, null);
}

