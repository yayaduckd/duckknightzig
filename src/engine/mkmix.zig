const std = @import("std");
pub usingnamespace @import("common.zig");
pub usingnamespace @import("camera.zig");
pub usingnamespace @import("renderable.zig");

pub const Batcher = @import("drawer.zig");
pub const Imgui = @import("imgui.zig");
pub const Engine = @import("mlemgine.zig");

const c = @import("cmix.zig");

pub const MkTexture = *c.SDL_GPUTexture;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
pub const alloc = gpa.allocator();
