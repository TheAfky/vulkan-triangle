const vk = @import("vulkan");

pub const Buffer = struct {
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
    size: u64,
};
