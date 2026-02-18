const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

pub const WindowError = error{
    WindowCreationFailed,
};

pub const Window = struct {
    const Self = @This();

    handle: *zglfw.Window,

    pub fn init(window_width: u32, window_height: u32, application_name: [*:0]const u8) !Self {
        zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
        zglfw.windowHint(zglfw.Resizable, 1);

        const handle = zglfw.createWindow(
            @intCast(window_width),
            @intCast(window_height),
            application_name,
            null, null
        ) catch return WindowError.WindowCreationFailed;

        return Self{
            .handle = handle,
        };
    }
    
    pub fn deinit(self: Self) void {
        zglfw.destroyWindow(self.handle);
    }

    pub fn isMinimized(self: Self) bool {
        var width: c_int = 0;
        var height: c_int = 0;
        zglfw.getFramebufferSize(self.handle, &width, &height);
        return width <= 0 and height <= 0;
    }

    pub fn getSurfaceExtent(self: Self, surface_capabilities: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
        // if not 0xFFFF_FFFF limit the size of the surface
        if (surface_capabilities.current_extent.width != 0xFFFF_FFFF) {
            return surface_capabilities.current_extent;
        } else {
            var width: c_int = 0;
            var height: c_int = 0;
            zglfw.getFramebufferSize(self.handle, &width, &height);

            const w: u32 = @intCast(width);
            const h: u32 = @intCast(height);
            return .{
                .width = std.math.clamp(w, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
                .height = std.math.clamp(h, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
            };
        }
    }

    pub fn shouldClose(self: Self) bool {
        return zglfw.windowShouldClose(self.handle);
    }

    pub fn setWindowSizeCallback(
        self: Window,
        callback: *const fn (window: *zglfw.Window, width: c_int, height: c_int) callconv(.c) void,
    ) void {
        _ = zglfw.setWindowSizeCallback(self.handle, callback);
    }
};
