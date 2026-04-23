const vk = @import("vulkan");
const cimgui = @import("cimgui");

const Window = @import("window.zig").Window;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;
const Device = @import("vulkan/device.zig").Device;

pub const Imgui = struct {
    const Self = @This();

    io: *cimgui.ImGuiIO,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(vulkan_context: *VulkanContext, window: *Window) !Self {
        _ = cimgui.ImGui_CreateContext(null);
        const io = cimgui.ImGui_GetIO();
        io.*.IniFilename = null;

        const pool_sizes = [_]vk.DescriptorPoolSize{
            .{ .type = .sampler, .descriptor_count = 1000 },
            .{ .type = .combined_image_sampler, .descriptor_count = 1000 },
            .{ .type = .sampled_image, .descriptor_count = 1000 },
            .{ .type = .storage_image, .descriptor_count = 1000 },
            .{ .type = .uniform_buffer, .descriptor_count = 1000 },
        };

        const descriptor_pool = try vulkan_context.device.handle.createDescriptorPool(&.{
            .flags = .{ .free_descriptor_set_bit = true },
            .max_sets = 1000,
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = &pool_sizes,
        }, null);
        errdefer vulkan_context.device.handle.destroyDescriptorPool(descriptor_pool, null);

        _ = cimgui.cImGui_ImplGlfw_InitForVulkan(@ptrCast(window.handle), true);
        errdefer cimgui.cImGui_ImplGlfw_Shutdown();

        const api_version = vk.makeApiVersion(0, 1, 3, 0);

        var init_info: cimgui.ImGui_ImplVulkan_InitInfo = .{
            .Instance = @ptrFromInt(@intFromEnum(vulkan_context.instance.handle.handle)),
            .PhysicalDevice = @ptrFromInt(@intFromEnum(vulkan_context.device.physical_device)),
            .Device = @ptrFromInt(@intFromEnum(vulkan_context.device.handle.handle)),
            .QueueFamily = vulkan_context.device.graphics_queue.family,
            .Queue = @ptrFromInt(@intFromEnum(vulkan_context.device.graphics_queue.handle)),
            .DescriptorPool = @ptrFromInt(@intFromEnum(descriptor_pool)),
            .MinImageCount = 2,
            .ImageCount = @intCast(vulkan_context.swapchain.swapchain_images.len),
            .ApiVersion = @as(u32, @bitCast(api_version)),
            .PipelineInfoMain = .{
                .RenderPass = @ptrFromInt(@intFromEnum(vulkan_context.pipeline.render_pass)),
            },
        };

        if (!cimgui.cImGui_ImplVulkan_LoadFunctionsEx(
            @as(u32, @bitCast(api_version)),
            imguiLoader,
            @ptrCast(&vulkan_context.instance.handle.handle),
        )) {
            return error.ImGuiVulkanLoadFailure;
        }

        if (!cimgui.cImGui_ImplVulkan_Init(&init_info)) {
            return error.ImGuiVulkanInitFailure;
        }

        // cimgui.ImGui_StyleColorsClassic(null);
        cimgui.ImGui_StyleColorsLight(null);

        const style = cimgui.ImGui_GetStyle();
        style.*.FontScaleDpi = 1.5;
        cimgui.ImGuiStyle_ScaleAllSizes(style, 1.5);

        return Self{
            .io = io,
            .descriptor_pool = descriptor_pool,
        };
    }

    pub fn beginFrame(self: Self) void {
        _ = self;
        cimgui.cImGui_ImplVulkan_NewFrame();
        cimgui.cImGui_ImplGlfw_NewFrame();
        cimgui.ImGui_NewFrame();
    }

    pub fn endFrame(self: Self, command_buffer: vk.CommandBuffer) void {
        _ = self;
        cimgui.ImGui_Render();
        const draw_data = cimgui.ImGui_GetDrawData();
        cimgui.cImGui_ImplVulkan_RenderDrawData(
            draw_data,
            @ptrFromInt(@intFromEnum(command_buffer))
        );
    }

    pub fn deinit(self: Self, device: *Device) void {
        _ = device.handle.deviceWaitIdle() catch {};

        cimgui.cImGui_ImplVulkan_Shutdown();
        cimgui.cImGui_ImplGlfw_Shutdown();
        cimgui.ImGui_DestroyContext(null);
        device.handle.destroyDescriptorPool(self.descriptor_pool, null);
    }
};

fn imguiLoader(name: [*c]const u8, user_data: ?*anyopaque) callconv(.c) cimgui.PFN_vkVoidFunction {
    const instance_ptr = user_data orelse return null;
    const instance: *vk.Instance = @ptrCast(@alignCast(instance_ptr));
    return glfwGetInstanceProcAddress(instance.*, name);
}

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
