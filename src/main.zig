const w4 = @import("wasm4.zig");
const std = @import("std");
const Rect = @import("Rect.zig");
const Spike = @import("Spike.zig");

const HorizontalDir = enum(i2) {
    left = -1,
    right = 1,

    fn flipped(self: HorizontalDir) HorizontalDir {
        return switch (self) {
            .left => .right,
            .right => .left,
        };
    }
};

const shield_sprite = [_]u8{
    0b10011001,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b01111110,
    0b00111100,
};

const jump_mask = w4.BUTTON_1 | w4.BUTTON_2 | w4.BUTTON_LEFT | w4.BUTTON_RIGHT | w4.BUTTON_UP | w4.BUTTON_DOWN;

const world_boundary_left = 38;
const world_boundary_right = w4.SCREEN_SIZE - 38;

var rng: std.Random.DefaultPrng = undefined;

var player: Rect = undefined;
var gravity_dir: HorizontalDir = .left;
var prev_gamepad: u8 = 0;
var jump_buffer: u8 = 0;
var prev_on_wall: bool = false;

const max_shield: u16 = 5 * 60; // 5s * 60FPS
var shield: u16 = 0;

var score: u32 = 0;
var score_text: [11]u8 = undefined;
var score_to_draw: []const u8 = &score_text;
var high_score: u32 = 0;
var high_score_text: [11]u8 = undefined;
var high_score_to_draw: []const u8 = &high_score_text;

const max_spikes = 4;
var spike_pool: std.BoundedArray(Spike, max_spikes) = std.BoundedArray(Spike, max_spikes).init(0) catch unreachable;
var spike_spawn_timer: usize = 0;
var spike_spawn_dir: HorizontalDir = .left;

fn reset() void {
    spike_pool.resize(0) catch unreachable;
    player = .{ .x = 38, .y = 160 - 50, .w = 8, .h = 8 };
    gravity_dir = .left;
    spike_spawn_timer = 0;
    spike_spawn_dir = .left;
    prev_on_wall = true;
    score = 0;
    shield = 0;
    score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch unreachable;
    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch unreachable;
}

export fn start() void {
    w4.PALETTE.* = .{
        0x565a75,
        0x0f0f1b,
        0xc6b7be,
        0xfafbf6,
    };

    rng = std.Random.DefaultPrng.init(0);

    reset();
}

export fn update() void {
    player.x += @intFromEnum(gravity_dir);

    const on_wall = switch (gravity_dir) {
        .left => blk: {
            if (player.x >= 38) {
                break :blk false;
            }
            player.x = 38;
            break :blk true;
        },
        .right => blk: {
            if (player.right() < 160 - 38) {
                break :blk false;
            }
            player.x = 160 - 38 - player.w;
            break :blk true;
        },
    };

    if (on_wall and !prev_on_wall) {
        score += 1;
        score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch unreachable;

        if (score > high_score) {
            high_score = score;
            high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch unreachable;
        }
    }

    prev_on_wall = on_wall;

    const gamepad = w4.GAMEPAD1.*;
    const prev_jump = prev_gamepad & jump_mask != 0;
    const jump = gamepad & jump_mask != 0;
    const jump_just_pressed = jump and !prev_jump;
    prev_gamepad = gamepad;

    if (jump_just_pressed) {
        jump_buffer = 10;
    }

    if (on_wall and jump_buffer > 0) {
        gravity_dir = gravity_dir.flipped();
        jump_buffer = 0;
    } else {
        jump_buffer -|= 1;
    }

    if (shield > max_shield) {
        shield = max_shield;
    } else if (shield < max_shield) {
        shield +|= 1;
    }

    const shield_ready = shield >= max_shield;

    // Update spikes
    var spikes_to_free = std.BoundedArray(usize, max_spikes).init(0) catch unreachable;
    for (spike_pool.slice(), 0..) |*spike, i| {
        spike.rect.y += 1;
        if (spike.rect.y >= w4.SCREEN_SIZE) {
            (spikes_to_free.addOne() catch unreachable).* = i;
        } else if (player.intersects(spike.rect)) {
            if (shield_ready) {
                (spikes_to_free.addOne() catch unreachable).* = i;
                shield = 0;
            } else {
                reset();
            }
        }
    }

    for (spikes_to_free.slice()) |i| {
        _ = spike_pool.swapRemove(i);
    }

    spike_spawn_timer -|= 1;
    if (spike_spawn_timer == 0) {
        spike_spawn_timer = if (spike_pool.addOne()) |spike| blk: {
            spike.* = Spike.init(spike_spawn_dir == .right, 4);

            spike.rect.x = switch (spike_spawn_dir) {
                .left => world_boundary_left,
                .right => world_boundary_right - spike.rect.w,
            };

            spike.rect.y = -@as(i32, @intCast(spike.rect.h));

            spike_spawn_dir = spike_spawn_dir.flipped();
            const new_timer: usize = @intCast(rng.next() % 20 + 60);
            break :blk new_timer;
        } else |_| 10;
    }

    // DRAW

    w4.DRAW_COLORS.* = 0x2;

    w4.rect(0, 0, 38, 160);
    w4.rect(160 - 38, 0, 38, 160);

    player.draw();

    w4.DRAW_COLORS.* = 0x20;

    for (spike_pool.slice()) |*spike| {
        // w4.DRAW_COLORS.* = 0x20;
        spike.draw();

        // DEBUG
        // w4.DRAW_COLORS.* = 0x30;
        // spike.rect.draw();
    }

    w4.DRAW_COLORS.* = 0x21;
    w4.text(score_to_draw, 2, 2);
    w4.text(high_score_to_draw, world_boundary_right + 2, 2);

    if (shield_ready) {
        w4.DRAW_COLORS.* = 0x10;
        w4.blit(&shield_sprite, 2, w4.SCREEN_SIZE - 12, 8, 8, 0);
    }
}
