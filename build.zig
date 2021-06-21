const std = @import("std");
const Builder = std.build.Builder;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const builtin = std.builtin;

pub fn build(b: *std.build.Builder) void
{
    const install_dir = "efi/boot";
    const uefi_bootloader = b.addExecutable("bootx64", "src/uefi.zig");
    uefi_bootloader.setBuildMode(b.standardReleaseOptions());
    uefi_bootloader.setTarget(CrossTarget
        {
            .cpu_arch = Target.Cpu.Arch.x86_64,
            .os_tag = Target.Os.Tag.uefi,
            .abi = Target.Abi.msvc,
        });
    uefi_bootloader.force_pic = true;
    uefi_bootloader.setOutputDir(install_dir);
    uefi_bootloader.install();

    const qemu_base_command = &[_][]const u8
    {
        "qemu-system-x86_64",
        "-no-shutdown",
        "-no-reboot",
        "-serial",
        "stdio",
        "-bios",
        "ovmf/OVMF_CODE-pure-efi.fd",
        "-hdd",
        "fat:rw:.",
        "-d",
        "guest_errors,int,cpu_reset",
    };

    const qemu_run_command = qemu_base_command;

    const kernel = b.addExecutable("kernel.elf", "src/main.zig");
    kernel.addAssemblyFile("src/arch/x86_64/boot.S");
    kernel.setBuildMode(b.standardReleaseOptions());
    kernel.setTarget(CrossTarget
        {
            .cpu_arch = Target.Cpu.Arch.x86_64,
            .os_tag = Target.Os.Tag.freestanding,
            .abi = Target.Abi.none,
        });
    kernel.setLinkerScriptPath("kernel.ld");
    kernel.setOutputDir(".");
    kernel.install();
    kernel.step.dependOn(&uefi_bootloader.step);

    const run_step = b.addSystemCommand(qemu_run_command);

    const run_command = b.step("run", "Run the kernel");
    run_command.dependOn(&uefi_bootloader.step);
    run_command.dependOn(&kernel.step);
    run_command.dependOn(&run_step.step);

    const qemu_debug_options = &[_][]const u8 { "-S", "-s", };

    const qemu_debug_cmd = qemu_base_command ++ qemu_debug_options;
    const debug_step = b.addSystemCommand(qemu_debug_cmd);

    const debug_command = b.step("debug", "Debug the kernel");
    debug_command.dependOn(&uefi_bootloader.step);
    debug_command.dependOn(&kernel.step);
    debug_command.dependOn(&debug_step.step);
}
