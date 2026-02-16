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

    pub fn init(allocator: std.mem.Allocator, application_name: [*:0]const u8, engine_name: [*:0]const u8, window: Window) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.base_wrapper = vk.BaseWrapper.load(glfwGetInstanceProcAddress);
        self.window = window;
        
        self.instance = try Instance.init(self.allocator, self.base_wrapper, application_name, engine_name);
        self.surface = try create_surface(self.instance.handle.handle, window.handle);
        self.device = try Device.init(self.allocator, self.base_wrapper, self.instance.handle, self.surface);
        self.swapchain = try Swapchain.init(self.allocator, self.instance.handle, self.device, self.surface, window);
        self.graphics_pipeline = try GraphicsPipeline.init(self.device, self.swapchain);
        self.framebuffers = try createFramebuffers(self);

        return self;
    }

    pub fn deinit(self: Self) void {
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
};

fn create_surface(raw_instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var raw_surface: u64 = 0;
    if (zglfw.createWindowSurface(@intFromEnum(raw_instance), window, null, &raw_surface) != zglfw.VkResult.success) {
        return error.SurfaceInitFailed;
    }
    return @enumFromInt(raw_surface);
}
