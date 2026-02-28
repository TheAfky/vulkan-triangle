const std = @import("std");
const vk = @import("vulkan");
const zglfw = @import("zglfw");
const vulkan = @import("../vulkan/context.zig");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_glfw.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

const Window = @import("../window/window.zig").Window;

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

fn imguiLoader(name: [*c]const u8, user_data: ?*anyopaque) callconv(.c) c.PFN_vkVoidFunction {
    if (user_data == null) return null;

    const instance: *vk.Instance = @ptrCast(@alignCast(user_data.?));
    return glfwGetInstanceProcAddress(instance.*, name);
}

pub const Imgui = struct {
    const Self = @This();

    io: [*c]c.ImGuiIO,
    device: vulkan.Device,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(vulkan_context: vulkan.VulkanContext, window: *Window) !Self {
        _ = c.ImGui_CreateContext(null);
        const io = c.ImGui_GetIO();
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
            .p_pool_sizes = &pool_sizes
        }, null);

        _ = c.cImGui_ImplGlfw_InitForVulkan(@ptrCast(window.Glfw.handle), true);

        const api_version: u32 =
            (@as(u32, vk.API_VERSION_1_3.major) << 22) |
            (@as(u32, vk.API_VERSION_1_3.minor) << 12) |
            (@as(u32, vk.API_VERSION_1_3.patch));
        var init_info: c.ImGui_ImplVulkan_InitInfo = .{
            .Instance = @ptrFromInt(@intFromEnum(vulkan_context.instance.handle.handle)),
            .PhysicalDevice = @ptrFromInt(@intFromEnum(vulkan_context.device.physical_device)),
            .Device = @ptrFromInt(@intFromEnum(vulkan_context.device.handle.handle)),
            .QueueFamily = vulkan_context.device.graphics_queue.family,
            .Queue = @ptrFromInt(@intFromEnum(vulkan_context.device.graphics_queue.handle)),
            .DescriptorPool = @ptrFromInt(@intFromEnum(descriptor_pool)),
            .MinImageCount = 2,
            .ImageCount = @intCast(vulkan_context.swapchain.swapchain_images.len),
            .ApiVersion = api_version,
            .PipelineInfoMain = .{ .RenderPass = @ptrFromInt(@intFromEnum(vulkan_context.pipeline.render_pass)) }
        };

        if (!c.cImGui_ImplVulkan_LoadFunctionsEx(api_version, imguiLoader, @ptrCast(@constCast(&vulkan_context.instance.handle.handle))))
            return error.ImGuiVulkanLoadFailure;

        _ = c.cImGui_ImplVulkan_Init(&init_info);
        c.ImGui_StyleColorsClassic(null);

        const style = c.ImGui_GetStyle();

        style.*.FontScaleDpi = 1.5;
        c.ImGuiStyle_ScaleAllSizes(style, 1.5);

        return Self{
            .io = io,
            .device = vulkan_context.device,
            .descriptor_pool = descriptor_pool,
        };
    }

    pub fn beginFrame(self: Self) void {
        _ = self;
        c.cImGui_ImplVulkan_NewFrame();
        c.cImGui_ImplGlfw_NewFrame();
        c.ImGui_NewFrame();
    }

    pub fn endFrame(self: Self, command_buffer: vk.CommandBuffer) void {
        _ = self;
        c.ImGui_Render();
        const draw_data = c.ImGui_GetDrawData();
        c.cImGui_ImplVulkan_RenderDrawData(draw_data, @ptrFromInt(@intFromEnum(command_buffer)));
    }

    pub fn deinit(self: Self) void {
        self.device.handle.deviceWaitIdle() catch {};

        c.cImGui_ImplVulkan_Shutdown();
        c.cImGui_ImplGlfw_Shutdown();
        c.ImGui_DestroyContext(null);
        self.device.handle.destroyDescriptorPool(self.descriptor_pool, null);
    }
};
