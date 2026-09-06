// ZigStarfight — 2-player vector space combat on the vgame platform
//
// Inspired by Spacewar! (1962) and pystarfight (2012).
// Two ships duel around a central gravity star with missiles and
// toroidal screen wrapping. First to the kill target wins.
//
// Player 1 (Triangle Ship, white):
//   A/D     Rotate left/right
//   W       Thrust
//   TAB     Fire missile
//   S       Hyperspace (random teleport)
//
// Player 2 (Hex Ship, pink):
//   Left/Right  Rotate
//   Up          Thrust
//   RShift      Fire missile
//   Down        Hyperspace
//
// General:
//   P    Pause
//   R    Restart match
//   F    Toggle fullscreen (platform)
//   ESC  Quit

const std = @import("std");
const math = std.math;
const vgame = @import("vgame");
const rl = vgame.rl;
const rlm = rl.math;
const Vector2 = vgame.Vector2;

// ── Tunable constants ─────────────────────────────────────────────
const THRUSTER_FORCE: f32 = 200.0;
const ROTATION_RATE: f32 = math.pi; // radians per second
const BULLET_SPEED: f32 = 400.0;
const BULLET_LIFETIME: f32 = 3.0; // seconds
const MAX_BULLETS_PER_SHIP: usize = 4;
const FRICTION: f32 = 0.995;
const GRAVITY_STRENGTH: f32 = 30000.0;
const SHIP_RADIUS: f32 = 18.0;
const BULLET_RADIUS: f32 = 3.0;
const SUN_RADIUS: f32 = 30.0;
const SUN_COLLISION_RADIUS: f32 = 25.0;
const RESPAWN_TIME: f32 = 3.0;
const RESPAWN_INVULN: f32 = 2.0;
const KILLS_TO_WIN: usize = 5;
const HYPERSPACE_COOLDOWN: f32 = 8.0;
const MAX_SPEED: f32 = 600.0;

// ── Sound effects ─────────────────────────────────────────────────
const SFX = enum(usize) {
    shoot,
    thrust,
    explosion,
    bang_large,
    tone_lo,
    tone_hi,
    saucer,
};

const sound_clips = [_][]const u8{
    "asteroids_shoot.wav",
    "asteroids_thrust.wav",
    "explosion.wav",
    "bangLarge.wav",
    "asteroids_tonelo.wav",
    "asteroids_tonehi.wav",
    "asteroids_saucer.wav",
};

// ── Colors ────────────────────────────────────────────────────────
const WHITE = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const PINK = rl.Color{ .r = 252, .g = 15, .b = 192, .a = 255 };
const RED = rl.Color{ .r = 255, .g = 80, .b = 80, .a = 255 };
const YELLOW = rl.Color{ .r = 255, .g = 220, .b = 100, .a = 255 };
const GREEN = rl.Color{ .r = 100, .g = 255, .b = 100, .a = 255 };
const GRAY = rl.Color{ .r = 120, .g = 120, .b = 140, .a = 255 };

// ── Vector shapes (normalized, centered at origin) ────────────────

// Player 1: Triangle ship — points right at rotation 0
const SHIP1_SHAPE = [_]Vector2{
    .{ .x = 0.5, .y = 0.0 },
    .{ .x = -0.3, .y = -0.35 },
    .{ .x = -0.15, .y = 0.0 },
    .{ .x = -0.3, .y = 0.35 },
};

