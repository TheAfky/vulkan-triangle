const std = @import("std");
const vk = @import("vulkan");
const zglfw = @import("zglfw");
const Instance = @import("instance.zig").Instance;
const Device = @import("device.zig").Device;

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

pub const VulkanContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    base_wrapper: vk.BaseWrapper,

    instance_context: Instance,
    instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch),
    device_context: Device,
    device: vk.DeviceProxyWithCustomDispatch(vk.DeviceDispatch),
    surface: vk.SurfaceKHR,

    pub fn init(allocator: std.mem.Allocator, application_name: [*:0]const u8, engine_name: [*:0]const u8, window: *zglfw.Window) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.base_wrapper = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

        // Instance creation
        self.instance_context = try Instance.init(self.allocator, self.base_wrapper, application_name, engine_name);
        self.instance = self.instance_context.instance;

        // Surface creation
        self.surface = try create_surface(self.instance.handle, window);

        // Device creation
        self.device_context = try Device.init(self.allocator, self.base_wrapper, self.instance, self.surface);
        self.device = self.device_context.device;
        return self;
    }

    pub fn deinit(self: Self) void {
        self.device_context.deinit();
        self.instance.destroySurfaceKHR(self.surface, null);
        self.instance_context.deinit();
    }
};

fn create_surface(raw_instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var raw_surface: u64 = 0;
    if (zglfw.createWindowSurface(@intFromEnum(raw_instance), window, null, &raw_surface) != zglfw.VkResult.success) {
        return error.SurfaceInitFailed;
    }
    return @enumFromInt(raw_surface);
}
