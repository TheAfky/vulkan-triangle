const std = @import("std");
const vk = @import("vulkan");
const zglfw = @import("zglfw");

const Window = @import("window.zig").Window;
const VulkanContext = @import("vulkan/context.zig").VulkanContext;
const Device = @import("vulkan/device.zig").Device;
const c = @import("c");

pub const Imgui = struct {
    const Self = @This();

    io: *c.ImGuiIO,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(vulkan_context: *VulkanContext, window: *Window) !Self {
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
            .p_pool_sizes = &pool_sizes,
        }, null);
        errdefer vulkan_context.device.handle.destroyDescriptorPool(descriptor_pool, null);

        _ = c.cImGui_ImplGlfw_InitForVulkan(@ptrCast(window.handle), true);
        errdefer c.cImGui_ImplGlfw_Shutdown();

        const api_version = vk.makeApiVersion(0, 1, 3, 0);

        var init_info: c.ImGui_ImplVulkan_InitInfo = .{
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

        if (!c.cImGui_ImplVulkan_LoadFunctionsEx(
            @as(u32, @bitCast(api_version)),
            imguiLoader,
            @ptrCast(&vulkan_context.instance.handle.handle),
        )) {
            return error.ImGuiVulkanLoadFailure;
        }

        if (!c.cImGui_ImplVulkan_Init(&init_info)) {
            return error.ImGuiVulkanInitFailure;
        }

        c.ImGui_StyleColorsClassic(null);

        const style = c.ImGui_GetStyle();
        style.*.FontScaleDpi = 1.5;
        c.ImGuiStyle_ScaleAllSizes(style, 1.5);

        return Self{
            .io = io,
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

    pub fn deinit(self: Self, device: *Device) void {
        _ = device.handle.deviceWaitIdle() catch {};

        c.cImGui_ImplVulkan_Shutdown();
        c.cImGui_ImplGlfw_Shutdown();
        c.ImGui_DestroyContext(null);
        device.handle.destroyDescriptorPool(self.descriptor_pool, null);
    }
};

fn imguiLoader(name: [*c]const u8, user_data: ?*anyopaque) callconv(.c) c.PFN_vkVoidFunction {
    const instance_ptr = user_data orelse return null;
    const instance: *vk.Instance = @ptrCast(@alignCast(instance_ptr));
    return glfwGetInstanceProcAddress(instance.*, name);
}

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
