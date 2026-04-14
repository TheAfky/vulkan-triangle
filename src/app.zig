const std = @import("std");
const zglfw = @import("zglfw");

const Window = @import("window/window.zig").Window;
const WindowBackend = @import("window/window.zig").WindowBackend;
const Renderer = @import("renderer/renderer.zig").Renderer;
const ImGui = @import("ui/imgui.zig").Imgui;
const Mesh = @import("renderer/resources/mesh.zig").Mesh;
const Vertex = @import("renderer/resources/vertex.zig").Vertex;

pub const c = @cImport({ @cInclude("dcimgui.h"); });

const application_name = "Vulkan Triangle";
const window_width: u32 = 960;
const window_height: u32 = 640;

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

pub const App = struct {
    allocator: std.mem.Allocator,
    window: Window,
    renderer: Renderer,
    triangle_mesh: Mesh,
    imgui: ImGui,
    draw_triangle: bool = false,

    pub fn init(allocator: std.mem.Allocator) !*App {
        try zglfw.init();

        const app = try allocator.create(App);

        app.allocator = allocator;

        app.window = try Window.init(.Glfw, window_width, window_height, application_name);
        app.window.registerCallbacks();
        errdefer app.window.deinit();

        app.renderer = try Renderer.init(allocator, &app.window);
        errdefer app.renderer.deinit();

        app.triangle_mesh = try Mesh.create(
            &app.renderer.context.device,
            &vertices,
            .{ .vertex_buffer_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );
        errdefer app.triangle_mesh.destroy(&app.renderer.context.device);

        app.imgui = try ImGui.init(&app.renderer.context, &app.window);
        errdefer app.imgui.deinit();

        return app;
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            self.window.pollEvents();
            if (self.window.isMinimized()) continue;

            const cmd = try self.renderer.beginFrame() orelse continue;

            // Imgui UI
            self.imgui.beginFrame();
            c.ImGui_SetNextWindowPos(.{ .x = 0, .y = 0 }, 0);
            _ = c.ImGui_Begin(
                "Main",
                1,
                c.ImGuiWindowFlags_NoDecoration |
                    c.ImGuiWindowFlags_NoMove |
                    c.ImGuiWindowFlags_NoBackground,
            );

            c.ImGui_Text("Carzy Triangle");

            if (c.ImGui_Button(
                if (self.draw_triangle) "Hide triangle" else "Show triangle",
            )) {
                self.draw_triangle = !self.draw_triangle;
            }

            if (self.draw_triangle) {
                self.renderer.submit(.{
                    .mesh = self.triangle_mesh,
                });
            }

            c.ImGui_End();

            self.imgui.endFrame(cmd);
            self.renderer.render(cmd);
            try self.renderer.endFrame(cmd);
        }
    }

    pub fn deinit(self: *App) void {
        self.imgui.deinit();
        self.triangle_mesh.destroy(&self.renderer.context.device);
        self.renderer.deinit();
        self.window.deinit();
        zglfw.terminate();
    }
};
