const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const Window = @import("window/window.zig").Window;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;

const application_name: [*:0]const u8 = "Vulkan Triangle";
const engine_name: [*:0]const u8 = "Engine";
const window_width: u32 = 960;
const window_height: u32 = 640;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const window = try Window.init(window_width, window_height, application_name);
    defer window.deinit();
    
    const vulkan_context = try VulkanContext.init(allocator, application_name, engine_name, window);
    defer vulkan_context.deinit();
    
    while (!window.shouldClose()) {
        zglfw.pollEvents();
    }
}
