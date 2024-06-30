const Sprite = @import("../Sprite.zig");

pub const width = 8;
pub const height = 7;
pub const flags = 0; // BLIT_1BPP
pub const data = [7]u8{
    0b11000000,
    0b11110000,
    0b11111100,
    0b11111111,
    0b11111100,
    0b11110000,
    0b11000000,
};

pub fn sprite() Sprite {
    return Sprite{
        .data = &data,
        .width = width,
        .height = height,
        .flags = flags,
    };
}
