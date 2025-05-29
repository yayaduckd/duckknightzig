const std = @import("std");
const c = @import("cmix.zig"); // your c bindings

// helper for sdl errors
fn fatal_sdl_error(comptime msg: []const u8) void {
    const err_str_ptr = c.SDL_GetError();
    if (err_str_ptr) |raw_err_str| {
        std.log.err("{s} - {s}", .{ msg, std.mem.sliceTo(raw_err_str, 0) });
        std.debug.panic("{s} - {s}", .{ msg, std.mem.sliceTo(raw_err_str, 0) });
    } else {
        std.log.err("{s} - (no sdl error message available)", .{msg});
        std.debug.panic("{s} - (no sdl error message available)", .{msg});
    }
}

fn sdlr(success: bool) void {
    if (!success) {
        const err_str_ptr = c.SDL_GetError();
        std.log.err("sdl error: {s}", .{err_str_ptr});
        std.debug.panic("sdl error: {s}", .{err_str_ptr});
    }
}

pub fn main() !void {
    // sdl initialization
    sdlr(c.SDL_Init(c.SDL_INIT_VIDEO));
    defer c.SDL_Quit(); // defer sdl_quit

    // window creation
    const window_ptr = c.SDL_CreateWindow("tongue", 1000, 1000, c.SDL_WINDOW_RESIZABLE);
    if (window_ptr == null) {
        fatal_sdl_error("failed to create window");
    }
    const window = window_ptr.?; // unwrap window pointer
    defer c.SDL_DestroyWindow(window);

    // gpu device creation
    const gpu_device_ptr = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_METALLIB,
        true, // debug_mode enabled
        null,
    );
    if (gpu_device_ptr == null) {
        fatal_sdl_error("failed to make gpu device");
    }
    const gpu_device = gpu_device_ptr.?;
    defer c.SDL_DestroyGPUDevice(gpu_device);

    // claim window for gpu device
    sdlr(c.SDL_ClaimWindowForGPUDevice(gpu_device, window));
    defer _ = c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    // set swapchain parameters
    sdlr(c.SDL_SetGPUSwapchainParameters(gpu_device, window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_MAILBOX));

    // setup imgui context and io
    _ = c.igCreateContext(null);
    defer c.igDestroyContext(null); // destroy context
    const io = c.igGetIO_Nil();
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard; // enable keyboard navigation
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableGamepad; // enable gamepad navigation

    // set imgui style to dark
    c.igStyleColorsDark(null);

    // initialize imgui platform/renderer backends
    // assuming sdl_bool return (0 for false) for imgui_implsdl3_initforsdlgpu
    if (c.ImGui_ImplSDL3_InitForSDLGPU(window) == false) {
        std.log.err("imgui_implsdl3_initforsdlgpu failed.", .{});
    }
    defer c.ImGui_ImplSDL3_Shutdown();

    var init_info: c.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = gpu_device,
        .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
        // other fields are zero-initialized by default
    };
    if (c.ImGui_ImplSDLGPU3_Init(&init_info) == false) {
        std.log.err("imgui_implsdlgpu3_init failed.", .{});
    }
    defer c.ImGui_ImplSDLGPU3_Shutdown();

    // application state
    var show_demo_window: bool = true;
    const clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }; // clear color for rendering

    // main event loop
    var done: bool = false;
    while (!done) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != false) {
            _ = c.ImGui_ImplSDL3_ProcessEvent(&event); // pass event to imgui for processing
            if (event.type == c.SDL_EVENT_QUIT) {
                done = true;
            }
            // handle specific window close request event (from c example)
            // note: the original code `event.type c.SDL_EVENT_WINDOW_CLOSE_REQUESTED and event.window.windowID c.SDL_GetWindowID(window)`
            // appeared to be missing comparison operators. if this was intentional due to a macro or specific binding behavior,
            // it has been preserved. otherwise, it might need `==` operators.
            if (event.type == c.SDL_EVENT_WINDOW_CLOSE_REQUESTED and event.window.windowID == c.SDL_GetWindowID(window)) {
                done = true;
            }
        }

        if ((c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_MINIMIZED) != 0) {
            c.SDL_Delay(10); // if window is minimized, delay to reduce cpu usage
            continue;
        }

        // start a new imgui frame
        c.ImGui_ImplSDLGPU3_NewFrame();
        c.ImGui_ImplSDL3_NewFrame();
        c.igNewFrame();

        // show imgui's built-in demo window
        if (show_demo_window) {
            c.igShowDemoWindow(&show_demo_window);
        }

        // rendering phase
        c.igRender();
        const draw_data_ptr = c.igGetDrawData();
        if (draw_data_ptr == null) {
            std.log.warn("iggetdrawdata() returned null.", .{});
            c.SDL_Delay(16);
            continue;
        }
        const draw_data = draw_data_ptr.?;
        if (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0) {
            c.SDL_Delay(16); // if draw area is 0 or negative, skip rendering cycle
            continue;
        }

        const command_buffer_ptr = c.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (command_buffer_ptr == null) {
            std.log.warn("failed to acquire gpu command buffer.", .{});
            c.SDL_Delay(16);
            continue;
        }
        const command_buffer = command_buffer_ptr.?;

        var swapchain_texture_ptr: ?*c.SDL_GPUTexture = null;
        if (c.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture_ptr, null, null) == false) {
            std.log.warn("failed to acquire gpu swapchain texture.", .{});
            _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit command buffer
            continue;
        }

        // sdl_acquiregpuswapchaintexture might return true without a valid texture pointer in some edge cases.
        // current code assumes a non-null texture if true is returned; specific error handling might be needed.
        if (swapchain_texture_ptr == null) {
            // this case might indicate an issue or a specific state (e.g., window resized, try next frame)
            // depending on sdl_gpu api contract, may need to submit command buffer here too.
            _ = c.SDL_SubmitGPUCommandBuffer(command_buffer); // submit command buffer, as it was acquired
            continue;
        }
        const swapchain_texture = swapchain_texture_ptr.?;

        c.Imgui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer); // prepare imgui draw data for sdlgpu backend

        var target_info: c.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
            .clear_color = .{ .r = clear_color.x, .g = clear_color.y, .b = clear_color.z, .a = clear_color.w },
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

    // application cleanup
    _ = c.SDL_WaitForGPUIdle(gpu_device); // ensure all gpu operations are complete before exiting
    // deferred statements will now execute for cleanup.
}
