const std = @import("std");

pub const Chuk = @import("chuks.zig");

pub var numIDs: u32 = 0;
pub fn newID() u32 {
    defer numIDs += 1;
    return numIDs;
}

pub fn SparseArray(T: type) type {
    return std.AutoArrayHashMap(u32, T);
}

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
pub const alloc = gpa.allocator();
