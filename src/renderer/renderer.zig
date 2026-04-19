const std = @import("std");
const vk = @import("vulkan");

const VulkanContext = @import("../vulkan/context.zig").VulkanContext;
const Instance = @import("../vulkan/instance.zig").Instance;
const Device = @import("../vulkan/device.zig").Device;

const Window = @import("../window.zig").Window;
const DrawCommand = @import("resources/draw_command.zig").DrawCommand;

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    context: VulkanContext,
    draw_commands: std.ArrayList(DrawCommand),

    pub fn init(allocator: std.mem.Allocator, window: *Window) !Self {
        return Self{
            .allocator = allocator,
            .context = try VulkanContext.init(
                allocator,
                "Vulkan Triangle",
                "Engine",
                window,
            ),
            .draw_commands = std.ArrayList(DrawCommand).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.context.deinit();
        self.draw_commands.deinit(self.allocator);
    }

    pub fn beginFrame(self: *Self, window: *Window) !?vk.CommandBuffer {
        return try self.context.beginFrame(window);
    }

    pub fn endFrame(self: *Self, cmd: vk.CommandBuffer, window: *Window) !void {
        try self.context.endFrame(cmd, window);
    }

    pub fn submit(self: *Self, cmd: DrawCommand) void {
        self.draw_commands.append(self.allocator, cmd) catch unreachable;
    }

    pub fn render(self: *Self, command_buffer: vk.CommandBuffer) void {
        for (self.draw_commands.items) |draw_command| {
            const mesh = draw_command.mesh;

            self.context.device.handle.cmdBindVertexBuffers(
                command_buffer,
                0,
                1,
                &[_]vk.Buffer{mesh.vertex_buffer.handle},
                &[_]vk.DeviceSize{0},
            );

            self.context.device.handle.cmdBindPipeline(
                command_buffer,
                .graphics,
                self.context.pipeline.pipeline,
            );

            self.context.device.handle.cmdDraw(
                command_buffer,
                mesh.vertex_count,
                1,
                0,
                0,
            );
        }

        self.draw_commands.clearRetainingCapacity();
    }

    pub fn device(self: *Self) *Device {
        return &self.context.device;
    }

    pub fn instance(self: *Self) *Instance {
        return &self.context.instance;
    }

    pub fn vulkan_context(self: *Self) *VulkanContext {
        return &self.context;
    }
};