const w4 = @import("wasm4.zig");

x: i32,
y: i32,
w: u16,
h: u16,

const Self = @This();

pub fn draw(self: Self) void {
    w4.rect(self.x, self.y, self.w, self.h);
}

pub inline fn right(self: Self) i32 {
    return self.x + @as(i32, self.w);
}

pub inline fn bottom(self: Self) i32 {
    return self.y + @as(i32, self.h);
}

pub fn intersects(self: Self, other: Self) bool {
    return self.right() > other.x and self.x < other.right() and self.bottom() > other.y and self.y < other.bottom();
}
