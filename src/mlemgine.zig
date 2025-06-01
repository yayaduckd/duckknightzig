const c = @import("cmix.zig");
const Batcher = @import("drawer.zig");
const mk = @import("common.zig");

const std = @import("std");
const zm = @import("include/zmath.zig");

const Engine = @This();

done: bool = false,
window: *c.SDL_Window = undefined,
gpu_device: *c.SDL_GPUDevice = undefined,

pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
// gpu resources
vertex_buffer: *c.SDL_GPUBuffer = undefined,
index_buffer: *c.SDL_GPUBuffer = undefined,

duck_texture: *c.SDL_GPUTexture = undefined,
duck_sampler: *c.SDL_GPUSampler = undefined,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

current_frame: u64 = 0,

batcher: Batcher = undefined,

fn cleanup(self: *Engine) void {
    c.ImGui_ImplSDLGPU3_Shutdown();
    c.ImGui_ImplSDL3_Shutdown();
    c.igDestroyContext(null); // destroy context
    c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, self.window);
    c.SDL_DestroyGPUDevice(self.gpu_device);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit(); // defer sdl_quit

}

fn init_graphics(self: *Engine) !void {
    // setup sdl stuff
    // sdl initialization
    try mk.sdlr(c.SDL_Init(c.SDL_INIT_VIDEO));

    // window creation
    const window_ptr = c.SDL_CreateWindow("tongue", 1000, 1000, c.SDL_WINDOW_RESIZABLE);
    if (window_ptr == null) {
        try mk.fatal_sdl_error("failed to create window");
    }
    self.window = window_ptr.?; // unwrap window pointer

    // gpu device creation
    const gpu_device_ptr = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true, // debug_mode enabled
        null,
    );
    if (gpu_device_ptr == null) {
        try mk.fatal_sdl_error("failed to make gpu device");
    }
    self.gpu_device = gpu_device_ptr.?;

    // claim window for gpu device
    try mk.sdlr(c.SDL_ClaimWindowForGPUDevice(self.gpu_device, self.window));

    // set swapchain parameters
    try mk.sdlr(c.SDL_SetGPUSwapchainParameters(self.gpu_device, self.window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX));
}

