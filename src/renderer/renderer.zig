const std = @import("std");
const vk = @import("vulkan");

const VulkanContext = @import("../vulkan/context.zig").VulkanContext;
const Window = @import("../window/window.zig").Window;

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    context: VulkanContext,

    pub fn init(allocator: std.mem.Allocator, window: *Window) !Self {
        return Self{
            .allocator = allocator,
            .context = try VulkanContext.init(
                allocator,
                "Vulkan Triangle",
                "Engine",
                window,
            ),
        };
    }

    pub fn deinit(self: *Self) void {
        self.context.deinit();
    }

    pub fn beginFrame(self: *Self) !?vk.CommandBuffer {
        return try self.context.beginFrame();
    }

    pub fn endFrame(self: *Self, cmd: vk.CommandBuffer) !void {
        try self.context.endFrame(cmd);
    }

    pub fn drawTriangle(self: *Self, cmd: vk.CommandBuffer) void {
        self.context.device.handle.cmdDraw(cmd, 3, 1, 0, 0);
    }
};