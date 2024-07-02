const w4 = @import("wasm4.zig");
const Rect = @import("Rect.zig");
const Sprite = @import("Sprite.zig");
const img = @import("img.zig");

rect: Rect,
sprite: Sprite,

const Self = @This();

pub fn init(flipped: bool) Self {
    var sprite = img.pipe.sprite();
    sprite.height = 8;

    if (flipped) {
        sprite.flags |= w4.BLIT_FLIP_X;
    }

    return Self{
        .rect = .{ .x = 0, .y = 0, .w = 8, .h = 8 },
        .sprite = sprite,
    };
}

pub fn draw(self: Self) void {
    self.sprite.draw(self.rect.x, self.rect.y);
}
