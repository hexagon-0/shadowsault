const w4 = @import("wasm4.zig");
const Rect = @import("Rect.zig");
const Sprite = @import("Sprite.zig");
const img = @import("img.zig");

rect: Rect,
sprite: Sprite,
length: u8,

const Spike = @This();

var spawn_timer: f32 = 0;

pub fn init(flipped: bool, length: u8) Spike {
    var sprite = img.spike.sprite();
    sprite.offset_y = -3; // Rect should only start and end at spike tips

    if (flipped) {
        sprite.flags |= w4.BLIT_FLIP_X;
    }

    const w: u16 = @intCast(sprite.width);
    const h = @as(i33, sprite.height * length) + sprite.offset_y * 2;

    return Spike{
        .rect = .{ .x = 0, .y = 0, .w = w, .h = @intCast(h) },
        .sprite = sprite,
        .length = length,
    };
}

pub fn draw(self: Spike) void {
    const x = self.rect.x;

    for (0..self.length) |i| {
        const y = self.rect.y + @as(i32, @intCast(i)) * @as(i32, @intCast(self.sprite.height));

        self.sprite.draw(x, y);
    }
}
