const std = @import("std");
const mk = @import("engine/mkmix.zig");
const c = @import("engine/cmix.zig");
const dk = @import("dkmix.zig");

pub var textures: dk.SparseArray(mk.MkTexture) = undefined;
pub var bodies: dk.SparseArray(c.b2BodyId) = undefined;

const Self = @This();

// const CELL_SIZE = 10;

// Constructor/initializer for the static struct
pub fn init() void {
    textures = dk.SparseArray(mk.MkTexture).init(dk.alloc);
    bodies = dk.SparseArray(c.b2BodyId).init(dk.alloc);
}

pub fn newSquare(world: c.b2WorldId, pos: c.b2Vec2, size: f32, texture: mk.MkTexture) u32 {
    // Implement the logic for creating a new square.
    // This will involve:
    // 1. Generating a new ID using DODUtils.newID().
    // 2. Getting the physics world from MlemKnight.Instance.PhysWorld.
    // 3. Defining and creating a Box2D body (b2DefaultBodyDef, b2CreateBody).
    // 4. Creating a Box2D polygon shape (b2MakeOffsetBox).
    // 5. Defining and creating a Box2D shape (b2DefaultShapeDef, b2CreatePolygonShape).
    // 6. Storing the bodyId and texture in the ch_bodies and ch_textures sparse arrays.
    const id = dk.newID();

    var bodyDef = c.b2DefaultBodyDef();
    bodyDef.position = pos;
    bodyDef.type = c.b2_dynamicBody;

    const body = c.b2CreateBody(world, &bodyDef);
    const box = c.b2MakeOffsetBox(size / 2, size / 2, .{ .x = size / 2, .y = size / 2 }, c.b2MakeRot(0));

    var shapeDef = c.b2DefaultShapeDef();
    shapeDef.density = 1.0;
    shapeDef.material.friction = 0.3;
    shapeDef.material.restitution = 0;
    const shapeId = c.b2CreatePolygonShape(body, &shapeDef, &box);
    _ = shapeId;

    textures.put(id, texture) catch unreachable;
    bodies.put(id, body) catch unreachable;

    return id;
}

pub fn draw(sprite_batch: *mk.Batcher) void {
    for (0..textures.count()) |i| {
        const texture = textures.get(@intCast(i)).?;
        const bodyId = bodies.get(@intCast(i)).?;
        const pos = c.b2Body_GetPosition(bodyId);
        const angle = c.b2Rot_GetAngle(c.b2Body_GetRotation(bodyId));

        sprite_batch.add(.{
            .pos = .{ pos.x, pos.y, 0 },
            .rot = angle,
            .scale = .{ 1, 1 },
        }, texture);
    }
}
