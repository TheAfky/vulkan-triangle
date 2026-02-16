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
        var self: Self = undefined;
        self.allocator = allocator;
        self.base_wrapper = vk.BaseWrapper.load(glfwGetInstanceProcAddress);
        self.window = window;
        
        self.instance = try Instance.init(self.allocator, self.base_wrapper, application_name, engine_name);
        self.surface = try createSurface(self.instance.handle.handle, window.handle);
        self.device = try Device.init(self.allocator, self.base_wrapper, self.instance.handle, self.surface);
        self.swapchain = try Swapchain.init(self.allocator, self.instance.handle, self.device, self.surface, window);
        self.graphics_pipeline = try GraphicsPipeline.init(self.device, self.swapchain);
        self.framebuffers = try createFramebuffers(self);
        self.command_pool = try createCommandPool(self);
        self.command_buffers = try createCommandBuffers(self);

        return self;
    }

    pub fn deinit(self: Self) void {
        self.swapchain.waitForAllFences() catch {};
        self.device.handle.deviceWaitIdle() catch {};

        self.destroyCommandBuffers();
        self.device.handle.destroyCommandPool(self.command_pool, null);
        self.destroyFramebuffers();
        self.graphics_pipeline.deinit();
        self.swapchain.deinit();
        self.device.deinit();
        self.instance.handle.destroySurfaceKHR(self.surface, null);
        self.instance.deinit();
    }

    fn createFramebuffers(self: Self) ![]vk.Framebuffer {
        const framebuffers = try self.allocator.alloc(vk.Framebuffer, self.swapchain.swapchain_images.len);
        errdefer self.allocator.free(framebuffers);

        var i: usize = 0;
        errdefer for (framebuffers[0..i]) |fb| self.device.handle.destroyFramebuffer(fb, null);

        for (framebuffers) |*framebuffer| {
            framebuffer.* = try self.device.handle.createFramebuffer(&.{
                .render_pass = self.graphics_pipeline.render_pass,
                .attachment_count = 1,
                .p_attachments = @ptrCast(&self.swapchain.swapchain_images[i].image_view),
                .width = self.swapchain.extent.width,
                .height = self.swapchain.extent.height,
                .layers = 1,
            }, null);
            i += 1;
        }

        return framebuffers;
    }

    fn destroyFramebuffers(self: Self) void {
        for (self.framebuffers) |framebuffer| self.device.handle.destroyFramebuffer(framebuffer, null);
        self.allocator.free(self.framebuffers);
    }

    fn createCommandPool(self: Self) !vk.CommandPool {
        const command_pool = try self.device.handle.createCommandPool(&.{
            .queue_family_index = self.device.graphics_queue.family,
        }, null);
        return command_pool;
    }

    fn createCommandBuffers(self: Self) ![]vk.CommandBuffer {
        const command_buffers = try self.allocator.alloc(vk.CommandBuffer, self.framebuffers.len);
        errdefer self.allocator.free(command_buffers);

        try self.device.handle.allocateCommandBuffers(&.{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = @intCast(command_buffers.len),
        }, command_buffers.ptr);
        errdefer self.device.handle.freeCommandBuffers(self.command_pool, @intCast(command_buffers.len), command_buffers.ptr);

        const clear = vk.ClearValue{
            .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
        };

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain.extent.width),
            .height = @floatFromInt(self.swapchain.extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        };

        for (command_buffers, self.framebuffers) |command_buffer, framebuffer| {
            try self.device.handle.beginCommandBuffer(command_buffer, &.{});

            self.device.handle.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&viewport));
            self.device.handle.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

            self.device.handle.cmdBeginRenderPass(command_buffer, &.{
                .render_pass = self.graphics_pipeline.render_pass,
                .framebuffer = framebuffer,
                .render_area = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = self.swapchain.extent,
                },
                .clear_value_count = 1,
                .p_clear_values = @ptrCast(&clear),
            }, .@"inline");

            self.device.handle.cmdBindPipeline(command_buffer, .graphics, self.graphics_pipeline.pipeline);
            
            self.device.handle.cmdDraw(command_buffer, 3, 1, 0, 0);
                        
            self.device.handle.cmdEndRenderPass(command_buffer);
            try self.device.handle.endCommandBuffer(command_buffer);
        }

        return command_buffers;
    }

    fn destroyCommandBuffers(self: Self) void {
        self.device.handle.freeCommandBuffers(self.command_pool, @intCast(self.command_buffers.len), self.command_buffers.ptr);
        self.allocator.free(self.command_buffers);
    }
    
    pub fn drawFrame(self: *Self) !void {
        var w: c_int = undefined;
        var h: c_int = undefined;
        zglfw.getFramebufferSize(self.window.handle, &w, &h);

        if (w == 0 or h == 0) return;

        if (self.swapchain.state == .suboptimal or self.swapchain.extent.width != @as(u32, @intCast(w)) or self.swapchain.extent.height != @as(u32, @intCast(h))) {
            self.swapchain.extent.width = @intCast(w);
            self.swapchain.extent.height = @intCast(h);

            try self.swapchain.recreate();

            self.destroyFramebuffers();
            self.framebuffers = try self.createFramebuffers();

            self.destroyCommandBuffers();
            self.command_buffers = try self.createCommandBuffers();
        }

        const command_buffer = self.command_buffers[self.swapchain.image_index];
        _ = self.swapchain.present(command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };
    }
};

fn createSurface(raw_instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var raw_surface: u64 = 0;
    if (zglfw.createWindowSurface(@intFromEnum(raw_instance), window, null, &raw_surface) != zglfw.VkResult.success) {
        return error.SurfaceInitFailed;
    }
    return @enumFromInt(raw_surface);
}