pub fn init() !Engine {
    var self = Engine{};

    // setup general stuff
    try self.init_graphics();

    // shaders
    const vertshader = try mk.load_shader(self.gpu_device, "tringle.vert.spv", 0, 1, 0, 0);
    const fragshader = try mk.load_shader(self.gpu_device, "trongle.frag.spv", 1, 1, 0, 0);

    const image_data = try mk.load_image("mduck.png", 4);

    const pipelineCreateInfo: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{ .format = c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, self.window), .blend_state = .{
                .enable_blend = true,
                .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            } },
        },
        .vertex_input_state = (c.SDL_GPUVertexInputState){
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &.{ .slot = 0, .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0, .pitch = @sizeOf(mk.PositionTextureColorVertex) },
            .num_vertex_attributes = 3,
            .vertex_attributes = &[_]c.SDL_GPUVertexAttribute{
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 0, .offset = 0 },
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 1, .offset = @sizeOf(f32) * 4 },
                c.struct_SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 2, .offset = @sizeOf(f32) * 4 + @sizeOf(f32) * 2 },
            },
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = vertshader,
        .fragment_shader = fragshader,
    };
    const pipeline_or_null = c.SDL_CreateGPUGraphicsPipeline(self.gpu_device, &pipelineCreateInfo);
    if (pipeline_or_null == null) {
        try mk.fatal_sdl_error("failed to create pipeline");
    }
    self.pipeline = pipeline_or_null.?;
    c.SDL_ReleaseGPUShader(self.gpu_device, vertshader);
    c.SDL_ReleaseGPUShader(self.gpu_device, fragshader);

    // Create the GPU resources
    self.vertex_buffer = c.SDL_CreateGPUBuffer(self.gpu_device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = @sizeOf(mk.PositionTextureColorVertex) * 4 }).?;

    self.index_buffer = c.SDL_CreateGPUBuffer(self.gpu_device, &.{ .usage = c.SDL_GPU_BUFFERUSAGE_INDEX, .size = @sizeOf(u16) * 6 }).?;

    // self.duck_texture = c.SDL_CreateGPUTexture(self.gpu_device, &(c.SDL_GPUTextureCreateInfo){
    //     .type = c.SDL_GPU_TEXTURETYPE_2D,
    //     .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    //     .width = 10,
    //     .height = 10,
    //     .layer_count_or_depth = 1,
    //     .num_levels = 1,
    //     .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    // }).?;
    // self.duck_texture = self.batcher.register_texture(image_data);

    self.duck_sampler = c.SDL_CreateGPUSampler(self.gpu_device, &(c.SDL_GPUSamplerCreateInfo){
        .min_filter = c.SDL_GPU_FILTER_NEAREST,
        .mag_filter = c.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    }).?;

    // Set up buffer data
    const buffer_transfer_buffer = c.SDL_CreateGPUTransferBuffer(self.gpu_device, &(c.SDL_GPUTransferBufferCreateInfo){
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = (@sizeOf(mk.PositionTextureColorVertex) * 4) + (@sizeOf(u16) * 6),
    });

    const c_transfer_data_ptr = c.SDL_MapGPUTransferBuffer(self.gpu_device, buffer_transfer_buffer, false).?;
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

    c.SDL_UnmapGPUTransferBuffer(self.gpu_device, buffer_transfer_buffer);

    // Upload the transfer data to the GPU resources
    const upload_cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    const copy_pass = c.SDL_BeginGPUCopyPass(upload_cmd_buf);

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = buffer_transfer_buffer, .offset = 0 },
        &(c.SDL_GPUBufferRegion){ .buffer = self.vertex_buffer, .offset = 0, .size = @sizeOf(mk.PositionTextureColorVertex) * 4 },
        false,
    );

    c.SDL_UploadToGPUBuffer(copy_pass, &(c.SDL_GPUTransferBufferLocation){ .transfer_buffer = buffer_transfer_buffer, .offset = @sizeOf(mk.PositionTextureColorVertex) * 4 }, &(c.SDL_GPUBufferRegion){
        .buffer = self.index_buffer,
        .offset = 0,
        .size = @sizeOf(u16) * 6,
    }, false);

    c.SDL_EndGPUCopyPass(copy_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(upload_cmd_buf);
    c.SDL_ReleaseGPUTransferBuffer(self.gpu_device, buffer_transfer_buffer);

    // setup imgui context and io
    _ = c.igCreateContext(null);

    const io = c.igGetIO_Nil();
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard; // enable keyboard navigation
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableGamepad; // enable gamepad navigation

    // set imgui style to dark
    c.igStyleColorsDark(null);

    // initialize imgui platform/renderer backends
    // assuming sdl_bool return (0 for false) for imgui_implsdl3_initforsdlgpu
    if (c.ImGui_ImplSDL3_InitForSDLGPU(self.window) == false) {
        std.log.err("imgui_implsdl3_initforsdlgpu failed.", .{});
    }

    var init_info: c.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = self.gpu_device,
        .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, self.window),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
        // other fields are zero-initialized by default
    };
    if (c.ImGui_ImplSDLGPU3_Init(&init_info) == false) {
        std.log.err("imgui_implsdlgpu3_init failed.", .{});
    }

    self.batcher = try Batcher.init(
        self.gpu_device,
        self.window,
    );
    self.duck_texture = self.batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);

    // self.batcher.regi
    return self;
}

pub fn deinit(self: *Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    self.cleanup();
}

