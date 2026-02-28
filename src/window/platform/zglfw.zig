const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const WindowError = @import("../window.zig").WindowError;
const FramebufferSize = @import("../window.zig").FramebufferSize;

fn framebufferResizeCallback(
    window: *zglfw.Window,
    width: c_int,
    height: c_int
) callconv(.c) void {
    if (width <= 0 or height <= 0) return;

    const ctx_ptr = zglfw.getWindowUserPointer(window);
    if (ctx_ptr == null) return;

    const glfw_window: *GlfwWindow = @ptrCast(@alignCast(ctx_ptr.?));
    glfw_window.framebuffer_resized = true;
}

pub const GlfwWindow = struct {
    const Self = @This();

    handle: *zglfw.Window,
    framebuffer_resized: bool,

    pub fn init(width: u32, height: u32, title: []const u8) !Self {
        zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
        zglfw.windowHint(zglfw.Resizable, 1);

        const handle = zglfw.createWindow(@intCast(width), @intCast(height), @ptrCast(title), null, null) catch return WindowError.WindowCreationFailed;

        return .{
            .handle = handle,
            .framebuffer_resized = false,
        };
    }

    pub fn deinit(self: Self) void {
        zglfw.destroyWindow(self.handle);
    }

    pub fn registerCallbacks(self: *Self) void {
        zglfw.setWindowUserPointer(self.handle, @ptrCast(@constCast(self)));
        _ = zglfw.setFramebufferSizeCallback(self.handle, framebufferResizeCallback);
    }

    pub fn getFramebufferSize(self: Self) FramebufferSize {
        var widht: c_int = 0;
        var height: c_int = 0;
        zglfw.getFramebufferSize(self.handle, &widht, &height);
        return .{ .width = @intCast(widht), .height = @intCast(height) };
    }

    pub fn isMinimized(self: Self) bool {
        const size = self.getFramebufferSize();
        return size.width <= 0 and size.height <= 0;
    }

    pub fn shouldClose(self: Self) bool {
        return zglfw.windowShouldClose(self.handle);
    }

    pub fn consumeResize(self: *Self) bool {
        if (self.framebuffer_resized) {
            self.framebuffer_resized = false;
            return true;
        }
        return false;
    }

    pub fn pollEvents(self: Self) void {
        _ = self;
        zglfw.waitEventsTimeout(0.001);
    }

    pub fn createVulkanSurface(self: Self, raw_instance: vk.Instance) !vk.SurfaceKHR {
        var raw_surface: u64 = 0;
        if (zglfw.createWindowSurface(@intFromEnum(raw_instance), self.handle, null, &raw_surface) != zglfw.VkResult.success) {
            return WindowError.SurfaceCreationFailed;
        }
        return @enumFromInt(raw_surface);
    }

    pub fn getSurfaceExtent(self: Self, surface_capabilities: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
        // if not 0xFFFF_FFFF limit the size of the surface
        if (surface_capabilities.current_extent.width != 0xFFFF_FFFF) {
            return surface_capabilities.current_extent;
        } else {
            const size = self.getFramebufferSize();
            return .{
                .width = std.math.clamp(size.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
                .height = std.math.clamp(size.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
            };
        }
    }
};
