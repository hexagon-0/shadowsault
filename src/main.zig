const w4 = @import("wasm4.zig");
const std = @import("std");
const Rect = @import("Rect.zig");
const Player = @import("Player.zig");
const Spike = @import("Spike.zig");
const Pipe = @import("Pipe.zig");
const img = @import("img.zig");

const GameState = enum { title_screen, gameplay_intro, gameplay, game_over_intro, game_over };

const jump_mask = w4.BUTTON_1 | w4.BUTTON_2 | w4.BUTTON_LEFT | w4.BUTTON_RIGHT | w4.BUTTON_UP | w4.BUTTON_DOWN;

const world_boundary_left = 38;
const world_boundary_right = w4.SCREEN_SIZE - 38;

var rng: std.Random.DefaultPrng = undefined;

var game_state: GameState = .title_screen;

const title_sprite = img.title.sprite();

var player: Player = undefined;
var gravity_dir: Player.HorizontalDir = .left;
var prev_gamepad: u8 = 0;
var jump_buffer: u8 = 0;
var prev_on_wall: bool = false;
const player_final_y = w4.SCREEN_SIZE - 50;

const max_gas: u16 = 15 * 60; // 15s
var gas: u16 = 0;
var pipe: ?Pipe = undefined;
var pipe_spawn_timer: u32 = 0; // Pipe actually spawns with the next spike
const pipe_time_to_spawn = 3 * 60; // 3s
const pipe_gas_replenish = 10 * 60;
var got_gas: bool = false;

var score: u32 = 0;
var score_text: [11]u8 = undefined;
var score_to_draw: []const u8 = &score_text;
var high_score: u32 = 0;
var high_score_text: [11]u8 = undefined;
var high_score_to_draw: []const u8 = &high_score_text;
var high_score_erase_timer: u32 = 0;
const high_score_time_to_erase: u32 = 5 * 60; // 5s

const max_spikes = 4;
var spike_pool: std.BoundedArray(Spike, max_spikes) = std.BoundedArray(Spike, max_spikes).init(0) catch unreachable;
var spike_spawn_timer: u32 = 0;
var spike_spawn_dir: Player.HorizontalDir = .left;
const base_spike_spawn_time = 120;
const variance_spike_spawn_time = 40;

var global_time: u64 = 0;
var player_anim_start: u64 = 0;
var player_anim_hold: bool = false;
var player_current_anim: []const u16 = undefined;

fn reset() void {
    rng.seed(global_time);
    spike_pool.resize(0) catch unreachable;
    player = Player.init();
    player.rect.x = world_boundary_left;
    player.rect.y = w4.SCREEN_SIZE;
    gravity_dir = .left;
    spike_spawn_timer = 0;
    spike_spawn_dir = .left;
    prev_on_wall = true;
    score = 0;
    pipe = null;
    pipe_spawn_timer = pipe_time_to_spawn;
    gas = max_gas;
    got_gas = false;
    score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch &score_text;
    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch &high_score_text;
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

    global_time = 0;
    rng = std.Random.DefaultPrng.init(0);
    load_high_score();
    game_state = .title_screen;
    reset();
}