// Player 2: overhead-view "Enterprise" silhouette — round saucer forward
// (nose at +x), a short neck into a slender engineering hull, and a nacelle
// on a swept pylon to each side, with the hull tapering to a stern point
// between them. Traced as one continuous outline: nose -> over the saucer ->
// down the neck -> aft along the hull -> out to one nacelle and back -> aft
// to the stern -> out to the other nacelle and back -> forward along the
// hull -> up the neck -> under the saucer -> back to nose.
const SHIP2_SHAPE = [_]Vector2{
    .{ .x = 0.55, .y = 0.00 }, // nose (saucer front)
    .{ .x = 0.527, .y = 0.115 }, // saucer
    .{ .x = 0.462, .y = 0.212 }, // saucer
    .{ .x = 0.365, .y = 0.277 }, // saucer
    .{ .x = 0.25, .y = 0.300 }, // saucer top (widest)
    .{ .x = 0.135, .y = 0.277 }, // saucer
    .{ .x = 0.038, .y = 0.212 }, // saucer
    .{ .x = -0.027, .y = 0.115 }, // saucer aft / neck start
    .{ .x = -0.08, .y = 0.07 }, // neck-to-hull junction
    .{ .x = -0.45, .y = 0.07 }, // hull, pylon leading edge
    .{ .x = -0.50, .y = 0.17 }, // pylon leading edge, rising
    .{ .x = -0.55, .y = 0.28 }, // nacelle nose
    .{ .x = -0.58, .y = 0.32 }, // nacelle outer shoulder, fwd
    .{ .x = -0.95, .y = 0.32 }, // nacelle outer shoulder, aft
    .{ .x = -1.02, .y = 0.28 }, // nacelle aft tip
    .{ .x = -0.95, .y = 0.24 }, // nacelle inner shoulder, aft
    .{ .x = -0.58, .y = 0.24 }, // nacelle inner shoulder, fwd
    .{ .x = -0.62, .y = 0.14 }, // pylon trailing edge, descending
    .{ .x = -0.66, .y = 0.07 }, // hull, pylon trailing edge
    .{ .x = -0.78, .y = 0.045 }, // hull aft taper, upper
    .{ .x = -0.88, .y = 0.00 }, // stern (aft-most point)
    .{ .x = -0.78, .y = -0.045 }, // hull aft taper, lower
    .{ .x = -0.66, .y = -0.07 }, // hull, pylon trailing edge (mirrored)
    .{ .x = -0.62, .y = -0.14 }, // pylon trailing edge, descending (mirrored)
    .{ .x = -0.58, .y = -0.24 }, // nacelle inner shoulder, fwd (mirrored)
    .{ .x = -0.95, .y = -0.24 }, // nacelle inner shoulder, aft (mirrored)
    .{ .x = -1.02, .y = -0.28 }, // nacelle aft tip (mirrored)
    .{ .x = -0.95, .y = -0.32 }, // nacelle outer shoulder, aft (mirrored)
    .{ .x = -0.58, .y = -0.32 }, // nacelle outer shoulder, fwd (mirrored)
    .{ .x = -0.55, .y = -0.28 }, // nacelle nose (mirrored)
    .{ .x = -0.50, .y = -0.17 }, // pylon leading edge, rising (mirrored)
    .{ .x = -0.45, .y = -0.07 }, // hull, pylon leading edge (mirrored)
    .{ .x = -0.08, .y = -0.07 }, // neck-to-hull junction (mirrored)
    .{ .x = -0.027, .y = -0.115 }, // saucer aft / neck start (mirrored)
    .{ .x = 0.038, .y = -0.212 }, // saucer
    .{ .x = 0.135, .y = -0.277 }, // saucer
    .{ .x = 0.25, .y = -0.300 }, // saucer bottom (widest)
    .{ .x = 0.365, .y = -0.277 }, // saucer
    .{ .x = 0.462, .y = -0.212 }, // saucer
    .{ .x = 0.527, .y = -0.115 }, // saucer
};

// Thrust flame — sits behind the ship's stern (local -x, opposite the nose
// at +x). The apex points further in -x, i.e. away from the ship and
// opposite the direction of thrust, with its base offset far enough back
// to leave a visible gap behind both ship shapes.
const THRUST_SHAPE = [_]Vector2{
    .{ .x = -0.65, .y = -0.2 },
    .{ .x = -1.15, .y = 0.0 },
    .{ .x = -0.65, .y = 0.2 },
};

// Central star — 4 independent diameters through the origin (0°, 45°, 90°,
// 135°), matching pystarfight's swModels.py centralStar: a single segment
// from (-100,0) to (100,0) rotated by pi/4 four times. Each pair of points
// below is one standalone line — they must be drawn separately (not as one
// connected polyline) or spurious segments appear joining their endpoints.
const STAR_SHAPE = [_]Vector2{
    .{ .x = -1.0, .y = 0.0 },  .{ .x = 1.0, .y = 0.0 },
    .{ .x = -0.7071, .y = -0.7071 }, .{ .x = 0.7071, .y = 0.7071 },
    .{ .x = 0.0, .y = -1.0 },  .{ .x = 0.0, .y = 1.0 },
    .{ .x = 0.7071, .y = -0.7071 },  .{ .x = -0.7071, .y = 0.7071 },
};

