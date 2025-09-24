const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target & optimization options
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "vulkan_triangle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    //exe.linkSystemLibrary("glfw");
    const glfw = b.dependency("glfw_zig", .{
        .target   = target,
        .optimize = optimize,
    });
    exe.linkLibrary(glfw.artifact("glfw"));

    // zGLFW dependency
    const zglfw = b.dependency("zglfw", .{
        .target   = target,
        .optimize = optimize,
    }).module("glfw");

    exe.root_module.addImport("zglfw", zglfw);

    // Vulkan dependency
    const vulkan = b.dependency("vulkan", .{
        .target   = b.graph.host,
        .optimize = optimize,
        .registry = b.path("registry/vk.xml"),
    }).module("vulkan-zig");

    exe.root_module.addImport("vulkan", vulkan);

    // "zig build run"
    const run_step = b.step("run", "Run the app");
    const run_cmd  = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
