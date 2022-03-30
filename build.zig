const Builder = @import("std").build.Builder;
const std = @import("std");
pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const b_opts = b.addOptions();

    const dvd = b.addExecutable("dvd", "examples/dvd.zig");
    const invaders = b.addExecutable("invaders", "examples/invaders.zig");
    const tests = b.addTest("src/box.zig");

    const example_log = b.fmt("{s}/{s}/{s}", .{ b.build_root, b.cache_root, "example.log" });
    b_opts.addOption([]const u8, "log_path", example_log);
    dvd.addOptions("build_options",b_opts);
    dvd.setTarget(target);
    dvd.setBuildMode(mode);
    dvd.addPackagePath("zbox", "src/box.zig");
    //dvd.addBuildOption([]const u8, "log_path", example_log);
    dvd.install();

    invaders.addOptions("build_options",b_opts);
    invaders.setTarget(target);
    invaders.setBuildMode(mode);
    invaders.addPackagePath("zbox", "src/box.zig");
    //invaders.linkLibC();
    //invaders.addBuildOption([]const u8, "log_path", example_log);
    invaders.install();

    tests.setTarget(target);
    tests.setBuildMode(mode);

    const dvd_cmd = dvd.run();
    dvd_cmd.step.dependOn(b.getInstallStep());

    const dvd_step = b.step("dvd", "Run bouncing DVD logo demo");
    dvd_step.dependOn(&dvd_cmd.step);

    const invaders_cmd = invaders.run();
    invaders_cmd.step.dependOn(b.getInstallStep());

    const invaders_step = b.step("invaders", "console space invaders");
    invaders_step.dependOn(&invaders_cmd.step);

    const test_step = b.step("test", "run package's test suite");
    test_step.dependOn(&tests.step);
}
