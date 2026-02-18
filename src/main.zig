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

    zglfw.setWindowUserPointer(window.handle, &vulkan);
    window.setWindowSizeCallback(framebufferResizeCallback);

    while (!window.shouldClose()) {
        zglfw.waitEventsTimeout(0.001);

        const command_buffer = try vulkan.startFrame() orelse continue;
        vulkan.device.handle.cmdDraw(command_buffer, 3, 1, 0, 0);

        vulkan.imgui.beginFrame();
        c.ImGui_Text("carzy");
        const clicked = c.ImGui_Button("Test");
        if (clicked)
            std.debug.print("Button clicked\n", .{});

        vulkan.imgui.endFrame(command_buffer);

        try vulkan.endFrame(command_buffer);
    }
}
