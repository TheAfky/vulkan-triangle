const std = @import("std");

// cimgui.zig
const cimgui = @import("cimgui_zig");
const Renderer = cimgui.Renderer;
const Platform = cimgui.Platform;

pub fn build(b: *std.Build) void {
    const use_system_glfw = b.option(bool, "use-system-glfw", "Link to system GLFW instead of building glfw.zig") orelse false;

    // Target & optimization options
    const target = b.standardTargetOptions(.{});
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
        .target = target,
        .optimize = optimize,
    });
    if (use_system_glfw) {
        exe.linkSystemLibrary("glfw");
    } else {
        exe.linkLibrary(glfw.artifact("glfw"));
    }

    // zGLFW dependency
    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zglfw", zglfw.module("glfw"));

    // Vulkan dependency
    const vulkan = b.dependency("vulkan", .{
        .target = b.graph.host,
        .optimize = optimize,
        .registry = b.path("registry/vk.xml"),
    });
    exe.root_module.addImport("vulkan", vulkan.module("vulkan-zig"));

    // CImgGui.zig dependency
    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]Platform{.GLFW},
        .renderers = &[_]Renderer{.Vulkan},
    });
    const cimgui_lib = cimgui_dep.artifact("cimgui");
    exe.linkLibrary(cimgui_lib);

    // Shader compilation
    const shader_dir = "src/shaders/";
    const shaders = [_][]const u8{
        "vert",
        "frag",
    };

    inline for (shaders) |shader| {
        const input = b.path(std.fmt.comptimePrint("{s}/shader.{s}", .{ shader_dir, shader }));
        const output = b.path(std.fmt.comptimePrint("{s}/{s}.spv", .{ shader_dir, shader }));

        const compile = b.addSystemCommand(&[_][]const u8{
            "glslc",
            "-o",
            output.getPath(b),
            input.getPath(b),
        });

        exe.step.dependOn(&compile.step);
    }

    // "zig build run"
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
