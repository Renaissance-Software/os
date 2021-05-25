const std = @import("std");
const uefi = std.os.uefi;

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var boot_services: *uefi.tables.BootServices = undefined;
var runtime_services: *uefi.tables.RuntimeServices = undefined;

pub fn puts(msg: []const u8) void
{
    for (msg) |c|
    {
        const fake_c = [2]u16 { c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &fake_c));
    }
    _ = con_out.outputString(&[_:0]u16 {'\r', '\n'});
}

fn printf(buffer: []u8, comptime format: []const u8, args: anytype) void
{
    puts(std.fmt.bufPrint(buffer, format, args) catch unreachable);
}

fn panic(message: []const u8) void
{
    puts(message);
    _ = boot_services.stall(10000 * 5 * 1000 * 1000);
}

pub fn main() void
{
    boot_services = uefi.system_table.boot_services.?;
    runtime_services = uefi.system_table.runtime_services;
    con_out = uefi.system_table.con_out.?;

    _ = con_out.reset(false);

    _ = con_out.outputString(&[_:0]u16{ 'H', 'e', 'l', 'l', 'o', ',', ' ' });
    _ = con_out.outputString(&[_:0]u16{ 'w', 'o', 'r', 'l', 'd', '\r', '\n' });

    const image_handle = uefi.handle;

    var loaded_image: *uefi.protocols.LoadedImageProtocol = undefined;
    if (boot_services.handleProtocol(image_handle, &uefi.protocols.LoadedImageProtocol.guid, @ptrCast(*?*c_void, &loaded_image)) != uefi.Status.Success)
    {
        panic("Failed to load image");
    }

    puts("Image loaded");

    var filesystem: *uefi.protocols.SimpleFileSystemProtocol = undefined;
    const device_handle = loaded_image.device_handle.?;
    if (boot_services.handleProtocol(device_handle, &uefi.protocols.SimpleFileSystemProtocol.guid, @ptrCast(*?*c_void, &filesystem)) != uefi.Status.Success)
    {
        panic("Failed to handle filesystem protocol");
    }

    puts("Filesystem protocol handled");

    var directory: *uefi.protocols.FileProtocol = undefined;
    if (filesystem.openVolume(&directory) != uefi.Status.Success)
    {
        panic("Failed to open directory");
    }

    puts("Directory opened");

    var loaded_file: *uefi.protocols.FileProtocol = undefined;
    const open_result = directory.open(&loaded_file, &[_:0]u16 {'k', 'e', 'r', 'n', 'e', 'l', '.', 'e', 'l', 'f', }, uefi.protocols.FileProtocol.efi_file_mode_read, uefi.protocols.FileProtocol.efi_file_read_only);
    if (open_result != uefi.Status.Success)
    {
        var buffer: [1024]u8 = undefined;
        printf(buffer[0..], "Result: {}", .{open_result});
        panic("Failed to open file kernel.elf");
    }

    puts("kernel.elf loaded");

    _ = boot_services.stall(10 * 5 * 1000 * 1000);
}
