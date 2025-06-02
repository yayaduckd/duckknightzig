const c = @import("cmix.zig");
const Batcher = @import("drawer.zig");
const mk = @import("common.zig");
const cam = @import("camera.zig");

const std = @import("std");
const zm = @import("include/zmath.zig");

const Engine = @This();

done: bool = false,
window: *c.SDL_Window = undefined,
gpu_device: *c.SDL_GPUDevice = undefined,

// pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
// gpu resources
// vertex_buffer: *c.SDL_GPUBuffer = undefined,
// index_buffer: *c.SDL_GPUBuffer = undefined,

duck_texture: *c.SDL_GPUTexture = undefined,
debug_texture: *c.SDL_GPUTexture = undefined,
// duck_sampler: *c.SDL_GPUSampler = undefined,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

current_frame: u64 = 0,

batcher: Batcher = undefined,

im_draw_data: ([*c]c.struct_ImDrawData) = undefined,

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
    self.window = try mk.sdlv(c.SDL_CreateWindow("tongue", 1000, 1000, c.SDL_WINDOW_RESIZABLE));

    // gpu device creation
    self.gpu_device = try mk.sdlv(c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true, // debug_mode enabled
        null,
    ));

    // claim window for gpu device
    try mk.sdlr(c.SDL_ClaimWindowForGPUDevice(self.gpu_device, self.window));

    // set swapchain parameters
    try mk.sdlr(c.SDL_SetGPUSwapchainParameters(self.gpu_device, self.window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX));
}

pub fn init() !Engine {
    var self = Engine{};

    // setup general stuff
    try self.init_graphics();

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

    const camera: cam = .default;
    self.batcher = try Batcher.init(
        self.gpu_device,
        self.window,
        camera,
    );
    try self.load_content();

    return self;
}

pub fn deinit(self: *Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    self.cleanup();
}

fn copy(self: *Engine, command_buffer: *c.SDL_GPUCommandBuffer) !void {
    const copy_pass = try mk.sdlv(c.SDL_BeginGPUCopyPass(command_buffer));
    self.batcher.copy(copy_pass);
    c.SDL_EndGPUCopyPass(copy_pass);

    c.Imgui_ImplSDLGPU3_PrepareDrawData(self.im_draw_data, command_buffer); // prepare imgui draw data for sdlgpu backend

}

pub fn render(self: *Engine, command_buffer: *c.SDL_GPUCommandBuffer) !void {
    var swapchain_texture_ptr: ?*c.SDL_GPUTexture = null;
    try mk.sdlr(c.SDL_AcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture_ptr, null, null));
    const swapchain_texture = try mk.sdlv(swapchain_texture_ptr);

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

    const render_pass = try mk.sdlv(c.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, null));

    self.batcher.render(command_buffer, render_pass);

    c.ImGui_ImplSDLGPU3_RenderDrawData(self.im_draw_data, command_buffer, render_pass, null); // render imgui draw data using the sdlgpu backend commands
    c.SDL_EndGPURenderPass(render_pass);
}

fn imgui_frame(self: *Engine) !void {
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

    const draw_data = try mk.sdlv(c.igGetDrawData());
    if (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0) {
        std.time.sleep(16 * 1000 * 1000); // if draw area is 0 or negative, skip rendering cycle
        return;
    }
    self.im_draw_data = draw_data;
}

fn draw_to_screen(self: *Engine) !void {
    const command_buffer = try mk.sdlv(c.SDL_AcquireGPUCommandBuffer(self.gpu_device));

    // get swapchain texture early
    // var swapchain_texture_ptr: ?*c.SDL_GPUTexture = null;
    // try mk.sdlr(c.SDL_AcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture_ptr, null, null));
    // const swapchain_texture = try mk.sdlv(swapchain_texture_ptr);

    try self.imgui_frame();

    try self.copy(command_buffer);
    try self.render(command_buffer);

    _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit gpu commands for execution
}

pub fn run(self: *Engine) !void {
    var prev_t = std.time.nanoTimestamp();
    while (!self.done) {
        const t = std.time.nanoTimestamp();
        if (t - prev_t < 1000000000 / 240) continue;
        self.update(); // update game logic
        try self.draw(); // draw sprites with xna-type interface
        try self.draw_to_screen(); // sdl gpu render logic
        self.current_frame += 1;
        prev_t = t;
    }
}

fn draw(self: *Engine) !void {
    self.batcher.begin();
    const t: f32 = @as(f32, @floatFromInt(self.current_frame)) / 600;
    const grid_size: usize = 700;
    const spacing: f32 = 1;
    const scale: f32 = 1;
    for (0..grid_size) |y| {
        for (0..grid_size) |x| {
            const xi: isize = @intCast(x);
            const yi: isize = @intCast(y);
            const pos_x = @as(f32, @floatFromInt(xi - grid_size / 2)) * spacing;
            const pos_y = @as(f32, @floatFromInt(yi - grid_size / 2)) * spacing;
            self.batcher.add(
                .{
                    .pos = .{ pos_x, pos_y, 0 },
                    .rot = t,
                    .scale = .{ scale, scale },
                },
                self.duck_texture,
            );
            self.batcher.add(
                .{
                    .pos = .{ pos_x + 0.5 * spacing, pos_y + 0.5, 0 },
                    .rot = t,
                    .scale = .{ scale / 2, scale / 2 },
                },
                self.debug_texture,
            );
        }
    }
    self.batcher.end();
}

fn load_content(self: *Engine) !void {
    var image_data = try mk.load_image("mduck.png", 4);
    self.duck_texture = self.batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);

    image_data = try mk.load_image("debug.png", 4);
    self.debug_texture = self.batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);
}

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

        // inputs
        if (event.type == c.SDL_EVENT_KEY_DOWN) {
            if (event.key.scancode == c.SDL_SCANCODE_A) {
                self.batcher.camera.translate(.{ -0.1, 0 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_D) {
                self.batcher.camera.translate(.{ 0.1, 0 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_W) {
                self.batcher.camera.translate(.{ 0, 0.1 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_S) {
                self.batcher.camera.translate(.{ 0, -0.1 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_Q) {
                self.batcher.camera.zoom(-0.1);
            }
            if (event.key.scancode == c.SDL_SCANCODE_E) {
                self.batcher.camera.zoom(0.1);
            }
            if (event.key.scancode == c.SDL_SCANCODE_R) {
                self.batcher.camera.rotate(std.math.degreesToRadians(10));
            }
        }

        // if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
        //     const x = event.motion.xrel;
        //     const y = event.motion.yrel;
        //     self.batcher.camera.origin_offset(.{ x, y });
        //     std.log.debug("motion x {d} y {d} offs {d}", .{ x, y, self.batcher.camera.lookat_origin_offset });
        // }
    }
    if ((c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MINIMIZED) != 0) {
        std.time.sleep(16 * 1000 * 1000); // if window is minimized, delay to reduce cpu usage
        return;
    }
}
