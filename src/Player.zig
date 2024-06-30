const Rect = @import("Rect.zig");

rect: Rect,

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

pub fn draw(self: Self) void {
    self.rect.draw();
}
