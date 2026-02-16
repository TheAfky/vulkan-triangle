const std = @import("std");
const vk = @import("vulkan");

const Device = @import("device.zig").Device;
const Window = @import("../window/window.zig").Window;

pub const Swapchain = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch),
    surface: vk.SurfaceKHR,
    device: Device,
    
    extent: vk.Extent2D,
    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    handle: vk.SwapchainKHR,

    swapchain_images: []SwapchainImage,
    
    pub fn init(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), device: Device, surface: vk.SurfaceKHR, window: Window) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.instance = instance;
        self.surface = surface;
        self.device = device;
        
        const surface_capabilities_khr = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, surface);
        self.extent = getSurfaceExtent(surface_capabilities_khr, window);
        
        self.surface_format = try findSurfaceFormat(self.allocator, self.instance, self.surface, self.device);
        self.present_mode = try findPresentMode(self.allocator, self.instance, self.surface, self.device);

        var image_count = surface_capabilities_khr.min_image_count + 1;
        // 0 means no maximum
        if (surface_capabilities_khr.max_image_count > 0 and image_count > surface_capabilities_khr.max_image_count) {
            image_count = surface_capabilities_khr.max_image_count;
        }

        const queue_family_indicies = [_]u32{ self.device.graphics_queue.family, self.device.presentation_queue.family };
        const sharing_mode: vk.SharingMode = if (self.device.graphics_queue.family != self.device.presentation_queue.family)
            .concurrent
        else
            .exclusive;

        const create_info = vk.SwapchainCreateInfoKHR{
            .surface = surface,
            .min_image_count = image_count,
            .image_format = self.surface_format.format,
            .image_color_space = self.surface_format.color_space,
            .image_extent = self.extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = queue_family_indicies.len,
            .p_queue_family_indices = &queue_family_indicies,
            .pre_transform = surface_capabilities_khr.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = self.present_mode,
            .clipped = .true,
            .old_swapchain = vk.SwapchainKHR.null_handle
        };
        
        self.handle = try self.device.handle.createSwapchainKHR(&create_info, null);
        errdefer self.device.handle.destroySwapchainKHR(self.handle, null);

        self.swapchain_images = try initSwapchainImages(allocator, self.device, self, self.surface_format.format);
        errdefer {
            for (self.swapchain_images) |swapchain_image| swapchain_image.deinit();
            allocator.free(self.swapchain_images);
        }
        
        return self;
    }
    
    pub fn deinit(self: Self) void {
        for (self.swapchain_images) |swapchain_image| swapchain_image.deinit(self.device);
        self.allocator.free(self.swapchain_images);
        self.device.handle.destroySwapchainKHR(self.handle, null);
    }
};

pub const SwapchainImage = struct {
    const Self = @This();

    image: vk.Image,
    image_view: vk.ImageView,

    pub fn init(image: vk.Image, device: Device, format: vk.Format) !Self {
        var self: Self = undefined;

        self.image = image;

        const create_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            }
        };

        self.image_view = try device.handle.createImageView(&create_info, null);
        errdefer device.handle.destroyImageView(self.image_view, null);

        return self;
    }
    pub fn deinit(self: Self, device: Device) void {
        device.handle.destroyImageView(self.image_view, null);
    }
};

fn initSwapchainImages(allocator: std.mem.Allocator, device: Device, swapchain: Swapchain, format: vk.Format) ![]SwapchainImage {
    const images = try device.handle.getSwapchainImagesAllocKHR(swapchain.handle, allocator);
    defer allocator.free(images);

    const swap_images = try allocator.alloc(SwapchainImage, images.len);
    errdefer allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |swapchan_image| swapchan_image.deinit(device);

    for (images) |image| {
        swap_images[i] = try SwapchainImage.init(image, device, format);
        i += 1;
    }

    return swap_images;
}

fn findSurfaceFormat(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), surface: vk.SurfaceKHR, device: Device) !vk.SurfaceFormatKHR {
    const surface_formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(device.physical_device, surface, allocator);
    defer allocator.free(surface_formats);

    const preferred_surface_formats = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    for (surface_formats) |surface_format| {
        if (std.meta.eql(surface_format, preferred_surface_formats)) {
            return preferred_surface_formats;
        }
    }

    return surface_formats[0];
}

fn findPresentMode(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), surface: vk.SurfaceKHR, device: Device) !vk.PresentModeKHR {
    const present_modes = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(device.physical_device, surface, allocator);
    defer allocator.free(present_modes);

    const preferred_present_mode: vk.PresentModeKHR = .mailbox_khr;

    for (present_modes) |present_mode| {
        if (present_mode == preferred_present_mode) {
            return present_mode;
        }
    }

    return .fifo_khr;
}

fn getSurfaceExtent(surface_capabilities: vk.SurfaceCapabilitiesKHR, window: Window) vk.Extent2D {
    // if not 0xFFFF_FFFF limit the size of the surface
    if (surface_capabilities.current_extent.width != 0xFFFF_FFFF) {
        return surface_capabilities.current_extent;
    } else {
        return .{
            .width = std.math.clamp(window.extent.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
            .height = std.math.clamp(window.extent.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
        };
    }
}