// ── Game structs ──────────────────────────────────────────────────

const Ship = struct {
    pos: Vector2,
    vel: Vector2,
    rot: f32 = 0.0,
    alive: bool = true,
    death_time: f32 = 0.0,
    thrusting: bool = false,
    color: rl.Color,
    is_p1: bool,
    bullets_active: usize = 0,
    hyperspace_cooldown: f32 = 0.0,
    invuln_timer: f32 = 0.0,
};

const Bullet = struct {
    pos: Vector2,
    vel: Vector2,
    ttl: f32,
    owner_p1: bool,
    remove: bool = false,
};

const Game = struct {
    ship1: Ship,
    ship2: Ship,
    bullets: std.ArrayList(Bullet),
    sun_pos: Vector2,
    sun_rot: f32 = 0.0,
    score_p1: usize = 0,
    score_p2: usize = 0,
    game_over: bool = false,
    winner: usize = 0, // 0 = none, 1 or 2
    paused: bool = false,
    time: f32 = 0.0,
    delta: f32 = 0.0,
    allocator: std.mem.Allocator,
    rand: std.Random,
};

// ── Physics helpers ───────────────────────────────────────────────

fn gravityAt(pos: Vector2, sun_pos: Vector2) Vector2 {
    const diff = rlm.vector2Subtract(sun_pos, pos);
    const dist_sq = diff.x * diff.x + diff.y * diff.y;
    if (dist_sq < 100.0) return .{ .x = 0, .y = 0 };
    const dist = @sqrt(dist_sq);
    const force = GRAVITY_STRENGTH / dist_sq;
    return rlm.vector2Scale(diff, force / dist);
}

fn wrapPos(pos: Vector2, field: Vector2) Vector2 {
    return .{
        .x = @mod(pos.x, field.x),
        .y = @mod(pos.y, field.y),
    };
}

fn updateShip(ship: *Ship, dt: f32, sun_pos: Vector2, field: Vector2) void {
    if (!ship.alive) return;

    // Apply gravity
    const g = gravityAt(ship.pos, sun_pos);
    ship.vel = rlm.vector2Add(ship.vel, rlm.vector2Scale(g, dt));

    // Apply thrust
    if (ship.thrusting) {
        const dir = Vector2{ .x = math.cos(ship.rot), .y = math.sin(ship.rot) };
        ship.vel = rlm.vector2Add(ship.vel, rlm.vector2Scale(dir, THRUSTER_FORCE * dt));
    }

    // Friction
    ship.vel = rlm.vector2Scale(ship.vel, FRICTION);

    // Speed cap
    const speed_sq = ship.vel.x * ship.vel.x + ship.vel.y * ship.vel.y;
    if (speed_sq > MAX_SPEED * MAX_SPEED) {
        const speed = @sqrt(speed_sq);
        ship.vel = rlm.vector2Scale(ship.vel, MAX_SPEED / speed);
    }

    // Move
    ship.pos = rlm.vector2Add(ship.pos, rlm.vector2Scale(ship.vel, dt));
    ship.pos = wrapPos(ship.pos, field);

    // Cooldowns
    if (ship.hyperspace_cooldown > 0) ship.hyperspace_cooldown -= dt;
    if (ship.invuln_timer > 0) ship.invuln_timer -= dt;
}

fn fireBullet(ship: *Ship, bullets: *std.ArrayList(Bullet), allocator: std.mem.Allocator, audio: ?*const vgame.AudioManager) !void {
    if (!ship.alive or ship.bullets_active >= MAX_BULLETS_PER_SHIP) return;
    const dir = Vector2{ .x = math.cos(ship.rot), .y = math.sin(ship.rot) };
    try bullets.append(allocator, .{
        .pos = rlm.vector2Add(ship.pos, rlm.vector2Scale(dir, SHIP_RADIUS)),
        .vel = rlm.vector2Add(ship.vel, rlm.vector2Scale(dir, BULLET_SPEED)),
        .ttl = BULLET_LIFETIME,
        .owner_p1 = ship.is_p1,
    });
    ship.bullets_active += 1;
    if (audio) |a| a.play(@intFromEnum(SFX.shoot));
}

