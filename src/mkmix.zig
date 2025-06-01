const std = @import("std");
pub usingnamespace @import("common.zig");

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
pub const alloc = gpa.allocator();
