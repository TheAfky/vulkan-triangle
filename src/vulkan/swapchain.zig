const std = @import("std");
const vk = @import("vulkan");

const Device = @import("device.zig").Device;

pub const Swapchain = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch),
    device: Device,
    extent: vk.Extent2D,
    
    swapchain: vk.SwapchainKHR,
    
    
    pub fn init(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), device: Device, surface: vk.SurfaceKHR, extent: vk.Extent2D) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.instance = instance;
        self.device = device;
        self.extent = extent;

        const surface_capabilities_khr = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, surface);
        _ = surface_capabilities_khr;
        
        self.swapchain = vk.SwapchainKHR.null_handle;

        return self;
    }
    
    pub fn deinit(self: Self) void {
        _ = self;
    }
};