fn hyperspaceShip(ship: *Ship, field: Vector2, rand: *std.Random, audio: ?*const vgame.AudioManager) void {
    if (!ship.alive or ship.hyperspace_cooldown > 0) return;
    ship.pos = .{
        .x = rand.float(f32) * field.x,
        .y = rand.float(f32) * field.y,
    };
    ship.vel = .{ .x = 0, .y = 0 };
    ship.hyperspace_cooldown = HYPERSPACE_COOLDOWN;
    ship.invuln_timer = 1.0;
    if (audio) |a| a.play(@intFromEnum(SFX.tone_lo));
}

fn explodeShip(ship: *Ship, particles: *vgame.Particles, audio: ?*const vgame.AudioManager, rand: *std.Random, scale: f32) !void {
    ship.alive = false;
    if (audio) |a| {
        a.play(@intFromEnum(SFX.explosion));
        a.play(@intFromEnum(SFX.bang_large));
    }
    try particles.spawnDots(ship.pos, 25, .{
        .color = ship.color,
        .scale = scale,
        .speed = 5.0,
    }, rand);
    try particles.spawnLines(ship.pos, 8, .{
        .color = ship.color,
        .scale = scale,
        .speed = 5.0,
    }, rand);
}

fn respawnShip(ship: *Ship, field: Vector2, opponent_pos: Vector2) void {
    // Respawn at whichever of the two fixed spawn points is farther from
    // the opponent, rather than always returning to this ship's own side.
    const spawn_left = Vector2{ .x = field.x * 0.2, .y = field.y * 0.5 };
    const spawn_right = Vector2{ .x = field.x * 0.8, .y = field.y * 0.5 };
    const use_left = rlm.vector2Distance(spawn_left, opponent_pos) >= rlm.vector2Distance(spawn_right, opponent_pos);
    ship.pos = if (use_left) spawn_left else spawn_right;
    ship.vel = .{ .x = 0, .y = 0 };
    ship.rot = if (use_left) 0.0 else math.pi;
    ship.alive = true;
    ship.thrusting = false;
    ship.bullets_active = 0;
    ship.invuln_timer = RESPAWN_INVULN;
}

fn resetMatch(game: *Game, field: Vector2) void {
    game.ship1.pos = .{ .x = field.x * 0.2, .y = field.y * 0.5 };
    game.ship1.vel = .{ .x = 0, .y = 0 };
    game.ship1.rot = 0.0;
    game.ship1.alive = true;
    game.ship1.thrusting = false;
    game.ship1.bullets_active = 0;
    game.ship1.hyperspace_cooldown = 0.0;
    game.ship1.invuln_timer = RESPAWN_INVULN;

    game.ship2.pos = .{ .x = field.x * 0.8, .y = field.y * 0.5 };
    game.ship2.vel = .{ .x = 0, .y = 0 };
    game.ship2.rot = math.pi;
    game.ship2.alive = true;
    game.ship2.thrusting = false;
    game.ship2.bullets_active = 0;
    game.ship2.hyperspace_cooldown = 0.0;
    game.ship2.invuln_timer = RESPAWN_INVULN;

    game.bullets.clearRetainingCapacity();
    game.score_p1 = 0;
    game.score_p2 = 0;
    game.game_over = false;
    game.winner = 0;
}

// ── Update ────────────────────────────────────────────────────────

