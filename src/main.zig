const std = @import("std");
const c = @import("cmix.zig"); // your c bindings

const e = @import("mlemgine.zig");

pub fn main() !void {
    var mlem = try e.init();
    mlem.run();
}
