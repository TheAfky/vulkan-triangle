const std = @import("std");
const vk = @import("vulkan");

const VulkanContext = @import("../vulkan/context.zig").VulkanContext;
const Window = @import("../window/window.zig").Window;
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

    pub fn beginFrame(self: *Self) !?vk.CommandBuffer {
        return try self.context.beginFrame();
    }

    pub fn endFrame(self: *Self, cmd: vk.CommandBuffer) !void {
        try self.context.endFrame(cmd);
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
                &[_]vk.Buffer{mesh.vertex_buffer},
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
};