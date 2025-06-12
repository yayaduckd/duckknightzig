const c = @import("cmix.zig");
const std = @import("std");
const mk = @import("mkmix.zig");
const zm = @import("include/zmath.zig");
const Camera = @import("camera.zig");
const Engine = @import("mlemgine.zig");

const Self = @This();

const log = std.log.scoped(.batcher);

const MAX_SPRITES = 1000;

const SpriteParams = extern struct {
    pos: [3]f32 align(1),
    rot: f32 align(1) = 0,
    source_rect: [4]f32 align(1) = .{ 0, 0, 1, 1 },
    color: [4]f32 align(1) = .{ 1, 1, 1, 1 },
    origin: [2]f32 align(1) = .{ 0.5, 0.5 },
    scale: [2]f32 align(1) = .{ 1, 1 },
};

gpu_device: *c.SDL_GPUDevice,
transfer_buffer: *c.SDL_GPUTransferBuffer,
storage_buffer: *c.SDL_GPUBuffer,
pipeline: *c.SDL_GPUGraphicsPipeline,
sampler: *c.SDL_GPUSampler,

camera: Camera = .default,

num_added: u32 = 0,

texture_map: std.AutoHashMap(*c.SDL_GPUTexture, std.ArrayList(SpriteParams)),

pub fn init(engine: Engine) !Self {
    // device: *c.SDL_GPUDevice, window: *c.SDL_Window, camera: ?Camera
    const device = engine.gpu_device;
    const window = engine.window;
    const cam = engine.camera;
    // var cam: Camera = undefined;
    // if (camera) |notnullcam| {
    //     cam = notnullcam;
    // } else {
    //     cam = .default;
    // }

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
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
        .vertex_shader = vertshader,
        .fragment_shader = fragshader,
    };
    const pipeline = try mk.sdlv(c.SDL_CreateGPUGraphicsPipeline(device, &pipelineCreateInfo));

    c.SDL_ReleaseGPUShader(device, vertshader);
    c.SDL_ReleaseGPUShader(device, fragshader);

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
    const transfer_buffer = try mk.sdlv(c.SDL_CreateGPUTransferBuffer(device, &transfer_create_info));

    const storage_buffer_create_info = c.SDL_GPUBufferCreateInfo{
        .usage = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
        .size = @sizeOf(SpriteParams) * MAX_SPRITES,
    };
    const storage_buffer = try mk.sdlv(c.SDL_CreateGPUBuffer(device, &storage_buffer_create_info));
    return Self{
        .gpu_device = device,
        .transfer_buffer = transfer_buffer,
        .storage_buffer = storage_buffer,
        .pipeline = pipeline,
        .sampler = sampler,
        .texture_map = std.AutoHashMap(*c.SDL_GPUTexture, std.ArrayList(SpriteParams)).init(mk.alloc),
        .camera = cam,
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

    const texture_transfer_ptr = c.SDL_MapGPUTransferBuffer(self.gpu_device, texture_transfer_buffer, true);
    _ = c.SDL_memcpy(texture_transfer_ptr, image_data.pixels, @intCast(image_data.w * image_data.h * 4));
    c.SDL_UnmapGPUTransferBuffer(self.gpu_device, texture_transfer_buffer);
    // Upload the transfer data to the GPU resources
    const upload_cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    const copy_pass = c.SDL_BeginGPUCopyPass(upload_cmd_buf);
    c.SDL_UploadToGPUTexture(copy_pass, &(c.SDL_GPUTextureTransferInfo){
        .transfer_buffer = texture_transfer_buffer,
        .offset = 0, //* Zeroes out the rest */
    }, &(c.SDL_GPUTextureRegion){ .texture = texture, .w = @intCast(image_data.w), .h = @intCast(image_data.h), .d = 1 }, true);

    c.SDL_DestroySurface(image_data);
    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(upload_cmd_buf);
    return texture;
}

pub fn add(self: *Self, params: SpriteParams, texture: *c.SDL_GPUTexture) void {
    self.num_added += 1;
    if (self.texture_map.contains(texture)) {
        self.texture_map.getPtr(texture).?.append(params) catch @panic("oom");
    } else {
        self.texture_map.put(texture, std.ArrayList(SpriteParams).init(mk.alloc)) catch @panic("oom");
        self.texture_map.getPtr(texture).?.append(params) catch @panic("oom");
    }
}

pub fn begin(self: *Self) void {
    self.num_added = 0;
    var iter = self.texture_map.iterator();
    while (iter.next()) |next| {
        next.value_ptr.*.clearRetainingCapacity();
    }
}

pub fn end(self: *Self) void {
    var iter = self.texture_map.iterator();
    const transfer_ptr = c.SDL_MapGPUTransferBuffer(self.gpu_device, self.transfer_buffer, true);
    var total: u32 = 0;
    while (iter.next()) |next| {
        const params_ptr = next.value_ptr.*.items.ptr;
        const params_len: u32 = @intCast(next.value_ptr.*.items.len);
        const params_num_bytes = params_len * @sizeOf(SpriteParams);

        _ = c.SDL_memcpy(
            @ptrFromInt(@intFromPtr(transfer_ptr) + total * @sizeOf(SpriteParams)),
            params_ptr,
            params_num_bytes,
        );
        total += params_len;
    }
    c.SDL_UnmapGPUTransferBuffer(self.gpu_device, self.transfer_buffer);
}

pub fn copy(self: *const Self, copy_pass: *c.SDL_GPUCopyPass) void {
    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = self.transfer_buffer, .offset = 0 },
        &(c.SDL_GPUBufferRegion){
            .buffer = self.storage_buffer,
            .offset = 0,
            .size = @sizeOf(SpriteParams) * self.num_added,
        },
        true, // enable cycling of the batcher buffer
    );
}

pub fn render(self: *const Self, render_pass: *c.SDL_GPURenderPass) void {
    c.SDL_BindGPUVertexStorageBuffers(render_pass, 0, &self.storage_buffer, 1);

    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);

    var iter = self.texture_map.iterator();

    var total: u32 = 0;
    while (iter.next()) |next| {
        const params_len: u32 = @intCast(next.value_ptr.*.items.len);

        c.SDL_BindGPUFragmentSamplers(render_pass, 0, &(c.SDL_GPUTextureSamplerBinding){ .texture = next.key_ptr.*, .sampler = self.sampler }, 1);
        c.SDL_DrawGPUPrimitives(render_pass, 4, params_len, 0, total);

        total += params_len;
    }
}

pub fn deinit(self: *Self) void {
    var iter = self.texture_map.iterator();
    while (iter.next()) |next| {
        next.value_ptr.*.clearAndFree();
    }
    self.texture_map.clearAndFree();
}
