const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none, // WebAssembly doesn't have a traditional ABI
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const exe = b.addExecutable(.{
        .name = "chip",
        .root_module = b.createModule(.{
            .root_source_file = b.path("chip.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.export_table = true;
    exe.rdynamic = true;
    exe.entry = .disabled;

    const install_step = b.addUpdateSourceFiles();
    install_step.addCopyFileToSource(exe.getEmittedBin(), "dist/chip.wasm");
    b.getInstallStep().dependOn(&install_step.step);

    // const mode = b.standardReleaseOptions();
    // const target: std.zig.CrossTarget = .{ .cpu_arch = .wasm32, .os_tag = .freestanding };

    // const lib = b.addSharedLibrary("chip_zig", "src/lib.zig", .unversioned);
    // lib.setTarget(target);
    // lib.setBuildMode(mode);
    // lib.addPackagePath("wokwi", "wokwi/wokwi_chip_ll.zig");
    // lib.export_table = true;
    // lib.install();
}
