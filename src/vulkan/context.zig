const std = @import("std");

const vk = @import("vulkan");
const zglfw = @import("zglfw");

const Window = @import("../window/window.zig").Window;
const Device = @import("device.zig").Device;
const Instance = @import("instance.zig").Instance;
const Swapchain = @import("swapchain.zig").Swapchain;
const GraphicsPipeline = @import("graphics_pipeline.zig").GraphicsPileline;

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

pub const VulkanContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    base_wrapper: vk.BaseWrapper,

    window: Window,
    instance: Instance,
    device: Device,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    graphics_pipeline: GraphicsPipeline,
    framebuffers: []vk.Framebuffer,
    command_pool: vk.CommandPool,
    command_buffers: []vk.CommandBuffer,

    pub fn init(allocator: std.mem.Allocator, application_name: [*:0]const u8, engine_name: [*:0]const u8, window: Window) !Self {
        const base_wrapper = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

        const instance = try Instance.init(allocator, base_wrapper, application_name, engine_name);
        const surface = try createSurface(instance.handle.handle, window.handle);
        const device = try Device.init(allocator, base_wrapper, instance.handle, surface);
        const swapchain = try Swapchain.init(allocator, instance.handle, device, surface, window);
        const graphics_pipeline = try GraphicsPipeline.init(device, swapchain);
        const framebuffers = try createFramebuffers(allocator, device, swapchain, graphics_pipeline);
        const command_pool = try createCommandPool(device);
        const command_buffers = try createCommandBuffers(allocator, device, framebuffers, command_pool, swapchain, graphics_pipeline);

        return Self{
            .allocator = allocator,
            .base_wrapper = base_wrapper,
            .window = window,
            .instance = instance,
            .device = device,
            .surface = surface,
            .swapchain = swapchain,
            .graphics_pipeline = graphics_pipeline,
            .framebuffers = framebuffers,
            .command_pool = command_pool,
            .command_buffers = command_buffers,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.handle.deviceWaitIdle() catch {};
        self.swapchain.waitForAllFences() catch {};

        destroyCommandBuffers(self.allocator, self.device, self.command_pool, self.command_buffers);
        self.device.handle.destroyCommandPool(self.command_pool, null);
        destroyFramebuffers(self.allocator, self.device, self.framebuffers);
        self.graphics_pipeline.deinit();
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
            self.graphics_pipeline,
        );

        destroyCommandBuffers(self.allocator, self.device, self.command_pool, self.command_buffers);
        self.command_buffers = try createCommandBuffers(
            self.allocator,
            self.device,
            self.framebuffers,
            self.command_pool,
            self.swapchain,
            self.graphics_pipeline,
        );
    }

    pub fn drawFrame(self: *Self) !void {
        var w: c_int = undefined;
        var h: c_int = undefined;
        zglfw.getFramebufferSize(self.window.handle, &w, &h);

        if (w == 0 or h == 0) return;

        const command_buffer = self.command_buffers[self.swapchain.image_index];

        _ = self.swapchain.present(command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => {
                try self.recreateSwapchain();
                return;
            },
            else => |e| return e,
        };

        if (self.swapchain.state == .suboptimal) {
            try self.recreateSwapchain();
        }
    }

};

fn createFramebuffers(allocator: std.mem.Allocator, device: Device, swapchain: Swapchain, graphics_pipeline: GraphicsPipeline) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swapchain_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |framebuffer| device.handle.destroyFramebuffer(framebuffer, null);

    for (framebuffers) |*framebuffer| {
        framebuffer.* = try device.handle.createFramebuffer(&.{
            .render_pass = graphics_pipeline.render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swapchain_images[i].image_view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
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
    }, null);
    return command_pool;
}

fn createCommandBuffers(allocator: std.mem.Allocator, device: Device, framebuffers: []vk.Framebuffer, command_pool: vk.CommandPool, swapchain: Swapchain, graphics_pipeline: GraphicsPipeline) ![]vk.CommandBuffer {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(command_buffers);

    try device.handle.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = @intCast(command_buffers.len),
    }, command_buffers.ptr);
    errdefer device.handle.freeCommandBuffers(command_pool, @intCast(command_buffers.len), command_buffers.ptr);

    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };

    for (command_buffers, framebuffers) |command_buffer, framebuffer| {
        try device.handle.beginCommandBuffer(command_buffer, &.{});

        device.handle.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&viewport));
        device.handle.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

        device.handle.cmdBeginRenderPass(command_buffer, &.{
            .render_pass = graphics_pipeline.render_pass,
            .framebuffer = framebuffer,
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.extent,
            },
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear),
        }, .@"inline");

        device.handle.cmdBindPipeline(command_buffer, .graphics, graphics_pipeline.pipeline);

        device.handle.cmdDraw(command_buffer, 3, 1, 0, 0);

        device.handle.cmdEndRenderPass(command_buffer);
        try device.handle.endCommandBuffer(command_buffer);
    }

    return command_buffers;
}

fn destroyCommandBuffers(allocator: std.mem.Allocator, device: Device, command_pool: vk.CommandPool, command_buffers: []vk.CommandBuffer) void {
    device.handle.freeCommandBuffers(command_pool, @intCast(command_buffers.len), command_buffers.ptr);
    allocator.free(command_buffers);
}

fn createSurface(raw_instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var raw_surface: u64 = 0;
    if (zglfw.createWindowSurface(@intFromEnum(raw_instance), window, null, &raw_surface) != zglfw.VkResult.success) {
        return error.SurfaceInitFailed;
    }
    return @enumFromInt(raw_surface);
}
