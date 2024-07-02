const w4 = @import("wasm4.zig");
const std = @import("std");
const Rect = @import("Rect.zig");
const Player = @import("Player.zig");
const Spike = @import("Spike.zig");
const Pipe = @import("Pipe.zig");
const img = @import("img.zig");

const jump_mask = w4.BUTTON_1 | w4.BUTTON_2 | w4.BUTTON_LEFT | w4.BUTTON_RIGHT | w4.BUTTON_UP | w4.BUTTON_DOWN;

const world_boundary_left = 38;
const world_boundary_right = w4.SCREEN_SIZE - 38;

var rng: std.Random.DefaultPrng = undefined;

var player: Player = undefined;
var gravity_dir: Player.HorizontalDir = .left;
var prev_gamepad: u8 = 0;
var jump_buffer: u8 = 0;
var prev_on_wall: bool = false;

const max_gas: u16 = 30 * 60; // 30s * 60FPS
var gas: u16 = 0;
var pipe: ?Pipe = undefined;
var pipe_spawn_timer: u32 = 0; // Pipe actually spawns with the next spike
const pipe_spawn_time = 3 * 60; // 3s * 60FPS
const pipe_gas_replenish = 10 * 60;
var got_gas: bool = false;

var score: u32 = 0;
var score_text: [11]u8 = undefined;
var score_to_draw: []const u8 = &score_text;
var high_score: u32 = 0;
var high_score_text: [11]u8 = undefined;
var high_score_to_draw: []const u8 = &high_score_text;

const max_spikes = 4;
var spike_pool: std.BoundedArray(Spike, max_spikes) = std.BoundedArray(Spike, max_spikes).init(0) catch unreachable;
var spike_spawn_timer: u32 = 0;
var spike_spawn_dir: Player.HorizontalDir = .left;
const base_spike_spawn_time = 120;
const variance_spike_spawn_time = 40;

var anim_time: u64 = 0;
var player_anim_start: u64 = 0;
var player_anim_hold: bool = false;
var player_current_anim: []const u16 = undefined;

