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

const Window = @import("../window/window.zig").Window;
const Device = @import("device.zig").Device;
const Instance = @import("instance.zig").Instance;
const Swapchain = @import("swapchain.zig").Swapchain;
const Pipeline = @import("pipeline.zig").Pipeline;
const Imgui = @import("imgui.zig").Imgui;

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

pub fn framebufferResizeCallback(
    window: *zglfw.Window,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    if (width <= 0 or height <= 0) return;

    const ctx_ptr = zglfw.getWindowUserPointer(window);
    if (ctx_ptr == null) return;

    const vulkan_context: *VulkanContext = @ptrCast(@alignCast(ctx_ptr.?));
    vulkan_context.framebuffer_resized = true;
}

pub const VulkanContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    base_wrapper: vk.BaseWrapper,

    window: Window,
    instance: Instance,
    device: Device,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    pipeline: Pipeline,

    imgui: Imgui,

    framebuffers: []vk.Framebuffer,
    framebuffer_resized: bool,
    command_pool: vk.CommandPool,
    command_buffers: []vk.CommandBuffer,

    pub fn init(allocator: std.mem.Allocator, application_name: [*:0]const u8, engine_name: [*:0]const u8, window: Window) !Self {
        const base_wrapper = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

        const instance = try Instance.init(allocator, base_wrapper, application_name, engine_name);
        errdefer instance.deinit();

        const surface = try createSurface(instance.handle.handle, window.handle);

        const device = try Device.init(allocator, base_wrapper, instance.handle, surface);
        errdefer device.deinit();

        const swapchain = try Swapchain.init(allocator, instance.handle, device, surface, window);
        errdefer swapchain.deinit();

        const pipeline = try Pipeline.init(device, swapchain);
        errdefer pipeline.deinit();

        const imgui = try Imgui.init(instance, device, swapchain, pipeline.render_pass, window);
        errdefer imgui.deinit();

        const framebuffers = try createFramebuffers(allocator, device, swapchain, pipeline);
        errdefer destroyFramebuffers(allocator, device, framebuffers);

        const command_pool = try createCommandPool(device);
        errdefer device.handle.destroyCommandPool(command_pool, null);

        const command_buffers = try createCommandBuffers(allocator, device, framebuffers, command_pool);
        errdefer destroyCommandBuffers(allocator, device, command_pool, command_buffers);
        
        return Self{
            .allocator = allocator,
            .base_wrapper = base_wrapper,
            .window = window,
            .instance = instance,
            .device = device,
            .surface = surface,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .imgui = imgui,
            .framebuffers = framebuffers,
            .command_pool = command_pool,
            .command_buffers = command_buffers,
            .framebuffer_resized = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.handle.deviceWaitIdle() catch {};
        self.swapchain.waitForAllFences() catch {};

        destroyCommandBuffers(self.allocator, self.device, self.command_pool, self.command_buffers);
        self.device.handle.destroyCommandPool(self.command_pool, null);
        destroyFramebuffers(self.allocator, self.device, self.framebuffers);
        self.imgui.deinit();
        self.pipeline.deinit();
        self.swapchain.deinit();
        self.device.deinit();
        self.instance.handle.destroySurfaceKHR(self.surface, null);
        self.instance.deinit();
    }

    fn recreateSwapchain(self: *Self) !void {
        self.device.handle.deviceWaitIdle() catch {};

        try self.swapchain.recreate();

        destroyFramebuffers(self.allocator, self.device, self.framebuffers);
        self.framebuffers = try createFramebuffers(
            self.allocator,
            self.device,
            self.swapchain,
            self.pipeline,
        );

        destroyCommandBuffers(self.allocator, self.device, self.command_pool, self.command_buffers);
        self.command_buffers = try createCommandBuffers(
            self.allocator,
            self.device,
            self.framebuffers,
            self.command_pool,
        );
    }

    pub fn startFrame(self: *Self) !?vk.CommandBuffer {
        if (self.window.isMinimized()) return null;

        const index = self.swapchain.image_index;
        const command_buffer = self.command_buffers[index];

        try self.swapchain.currentSwapchainImage().waitForFence(self.device);

        if (self.framebuffer_resized) {
            self.framebuffer_resized = false;
            try self.recreateSwapchain();
            return null;
        }

        self.device.handle.resetCommandBuffer(command_buffer, .{}) catch {};
        try self.device.handle.beginCommandBuffer(command_buffer, &.{});

        const clear: vk.ClearValue = .{
            .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } },
        };

        const framebuffer = self.framebuffers[index];
        self.device.handle.cmdBeginRenderPass(command_buffer, &.{ .render_pass = self.pipeline.render_pass, .framebuffer = framebuffer, .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.surface_extent,
        }, .clear_value_count = 1, .p_clear_values = @ptrCast(&clear) }, .@"inline");

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain.surface_extent.width),
            .height = @floatFromInt(self.swapchain.surface_extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.surface_extent,
        };

        self.device.handle.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&viewport));
        self.device.handle.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

        self.device.handle.cmdBindPipeline(command_buffer, .graphics, self.pipeline.pipeline);

        return command_buffer;
    }

    pub fn endFrame(self: *Self, command_buffer: vk.CommandBuffer) !void {
        self.device.handle.cmdEndRenderPass(command_buffer);
        try self.device.handle.endCommandBuffer(command_buffer);

        _ = self.swapchain.present(command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => {
                try self.recreateSwapchain();
            },
            else => |e| return e,
        };

        if (self.swapchain.state == .suboptimal) {
            try self.recreateSwapchain();
        }
    }
};

fn createFramebuffers(allocator: std.mem.Allocator, device: Device, swapchain: Swapchain, graphics_pipeline: Pipeline) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swapchain_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |framebuffer| device.handle.destroyFramebuffer(framebuffer, null);

    for (framebuffers) |*framebuffer| {
        framebuffer.* = try device.handle.createFramebuffer(&.{
            .render_pass = graphics_pipeline.render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swapchain_images[i].image_view),
            .width = swapchain.surface_extent.width,
            .height = swapchain.surface_extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(allocator: std.mem.Allocator, device: Device, framebuffers: []vk.Framebuffer) void {
    for (framebuffers) |framebuffer| device.handle.destroyFramebuffer(framebuffer, null);
    if (framebuffers.len > 0)
        allocator.free(framebuffers);
}

fn createCommandPool(device: Device) !vk.CommandPool {
    const command_pool = try device.handle.createCommandPool(&.{
        .queue_family_index = device.graphics_queue.family,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);
    return command_pool;
}

fn createCommandBuffers(allocator: std.mem.Allocator, device: Device, framebuffers: []vk.Framebuffer, command_pool: vk.CommandPool) ![]vk.CommandBuffer {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(command_buffers);

    try device.handle.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = @intCast(command_buffers.len),
    }, command_buffers.ptr);
    errdefer device.handle.freeCommandBuffers(command_pool, @intCast(command_buffers.len), command_buffers.ptr);

    return command_buffers;
}

fn destroyCommandBuffers(allocator: std.mem.Allocator, device: Device, command_pool: vk.CommandPool, command_buffers: []vk.CommandBuffer) void {
    device.handle.freeCommandBuffers(command_pool, @intCast(command_buffers.len), command_buffers.ptr);
    allocator.free(command_buffers);
}

fn createSurface(raw_instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var raw_surface: u64 = 0;
    if (zglfw.createWindowSurface(@intFromEnum(raw_instance), window, null, &raw_surface) != zglfw.VkResult.success) {
        return error.SurfaceCreationFailed;
    }
    return @enumFromInt(raw_surface);
}
