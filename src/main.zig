const std = @import("std");
const zglfw = @import("zglfw");
const vk = @import("vulkan");

const window_width: u32 = 1080;
const window_height: u32 = 720;
const enable_validation_layers: bool = false;

const ExtensionsError = error{
    MissingGLFWExtensions,
};

const LayersError = error{
    MissingValidationLayers,
};

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(zglfw.ClientAPI, zglfw.NoAPI);
    zglfw.windowHint(zglfw.Resizable, 0);
    const window = try zglfw.createWindow(window_width, window_height, "Vulkan Triangle", null, null);
    defer zglfw.destroyWindow(window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application_info = vk.ApplicationInfo{
        .s_type = vk.StructureType.application_info,
        .p_next = null,
        .p_application_name = "Vulkan Triangle",
        .p_engine_name = "Vulkan Triangle",
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .api_version = @bitCast(vk.API_VERSION_1_2),
    };

    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(allocator);

    if (enable_validation_layers)
        try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);

    var glfw_extensions_count: u32 = 0;
    const glfw_extensions_ptr = zglfw.getRequiredInstanceExtensions(&glfw_extensions_count) orelse return ExtensionsError.MissingGLFWExtensions;

    const glfw_extensions_slice = glfw_extensions_ptr[0..glfw_extensions_count];
    try extension_names.appendSlice(allocator, glfw_extensions_slice);

    var layer_names: std.ArrayList([*:0]const u8) = .empty;
    defer layer_names.deinit(allocator);

    const vkbw = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

    var layer_count: u32 = 0;

    var result = try vkbw.enumerateInstanceLayerProperties(&layer_count, null);

    var layers_ptr = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(layers_ptr);

    result = try vkbw.enumerateInstanceLayerProperties(&layer_count, @ptrCast(layers_ptr));

    if (enable_validation_layers) {
        var validation_available = false;
        for (layers_ptr[0..layer_count]) |layer| {
            if (std.mem.eql(u8, layer.layer_name[0..27], "VK_LAYER_KHRONOS_validation")) {
                validation_available = true;
                break;
            }
        }

        if (!validation_available)
            return LayersError.MissingValidationLayers;

        try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
    } else {
        std.debug.print("Validation layers inactive", .{});
    }

    const create_info = vk.InstanceCreateInfo{
        .s_type = vk.StructureType.instance_create_info,
        .p_next = null,
        .p_application_info = &application_info,
        .pp_enabled_extension_names = extension_names.items.ptr,
        .pp_enabled_layer_names = layer_names.items.ptr,
        .enabled_extension_count = @intCast(extension_names.items.len),
        .enabled_layer_count = @intCast(layer_names.items.len),
        .flags = .{},
    };

    // Create a vulkan instance
    const inst = try vkbw.createInstance(&create_info, null);

    // Wrap the instance with the allocator
    const vkiw = try allocator.create(vk.InstanceWrapper);
    defer allocator.destroy(vkiw);

    // Load the instance wrapper functions
    vkiw.* = vk.InstanceWrapper.load(inst, vkbw.dispatch.vkGetInstanceProcAddr.?);

    // Wrap the vulkan instance with the instance wrapper functions
    const instance = vk.InstanceProxy.init(inst, vkiw);
    defer instance.destroyInstance(null);

    if (enable_validation_layers) {
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

        const debug_messenger = try instance.createDebugUtilsMessengerEXT(&debug_utils_messenger_create_info_ext, null);
        defer instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);
    }

    while (!zglfw.windowShouldClose(window)) {
        zglfw.pollEvents();
    }
}

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]\n{s}\n\n", .{ severity_str, type_str, message });

    return .false;
}
