const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const GlfwWindow = @import("platform/zglfw.zig").GlfwWindow;

pub const WindowError = error{
    WindowCreationFailed,
    SurfaceCreationFailed
};

pub const FramebufferSize = struct {
    width: u32,
    height: u32,
};

pub const WindowBackend = enum {
    Glfw
};

pub const Window = union(enum) {
    const Self = @This();

    Glfw: GlfwWindow,

    pub fn init(comptime backend: WindowBackend, width: u32, height: u32, title: []const u8) !Self {
        return switch (backend) {
            .Glfw => .{ .Glfw = try GlfwWindow.init(width, height, title) },
        };
    }

    pub fn deinit(self: Self) void {
        switch (self) {
            .Glfw => |w| w.deinit(),
        }
    }

    pub fn registerCallbacks(self: *Self) void {
        return switch (self.*) {
            .Glfw => self.Glfw.registerCallbacks()
        };
    }

    pub fn getFramebufferSize(self: Self) FramebufferSize {
        return switch (self) {
            .Glfw => |w| w.getFramebufferSize(),
        };
    }

    pub fn isMinimized(self: Self) bool {
        return switch (self) {
            .Glfw => |w| w.isMinimized(),
        };
    }

    pub fn shouldClose(self: Self) bool {
        return switch (self) {
            .Glfw => |w| w.shouldClose(),
        };
    }

    pub fn consumeResize(self: *Self) bool {
        return switch (self.*) {
            .Glfw => self.Glfw.consumeResize()
        };
    }

    pub fn pollEvents(self: Self) void {
        switch (self) {
            .Glfw => |w| w.pollEvents(),
        }
    }

    pub fn createVulkanSurface(self: Self, instance: vk.Instance) !vk.SurfaceKHR {
        return switch (self) {
            .Glfw => |w| w.createVulkanSurface(instance),
        };
    }

    pub fn getSurfaceExtent(self: Self, surface_capabilities: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
        return switch (self) {
            .Glfw => |w| w.getSurfaceExtent(surface_capabilities),
        };
    }
};