fn update(game: *Game, audio: ?*const vgame.AudioManager, particles: *vgame.Particles, field: Vector2) !void {
    if (game.paused or game.game_over) {
        // Still allow restart from game over
        if (game.game_over and rl.isKeyPressed(.r)) resetMatch(game, field);
        if (game.paused and rl.isKeyPressed(.p)) game.paused = false;
        if (game.paused and rl.isKeyPressed(.r)) resetMatch(game, field);
        return;
    }

    game.time += game.delta;

    // Rotate sun slowly
    game.sun_rot += game.delta * 0.3;

    // Player 1: A/D rotate, W thrust, TAB fire, S hyperspace
    if (game.ship1.alive) {
        if (rl.isKeyDown(.a)) game.ship1.rot -= ROTATION_RATE * game.delta;
        if (rl.isKeyDown(.d)) game.ship1.rot += ROTATION_RATE * game.delta;
        game.ship1.thrusting = rl.isKeyDown(.w);
        if (rl.isKeyPressed(.tab)) {
            try fireBullet(&game.ship1, &game.bullets, game.allocator, audio);
        }
        if (rl.isKeyPressed(.s)) {
            hyperspaceShip(&game.ship1, field, &game.rand, audio);
        }
    }

    // Player 2: Left/Right rotate, Up thrust, RShift fire, Down hyperspace
    if (game.ship2.alive) {
        if (rl.isKeyDown(.left)) game.ship2.rot -= ROTATION_RATE * game.delta;
        if (rl.isKeyDown(.right)) game.ship2.rot += ROTATION_RATE * game.delta;
        game.ship2.thrusting = rl.isKeyDown(.up);
        if (rl.isKeyPressed(.right_shift)) {
            try fireBullet(&game.ship2, &game.bullets, game.allocator, audio);
        }
        if (rl.isKeyPressed(.down)) {
            hyperspaceShip(&game.ship2, field, &game.rand, audio);
        }
    }

    // Update ships
    updateShip(&game.ship1, game.delta, game.sun_pos, field);
    updateShip(&game.ship2, game.delta, game.sun_pos, field);

    // Update bullets
    var i: usize = 0;
    while (i < game.bullets.items.len) {
        var b = &game.bullets.items[i];
        // Apply gravity to bullets
        const g = gravityAt(b.pos, game.sun_pos);
        b.vel = rlm.vector2Add(b.vel, rlm.vector2Scale(g, game.delta * 0.5));
        b.pos = rlm.vector2Add(b.pos, rlm.vector2Scale(b.vel, game.delta));
        b.pos = wrapPos(b.pos, field);
        b.ttl -= game.delta;

        if (b.ttl <= 0) {
            b.remove = true;
            if (b.owner_p1) game.ship1.bullets_active -= 1 else game.ship2.bullets_active -= 1;
        }

        // Bullet vs sun
        if (!b.remove) {
            const dist_to_sun = rlm.vector2Distance(b.pos, game.sun_pos);
            if (dist_to_sun < SUN_COLLISION_RADIUS) {
                b.remove = true;
                if (b.owner_p1) game.ship1.bullets_active -= 1 else game.ship2.bullets_active -= 1;
                if (audio) |a| a.play(@intFromEnum(SFX.tone_hi));
            }
        }

        // Bullet vs ship
        if (!b.remove) {
            const target = if (b.owner_p1) &game.ship2 else &game.ship1;
            if (target.alive and target.invuln_timer <= 0) {
                const dist = rlm.vector2Distance(b.pos, target.pos);
                if (dist < SHIP_RADIUS) {
                    b.remove = true;
                    if (b.owner_p1) game.ship1.bullets_active -= 1 else game.ship2.bullets_active -= 1;
                    try explodeShip(target, particles, audio, &game.rand, 38.0);
                    target.death_time = game.time;
                    if (b.owner_p1) game.score_p1 += 1 else game.score_p2 += 1;
                    if (audio) |a| a.play(@intFromEnum(SFX.tone_hi));

                    if (game.score_p1 >= KILLS_TO_WIN) {
                        game.game_over = true;
                        game.winner = 1;
                    } else if (game.score_p2 >= KILLS_TO_WIN) {
                        game.game_over = true;
                        game.winner = 2;
                    }
                }
            }
        }

        if (b.remove) _ = game.bullets.swapRemove(i) else i += 1;
    }

    // Ship vs sun collision
    for ([_]*Ship{ &game.ship1, &game.ship2 }) |ship| {
        if (!ship.alive or ship.invuln_timer > 0) continue;
        const dist = rlm.vector2Distance(ship.pos, game.sun_pos);
        if (dist < SUN_COLLISION_RADIUS) {
            try explodeShip(ship, particles, audio, &game.rand, 38.0);
            ship.death_time = game.time;
        }
    }

    // Ship vs ship collision (elastic bounce)
    if (game.ship1.alive and game.ship2.alive and game.ship1.invuln_timer <= 0 and game.ship2.invuln_timer <= 0) {
        const dist = rlm.vector2Distance(game.ship1.pos, game.ship2.pos);
        if (dist < SHIP_RADIUS * 1.5) {
            const normal = rlm.vector2Normalize(rlm.vector2Subtract(game.ship2.pos, game.ship1.pos));
            const rel_vel = rlm.vector2Subtract(game.ship1.vel, game.ship2.vel);
            const dot = rel_vel.x * normal.x + rel_vel.y * normal.y;
            if (dot > 0) {
                const impulse = rlm.vector2Scale(normal, dot);
                game.ship1.vel = rlm.vector2Subtract(game.ship1.vel, impulse);
                game.ship2.vel = rlm.vector2Add(game.ship2.vel, impulse);
                const overlap = SHIP_RADIUS * 1.5 - dist;
                const sep = rlm.vector2Scale(normal, overlap * 0.5);
                game.ship1.pos = rlm.vector2Subtract(game.ship1.pos, sep);
                game.ship2.pos = rlm.vector2Add(game.ship2.pos, sep);
            }
        }
    }

    // Respawn dead ships
    for ([_]*Ship{ &game.ship1, &game.ship2 }) |ship| {
        if (!ship.alive and (game.time - ship.death_time) > RESPAWN_TIME) {
            const opponent_pos = if (ship.is_p1) game.ship2.pos else game.ship1.pos;
            respawnShip(ship, field, opponent_pos);
        }
    }

    // Pause toggle
    if (rl.isKeyPressed(.p)) game.paused = true;

    // Restart
    if (rl.isKeyPressed(.r)) {
        resetMatch(game, field);
    }
}

