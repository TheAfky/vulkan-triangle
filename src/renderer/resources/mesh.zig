const std = @import("std");
const vk = @import("vulkan");
const Device = @import("../../vulkan/device.zig").Device;
const Vertex = @import("vertex.zig").Vertex;

pub const Mesh = struct {
    vertex_buffer: vk.Buffer,
    vertex_memory: vk.DeviceMemory,
    vertex_count: u32,

    pub fn create(
        device: *Device,
        vertices: []const Vertex,
        usage: vk.BufferUsageFlags,
        properties: vk.MemoryPropertyFlags,
    ) !Mesh {
        const size = @sizeOf(Vertex) * vertices.len;

        const buffer = try device.handle.createBuffer(&.{
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
        }, null);

        const mem_requirements = device.handle.getBufferMemoryRequirements(buffer);
        const memory = try device.allocateMemory(mem_requirements, properties);

        try device.handle.bindBufferMemory(buffer, memory, 0);

        // 🔥 IMPORTANT: upload vertex data
    const data = try device.handle.mapMemory(
            memory,
            0,
            size,
            .{},
        );

        @memcpy(
            @as([*]u8, @ptrCast(data)),
            std.mem.sliceAsBytes(vertices),
        );

        device.handle.unmapMemory(memory);

        return Mesh{
            .vertex_buffer = buffer,
            .vertex_memory = memory,
            .vertex_count = @intCast(vertices.len),
        };
    }

    pub fn destroy(self: *Mesh, device: *Device) void {
        device.handle.freeMemory(self.vertex_memory, null);
        device.handle.destroyBuffer(self.vertex_buffer, null);
    }
};