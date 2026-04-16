const std = @import("std");

const Window = @import("window.zig").Window;
const Renderer = @import("renderer/renderer.zig").Renderer;
const ImGui = @import("imgui.zig").Imgui;
const Mesh = @import("renderer/resources/mesh.zig").Mesh;
const Vertex = @import("renderer/resources/vertex.zig").Vertex;

pub const c = @cImport({ @cInclude("dcimgui.h"); });

const application_name = "Vulkan Triangle";
const window_width: u32 = 960;
const window_height: u32 = 640;

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5, 0 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5, 0 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5, 0 }, .color = .{ 0, 0, 1 } },
};

pub const App = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: Window,
    renderer: Renderer,
    triangle_mesh: Mesh,
    imgui: ImGui,
    draw_triangle: bool = true,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var window = try Window.init(window_width, window_height, application_name);
        errdefer window.deinit();

        var renderer = try Renderer.init(allocator, &window);
        errdefer renderer.deinit();

        var triangle_mesh = try Mesh.create(
            renderer.device(),
            &vertices,
            .{ .vertex_buffer_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );
        errdefer triangle_mesh.destroy(renderer.device());

        const imgui = try ImGui.init(renderer.vulkan_context(), &window);
        errdefer imgui.deinit(renderer.device());

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .triangle_mesh = triangle_mesh,
            .imgui = imgui,
        };
    }

    fn drawUI(self: *Self) void {
        c.ImGui_SetNextWindowPos(.{ .x = 0, .y = 0 }, 0);
        _ = c.ImGui_Begin(
            "Main",
            1,
            c.ImGuiWindowFlags_NoDecoration |
                c.ImGuiWindowFlags_NoMove |
                c.ImGuiWindowFlags_NoBackground,
        );

        c.ImGui_Text("Crazy Triangle");

        if (c.ImGui_Button(
            if (self.draw_triangle) "Hide triangle" else "Show triangle",
        )) {
            self.draw_triangle = !self.draw_triangle;
        }

        c.ImGui_End();
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            self.window.pollEvents();
            if (try self.window.isMinimized()) continue;

            const cmd = try self.renderer.beginFrame(&self.window) orelse continue;

            self.imgui.beginFrame();
            self.drawUI();
            self.imgui.endFrame(cmd);

            if (self.draw_triangle) {
                self.renderer.submit(.{
                    .mesh = self.triangle_mesh,
                });
            }

            self.renderer.render(cmd);
            try self.renderer.endFrame(cmd, &self.window);
        }
    }

    pub fn deinit(self: *Self) void {
        self.imgui.deinit(self.renderer.device());
        self.triangle_mesh.destroy(self.renderer.device());
        self.renderer.deinit();
        self.window.deinit();
    }
};
