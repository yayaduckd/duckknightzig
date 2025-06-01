const c = @import("cmix.zig");
const std = @import("std");
const mk = @import("mkmix.zig");
const zm = @import("include/zmath.zig");
const Self = @This();

const MAX_SPRITES = 69;

const SpriteParams = extern struct {
    pos: [3]f32 align(1),
    rot: f32 align(1) = 0,
    source_rect: [4]f32 align(1) = .{ 0, 0, 1, 1 },
    color: [4]f32 align(1) = .{ 1, 1, 1, 1 },
    origin: [2]f32 align(1) = .{ 0.5, 0.5 },
    scale: [2]f32 align(1) = .{ 1, 1 },

    // texture,
};

gpu_device: *c.SDL_GPUDevice,
transfer_buffer: *c.SDL_GPUTransferBuffer,
storage_buffer: *c.SDL_GPUBuffer,
pipeline: *c.SDL_GPUGraphicsPipeline,
vertex_buffer: *c.SDL_GPUBuffer,
index_buffer: *c.SDL_GPUBuffer,
sampler: *c.SDL_GPUSampler,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

num_added: u32 = 0,
// registered_textures: std.ArrayList(c.SDL_Texture),

texture_map: std.AutoHashMap(*c.SDL_GPUTexture, u32),

