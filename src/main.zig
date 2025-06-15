const std = @import("std");
const c = @import("cmix.zig");
const mk = @import("mkmix.zig");

const Engine = @import("mlemgine.zig");
const Batcher = @import("drawer.zig");

var batcher: Batcher = undefined;

fn init(engine: *Engine) anyerror!void {
    batcher = try Batcher.init(engine.*);
    var image_data = try mk.load_image("mduck.png", 4);
    engine.duck_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);

    image_data = try mk.load_image("debug.png", 4);
    engine.debug_texture = batcher.register_texture(image_data);
    c.SDL_DestroySurface(image_data);
    try engine.renderables.append(mk.Renderable{ .batcher = &batcher });
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
