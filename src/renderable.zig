const Engine = @import("mlemgine.zig");
const c = @import("cmix.zig");
const mk = @import("mkmix.zig");
const std = @import("std");

const batcher = @import("drawer.zig");
const imgui = @import("imgui.zig");

const log = std.log.scoped(.renderable);

pub const Renderable = union(enum) {
    batcher: *batcher,
    imgui: *imgui,

    pub fn pre_frame(self: Renderable, cmd_buf: *c.SDL_GPUCommandBuffer) void {
        switch (self) {
            .imgui => |i| return i.pre_frame(cmd_buf),
            else => {},
        }
    }

    pub fn copy(self: Renderable, cmd_buf: *c.SDL_GPUCommandBuffer, copy_pass: *c.SDL_GPUCopyPass) void {
        switch (self) {
            .batcher => |b| return b.copy(copy_pass),

            .imgui => |i| return i.copy(cmd_buf),
        }
    }

    pub fn render(self: Renderable, cmd_buf: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass) void {
        switch (self) {
            .batcher => |b| return b.render(render_pass),
            .imgui => |i| return i.render(cmd_buf, render_pass),
        }
    }
};
