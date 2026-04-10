const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const Window = @import("window/window.zig").Window;
const WindowBackend = @import("window/window.zig").WindowBackend;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;
const Renderer = @import("renderer/renderer.zig").Renderer;
const ImGui = @import("ui/imgui.zig").Imgui;
const Mesh = @import("renderer/resources/mesh.zig").Mesh;
const Vertex = @import("renderer/resources/vertex.zig").Vertex;

pub const c = @cImport({ @cInclude("dcimgui.h"); });

const application_name = "Vulkan Triangle";
const engine_name = "Engine";
const window_width: u32 = 960;
const window_height: u32 = 640;

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    var window = try Window.init(WindowBackend.Glfw, window_width, window_height, application_name);
    window.registerCallbacks();
    defer window.deinit();

    var renderer = try Renderer.init(allocator, &window);
    defer renderer.deinit();

    var triangle_mesh = try Mesh.create(
        &renderer.context.device,
        &vertices,
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    defer triangle_mesh.destroy(&renderer.context.device);

    var imgui = try ImGui.init(&renderer.context, &window);
    defer imgui.deinit();

    var draw_trinagle = false;
    while (!window.shouldClose()) {
        if (window.isMinimized()) continue;
        window.pollEvents();

        const command_buffer = try renderer.beginFrame() orelse continue;
        imgui.beginFrame();
        c.ImGui_SetNextWindowPos(.{ .x = 0, .y = 0 }, 0);
        _ = c.ImGui_Begin("Main", 1,
            c.ImGuiWindowFlags_NoDecoration |
                c.ImGuiWindowFlags_NoMove |
                c.ImGuiWindowFlags_NoBackground
        );

        c.ImGui_Text("Carzy Triangle");
        if (c.ImGui_Button(if (draw_trinagle) "Hide triangle" else "Show triangle"))
            draw_trinagle = !draw_trinagle;

        if (draw_trinagle) {
            renderer.submit(.{
                .mesh = triangle_mesh,
            });
        }
        c.ImGui_End();

        imgui.endFrame(command_buffer);
        renderer.render(command_buffer);
        try renderer.endFrame(command_buffer);
    }
}
