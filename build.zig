const std = @import("std");

pub fn build(b: *std.Build) void {
    const use_system_glfw = b.option(bool, "use-system-glfw", "Link to system GLFW instead of building glfw.zig") orelse false;

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

    // GLFW c build dependency
    const glfw = b.dependency("glfw_zig", .{
        .target   = target,
        .optimize = optimize,
    });
    if (use_system_glfw) {
        exe.linkSystemLibrary("glfw");
    } else {
        exe.linkLibrary(glfw.artifact("glfw"));
    }

    // zGLFW dependency
    const zglfw = b.dependency("zglfw", .{
        .target   = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zglfw", zglfw.module("glfw"));

    // Vulkan dependency
    const vulkan = b.dependency("vulkan", .{
        .target   = b.graph.host,
        .optimize = optimize,
        .registry = b.path("registry/vk.xml"),
    });
    exe.root_module.addImport("vulkan", vulkan.module("vulkan-zig"));

    // "zig build run"
    const run_step = b.step("run", "Run the app");
    const run_cmd  = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