pub fn init(device: *c.SDL_GPUDevice, window: *c.SDL_Window) !Self {

    // shaders
    const vertshader = try mk.load_shader(device, "tringlesprite.vert.spv", 0, 1, 1, 0);
    const fragshader = try mk.load_shader(device, "trongle.frag.spv", 1, 0, 0, 0);

    const pipelineCreateInfo: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{ .format = c.SDL_GetGPUSwapchainTextureFormat(device, window), .blend_state = .{
                .enable_blend = true,
                .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            } },
        },
        .rasterizer_state = .{
            .cull_mode = c.SDL_GPU_CULLMODE_NONE,
        },
        .vertex_input_state = (c.SDL_GPUVertexInputState){
            .num_vertex_buffers = 0,
            .vertex_buffer_descriptions = &.{ .slot = 0, .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0, .pitch = @sizeOf(mk.PositionTextureColorVertex) },
            .num_vertex_attributes = 0,
            .vertex_attributes = &[_]c.SDL_GPUVertexAttribute{
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 0, .offset = 0 },
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 1, .offset = @sizeOf(f32) * 4 },
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 2, .offset = @sizeOf(f32) * 4 + @sizeOf(f32) * 2 },
            },
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
        .vertex_shader = vertshader,
        .fragment_shader = fragshader,
    };
    const pipeline_or_null = c.SDL_CreateGPUGraphicsPipeline(device, &pipelineCreateInfo);
    if (pipeline_or_null == null) {
        try mk.fatal_sdl_error("failed to create pipeline");
    }
    const pipeline = pipeline_or_null.?;
    c.SDL_ReleaseGPUShader(device, vertshader);
    c.SDL_ReleaseGPUShader(device, fragshader);

    // Create the GPU resources
    const vertex_buffer = c.SDL_CreateGPUBuffer(device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = @sizeOf(mk.PositionTextureColorVertex) * 4 }).?;

    const index_buffer = c.SDL_CreateGPUBuffer(device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_INDEX, .size = @sizeOf(u16) * 6 }).?;

    // Set up buffer data
    const buffer_transfer_buffer = c.SDL_CreateGPUTransferBuffer(device, &(c.SDL_GPUTransferBufferCreateInfo){
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = (@sizeOf(mk.PositionTextureColorVertex) * 4) + (@sizeOf(u16) * 6),
    });

    const c_transfer_data_ptr = c.SDL_MapGPUTransferBuffer(device, buffer_transfer_buffer, false).?;
    var buf: []u8 = undefined;
    buf.ptr = @ptrCast(c_transfer_data_ptr);
    buf.len = (@sizeOf(mk.PositionTextureColorVertex) * 4) + (@sizeOf(u16) * 6);

    var transferData: [4]mk.PositionTextureColorVertex = undefined;
    transferData[0] = mk.PositionTextureColorVertex{
        .x = -0.5,
        .y = -0.5,
        .z = 0,
        .u = 0,
        .v = 0,
    };
    transferData[1] = mk.PositionTextureColorVertex{
        .x = 0.5,
        .y = -0.5,
        .z = 0,
        .u = 1,
        .v = 0,
    };
    transferData[2] = mk.PositionTextureColorVertex{
        .x = 0.5,
        .y = 0.5,
        .z = 0,
        .u = 1,
        .v = 1,
    };
    transferData[3] = mk.PositionTextureColorVertex{
        .x = -0.5,
        .y = 0.5,
        .z = 0,
        .u = 0,
        .v = 1,
    };
    @memcpy(@as([*]mk.PositionTextureColorVertex, @alignCast(@ptrCast(buf))), &transferData);

    var indexData: [6]u16 = undefined;
    indexData[0] = 0;
    indexData[1] = 1;
    indexData[2] = 2;
    indexData[3] = 0;
    indexData[4] = 2;
    indexData[5] = 3;
    @memcpy(@as([*]u16, @alignCast(@ptrCast(buf[@sizeOf(mk.PositionTextureColorVertex) * 4 ..]))), &indexData);

    c.SDL_UnmapGPUTransferBuffer(device, buffer_transfer_buffer);
    // Upload the transfer data to the GPU resources
    const upload_cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const copy_pass = c.SDL_BeginGPUCopyPass(upload_cmd_buf);

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = buffer_transfer_buffer, .offset = 0 },
        &(c.SDL_GPUBufferRegion){ .buffer = vertex_buffer, .offset = 0, .size = @sizeOf(mk.PositionTextureColorVertex) * 4 },
        false,
    );

    c.SDL_UploadToGPUBuffer(copy_pass, &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = buffer_transfer_buffer, .offset = @sizeOf(mk.PositionTextureColorVertex) * 4 }, &(c.SDL_GPUBufferRegion){
        .buffer = index_buffer,
        .offset = 0,
        .size = @sizeOf(u16) * 6,
    }, false);

    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(upload_cmd_buf);
    c.SDL_ReleaseGPUTransferBuffer(device, buffer_transfer_buffer);

    const sampler = c.SDL_CreateGPUSampler(device, &(c.SDL_GPUSamplerCreateInfo){
        .min_filter = c.SDL_GPU_FILTER_NEAREST,
        .mag_filter = c.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    }).?;

    const transfer_create_info = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @sizeOf(SpriteParams) * MAX_SPRITES,
    };
    const transfer_buffer_or_null = c.SDL_CreateGPUTransferBuffer(device, &transfer_create_info);
    if (transfer_buffer_or_null == null) {
        return error.MkFailedCreateTransferBuffer;
    }
    const transfer_buffer = transfer_buffer_or_null.?;

    const create_info = c.SDL_GPUBufferCreateInfo{
        .usage = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
        .size = @sizeOf(SpriteParams) * MAX_SPRITES,
    };
    const storage_buffer_or_null = c.SDL_CreateGPUBuffer(device, &create_info);
    if (storage_buffer_or_null == null) {
        return error.MkFailedCreateBuffer;
    }
    const storage_buffer = storage_buffer_or_null.?;
    return Self{
        .gpu_device = device,
        .transfer_buffer = transfer_buffer,
        .storage_buffer = storage_buffer,
        .pipeline = pipeline,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .sampler = sampler,
        .texture_map = std.AutoHashMap(*c.SDL_GPUTexture, u32).init(mk.alloc),
    };
}

