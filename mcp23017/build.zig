const std = @import("std");

pub fn build(b: *std.Build) void {
    // This is the equivalent of clang's `--target=wasm32-unknown-wasi`
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .abi = .none, // WebAssembly doesn't have a traditional ABI
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_mode = .ReleaseSmall,
    });

    const mod = b.addModule("chip_zig", .{
        .root_source_file = b.path("chip.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.install();
    //lib.setTarget(target);
    //lib.setBuildMode(mode);
    //lib.addPackagePath("wokwi", "wokwi/wokwi_chip_ll.zig");
    //lib.export_table = true;
    //lib.install();
}
