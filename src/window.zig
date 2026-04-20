const std = @import("std");
const vk = @import("vulkan");
const zglfw = @import("zglfw");

pub const WindowError = error{ WindowCreationFailed, SurfaceCreationFailed };
pub const FramebufferSize = struct{ width: u32, height: u32 };

extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

pub const Window = struct {
    const Self = @This();

    handle: *zglfw.Window,
    framebuffer_resized: bool,
    last_width: u32,
    last_height: u32,

    pub fn init(width: u32, height: u32, title: []const u8) !Self {
        try zglfw.init();

        zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
        zglfw.windowHint(zglfw.Resizable, 1);

        const handle = zglfw.createWindow(@intCast(width), @intCast(height), @ptrCast(title), null, null) catch return WindowError.WindowCreationFailed;

        return .{
            .handle = handle,
            .framebuffer_resized = false,
            .last_width = width,
            .last_height = height,
        };
    }

    pub fn deinit(self: Self) void {
        zglfw.destroyWindow(self.handle);
        zglfw.terminate();
    }

    pub fn getFramebufferSize(self: Self) !FramebufferSize {
        var widht: c_int = 0;
        var height: c_int = 0;
        zglfw.getFramebufferSize(self.handle, &widht, &height);
        return .{ .width = @intCast(widht), .height = @intCast(height) };
    }

    pub fn isMinimized(self: Self) !bool {
        const size = try self.getFramebufferSize();
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

    pub fn pollEvents(self: *Self) void {
        const size = try self.getFramebufferSize();

        if (size.width != self.last_width or size.height != self.last_height) {
            self.last_width = size.width;
            self.last_height = size.height;
            self.framebuffer_resized = true;
        }

        zglfw.waitEventsTimeout(0.001);
    }

    pub fn createVulkanSurface(self: Self, raw_instance: vk.Instance) !vk.SurfaceKHR {
        var raw_surface: u64 = 0;
        if (zglfw.createWindowSurface(@intFromEnum(raw_instance), self.handle, null, &raw_surface) != zglfw.VkResult.success) {
            return WindowError.SurfaceCreationFailed;
        }
        return @enumFromInt(raw_surface);
    }

    pub fn getSurfaceExtent(self: Self, surface_capabilities: vk.SurfaceCapabilitiesKHR) !vk.Extent2D {
        // if not 0xFFFF_FFFF limit the size of the surface
        if (surface_capabilities.current_extent.width != 0xFFFF_FFFF) {
            return surface_capabilities.current_extent;
        } else {
            const size = try self.getFramebufferSize();
            return .{
                .width = std.math.clamp(size.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
                .height = std.math.clamp(size.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
            };
        }
    }

    pub fn getInstanceExtensions(self: Self) ![]const [*:0]const u8 {
        _ = self;
        var glfw_extensions_count: u32 = 0;
        const glfw_extensions = zglfw.getRequiredInstanceExtensions(&glfw_extensions_count) orelse return error.MissingGLFWExtensions;
        return @ptrCast(glfw_extensions[0..glfw_extensions_count]);
    }

    pub fn getInstanceProcAddress(self: Self) *const fn (vk.Instance, [*:0]const u8) callconv(.c) vk.PfnVoidFunction {
        _ = self;
        return glfwGetInstanceProcAddress;
    }
};
