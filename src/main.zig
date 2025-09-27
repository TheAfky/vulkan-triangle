const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");
const VulkanContext = @import("vulkan/context.zig").VulkanContext;

const application_name: [*:0]const u8 = "Vulkan Trinagle";
const engine_name: [*:0]const u8 = "Engine";
const window_width: u32 = 1080;
const window_height: u32 = 720;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
    zglfw.windowHint(zglfw.Resizable, 0);

    const window = try zglfw.createWindow(window_width, window_height, application_name, null, null);
    defer zglfw.destroyWindow(window);

    const vulkan_context = try VulkanContext.init(allocator, application_name, engine_name, window);
    defer vulkan_context.deinit();

    while (!zglfw.windowShouldClose(window)) {
        zglfw.pollEvents();
    }
}
