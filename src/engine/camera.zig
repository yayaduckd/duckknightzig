const std = @import("std");

const zm = @import("include/zmath.zig");

projection: zm.Mat,

pos: @Vector(3, f32),
angle: f32,
scale: f32,

lookat_origin_offset: @Vector(2, f32),

const Camera = @This();

pub const default: Camera = .{
    .pos = .{ 0, 0, 20 },
    .lookat_origin_offset = .{ 0, 0 },
    .angle = 0,
    .scale = 1,
    .projection = zm.perspectiveFovLh(std.math.degreesToRadians(90), 1, 1, 100),
};

pub fn translate(self: *Camera, dir: @Vector(3, f32)) void {
    self.pos += dir;
}

pub fn origin_offset(self: *Camera, dir: @Vector(2, f32)) void {
    self.lookat_origin_offset += dir;
}

pub fn rotate(self: *Camera, angle: f32) void {
    self.angle += angle;
}

pub fn zoom(self: *Camera, factor: f32) void {
    self.scale += factor;
}

pub fn create_transform(self: *Camera) zm.Mat {
    return zm.transpose(zm.mulMats(&.{
        zm.rotationZ(self.angle),
        zm.scaling(self.scale, self.scale, 1),
        zm.lookAtLh(.{ self.pos[0], self.pos[1], self.pos[2], 0 }, .{ self.pos[0], self.pos[1], self.pos[2] - 20, 0 }, .{ 0, -1, 0, 0 }),
        self.projection,
    }));
}
