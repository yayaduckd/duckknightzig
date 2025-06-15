const c = @import("cmix.zig");
const Batcher = @import("drawer.zig");
const mk = @import("mkmix.zig");
const cam = @import("camera.zig");

const std = @import("std");
const zm = @import("include/zmath.zig");

const log = std.log.scoped(.engine);

const Engine = @This();

pub const EngineImpl = struct {
    init_fn: *const fn (self: *Engine) anyerror!void,
    draw_fn: *const fn (self: *Engine) anyerror!void,
    update_fn: *const fn (self: *Engine) anyerror!void,
};

impl: EngineImpl,

done: bool = false,
window: *c.SDL_Window = undefined,
gpu_device: *c.SDL_GPUDevice = undefined,

// pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
// gpu resources
// vertex_buffer: *c.SDL_GPUBuffer = undefined,
// index_buffer: *c.SDL_GPUBuffer = undefined,

duck_texture: *c.SDL_GPUTexture = undefined,
debug_texture: *c.SDL_GPUTexture = undefined,

depth_texture: *c.SDL_GPUTexture = undefined,
// duck_sampler: *c.SDL_GPUSampler = undefined,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

current_frame: u64 = 0,

// batcher: Batcher = undefined,
renderables: std.ArrayList(mk.Renderable) = undefined,

// im_draw_data: ([*c]c.struct_ImDrawData) = undefined,
camera: @import("camera.zig") = undefined,

fn cleanup(self: *Engine) void {
    c.ImGui_ImplSDLGPU3_Shutdown();
    c.ImGui_ImplSDL3_Shutdown();
    c.igDestroyContext(null); // destroy context
    c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, self.window);
    c.SDL_DestroyGPUDevice(self.gpu_device);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit(); // defer sdl_quit

}

pub fn init(impl: EngineImpl) !Engine {
    var self = Engine{ .impl = impl };

    // setup sdl stuff
    try mk.sdlr(c.SDL_Init(c.SDL_INIT_VIDEO));

    // window & gpu device
    self.window = try mk.sdlv(c.SDL_CreateWindow("tongue", 1000, 1000, c.SDL_WINDOW_RESIZABLE));
    self.gpu_device = try mk.sdlv(c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true, // debug_mode enabled
        null,
    ));
    try mk.sdlr(c.SDL_ClaimWindowForGPUDevice(self.gpu_device, self.window));
    try mk.sdlr(c.SDL_SetGPUSwapchainParameters(self.gpu_device, self.window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX));

    const camera: cam = .default;
    self.camera = camera;
    self.renderables = std.ArrayList(mk.Renderable).init(mk.alloc);

    var w: c_int = 0;
    var h: c_int = 0;
    try mk.sdlr(c.SDL_GetWindowSizeInPixels(self.window, &w, &h));

    self.depth_texture = c.SDL_CreateGPUTexture(self.gpu_device, &(c.SDL_GPUTextureCreateInfo){
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
        .width = @intCast(w),
        .height = @intCast(h),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    }).?;

    try self.impl.init_fn(&self);

    return self;
}

pub fn deinit(self: *Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    self.cleanup();
}

fn push_uniform_buffers(self: *Engine, command_buffer: *c.SDL_GPUCommandBuffer) !void {
    var matrix_uniform = self.camera.create_transform();
    const mat_size = @sizeOf(@TypeOf(matrix_uniform));

    // push vp matrix to position 0
    c.SDL_PushGPUVertexUniformData(command_buffer, 0, &matrix_uniform, mat_size);
}

fn copy(self: *Engine, command_buffer: *c.SDL_GPUCommandBuffer) !void {
    const copy_pass = try mk.sdlv(c.SDL_BeginGPUCopyPass(command_buffer));
    // self.batcher.copy(copy_pass);

    for (self.renderables.items) |*r| {
        r.copy(command_buffer, copy_pass);
    }

    c.SDL_EndGPUCopyPass(copy_pass);

    // imgui.copy_stage(command_buffer);
}

pub fn render(self: *Engine, command_buffer: *c.SDL_GPUCommandBuffer) !void {
    var swapchain_texture_ptr: ?*c.SDL_GPUTexture = null;
    try mk.sdlr(c.SDL_AcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture_ptr, null, null));
    const swapchain_texture = swapchain_texture_ptr orelse {
        log.debug("swapchain texture couldn't be aquired", .{});
        return;
    };

    const target_info: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .clear_color = .{ .r = self.clear_color.x, .g = self.clear_color.y, .b = self.clear_color.z, .a = self.clear_color.w },
        .load_op = c.SDL_GPU_LOADOP_CLEAR, // clear render target on load
        .store_op = c.SDL_GPU_STOREOP_STORE, // store render target contents
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .cycle = true, // safe to cycle as we are re-drawing each frame from scratch (loadop == clear)
        // other target_info fields use default zero-initialization
    };

    const depthStencilTargetInfo: c.SDL_GPUDepthStencilTargetInfo = .{
        .texture = self.depth_texture,
        .cycle = true,
        .clear_depth = 1,
        .clear_stencil = 0,
        .load_op = c.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
    };
    const render_pass = try mk.sdlv(c.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, &depthStencilTargetInfo));

    // self.batcher.render(render_pass);
    for (self.renderables.items) |*r| {
        r.render(command_buffer, render_pass);
    }

    // imgui.render_stage(command_buffer, render_pass);
    c.SDL_EndGPURenderPass(render_pass);
}

fn draw_to_screen(self: *Engine) !void {
    const command_buffer = try mk.sdlv(c.SDL_AcquireGPUCommandBuffer(self.gpu_device));

    for (self.renderables.items) |*r| {
        r.pre_frame(command_buffer);
    }

    try self.push_uniform_buffers(command_buffer);

    try self.copy(command_buffer);

    try self.render(command_buffer);

    _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit gpu commands for execution
}

pub fn run(self: *Engine) !void {
    var prev_t = std.time.nanoTimestamp();
    while (!self.done) {
        const t = std.time.nanoTimestamp();
        if (t - prev_t < 1000000000 / 240) continue;
        try self.impl.update_fn(self);
        self.update();
        try self.impl.draw_fn(self);

        try self.draw_to_screen(); // sdl gpu render logic

        self.current_frame += 1;
        prev_t = t;
    }
}

fn update(self: *Engine) void {
    _ = self; // autofix

}
