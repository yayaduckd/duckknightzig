const Engine = @import("mlemgine.zig");
const c = @import("cmix.zig");
const mk = @import("mkmix.zig");
const std = @import("std");

const batcher = @import("drawer.zig");

const log = std.log.scoped(.renderable);

pub const Renderable = union(enum) {
    batcher: *mk.batcher,

    pub fn copy(self: Renderable, copy_pass: *c.SDL_GPUCopyPass) void {
        switch (self) {
            .batcher => |b| return b.copy(copy_pass),
        }
    }

    pub fn render(self: Renderable, render_pass: *c.SDL_GPURenderPass) void {
        switch (self) {
            .batcher => |b| return b.render(render_pass),
        }
    }
};