pub fn register_texture(self: *Self, image_data: *c.SDL_Surface) *c.SDL_GPUTexture {
    const texture = c.SDL_CreateGPUTexture(self.gpu_device, &(c.SDL_GPUTextureCreateInfo){
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .width = @intCast(image_data.w),
        .height = @intCast(image_data.h),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    }).?;

    // Set up texture data
    const texture_transfer_buffer: ?*c.SDL_GPUTransferBuffer = c.SDL_CreateGPUTransferBuffer(
        self.gpu_device,
        &(c.SDL_GPUTransferBufferCreateInfo){ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = @intCast(image_data.w * image_data.h * 4) },
    );

    const texture_transfer_ptr = c.SDL_MapGPUTransferBuffer(self.gpu_device, texture_transfer_buffer, false);
    _ = c.SDL_memcpy(texture_transfer_ptr, image_data.pixels, @intCast(image_data.w * image_data.h * 4));
    c.SDL_UnmapGPUTransferBuffer(self.gpu_device, texture_transfer_buffer);
    // Upload the transfer data to the GPU resources
    const upload_cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    const copy_pass = c.SDL_BeginGPUCopyPass(upload_cmd_buf);
    c.SDL_UploadToGPUTexture(copy_pass, &(c.SDL_GPUTextureTransferInfo){
        .transfer_buffer = texture_transfer_buffer,
        .offset = 0, //* Zeroes out the rest */
    }, &(c.SDL_GPUTextureRegion){ .texture = texture, .w = @intCast(image_data.w), .h = @intCast(image_data.h), .d = 1 }, false);

    c.SDL_DestroySurface(image_data);
    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(upload_cmd_buf);
    return texture;
}

pub fn add(self: *Self, params: SpriteParams, texture: *c.SDL_GPUTexture) void {
    const texture_transfer_ptr = c.SDL_MapGPUTransferBuffer(self.gpu_device, self.transfer_buffer, false);
    _ = c.SDL_memcpy(
        @ptrFromInt(@intFromPtr(texture_transfer_ptr) + self.num_added * @sizeOf(SpriteParams)),
        &params,
        @sizeOf(SpriteParams),
    );
    // std.log.debug("{x}", .{texture});
    self.num_added += 1;
    if (self.texture_map.contains(texture)) {
        const val = self.texture_map.get(texture).?;
        self.texture_map.put(texture, val + 1) catch unreachable;
    } else {
        self.texture_map.put(texture, 1) catch unreachable;
    }
}

pub fn draw(self: *Self, cmd_buf: *c.SDL_GPUCommandBuffer, target_info: c.SDL_GPUColorTargetInfo) void {
    // Upload the transfer data to the GPU resources
    // const cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    // std.log.debug("drawr", .{});
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buf);

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = self.transfer_buffer, .offset = 0 },
        &(c.SDL_GPUBufferRegion){
            .buffer = self.storage_buffer,
            .offset = 0,
            .size = @sizeOf(SpriteParams) * MAX_SPRITES,
        },
        false,
    );

    c.SDL_EndGPUCopyPass(copy_pass);

    const render_pass_ptr = c.SDL_BeginGPURenderPass(cmd_buf, &target_info, 1, null);
    if (render_pass_ptr == null) {
        return;
    }
    const render_pass = render_pass_ptr.?;

    c.SDL_BindGPUVertexStorageBuffers(render_pass, 0, &self.storage_buffer, 1);

    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    c.SDL_BindGPUVertexBuffers(render_pass, 0, &(c.SDL_GPUBufferBinding){ .buffer = self.vertex_buffer, .offset = 0 }, 1);
    c.SDL_BindGPUIndexBuffer(render_pass, &(c.SDL_GPUBufferBinding){ .buffer = self.index_buffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

    var matrix_uniform = zm.mulMats(&.{
        comptime zm.lookAtLh(.{ 0, 0, -5, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 1, 0, 0 }),
        comptime zm.perspectiveFovLh(std.math.degreesToRadians(90), 1, 1, 100),
    });
    // var matrix_uniform = zm.identity();
    const mat_size = @sizeOf(@TypeOf(matrix_uniform));

    c.SDL_PushGPUVertexUniformData(cmd_buf, 0, &matrix_uniform, mat_size);

    var iter = self.texture_map.iterator();
    while (iter.next()) |next| {
        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &(c.SDL_GPUTextureSamplerBinding){ .texture = next.key_ptr.*, .sampler = self.sampler }, 1);

        // c.SDL_DrawGPUIndexedPrimitives(render_pass, 4, next.value_ptr.*, 0, 0, 0);
        c.SDL_DrawGPUPrimitives(render_pass, 4, next.value_ptr.*, 0, 0);
    }

    c.SDL_EndGPURenderPass(render_pass);

    // _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
}

pub fn reset(self: *Self) void {
    self.num_added = 0;
    self.texture_map.clearRetainingCapacity();
}
