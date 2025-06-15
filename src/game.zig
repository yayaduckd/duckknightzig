const std = @import("std");
const c = @import("engine/cmix.zig");
const mk = @import("engine/mkmix.zig");
const dk = @import("dkmix.zig");

var batcher: mk.Batcher = undefined;
var igInst: mk.Imgui = undefined;

var world: c.b2WorldId = undefined;

pub fn imgui_menu() void {
    // start a new imgui frame
    c.ImGui_ImplSDLGPU3_NewFrame();
    c.ImGui_ImplSDL3_NewFrame();
    c.igNewFrame();
    // show imgui's built-in demo window
    var show_demo_window = true;
    if (show_demo_window) {
        c.igShowDemoWindow(&show_demo_window);
    }

    var show_mlem_window = true;
    c.igSetNextWindowSize(.{ .x = 200, .y = 200 }, c.ImGuiCond_Once);
    if (!c.igBegin("mlamOS", &show_mlem_window, 0)) {
        c.igEnd();
        c.igRender();
        const draw_data = mk.sdlv(c.igGetDrawData()) catch return;
        if (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0) {
            std.time.sleep(16 * 1000 * 1000); // if draw area is 0 or negative, skip rendering cycle
            return;
        }
        return;
    }
    c.igPushItemWidth(c.igGetFontSize() * -12);
    c.igText(&mk.frame_print_buffer);
    mk.reset_frame_print_buffer();
    c.igEnd();
}

var duck_texture: mk.MkTexture = undefined;
var debug_texture: mk.MkTexture = undefined;
pub fn init(engine: *mk.Engine) anyerror!void {
    batcher = try mk.Batcher.init(engine.*);
    var image_data = try mk.load_image("mduck.png", 4);
    duck_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);

    image_data = try mk.load_image("debug.png", 4);
    debug_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);
    try engine.renderables.append(mk.Renderable{ .batcher = &batcher });

    igInst = try mk.Imgui.init(engine.window, engine.gpu_device);
    try engine.renderables.append(mk.Renderable{ .imgui = &(igInst) });

    var worlddef = c.b2DefaultWorldDef();
    worlddef.gravity = c.b2Vec2{ .x = 0, .y = 1 };

    world = c.b2CreateWorld(&worlddef);
    dk.Chuk.init();
    _ = dk.Chuk.newSquare(world, c.b2Vec2{ .x = -1, .y = -1 }, 1, debug_texture, true);
}

pub fn draw(self: *mk.Engine) !void {
    batcher.begin();
    const t: f32 = @as(f32, @floatFromInt(self.current_frame)) / 600;
    const grid_size: usize = 10;
    const spacing: f32 = 1;
    const scale: f32 = 1;
    for (0..grid_size) |y| {
        for (0..grid_size) |x| {
            const xi: isize = @intCast(x);
            const yi: isize = @intCast(y);
            const pos_x = @as(f32, @floatFromInt(xi - grid_size / 2)) * spacing;
            const pos_y = @as(f32, @floatFromInt(yi - grid_size / 2)) * spacing;
            batcher.add(
                .{
                    .pos = .{ pos_x, pos_y, 0 },
                    .rot = t,
                    .scale = .{ scale, scale },
                },
                duck_texture,
            );
            batcher.add(
                .{
                    .pos = .{ pos_x + 0.5 * spacing, pos_y + 0.5, @sin(t) },
                    .rot = t,
                    .scale = .{ scale / 2, scale / 2 },
                },
                debug_texture,
            );
        }
    }

    dk.Chuk.draw(&batcher);

    batcher.end();
    imgui_menu();
}

pub fn update(self: *mk.Engine) anyerror!void {

    // inputs
    var event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&event) != false) {
        _ = c.ImGui_ImplSDL3_ProcessEvent(&event); // pass event to imgui for processing
        if (event.type == c.SDL_EVENT_QUIT) {
            self.done = true;
        }

        if (event.type == c.SDL_EVENT_WINDOW_CLOSE_REQUESTED and event.window.windowID == c.SDL_GetWindowID(self.window)) {
            self.done = true;
        }
        if (event.type == c.SDL_EVENT_KEY_DOWN) {
            if (event.key.scancode == c.SDL_SCANCODE_A) {
                self.camera.translate(.{ -0.1, 0, 0 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_D) {
                self.camera.translate(.{ 0.1, 0, 0 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_W) {
                self.camera.translate(.{ 0, 0, -0.1 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_S) {
                self.camera.translate(.{ 0, 0, 0.1 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_Q) {
                self.camera.translate(.{ 0, -0.1, 0 });

                // self.camera.zoom(-0.1);
            }
            if (event.key.scancode == c.SDL_SCANCODE_E) {
                // self.camera.zoom(0.1);
                self.camera.translate(.{ 0, 0.1, 0 });
            }
            if (event.key.scancode == c.SDL_SCANCODE_R) {
                self.camera.rotate(std.math.degreesToRadians(10));
            }
        }
    }
    var x: f32 = 0;
    var y: f32 = 0;
    _ = c.SDL_GetMouseState(&x, &y);
    mk.frame_print("mouse x {d} y {d}\n", .{ x, y });
    mk.frame_print("cam x {d} y {d} z {d}", .{ self.camera.pos[0], self.camera.pos[1], self.camera.pos[2] });

    if ((c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MINIMIZED) != 0) {
        std.time.sleep(16 * 1000 * 1000); // if window is minimized, delay to reduce cpu usage
        return;
    }

    const time_step: f32 = 1.0 / 60.0;
    const substep_count = 4;
    c.b2World_Step(world, time_step, substep_count);
}
