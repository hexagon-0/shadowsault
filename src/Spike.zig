const w4 = @import("wasm4.zig");
const Rect = @import("Rect.zig");

rect: Rect,
flipped: bool,
length: u8,

const Spike = @This();

const sprite = [_]u8{
    0b11000000,
    0b11110000,
    0b11111100,
    0b11111111,
    0b11111100,
    0b11110000,
    0b11000000,
};

const sprite_w = 8;
const sprite_h = 7;
const sprite_offset_y = -3; // Rect should only start and end at spike tips

var spawn_timer: f32 = 0;

pub fn init(flipped: bool, length: u8) Spike {
    const w = sprite_w;
    const h = sprite_h * @as(i16, @intCast(length)) + sprite_offset_y + sprite_offset_y;

    return Spike{
        .rect = .{ .x = 0, .y = 0, .w = w, .h = @intCast(h) },
        .flipped = flipped,
        .length = length,
    };
}

pub fn draw(self: Spike) void {
    var flags = w4.BLIT_1BPP;
    const x = self.rect.x;

    if (self.flipped) {
        flags |= w4.BLIT_FLIP_X;
    }

    for (0..self.length) |i| {
        const y = self.rect.y + @as(i32, @intCast(i)) * Spike.sprite_h + Spike.sprite_offset_y;

        w4.blit(&Spike.sprite, x, y, Spike.sprite_w, Spike.sprite_h, flags);
    }
}

pub fn update(self: *Spike) void {
    self.rect.y += 1;
    if (self.rect.y >= w4.SCREEN_SIZE) {
        self.rect.y = @intCast(self.rect.h);
        self.rect.y = -self.rect.y;
    }
}
