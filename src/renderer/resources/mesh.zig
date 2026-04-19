const std = @import("std");
const vk = @import("vulkan");
const Device = @import("../../vulkan/device.zig").Device;
const Vertex = @import("vertex.zig").Vertex;
const Buffer = @import("../../vulkan/buffer.zig").Buffer;

pub const Mesh = struct {
    vertex_buffer: Buffer,
    vertex_count: u32,

    pub fn create(
        device: *Device,
        vertices: []const Vertex,
        usage: vk.BufferUsageFlags,
        properties: vk.MemoryPropertyFlags,
    ) !Mesh {
        const size = @sizeOf(Vertex) * vertices.len;
        const buffer = try device.createBuffer(size, usage, properties);

        const data = try device.handle.mapMemory(buffer.memory, 0, size, .{});

        @memcpy(
            @as([*]u8, @ptrCast(data)),
            std.mem.sliceAsBytes(vertices),
        );

        return Mesh{
            .vertex_buffer = buffer,
            .vertex_count = @intCast(vertices.len),
        };
    }

    pub fn destroy(self: *Mesh, device: *Device) void {
        device.handle.freeMemory(self.vertex_buffer.memory, null);
        device.handle.destroyBuffer(self.vertex_buffer.handle, null);
    }
};