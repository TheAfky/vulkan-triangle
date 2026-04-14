const std = @import("std");
const App = @import("app.zig").App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        switch (gpa.deinit()) {
            .ok => {},
            .leak => std.debug.panic("Memory leaked", .{}),
        }
    }

    const allocator = gpa.allocator();
    var app = try App.init(allocator);
    defer {
        app.deinit();
        allocator.destroy(app);
    }

    try app.run();
}