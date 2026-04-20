const std = @import("std");

// cimgui.zig
const cimgui = @import("cimgui_zig");
const Renderer = cimgui.Renderer;
const Platform = cimgui.Platform;

fn addIncludePathsToTranslateC(translate_c: *std.Build.Step.TranslateC, lib: *std.Build.Step.Compile) void {
    for (lib.root_module.include_dirs.items) |*included| {
        switch (included.*) {
            .path => translate_c.addIncludePath(included.path),
            .config_header_step => translate_c.addConfigHeader(included.config_header_step),
            .path_system => translate_c.addSystemIncludePath(included.path_system),
            .other_step => addIncludePathsToTranslateC(translate_c, included.other_step),
            else => unreachable,
        }
    }
}

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
        _ = exe.dependsOnSystemLibrary("glfw");
    } else {
        exe.installLibraryHeaders(glfw.artifact("glfw"));
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
    const cimgui_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/cimgui.h"),
        .target = target,
        .optimize = optimize,
    });

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]Platform{.GLFW},
        .renderers = &[_]Renderer{.Vulkan},
        // .docking = true, // Default value: false
    });

    const cimgui_lib = cimgui_dep.artifact("cimgui");
    addIncludePathsToTranslateC(cimgui_translate_c, cimgui_lib);
    const cimgui_c_module = cimgui_translate_c.createModule();
    cimgui_c_module.linkLibrary(cimgui_lib);
    exe.root_module.addImport("cimgui", cimgui_c_module);

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
