const std = @import("std");
const uefi = std.os.uefi;

pub fn main() void
{
    const con_out = uefi.system_table.con_out.?;

    _ = con_out.reset(false);

    _ = con_out.outputString(&[_:0]u16{ 'H', 'e', 'l', 'l', 'o', ',', ' ' });
    _ = con_out.outputString(&[_:0]u16{ 'w', 'o', 'r', 'l', 'd', '\r', '\n' });

    const boot_services = uefi.system_table.boot_services.?;
    const image_handle = uefi.handle;

    var loaded_image: *uefi.protocols.LoadedImageProtocol = undefined;
    if (boot_services.handleProtocol(image_handle, &uefi.protocols.LoadedImageProtocol.guid, @ptrCast(*?*c_void, &loaded_image)) != uefi.Status.Success)
    {
        _ = con_out.outputString(&[_:0]u16{ 'K', 'O', '\r', '\n' });
    }
    _ = con_out.outputString(&[_:0]u16{ 'O', 'K', '\r', '\n' });
    

    _ = boot_services.stall(10 * 5 * 1000 * 1000);
}
