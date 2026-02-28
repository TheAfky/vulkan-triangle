const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const Window = @import("window/window.zig").Window;
const WindowBackend = @import("window/window.zig").WindowBackend;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;

pub const c = @cImport({ @cInclude("dcimgui.h"); });

const application_name = "Vulkan Triangle";
const engine_name = "Engine";
const window_width: u32 = 960;
const window_height: u32 = 640;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    var window = try Window.init(WindowBackend.Glfw, window_width, window_height, application_name);
    window.registerCallbacks();
    defer window.deinit();

    var vulkan = try VulkanContext.init(allocator, application_name, engine_name, &window);
    defer vulkan.deinit();

    var draw_trinagle = false;
    while (!window.shouldClose()) {
        if (window.isMinimized()) continue;
        window.pollEvents();

        const command_buffer = try vulkan.startFrame() orelse continue;

        vulkan.imgui.beginFrame();
        c.ImGui_SetNextWindowPos(.{ .x = 0, .y = 0 }, 0);
        _ = c.ImGui_Begin("Main", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBackground);
        c.ImGui_Text("Carzy Triangle");
        if(c.ImGui_Button(if (draw_trinagle) "Hide triangle" else "Show triangle")) draw_trinagle = !draw_trinagle;

        if (draw_trinagle)
            vulkan.device.handle.cmdDraw(command_buffer, 3, 1, 0, 0);

        c.ImGui_End();
        vulkan.imgui.endFrame(command_buffer);

        try vulkan.endFrame(command_buffer);
    }
}
