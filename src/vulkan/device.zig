const std = @import("std");

const vk = @import("vulkan");
const zglfw = @import("zglfw");

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const DeviceCandidate = struct {
    physical_device: vk.PhysicalDevice,
    score: u8,
    physical_device_properties: vk.PhysicalDeviceProperties,
    physical_device_features: vk.PhysicalDeviceFeatures,
    graphics_family: u32,
    presentation_family: u32,
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: vk.DeviceProxyWithCustomDispatch(vk.DeviceDispatch), family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

pub const Device = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    base_wrapper: vk.BaseWrapper,

    handle: vk.DeviceProxyWithCustomDispatch(vk.DeviceDispatch),
    physical_device: vk.PhysicalDevice,
    graphics_queue: Queue,
    presentation_queue: Queue,

    pub fn init(allocator: std.mem.Allocator, base_wrapper: vk.BaseWrapper, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), surface: vk.SurfaceKHR) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.base_wrapper = base_wrapper;

        const device_candidate = try pickPhysicalDevice(allocator, instance, surface);

        const priority = [_]f32{1};
        const device_queue_create_info = [_]vk.DeviceQueueCreateInfo{ .{
            .s_type = vk.StructureType.device_queue_create_info,
            .p_next = null,
            .queue_family_index = device_candidate.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        }, .{
            .s_type = vk.StructureType.device_queue_create_info,
            .p_next = null,
            .queue_family_index = device_candidate.presentation_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        } };

        const queue_count: u32 = if (device_candidate.graphics_family == device_candidate.presentation_family) 1 else 2;

        const device_create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = queue_count,
            .p_queue_create_infos = &device_queue_create_info,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
        };

        const raw_device = try instance.createDevice(device_candidate.physical_device, &device_create_info, null);

        const device_wrapper = try allocator.create(vk.DeviceWrapper);
        device_wrapper.* = vk.DeviceWrapper.load(raw_device, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        
        self.physical_device = device_candidate.physical_device;
        self.handle = vk.DeviceProxy.init(raw_device, device_wrapper);

        self.graphics_queue = Queue.init(self.handle, device_candidate.graphics_family);
        _ = self.graphics_queue;
        self.presentation_queue = Queue.init(self.handle, device_candidate.presentation_family);
        _ = self.presentation_queue;

        return self;
    }
    pub fn deinit(self: Self) void {
        self.handle.destroyDevice(null);
        self.allocator.destroy(self.handle.wrapper);
    }
};

fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), surface: vk.SurfaceKHR) !DeviceCandidate {
    const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_devices);

    var device_candidates: std.ArrayList(DeviceCandidate) = .empty;
    defer device_candidates.deinit(allocator);

    for (physical_devices) |physical_device| {
        if (try checkSuitable(allocator, instance, physical_device, surface)) |device_candidate| {
            try device_candidates.append(allocator, device_candidate);
        }
    }

    if (device_candidates.items.len > 0) {
        var best_candidate: DeviceCandidate = device_candidates.items[0];
        for (device_candidates.items) |device_candidate| {
            if (device_candidate.score > best_candidate.score) {
                best_candidate = device_candidate;
            }
        }
        return best_candidate;
    } else {
        return error.NoSuitablePhysicalDevice;
    }
}

fn checkSuitable(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?DeviceCandidate {
    const physical_device_properties = instance.getPhysicalDeviceProperties(physical_device);
    const physical_device_features = instance.getPhysicalDeviceFeatures(physical_device);

    if (!try checkExtensionSupport(allocator, instance, physical_device)) return null;
    if (!try checkSurfaceSupport(instance, physical_device, surface)) return null;
    if (!try checkFeaturesSupport(physical_device_features)) return null;

    var score: u8 = 0;
    if (physical_device_properties.device_type == vk.PhysicalDeviceType.discrete_gpu) {
        score += 1;
    }

    const queue_family_properties = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);
    defer allocator.free(queue_family_properties);

    var graphics_family: ?u32 = null;
    var presentation_family: ?u32 = null;

    for (queue_family_properties, 0..) |queue_family_property, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and queue_family_property.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (presentation_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(physical_device, family, surface)) == .true) {
            presentation_family = family;
        }

        return .{
            .physical_device = physical_device,
            .score = score,
            .physical_device_properties = physical_device_properties,
            .physical_device_features = physical_device_features,
            .graphics_family = graphics_family.?,
            .presentation_family = presentation_family.?,
        };
    }

    return null;
}

fn checkExtensionSupport(allocator: std.mem.Allocator, instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), physical_device: vk.PhysicalDevice) !bool {
    const device_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device, null, allocator);
    defer allocator.free(device_extensions);

    for (required_device_extensions) |required_extension| {
        for (device_extensions) |device_extension| {
            if (std.mem.eql(u8, std.mem.span(required_extension), std.mem.sliceTo(&device_extension.extension_name, 0)))
                break;
        } else {
            return false;
        }
    }

    return true;
}

fn checkSurfaceSupport(instance: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch), physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkFeaturesSupport(device_features: vk.PhysicalDeviceFeatures) !bool {
    if (device_features.geometry_shader == vk.Bool32.true) return true;

    return false;
}
