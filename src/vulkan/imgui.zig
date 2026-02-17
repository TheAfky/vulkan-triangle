const std = @import("std");
const vk = @import("vulkan");
const zglfw = @import("zglfw");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_glfw.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

const Instance = @import("instance.zig").Instance;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const Window = @import("../window/window.zig").Window;

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

fn imguiLoader(name: [*c]const u8, user_data: ?*anyopaque) callconv(.c) c.PFN_vkVoidFunction {
    if (user_data == null) return null;

    const instance: *vk.Instance = @ptrCast(@alignCast(user_data.?));
    return glfwGetInstanceProcAddress(instance.*, name);
}

pub const Imgui = struct {
    const Self = @This();

    device: Device,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(instance: Instance, device: Device, swapchain: Swapchain, render_pass: vk.RenderPass, window: Window) !Self {
        _ = c.ImGui_CreateContext(null);
        // const io = c.ImGui_GetIO();
        // io.*.ConfigFlags |= cimgui.ImGuiConfigFlags_DockingEnable;

        const pool_sizes = [_]vk.DescriptorPoolSize{
            .{ .type = .sampler, .descriptor_count = 1000 },
            .{ .type = .combined_image_sampler, .descriptor_count = 1000 },
            .{ .type = .sampled_image, .descriptor_count = 1000 },
            .{ .type = .storage_image, .descriptor_count = 1000 },
            .{ .type = .uniform_buffer, .descriptor_count = 1000 },
        };

        const descriptor_pool = try device.handle.createDescriptorPool(&.{
            .flags = .{ .free_descriptor_set_bit = true },
            .max_sets = 1000,
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = &pool_sizes
        }, null);

        _ = c.cImGui_ImplGlfw_InitForVulkan(@ptrCast(window.handle), true);

        const api_version: u32 =
            (@as(u32, vk.API_VERSION_1_3.major) << 22) |
            (@as(u32, vk.API_VERSION_1_3.minor) << 12) |
            (@as(u32, vk.API_VERSION_1_3.patch));
        var init_info: c.ImGui_ImplVulkan_InitInfo = .{
            .Instance = @ptrFromInt(@intFromEnum(instance.handle.handle)),
            .PhysicalDevice = @ptrFromInt(@intFromEnum(device.physical_device)),
            .Device = @ptrFromInt(@intFromEnum(device.handle.handle)),
            .QueueFamily = device.graphics_queue.family,
            .Queue = @ptrFromInt(@intFromEnum(device.graphics_queue.handle)),
            .DescriptorPool = @ptrFromInt(@intFromEnum(descriptor_pool)),
            .MinImageCount = 2,
            .ImageCount = @intCast(swapchain.swapchain_images.len),
            .ApiVersion = api_version,
            .PipelineInfoMain = .{ .RenderPass = @ptrFromInt(@intFromEnum(render_pass)) }
        };

        if (!c.cImGui_ImplVulkan_LoadFunctionsEx(api_version, imguiLoader, @ptrCast(@constCast(&instance.handle.handle))))
            return error.ImGuiVulkanLoadFailure;

        _ = c.cImGui_ImplVulkan_Init(&init_info);
        return Self{
            .device = device,
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

    pub fn deinit(self: *Self) void {
        c.cImGui_ImplVulkan_Shutdown();
        c.cImGui_ImplGlfw_Shutdown();
        c.ImGui_DestroyContext(null);
        self.device.handle.destroyDescriptorPool(self.descriptor_pool, null);
    }
};
