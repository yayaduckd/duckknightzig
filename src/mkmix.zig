const std = @import("std");
pub usingnamespace @import("common.zig");
pub usingnamespace @import("camera.zig");
pub usingnamespace @import("renderable.zig");

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
pub const alloc = gpa.allocator();
