const std = @import("std");
const Builder = std.build.Builder;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const builtin = std.builtin;

pub fn build(b: *std.build.Builder) void
{
    const exe = b.addExecutable("bootx64", "src/main.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setTarget(CrossTarget
        {
            .cpu_arch = Target.Cpu.Arch.x86_64,
            .os_tag = Target.Os.Tag.uefi,
            .abi = Target.Abi.msvc,
        });
    exe.force_pic = true;
    exe.setOutputDir("efi/boot");
    exe.install();

    const cmd = &[_][]const u8
    {
        "qemu-system-x86_64",
        "-bios",
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd",
        "-hdd",
        "fat:rw:.",
        "-serial",
        "stdio",
    };

    const run_step = b.addSystemCommand(cmd);

    const run_command = b.step("run", "Run the kernel");
    run_command.dependOn(&run_step.step);

    //const run_cmd = exe.run();
    //run_cmd.step.dependOn(b.getInstallStep());
    //if (b.args) |args| {
        //run_cmd.addArgs(args);
    //}

    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);
}
