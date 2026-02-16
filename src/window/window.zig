const zglfw = @import("zglfw");
const vk = @import("vulkan");

pub const Window = struct {
    const Self = @This();
    
    handle: *zglfw.Window,
    extent: vk.Extent2D,
    
    pub fn init(window_width: u32, window_height: u32, application_name: [*:0]const u8) !Self {
        var self: Self = undefined;
        
        try zglfw.init();
        zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
        zglfw.windowHint(zglfw.Resizable, 1);
        
        self.extent = vk.Extent2D{ .width = window_width, .height = window_height };

        self.handle = try zglfw.createWindow(
            @intCast(window_width),
            @intCast(window_height),
            application_name,
            null, null
        );

        try checkExtent(&self);

        return self;
    }
    
    pub fn deinit(self: Self) void {
        zglfw.destroyWindow(self.handle);
        zglfw.terminate();
    }

    fn checkExtent(self: *Self) !void {
        var width: c_int = undefined;
        var height: c_int = undefined;
        zglfw.getFramebufferSize(self.handle, &width, &height);

        self.extent.width = @intCast(width);
        self.extent.height = @intCast(height);
    }
    
    pub fn shouldClose(self: Self) bool {
        return zglfw.windowShouldClose(self.handle);
    }
};