fn reset() void {
    spike_pool.resize(0) catch unreachable;
    player = Player.init();
    player.rect.x = world_boundary_left;
    player.rect.y = w4.SCREEN_SIZE - 50;
    gravity_dir = .left;
    spike_spawn_timer = 0;
    spike_spawn_dir = .left;
    prev_on_wall = true;
    score = 0;
    pipe = null;
    pipe_spawn_timer = pipe_spawn_time;
    gas = max_gas;
    got_gas = false;
    score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch unreachable;
    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch unreachable;
    anim_time = 0;
    player_anim_start = 0;
    player_current_anim = &img.player.anim_run;
    player_anim_hold = false;
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
    player.rect.x += @intFromEnum(gravity_dir);

    const on_wall = switch (gravity_dir) {
        .left => blk: {
            if (player.rect.x >= world_boundary_left) {
                break :blk false;
            }
            player.sprite.flags &= ~w4.BLIT_FLIP_X;
            player.rect.x = world_boundary_left;
            break :blk true;
        },
        .right => blk: {
            if (player.rect.right() < world_boundary_right) {
                break :blk false;
            }
            player.sprite.flags |= w4.BLIT_FLIP_X;
            player.rect.x = @intCast(world_boundary_right - player.rect.w);
            break :blk true;
        },
    };

    if (on_wall and !prev_on_wall) { // Land
        score += 1;
        score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch unreachable;

        if (score > high_score) {
            high_score = score;
            high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch unreachable;
        }

        player_anim_start = anim_time;
        player_current_anim = &img.player.anim_run;
        player_anim_hold = false;
    }

    prev_on_wall = on_wall;

    const gamepad = w4.GAMEPAD1.*;
    const prev_jump = prev_gamepad & jump_mask != 0;
    const jump = gamepad & jump_mask != 0;
    const jump_just_pressed = jump and !prev_jump;
    prev_gamepad = gamepad;

    if (jump_just_pressed) {
        jump_buffer = 8;
    }

    if (on_wall and jump_buffer > 0) { // Jump
        gravity_dir.flip();
        jump_buffer = 0;
        player_anim_start = anim_time;
        player_current_anim = &img.player.anim_flip;
        player_anim_hold = true;
    } else {
        jump_buffer -|= 1;
    }

    gas -|= 1;
    if (gas <= 0 and on_wall) {
        reset();
    }

    // Update spikes
    var i: usize = 0;
    while (i < spike_pool.len) {
        var spike = &spike_pool.buffer[i];
        spike.rect.y += 1;

        if (spike.rect.y >= w4.SCREEN_SIZE) {
            _ = spike_pool.swapRemove(i);
            continue;
        } else if (player.rect.intersects(spike.rect)) {
            reset();
        }

        i += 1;
    }

    // Update pipe
    if (pipe) |*p| {
        p.rect.y += 1;

        if (p.rect.y >= w4.SCREEN_SIZE) {
            pipe = null;
            got_gas = false;
        } else if (!got_gas and player.rect.intersects(p.rect)) {
            gas = @min(gas + pipe_gas_replenish, max_gas);
            got_gas = true;
            pipe_spawn_timer = pipe_spawn_time;
        }
    }

    // Spawn spikes/pipes
    pipe_spawn_timer -|= 1;
    spike_spawn_timer -|= 1;
    if (spike_spawn_timer <= 0) {
        if (spike_pool.addOne()) |spike| {
            spike.* = Spike.init(spike_spawn_dir == .right, 4);

            spike.rect.x = switch (spike_spawn_dir) {
                .left => @intCast(world_boundary_left),
                .right => @intCast(world_boundary_right - spike.rect.w),
            };

            spike.rect.y = -@as(i32, @intCast(spike.rect.h));

            const new_timer: u32 = @intCast(base_spike_spawn_time + rng.next() % variance_spike_spawn_time);
            spike_spawn_timer = new_timer;

            if (pipe == null and pipe_spawn_timer <= 0) {
                var p = Pipe.init(spike_spawn_dir == .right);
                p.rect.x = switch (spike_spawn_dir) {
                    .left => @intCast(world_boundary_left),
                    .right => @intCast(world_boundary_right - p.rect.w),
                };
                p.rect.y = spike.rect.y - 4 - @as(i32, @intCast(p.rect.h));
                pipe = p;
            }

            spike_spawn_dir.flip();
        } else |_| {
            spike_spawn_timer = 10; // Pool out of free objects, try again later
        }
    }

    // DRAW

    w4.DRAW_COLORS.* = 0x2;

    w4.rect(0, 0, 38, 160);
    w4.rect(160 - 38, 0, 38, 160);

    var player_anim_frame: usize = @intCast((anim_time - player_anim_start) / 6);
    if (player_anim_frame >= player_current_anim.len) {
        player_anim_frame = if (player_anim_hold) player_current_anim.len - 1 else player_anim_frame % player_current_anim.len;
    }
    player.sprite.frame = player_current_anim[player_anim_frame];
    player.draw();

    w4.DRAW_COLORS.* = 0x20;

    for (spike_pool.slice()) |spike| {
        // w4.DRAW_COLORS.* = 0x20;
        spike.draw();

        // DEBUG
        // w4.DRAW_COLORS.* = 0x30;
        // spike.rect.draw();
    }

    w4.DRAW_COLORS.* = 0x2;
    if (pipe) |*p| {
        p.sprite.frame = @intCast(@divFloor(anim_time, 5) % (p.sprite.vframes * p.sprite.hframes));
        p.draw();
    }

    w4.DRAW_COLORS.* = 0x21;
    w4.text(score_to_draw, 2, 2);
    w4.text(high_score_to_draw, world_boundary_right + 2, 2);

    {
        const text_x = 6;
        const text_y = 60;
        w4.DRAW_COLORS.* = 0x1;
        w4.text("GAS", text_x, text_y);

        const gas_pct = @as(f32, @floatFromInt(gas)) / max_gas;
        const bar_x = text_x + 8;
        const bar_y = text_y + 12;
        const bar_w = 8;
        const max_bar_h = 80;
        const bar_h: u32 = @intFromFloat(max_bar_h * gas_pct);
        w4.rect(bar_x, bar_y, bar_w, bar_h);
    }

    anim_time += 1;
}
