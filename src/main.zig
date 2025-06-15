const Engine = @import("engine/mlemgine.zig");

const Game = @import("game.zig");

pub fn main() !void {
    const impl = Engine.EngineImpl{
        .init_fn = &Game.init,
        .draw_fn = &Game.draw,
        .update_fn = &Game.update,
    };

    var mlem = try Engine.init(impl);
    try mlem.run();
}
