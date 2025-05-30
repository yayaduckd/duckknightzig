const c = @import("cmix.zig");
const std = @import("std");
const mk = @import("common.zig");

const Engine = @This();

done: bool = false,
window: *c.struct_SDL_Window = undefined,
gpu_device: *c.SDL_GPUDevice = undefined,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

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
    const shader = try mk.load_shader(self.gpu_device, "tringle.vert.spv", 0, 0, 0, 0);
    _ = shader; // autofix

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
        c.SDL_Delay(16);
        return;
    }
    const draw_data = draw_data_ptr.?;
    if (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0) {
        c.SDL_Delay(16); // if draw area is 0 or negative, skip rendering cycle
        return;
    }

    const command_buffer_ptr = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
    if (command_buffer_ptr == null) {
        std.log.warn("failed to acquire gpu command buffer.", .{});
        c.SDL_Delay(16);
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

    var target_info: c.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .clear_color = .{ .r = self.clear_color.x, .g = self.clear_color.y, .b = self.clear_color.z, .a = self.clear_color.w },
        .load_op = c.SDL_GPU_LOADOP_CLEAR, // clear render target on load
        .store_op = c.SDL_GPU_STOREOP_STORE, // store render target contents
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .cycle = false,
        // other target_info fields use default zero-initialization
    };

    const render_pass_ptr = c.SDL_BeginGPURenderPass(command_buffer, &target_info, 1, null);
    if (render_pass_ptr != null) {
        const render_pass = render_pass_ptr.?;
        c.ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass, null); // render imgui draw data using the sdlgpu backend commands
        c.SDL_EndGPURenderPass(render_pass);
    } else {
        std.log.warn("failed to begin gpu render pass.", .{});
    }
    _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit gpu commands for execution
}

pub fn run(self: *Engine) void {
    while (!self.done) {
        self.update();
        self.draw();
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
        c.SDL_Delay(10); // if window is minimized, delay to reduce cpu usage
        return;
    }
}
