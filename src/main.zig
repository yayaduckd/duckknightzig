const std = @import("std");
const c = @import("cmix.zig");
const mk = @import("mkmix.zig");

const Engine = @import("mlemgine.zig");
const Batcher = @import("drawer.zig");
const Imgui = @import("imgui.zig");

var batcher: Batcher = undefined;
var igInst: @import("imgui.zig") = undefined;

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
        // self.im_draw_data = draw_data;
        return;
    }
    c.igPushItemWidth(c.igGetFontSize() * -12);
    c.igText(&mk.frame_print_buffer);
    mk.reset_frame_print_buffer();
    c.igEnd();
}

fn init(engine: *Engine) anyerror!void {
    batcher = try Batcher.init(engine.*);
    var image_data = try mk.load_image("mduck.png", 4);
    engine.duck_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);

    image_data = try mk.load_image("debug.png", 4);
    engine.debug_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);
    try engine.renderables.append(mk.Renderable{ .batcher = &batcher });

    igInst = try Imgui.init(engine.window, engine.gpu_device);
    try engine.renderables.append(mk.Renderable{ .imgui = &(igInst) });
}

fn draw(self: *Engine) !void {
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
                self.duck_texture,
            );
            batcher.add(
                .{
                    .pos = .{ pos_x + 0.5 * spacing, pos_y + 0.5, @sin(t) },
                    .rot = t,
                    .scale = .{ scale / 2, scale / 2 },
                },
                self.debug_texture,
            );
        }
    }
    batcher.end();
    imgui_menu();
}

fn update(self: *Engine) anyerror!void {
    _ = self; // autofix

}

pub fn main() !void {
    const impl = Engine.EngineImpl{
        .init_fn = &init,
        .draw_fn = &draw,
        .update_fn = &update,
    };

    var mlem = try Engine.init(impl);
    try mlem.run();
}
