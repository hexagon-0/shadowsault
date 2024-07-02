const img = @import("img.zig");
const Rect = @import("Rect.zig");
const Sprite = @import("Sprite.zig");

rect: Rect,
sprite: Sprite,

const Self = @This();

pub const HorizontalDir = enum(i2) {
    left = -1,
    right = 1,

    pub fn flipped(self: HorizontalDir) HorizontalDir {
        return switch (self) {
            .left => .right,
            .right => .left,
        };
    }

    pub fn flip(self: *HorizontalDir) void {
        self.* = self.flipped();
    }
};

pub fn init() Self {
    const sprite = img.player.sprite();
    return Self{ .rect = .{ .x = 0, .y = 0, .w = 8, .h = 8 }, .sprite = sprite };
}

pub fn draw(self: Self) void {
    self.sprite.draw(self.rect.x, self.rect.y);
}