// ── Render ────────────────────────────────────────────────────────

fn drawShip(ctx: *const vgame.RenderContext, ship: *const Ship, scale: f32) void {
    if (!ship.alive) return;

    // Invulnerability blink
    if (ship.invuln_timer > 0) {
        const blink = @as(u8, @intFromFloat(@abs(@sin(ship.invuln_timer * 15.0)) * 255.0));
        if (blink < 100) return;
    }

    const shape = if (ship.is_p1) &SHIP1_SHAPE else &SHIP2_SHAPE;
    const draw_scale = SHIP_RADIUS * scale / 18.0;

    // Thrust flame — same rotation frame as the ship body so it attaches
    // to the stern (aft) rather than the nose.
    if (ship.thrusting) {
        ctx.drawLines(ship.pos, draw_scale * 0.8, ship.rot, &THRUST_SHAPE, false, YELLOW);
    }

    // Ship body
    ctx.drawLines(ship.pos, draw_scale, ship.rot, shape, true, ship.color);
}

fn drawBullet(ctx: *const vgame.RenderContext, b: *const Bullet) void {
    const c = if (b.owner_p1) WHITE else PINK;
    // Draw as a small vector rod
    const dir = rlm.vector2Normalize(b.vel);
    const tip = rlm.vector2Add(b.pos, rlm.vector2Scale(dir, 8.0));
    ctx.drawLine(b.pos, tip, 2, c);
}

fn drawSun(ctx: *const vgame.RenderContext, pos: Vector2, rot: f32, scale: f32) void {
    const sun_scale = SUN_RADIUS * scale / 18.0;
    // Draw each of the 4 diameters as its own line so they cross cleanly
    // at the center instead of being joined into one connected polyline.
    var i: usize = 0;
    while (i < STAR_SHAPE.len) : (i += 2) {
        ctx.drawLines(pos, sun_scale, rot, STAR_SHAPE[i .. i + 2], false, YELLOW);
    }
}

