const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const Window = @import("window/window.zig").Window;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;
const framebufferResizeCallback = @import("vulkan//context.zig").framebufferResizeCallback;

pub const c = @cImport({
    @cInclude("dcimgui.h");
});

const application_name: [*:0]const u8 = "Vulkan Triangle";
const engine_name: [*:0]const u8 = "Engine";
const window_width: u32 = 960;
const window_height: u32 = 640;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    const window = try Window.init(window_width, window_height, application_name);
    defer window.deinit();

    var vulkan = try VulkanContext.init(allocator, application_name, engine_name, window);
    defer vulkan.deinit();

    window.setWindowSizeCallback(&vulkan, framebufferResizeCallback);

    var draw_trinagle = false;
    while (!window.shouldClose()) {
        zglfw.waitEventsTimeout(0.001);

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