fn draw(self: *Engine) void {
    // start a new imgui frame
    c.ImGui_ImplSDLGPU3_NewFrame();
    c.ImGui_ImplSDL3_NewFrame();
    c.igNewFrame();

    // show imgui's built-in demo window
    var show_demo_window = true;
    if (show_demo_window) {
        c.igShowDemoWindow(&show_demo_window);
    }

    // rendering phase
    c.igRender();
    const draw_data_ptr = c.igGetDrawData();
    if (draw_data_ptr == null) {
        std.log.warn("iggetdrawdata() returned null.", .{});

        std.time.sleep(16 * 1000 * 1000);
        return;
    }
    const draw_data = draw_data_ptr.?;
    if (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0) {
        std.time.sleep(16 * 1000 * 1000); // if draw area is 0 or negative, skip rendering cycle
        return;
    }

    const command_buffer_ptr = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    if (command_buffer_ptr == null) {
        std.log.warn("failed to acquire gpu command buffer.", .{});
        std.time.sleep(16 * 1000 * 1000);
        return;
    }
    const command_buffer = command_buffer_ptr.?;

    var swapchain_texture_ptr: ?*c.SDL_GPUTexture = null;
    if (c.SDL_AcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture_ptr, null, null) == false) {
        std.log.warn("failed to acquire gpu swapchain texture.", .{});
        _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit command buffer
        return;
    }

    // sdl_acquiregpuswapchaintexture might return true without a valid texture pointer in some edge cases.
    // current code assumes a non-null texture if true is returned; specific error handling might be needed.
    if (swapchain_texture_ptr == null) {
        // this case might indicate an issue or a specific state (e.g., window resized, try next frame)
        // depending on sdl_gpu api contract, may need to submit command buffer here too.
        _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit command buffer, as it was acquired
        return;
    }
    const swapchain_texture = swapchain_texture_ptr.?;

    c.Imgui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer); // prepare imgui draw data for sdlgpu backend

    const target_info: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .clear_color = .{ .r = self.clear_color.x, .g = self.clear_color.y, .b = self.clear_color.z, .a = self.clear_color.w },
        .load_op = c.SDL_GPU_LOADOP_CLEAR, // clear render target on load
        .store_op = c.SDL_GPU_STOREOP_STORE, // store render target contents
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .cycle = false,
        // other target_info fields use default zero-initialization
    };
    const t: f32 = @as(f32, @floatFromInt(self.current_frame)) / 600;

    const pos: [3]f32 = .{ @sin(t * 10) * 5, @sin(t) * 4, 0 };
    // const pos: [3]f32 = .{ 0, 0, 0 };

    self.batcher.reset();
    self.batcher.add(.{ .pos = pos, .rot = 0, .scale = .{ 1, 1 } }, self.duck_texture);
    self.batcher.draw(command_buffer, target_info);
    // const render_pass_ptr = c.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, null);
    // if (render_pass_ptr != null) {
    // const render_pass = render_pass_ptr.?;

    // c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    // c.SDL_BindGPUVertexBuffers(render_pass, 0, &(c.SDL_GPUBufferBinding){ .buffer = self.vertex_buffer, .offset = 0 }, 1);
    // c.SDL_BindGPUIndexBuffer(render_pass, &(c.SDL_GPUBufferBinding){ .buffer = self.index_buffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);
    // c.SDL_BindGPUFragmentSamplers(render_pass, 0, &(c.SDL_GPUTextureSamplerBinding){ .texture = self.duck_texture, .sampler = self.duck_sampler }, 1);

    // const t: f32 = @as(f32, @floatFromInt(self.current_frame)) / 600;
    // // Top-left

    // const pos: zm.Vec = .{ @sin(t * 10) * 5, @sin(t) * 4, 0, 0 };

    // // zm uses row-major matrices so stuff is backwards :)
    // var matrix_uniform = zm.mulMats(&.{
    //     zm.rotationZ(t),
    //     zm.translationV(pos),
    //     comptime zm.lookAtLh(.{ 0, 0, -5, 0 }, .{ 0, 0, 0, 0 }, .{ 0, -1, 0, 0 }),
    //     comptime zm.perspectiveFovLh(std.math.degreesToRadians(90), 1, 1, 100),
    // });
    // const mat_size = @sizeOf(@TypeOf(matrix_uniform));

    // c.SDL_PushGPUVertexUniformData(command_buffer, 0, &matrix_uniform, mat_size);
    // c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &mk.FragMultiplyUniform{ .r = 1.0, .g = 0.5 + c.SDL_sinf(t) * 0.5, .b = 1.0, .a = 1.0 }, @sizeOf(mk.FragMultiplyUniform));
    // c.SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

    // c.ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass, null); // render imgui draw data using the sdlgpu backend commands
    // c.SDL_EndGPURenderPass(render_pass);
    // } else {
    // std.log.warn("failed to begin gpu render pass.", .{});
    // }
    _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit gpu commands for execution
}

pub fn run(self: *Engine) void {
    var prev_t = std.time.nanoTimestamp();
    while (!self.done) {
        const t = std.time.nanoTimestamp();
        if (t - prev_t < 1000000000 / 240) continue;
        self.update();
        self.draw();
        self.current_frame += 1;
        prev_t = t;
    }
}

fn load_content() void {}

fn update(self: *Engine) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != false) {
        _ = c.ImGui_ImplSDL3_ProcessEvent(&event); // pass event to imgui for processing
        if (event.type == c.SDL_EVENT_QUIT) {
            self.done = true;
        }

        if (event.type == c.SDL_EVENT_WINDOW_CLOSE_REQUESTED and event.window.windowID == c.SDL_GetWindowID(self.window)) {
            self.done = true;
        }
    }
    if ((c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MINIMIZED) != 0) {
        std.time.sleep(16 * 1000 * 1000); // if window is minimized, delay to reduce cpu usage
        return;
    }
}
