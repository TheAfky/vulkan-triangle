const std = @import("std");

const vk = @import("vulkan");
const zglfw = @import("zglfw");

pub const Instance = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    handle: vk.InstanceProxyWithCustomDispatch(vk.InstanceDispatch),
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,
    raw_instance: vk.Instance,

    pub fn init(allocator: std.mem.Allocator, base_wrapper: vk.BaseWrapper, application_name: [*:0]const u8, engine_name: [*:0]const u8) !Self {
        const application_info = vk.ApplicationInfo{
            .s_type = vk.StructureType.application_info,
            .p_next = null,
            .p_application_name = application_name,
            .p_engine_name = engine_name,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_3),
        };

        var layer_names: std.ArrayList([*:0]const u8) = .empty;
        defer layer_names.deinit(allocator);
        var extension_names: std.ArrayList([*:0]const u8) = .empty;
        defer extension_names.deinit(allocator);

        // Validation layers
        var enabled_validation_layers = false;
        if (@import("builtin").mode == std.builtin.OptimizeMode.Debug) {
            enabled_validation_layers = try enable_validation_layers(allocator, base_wrapper, &layer_names);
            if (enabled_validation_layers)
                try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);
        }

        // the following extensions are to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        try extension_names.append(allocator, vk.extensions.khr_portability_enumeration.name);
        try extension_names.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);

        // GLFW extensions
        var glfw_extensions_count: u32 = 0;
        const glfw_extensions = zglfw.getRequiredInstanceExtensions(&glfw_extensions_count) orelse return error.MissingGLFWExtensions;
        try extension_names.appendSlice(allocator, @ptrCast(glfw_extensions[0..glfw_extensions_count]));

        const create_info = vk.InstanceCreateInfo{
            .s_type = vk.StructureType.instance_create_info,
            .p_next = null,
            .p_application_info = &application_info,
            .enabled_layer_count = @intCast(layer_names.items.len),
            .pp_enabled_layer_names = layer_names.items.ptr,
            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,
            .flags = .{ .enumerate_portability_bit_khr = true },
        };

        const raw_instance = try base_wrapper.createInstance(&create_info, null);

        const instance_wrapper = try allocator.create(vk.InstanceWrapper);
        instance_wrapper.* = vk.InstanceWrapper.load(raw_instance, base_wrapper.dispatch.vkGetInstanceProcAddr.?);

        const handle = vk.InstanceProxy.init(raw_instance, instance_wrapper);

        if (enabled_validation_layers) {
            const debug_utils_messenger_create_info_ext: vk.DebugUtilsMessengerCreateInfoEXT = .{
                .message_severity = .{
                    .verbose_bit_ext = true,
                    .info_bit_ext = true,
                    .warning_bit_ext = true,
                    .error_bit_ext = true,
                },
                .message_type = .{
                    .general_bit_ext = true,
                    .validation_bit_ext = true,
                    .performance_bit_ext = true,
                },
                .pfn_user_callback = &debugUtilsMessengerCallback,
                .p_user_data = null,
            };

            const debug_messenger = try handle.createDebugUtilsMessengerEXT(&debug_utils_messenger_create_info_ext, null);

            return Self{
                .allocator = allocator,
                .handle = handle,
                .debug_messenger = debug_messenger,
                .raw_instance = raw_instance,
            };
        }

        return Self{
            .allocator = allocator,
            .handle = handle,
            .raw_instance = raw_instance,
        };
    }
    pub fn deinit(self: Self) void {
        if (self.debug_messenger != null)
            self.handle.destroyDebugUtilsMessengerEXT(self.debug_messenger.?, null);
        self.handle.destroyInstance(null);
        self.allocator.destroy(self.handle.wrapper);
    }
};

fn enable_validation_layers(allocator: std.mem.Allocator, base_wrapper: vk.BaseWrapper, layer_names: *std.ArrayList([*:0]const u8)) !bool {
    const layer_properties = try base_wrapper.enumerateInstanceLayerPropertiesAlloc(allocator);
    defer allocator.free(layer_properties);

    for (layer_properties) |layer_property| {
        if (std.mem.eql(u8, std.mem.sliceTo(&layer_property.layer_name, 0), "VK_LAYER_KHRONOS_validation")) {
            try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
            std.debug.print("Validation layers active\n", .{});
            return true;
        }
    } else {
        std.debug.print("Validation layers unavailable\n", .{});
        return false;
    }
}

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";
    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]\n{s}\n", .{ severity_str, type_str, message });

    return .false;
}
