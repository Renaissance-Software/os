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

    const cmd = &[_][]const u8
    {
        "qemu-system-x86_64",
        //"-nographic",
        "-bios",
        "ovmf/OVMF_CODE-pure-efi.fd",
        "-hdd",
        "fat:rw:.",
        "-serial",
        "stdio",
    };

    const kernel = b.addExecutable("kernel.elf", "src/main.zig");
    kernel.setBuildMode(b.standardReleaseOptions());
    kernel.setTarget(CrossTarget
        {
            .cpu_arch = Target.Cpu.Arch.x86_64,
            .os_tag = Target.Os.Tag.freestanding,
            .abi = Target.Abi.none,
        });
    kernel.setOutputDir(".");
    kernel.install();
    kernel.step.dependOn(&uefi_bootloader.step);

    const run_step = b.addSystemCommand(cmd);

    const run_command = b.step("run", "Run the kernel");
    run_command.dependOn(&uefi_bootloader.step);
    run_command.dependOn(&kernel.step);
    run_command.dependOn(&run_step.step);

    const debug_cmd = &[_][]const u8
    {
        "qemu-system-x86_64",
        "-bios",
        "ovmf/OVMF_CODE-pure-efi.fd",
        "-hdd",
        "fat:rw:.",
        "-serial",
        "stdio",
        "-S",
        "-s",
    };

    const debug_step = b.addSystemCommand(debug_cmd);

    const debug_command = b.step("debug", "Debug the kernel");
    debug_command.dependOn(&uefi_bootloader.step);
    debug_command.dependOn(&kernel.step);
    debug_command.dependOn(&debug_step.step);
}
