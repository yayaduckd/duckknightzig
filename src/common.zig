const c = @import("cmix.zig");
const std = @import("std");

pub fn sdlr(success: bool) !void {
    if (!success) {
        const err_str_ptr = c.SDL_GetError();
        std.log.err("sdl error: {s}", .{err_str_ptr});
        return error.SDLBorken;
    }
}

pub fn fatal_sdl_error(comptime msg: []const u8) !void {
    const err_str_ptr = c.SDL_GetError();
    if (err_str_ptr) |raw_err_str| {
        std.log.err("{s} - {s}", .{ msg, std.mem.sliceTo(raw_err_str, 0) });
    } else {
        std.log.err("{s} - (no sdl error message available)", .{msg});
    }
    return error.SDLBorken;
}
