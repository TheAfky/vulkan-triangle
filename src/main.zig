const std = @import("std");
const App = @import("app.zig").App;

const application_name = "Vulkan Triangle";
const window_width: u32 = 960;
const window_height: u32 = 640;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.panic("Memory leaked", .{});
    };

    const allocator = gpa.allocator();
    var app = try App.init(
        allocator,
        window_width,
        window_height,
        application_name
    );
    defer app.deinit();

    try app.run();
}