export fn update() void {
    const gamepad = w4.GAMEPAD1.*;
    const just_pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    var flicker_del_text = false;

    switch (game_state) {
        .title_screen => {
            if (just_pressed & w4.BUTTON_2 != 0) {
                start_gameplay();
            }

            if (gamepad & w4.BUTTON_1 != 0) {
                high_score_erase_timer -|= 1;
                flicker_del_text = true;

                if (high_score_erase_timer <= 0) {
                    erase_high_score();
                    high_score_erase_timer = high_score_time_to_erase;
                }
            } else {
                high_score_erase_timer = high_score_time_to_erase;
            }
        },

        .gameplay_intro => {
            if (player.rect.y <= player_final_y) {
                player.rect.y = player_final_y;
                game_state = .gameplay;
            } else {
                player.rect.y -= 1;
            }
        },

        .gameplay => {
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
                if (!got_gas) {
                    w4.tone(340, 4 | (2 << 16), (40 << 8) | 5, w4.TONE_NOISE | w4.TONE_MODE4);
                }
                score += 1;
                score_to_draw = std.fmt.bufPrint(&score_text, "{}", .{score}) catch &score_text;

                if (score > high_score) {
                    high_score = score;
                    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch &high_score_text;
                }

                player_anim_start = global_time;
                player_current_anim = &img.player.anim_run;
                player_anim_hold = false;
            }

            prev_on_wall = on_wall;

            const jump_just_pressed = just_pressed & jump_mask != 0;
            prev_gamepad = gamepad;

            if (jump_just_pressed) {
                jump_buffer = 8;
            }

            if (on_wall and jump_buffer > 0) { // Jump
                w4.tone(500 | (1600 << 16), 8, 40, w4.TONE_TRIANGLE | w4.TONE_MODE1);

                gravity_dir.flip();
                jump_buffer = 0;

                player_anim_start = global_time;
                player_current_anim = &img.player.anim_flip;
                player_anim_hold = true;
            } else {
                jump_buffer -|= 1;
            }

            gas -|= 1;
            if (gas <= 0 and on_wall) {
                game_over();
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
                    game_over();
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
                    w4.tone(1200, (5 << 24) | 20 | (40 << 8), (15 << 8) | 10, w4.TONE_NOISE);
                    gas = @min(gas + pipe_gas_replenish, max_gas);
                    got_gas = true;
                    pipe_spawn_timer = pipe_time_to_spawn;
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
        },

        .game_over_intro => {
            player_current_anim = &img.player.anim_fall;
            player_anim_hold = false;
            if (player.rect.y < w4.SCREEN_SIZE) {
                player.rect.y += 1;
            } else {
                game_state = .game_over;
            }
        },

        .game_over => {
            if (just_pressed & jump_mask != 0) {
                start_gameplay();
            }
        },
    }

    // DRAW

    w4.DRAW_COLORS.* = 0x2;

    w4.rect(0, 0, 38, 160);
    w4.rect(160 - 38, 0, 38, 160);

    var player_anim_frame: usize = @intCast((global_time - player_anim_start) / 6);
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
        p.sprite.frame = @intCast(@divFloor(global_time, 5) % (p.sprite.vframes * p.sprite.hframes));
        p.draw();
    }

    {
        w4.DRAW_COLORS.* = 0x21;
        w4.text("SCOR", world_boundary_right + 2, 2);
        w4.text(score_to_draw, world_boundary_right + 2, 12);
        w4.text("HI", world_boundary_right + 2, 26);
        w4.text(high_score_to_draw, world_boundary_right + 2, 36);
    }

    {
        const text_x = 6;
        const text_y = 6;
        w4.DRAW_COLORS.* = 0x1;
        w4.text("GAS", text_x, text_y);

        const gas_pct = @as(f32, @floatFromInt(gas)) / max_gas;
        const bar_x = text_x + 8;
        const bar_y = text_y + 12;
        const bar_w = 8;
        const max_bar_h = 80;
        const bar_h: u32 = @intFromFloat(max_bar_h * gas_pct);
        w4.rect(bar_x, bar_y, bar_w, bar_h);

        w4.line(bar_x, bar_y + max_bar_h - 1, bar_x + bar_w - 1, bar_y + max_bar_h - 1);
    }

    if (game_state == .title_screen) {
        w4.DRAW_COLORS.* = 0x21;
        title_sprite.draw(w4.SCREEN_SIZE / 2, w4.SCREEN_SIZE / 3);

        const base_y = w4.SCREEN_SIZE / 2;

        w4.DRAW_COLORS.* = 0x12;
        w4.text("\x81 start", 40, base_y);
        draw_del_text: {
            if (flicker_del_text) {
                // Flicker quicker after halfway
                const divide_by: u64 = if (high_score_erase_timer > high_score_time_to_erase / 2) 14 else 6;
                if (@divFloor(global_time, divide_by) % 2 != 0) {
                    break :draw_del_text;
                }
            }

            w4.text("\x80 del high", 40, base_y + 10);
            w4.text("score", 56, base_y + 18);
        }
    } else if (game_state == .game_over) {
        w4.DRAW_COLORS.* = 0x12;
        w4.text("GAME", w4.SCREEN_SIZE / 2 - 16, w4.SCREEN_SIZE / 2 - 8);
        w4.text("OVER", w4.SCREEN_SIZE / 2 - 16, w4.SCREEN_SIZE / 2);
    }

    global_time += 1;
}

fn start_gameplay() void {
    game_state = .gameplay_intro;
    reset();
}

fn game_over() void {
    save_high_score();
    game_state = .game_over_intro;
    w4.tone(220 | (170 << 16), 30 | (80 << 8), (40 << 8) | 40, w4.TONE_PULSE1 | w4.TONE_MODE2);
}

fn load_high_score() void {
    _ = w4.diskr(@as([*]u8, @ptrCast(&high_score)), @sizeOf(@TypeOf(high_score)));
    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch &high_score_text;
}

fn save_high_score() void {
    _ = w4.diskw(@as([*]u8, @ptrCast(&high_score)), @sizeOf(@TypeOf(high_score)));
}

fn erase_high_score() void {
    high_score = 0;
    save_high_score();
    high_score_to_draw = std.fmt.bufPrint(&high_score_text, "{}", .{high_score}) catch &high_score_text;
}
