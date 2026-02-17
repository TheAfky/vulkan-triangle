const vk = @import("vulkan");

const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;

const vert_spv align(@alignOf(u32)) = @embedFile("../shaders/vert.spv").*;
const frag_spv align(@alignOf(u32)) = @embedFile("../shaders/frag.spv").*;

pub const GraphicsPileline = struct {
    const Self = @This();

    device: Device,
    swapchain: Swapchain,

    pipeline_layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,

    pub fn init(device: Device, swapchain: Swapchain) !Self {
        var self: Self = undefined;
        self.device = device;
        self.swapchain = swapchain;

        const vert_shader_module = try self.device.handle.createShaderModule(&.{
            .code_size = vert_spv.len,
            .p_code = @ptrCast(&vert_spv),
        }, null);
        defer self.device.handle.destroyShaderModule(vert_shader_module, null);

        const frag_shader_module = try self.device.handle.createShaderModule(&.{
            .code_size = frag_spv.len,
            .p_code = @ptrCast(&frag_spv),
        }, null);
        defer self.device.handle.destroyShaderModule(frag_shader_module, null);

        const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .stage = .{ .vertex_bit = true },
                .module = vert_shader_module,
                .p_name = "main",
            },
            .{
                .stage = .{ .fragment_bit = true },
                .module = frag_shader_module,
                .p_name = "main",
            },
        };

        const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

        const vertex_input = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 0,
            // .p_vertex_binding_descriptions = null,
            .vertex_attribute_description_count = 0,
            // .p_vertex_attribute_descriptions = null,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain.extent.width),
            .height = @floatFromInt(self.swapchain.extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = @ptrCast(&viewport),
            .scissor_count = 1,
            .p_scissors = @ptrCast(&scissor),
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = .false,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        };

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_blend_attachment),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        };

        self.pipeline_layout = try self.device.handle.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = undefined,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = undefined,
        }, null);

        const color_attachment = vk.AttachmentDescription{
            .format = self.swapchain.surface_format.format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        };

        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_ref),
        };

        self.render_pass = try self.device.handle.createRenderPass(&.{
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_attachment),
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
        }, null);

        const graphics_pipeline = vk.GraphicsPipelineCreateInfo{
            .flags = .{},
            .stage_count = 2,
            .p_stages = &shader_stages,
            .p_vertex_input_state = &vertex_input,
            .p_input_assembly_state = &input_assembly,
            .p_tessellation_state = null,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_state,
            .layout = self.pipeline_layout,
            .render_pass = self.render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        const result = try self.device.handle.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&graphics_pipeline),
            null,
            @ptrCast(&self.pipeline),
        );
        if (result != .success) {
            return error.PipelineCreationFailed;
        }

        return self;
    }

    pub fn deinit(self: Self) void {
        self.device.handle.destroyPipelineLayout(self.pipeline_layout, null);
        self.device.handle.destroyRenderPass(self.render_pass, null);
        self.device.handle.destroyPipeline(self.pipeline, null);
    }
};