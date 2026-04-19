const std = @import("std");

const Window = @import("window.zig").Window;
const Renderer = @import("renderer/renderer.zig").Renderer;
const ImGui = @import("imgui.zig").Imgui;
const Mesh = @import("renderer/resources/mesh.zig").Mesh;
const Vertex = @import("renderer/resources/vertex.zig").Vertex;

const c = @import("c");

const application_name = "Vulkan Triangle";
const window_width: u32 = 960;
const window_height: u32 = 640;

const initial_vertices = [_]Vertex{
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
    vertices: [3]Vertex = initial_vertices,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var window = try Window.init(window_width, window_height, application_name);
        errdefer window.deinit();

        var renderer = try Renderer.init(allocator, &window);
        errdefer renderer.deinit();

        var triangle_mesh = try Mesh.create(
            renderer.device(),
            &initial_vertices,
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
        c.ImGui_SetNextWindowSize(.{ .x = 300, .y = 300}, 0);
        _ = c.ImGui_Begin(
            "Main",
            1,
            c.ImGuiWindowFlags_NoDecoration |
                c.ImGuiWindowFlags_NoMove |
                c.ImGuiWindowFlags_NoBackground,
        );

        c.ImGui_SetWindowFontScale(2);
        c.ImGui_Text("Controls");
        c.ImGui_SetWindowFontScale(1);

        if (c.ImGui_Button(
            if (self.draw_triangle) "Hide triangle" else "Show triangle",
        )) {
            self.draw_triangle = !self.draw_triangle;
        }

        c.ImGui_Separator();

        for (&self.vertices, 0..) |*v, i| {
            var color: [3]f32 = v.color;

            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrintZ(&label_buf, "Vertex {d}", .{i}) catch "Vertex";

            if (c.ImGui_ColorEdit3(label, &color, 0)) {
                v.color = color;
            }
        }

        c.ImGui_End();
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            self.window.pollEvents();
            if (try self.window.isMinimized()) continue;

            const cmd = try self.renderer.beginFrame(&self.window) orelse continue;

            if (self.draw_triangle) {
                self.renderer.submit(.{
                    .mesh = self.triangle_mesh,
                });
            }
            self.renderer.render(cmd);

            self.imgui.beginFrame();
            self.drawUI();
            self.imgui.endFrame(cmd);

            try self.triangle_mesh.update(self.renderer.device(), &self.vertices);

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
