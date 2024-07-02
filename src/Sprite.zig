const w4 = @import("wasm4.zig");
const Self = @This();

data: []const u8,
width: u32,
height: u32,
flags: u32,
offset_x: i16 = 0,
offset_y: i16 = 0,
hframes: u16 = 1,
vframes: u16 = 1,
frame: u16 = 0,

pub fn draw(self: Self, x: i32, y: i32) void {
    const src_x = self.frame % self.hframes * self.width;
    const src_y = @divFloor(self.frame, self.hframes) * self.height;
    w4.blitSub(self.data.ptr, x + self.offset_x, y + self.offset_y, self.width, self.height, src_x, src_y, self.width, self.flags);
}

pub const Region = struct {
    x: u32,
    y: u32,
    stride: u32,
};