fn render(game: *const Game, ctx: *const vgame.RenderContext, particles: *const vgame.Particles, scale: f32, field: Vector2) void {
    // Sun
    drawSun(ctx, game.sun_pos, game.sun_rot, scale);

    // Ships
    drawShip(ctx, &game.ship1, scale);
    drawShip(ctx, &game.ship2, scale);

    // Bullets
    for (game.bullets.items) |*b| {
        drawBullet(ctx, b);
    }

    // Particles
    particles.render();

    // Score display
    var score_buf: [64:0]u8 = undefined;
    const p1_str = std.fmt.bufPrintZ(&score_buf, "P1: {d}", .{game.score_p1}) catch unreachable;
    ctx.drawText(p1_str, 30, 30, 24, WHITE);

    var score2_buf: [64:0]u8 = undefined;
    const p2_str = std.fmt.bufPrintZ(&score2_buf, "P2: {d}", .{game.score_p2}) catch unreachable;
    const p2_w = rl.measureText(p2_str, 24);
    ctx.drawText(p2_str, @as(i32, @intFromFloat(field.x)) - p2_w - 30, 30, 24, PINK);

    // Kill target
    var target_buf: [64:0]u8 = undefined;
    const target_str = std.fmt.bufPrintZ(&target_buf, "First to {d}", .{KILLS_TO_WIN}) catch unreachable;
    const target_w = rl.measureText(target_str, 20);
    ctx.drawText(target_str, @as(i32, @intFromFloat(field.x / 2)) - @divTrunc(target_w, 2), 30, 20, GRAY);

    // Hyperspace cooldown indicators
    if (game.ship1.alive and game.ship1.hyperspace_cooldown > 0) {
        var hs_buf: [32:0]u8 = undefined;
        const hs_str = std.fmt.bufPrintZ(&hs_buf, "HS: {d:.0}s", .{game.ship1.hyperspace_cooldown}) catch unreachable;
        ctx.drawText(hs_str, 30, 60, 16, GRAY);
    }
    if (game.ship2.alive and game.ship2.hyperspace_cooldown > 0) {
        var hs_buf: [32:0]u8 = undefined;
        const hs_str = std.fmt.bufPrintZ(&hs_buf, "HS: {d:.0}s", .{game.ship2.hyperspace_cooldown}) catch unreachable;
        const hs_w = rl.measureText(hs_str, 16);
        ctx.drawText(hs_str, @as(i32, @intFromFloat(field.x)) - hs_w - 30, 60, 16, GRAY);
    }

    // Overlays
    if (game.paused) {
        vgame.drawOverlay(field, .{
            .title = "PAUSED",
            .lines = &.{
                "P to resume",
                "R to restart match",
                "",
                "P1: A/D rotate  W thrust  TAB fire  S hyperspace",
                "P2: L/R rotate  Up thrust  RShift fire  Down hyperspace",
            },
        });
    }
    if (game.game_over) {
        var win_buf: [64:0]u8 = undefined;
        const winner_color = if (game.winner == 1) WHITE else PINK;
        const winner_name = if (game.winner == 1) "PLAYER 1" else "PLAYER 2";
        const win_str = std.fmt.bufPrintZ(&win_buf, "{s} WINS!", .{winner_name}) catch unreachable;
        vgame.drawOverlay(field, .{
            .title = win_str,
            .title_color = winner_color,
            .lines = &.{ "", "Press R to play again" },
            .fullscreen_dim = true,
        });
    }
}

// ── Main ──────────────────────────────────────────────────────────

pub fn main() void {
    mainImpl() catch |err| {
        std.log.err("game error: {}", .{err});
    };
}

fn mainImpl() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "ZigStarfight",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
        .glow = true,
        .msaa = true,
    });
    defer app.deinit();

    // Audio — optional, game runs silent if unavailable
    app.initAudio(.{
        .clips = &sound_clips,
        .resource_dir = "resources",
    }) catch |err| {
        std.log.warn("Audio init failed (game will be silent): {}", .{err});
    };
    const audio: ?*const vgame.AudioManager = if (app.audio != null) &app.audio.? else null;

    // Particles
    var particles = vgame.Particles.init(allocator);
    defer particles.deinit();

    // PRNG
    var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
    const rand = prng.random();

    const field = app.screen.size;
    var game = Game{
        .ship1 = .{
            .pos = .{ .x = field.x * 0.2, .y = field.y * 0.5 },
            .vel = .{ .x = 0, .y = 0 },
            .rot = 0.0,
            .color = WHITE,
            .is_p1 = true,
            .invuln_timer = RESPAWN_INVULN,
        },
        .ship2 = .{
            .pos = .{ .x = field.x * 0.8, .y = field.y * 0.5 },
            .vel = .{ .x = 0, .y = 0 },
            .rot = math.pi,
            .color = PINK,
            .is_p1 = false,
            .invuln_timer = RESPAWN_INVULN,
        },
        .bullets = .empty,
        .sun_pos = .{ .x = field.x * 0.5, .y = field.y * 0.5 },
        .allocator = allocator,
        .rand = rand,
    };
    defer game.bullets.deinit(allocator);

    while (app.frame()) {
        game.delta = app.delta;
        const scale = app.screen.scale;
        const fs = app.screen.size;

        particles.update(game.delta, fs);
        try update(&game, audio, &particles, fs);

        var ctx = app.beginRender();
        defer ctx.end();

        render(&game, &ctx, &particles, scale, fs);
    }
}