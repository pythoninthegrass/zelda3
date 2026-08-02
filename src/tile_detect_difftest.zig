// Tier-B differential test for src/tile_detect.zig: links the pre-port
// tile_detect.c (symbols renamed with a c_ prefix via objcopy, wired in
// build.zig's difftest step) against the ported Zig module and diffs their
// observable g_ram state over fixed-seed randomized inputs.
//
// Tile detection is a pure g_ram state machine: inputs are the link coords /
// layer / room-index scalars, the dungeon attr window, the overworld tileattr
// window, and the ancilla coordinate arrays; outputs are the tiledetect_*
// bitfields plus R12/R14/scratch_1. The harness seeds identical inputs,
// snapshots, runs the C reference, captures the post-state, restores, runs
// the Zig port, and byte-compares the two post-states. g_ram and g_zenv are
// defined here so both flavours share one buffer. The cross-module externs
// (map8/map16 lookup tables, Ancilla_GetX/Y) are stubbed per flavour: the C
// side through other/tile_detect_difftest_stubs/, the Zig side below.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

const expectEqual = std.testing.expectEqual;

// Test-local definitions of the externs tile_detect.zig and the renamed C
// object reference. Same shape as the C side: extern uint8 g_ram[131072].
export var g_ram: [0x20000]u8 = undefined;
export var g_zenv: v.ZeldaEnv = .{
    .ram = null,
    .sram = null,
    .vram = null,
    .ppu = null,
    .player = null,
    .dma = null,
    .dialogue_blk = .{ .ptr = null, .size = 0 },
    .dialogue_font_blk = .{ .ptr = null, .size = 0 },
    .dialogue_flags = 0,
};

// Scrambled tables: map16 indices span 0..0x1ff with the 0x4000/0x8000 high
// bits (feeding the slope or-in and bit-14 paths), map8 attrs span the full
// byte range so every behavior case fires. Both flavours read these buffers.
export var tile_detect_difftest_map8toattr: [512]t.uint8 = undefined;
export var tile_detect_difftest_map16tomap8: [0x2000]t.uint16 = undefined;

// Zig-side cross-module lookups (the C flavour's c_ variants live in the
// stubs and read the same buffers).
export fn GetMap8toTileAttr() [*]const t.uint8 {
    return &tile_detect_difftest_map8toattr;
}
export fn GetMap16toMap8Table() [*]const t.uint16 {
    return &tile_detect_difftest_map16tomap8;
}
export fn Ancilla_GetX(k: c_int) t.uint16 {
    return @as(t.uint16, v.ancilla_x_lo()[@intCast(k)]) | @as(t.uint16, v.ancilla_x_hi()[@intCast(k)]) << 8;
}
export fn Ancilla_GetY(k: c_int) t.uint16 {
    return @as(t.uint16, v.ancilla_y_lo()[@intCast(k)]) | @as(t.uint16, v.ancilla_y_hi()[@intCast(k)]) << 8;
}

// The Zig port's exported symbols resolve against the linked tile_detect.o
// (the ported module), the C reference via the c_* externs (objcopy-renamed).
extern fn Overworld_GetTileAttributeAtLocation(x: t.uint16, y: t.uint16) t.uint8;
extern fn TileDetect_Movement_Y(direction: t.uint16) void;
extern fn TileDetect_Movement_X(direction: t.uint16) void;
extern fn TileDetect_Movement_VerticalSlopes(direction: t.uint16) void;
extern fn TileDetect_Movement_HorizontalSlopes(direction: t.uint16) void;
extern fn Player_TileDetectNearby() void;
extern fn Hookshot_CheckTileCollision(k: c_int) void;
extern fn Hookshot_CheckSingleLayerTileCollision(x: t.uint16, y: t.uint16, dir: c_int) void;
extern fn HandleNudgingInADoor(speed: t.int8) void;
extern fn TileCheckForMirrorBonk() void;
extern fn TileDetect_SwordSwingDeepInDoor(dw: t.uint8) void;
extern fn TileDetect_ResetState() void;
extern fn TileDetection_Execute(x: t.uint16, y: t.uint16, bits: t.uint16) void;
extern fn TileDetect_ExecuteInner(tile: t.uint8, offs: t.uint16, bits: t.uint16, is_indoors: bool) void;

// Pre-port C reference (tile_detect.c), symbols renamed to c_<name> by objcopy.
extern fn c_Overworld_GetTileAttributeAtLocation(x: t.uint16, y: t.uint16) t.uint8;
extern fn c_TileDetect_Movement_Y(direction: t.uint16) void;
extern fn c_TileDetect_Movement_X(direction: t.uint16) void;
extern fn c_TileDetect_Movement_VerticalSlopes(direction: t.uint16) void;
extern fn c_TileDetect_Movement_HorizontalSlopes(direction: t.uint16) void;
extern fn c_Player_TileDetectNearby() void;
extern fn c_Hookshot_CheckTileCollision(k: c_int) void;
extern fn c_Hookshot_CheckSingleLayerTileCollision(x: t.uint16, y: t.uint16, dir: c_int) void;
extern fn c_HandleNudgingInADoor(speed: t.int8) void;
extern fn c_TileCheckForMirrorBonk() void;
extern fn c_TileDetect_SwordSwingDeepInDoor(dw: t.uint8) void;
extern fn c_TileDetect_ResetState() void;
extern fn c_TileDetection_Execute(x: t.uint16, y: t.uint16, bits: t.uint16) void;
extern fn c_TileDetect_ExecuteInner(tile: t.uint8, offs: t.uint16, bits: t.uint16, is_indoors: bool) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x71de7ec7);
    return prng.?.random();
}

var seed: [0x20000]u8 = undefined;
var c_post: [0x20000]u8 = undefined;

fn seedRam() void {
    @memcpy(&g_ram, &seed);
}

fn captureSeed() void {
    @memcpy(&seed, &g_ram);
}

// Argument slots for the no-arg wrapper pairs (Zig inner fns can't capture
// the enclosing test's locals, so each parameterized entry point reads its
// inputs from here).
var arg_x: t.uint16 = 0;
var arg_y: t.uint16 = 0;
var arg_bits: t.uint16 = 0;
var arg_dir16: t.uint16 = 0;
var arg_tile: t.uint8 = 0;
var arg_offs: t.uint16 = 0;
var arg_indoors: bool = false;
var arg_k: c_int = 0;
var arg_dirc: c_int = 0;
var arg_speed: t.int8 = 0;
var arg_dw: t.uint8 = 0;

// Run `cFn` then `zFn` against identical seeded g_ram, then byte-compare the
// whole buffer so any write outside the expected windows is caught.
fn runAndDiff(context: []const u8, cFn: anytype, zFn: anytype) !void {
    captureSeed();
    seedRam();
    cFn();
    @memcpy(&c_post, &g_ram);
    seedRam();
    zFn();
    if (!std.mem.eql(u8, &c_post, &g_ram)) {
        var i: usize = 0;
        while (i < 0x20000) : (i += 1) {
            if (c_post[i] != g_ram[i]) {
                std.debug.print("{s}: g_ram[0x{X:0>5}] c=0x{X:0>2} z=0x{X:0>2}\n", .{ context, i, c_post[i], g_ram[i] });
                break;
            }
        }
        return error.RamMismatch;
    }
}

// Baseline: a room-sized random dungeon attr window, sane masks, plus the
// lookup tables. Individual tests override the flag they exercise.
fn seedBase() void {
    var r = rnd();
    var i: usize = 0;
    while (i < 0x2000) : (i += 1)
        g_ram[0x12000 + i] = r.int(t.uint8);
    i = 0;
    while (i < 0x800) : (i += 1)
        v.overworld_tileattr()[i] = r.intRangeAtMost(t.uint16, 0, 0x1ff);
    i = 0;
    while (i < 512) : (i += 1)
        tile_detect_difftest_map8toattr[i] = r.int(t.uint8);
    i = 0;
    while (i < 0x2000) : (i += 1) {
        var val = r.intRangeAtMost(t.uint16, 0, 0x1ff);
        if (r.boolean()) val |= 0x4000;
        if (r.boolean()) val |= 0x8000;
        tile_detect_difftest_map16tomap8[i] = val;
    }
    v.tilemap_location_calc_mask().* = 0x1ff;
    v.overworld_offset_mask_x().* = 0x1ff;
    v.overworld_offset_mask_y().* = 0x1ff;
    v.overworld_offset_base_x().* = r.intRangeAtMost(t.uint16, 0, 0x1e0) & ~@as(t.uint16, 7);
    v.overworld_offset_base_y().* = r.intRangeAtMost(t.uint16, 0, 0x1e0) & ~@as(t.uint16, 7);
    i = 0;
    while (i < 6) : (i += 1)
        v.dung_chest_locations()[i] = if (r.boolean()) @as(t.uint16, 0x8000) else r.int(t.uint16);
}

fn cReset() void {
    c_TileDetect_ResetState();
}
fn zReset() void {
    TileDetect_ResetState();
}

test "diff TileDetect_ResetState over random dirty state" {
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        var r = rnd();
        var j: usize = 0;
        while (j < 0x400) : (j += 1)
            g_ram[j] = r.int(t.uint8);
        j = 0x2c0;
        while (j < 0x400) : (j += 1)
            g_ram[j] = r.int(t.uint8);
        try runAndDiff("ResetState", cReset, zReset);
    }
}

fn cInner() void {
    c_TileDetect_ExecuteInner(arg_tile, arg_offs, arg_bits, arg_indoors);
}
fn zInner() void {
    TileDetect_ExecuteInner(arg_tile, arg_offs, arg_bits, arg_indoors);
}

test "diff TileDetect_ExecuteInner over every tile value, indoors and out" {
    var tile: usize = 0;
    while (tile < 256) : (tile += 1) {
        const bits_cases = [4]t.uint16{ 1, 2, 4, 8 };
        var bits_idx: usize = 0;
        while (bits_idx < 4) : (bits_idx += 1) {
            var indoor_i: u1 = 0;
            while (true) {
                seedBase();
                arg_tile = @intCast(tile);
                arg_offs = 0x40;
                arg_bits = bits_cases[bits_idx];
                arg_indoors = indoor_i == 1;
                // give the RupeeTile read a defined neighbour
                v.dung_bg2_attr_table()[@as(usize, 0x40) + 64] = if (rnd().boolean()) 0x60 else 0x00;
                try runAndDiff("ExecuteInner", cInner, zInner);
                if (indoor_i == 1) break;
                indoor_i = 1;
            }
        }
    }
}

test "diff Overworld_GetTileAttributeAtLocation over random coords" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        seedBase();
        const x = rnd().int(t.uint16);
        const y = rnd().int(t.uint16);
        captureSeed();
        seedRam();
        const rc = c_Overworld_GetTileAttributeAtLocation(x, y);
        seedRam();
        const rz = Overworld_GetTileAttributeAtLocation(x, y);
        try expectEqual(rc, rz);
    }
}

fn cExec() void {
    c_TileDetection_Execute(arg_x, arg_y, arg_bits);
}
fn zExec() void {
    TileDetection_Execute(arg_x, arg_y, arg_bits);
}

test "diff TileDetection_Execute over random coords indoors and out" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        seedBase();
        arg_x = rnd().intRangeAtMost(t.uint16, 0, 0x1ff);
        arg_y = rnd().intRangeAtMost(t.uint16, 0, 0x1ff);
        arg_bits = @as(t.uint16, 1) << @intCast(rnd().intRangeAtMost(u4, 0, 3));
        v.player_is_indoors().* = rnd().int(t.uint8);
        v.link_is_on_lower_level().* = rnd().int(t.uint8);
        v.force_move_any_direction().* = rnd().int(t.uint16);
        try runAndDiff("Execute", cExec, zExec);
    }
}

fn cMoveY() void {
    c_TileDetect_Movement_Y(arg_dir16);
}
fn zMoveY() void {
    TileDetect_Movement_Y(arg_dir16);
}
fn cMoveX() void {
    c_TileDetect_Movement_X(arg_dir16);
}
fn zMoveX() void {
    TileDetect_Movement_X(arg_dir16);
}

test "diff TileDetect_Movement_Y/X over all directions and random coords" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        arg_dir16 = rnd().intRangeAtMost(t.uint16, 0, 3);
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("Movement_Y", cMoveY, zMoveY);
        try runAndDiff("Movement_X", cMoveX, zMoveX);
    }
}

fn cVertSlopes() void {
    c_TileDetect_Movement_VerticalSlopes(arg_dir16);
}
fn zVertSlopes() void {
    TileDetect_Movement_VerticalSlopes(arg_dir16);
}
fn cHorizSlopes() void {
    c_TileDetect_Movement_HorizontalSlopes(arg_dir16);
}
fn zHorizSlopes() void {
    TileDetect_Movement_HorizontalSlopes(arg_dir16);
}

test "diff slope movement variants over all directions" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        arg_dir16 = rnd().intRangeAtMost(t.uint16, 0, 3);
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("VerticalSlopes", cVertSlopes, zVertSlopes);
        try runAndDiff("HorizontalSlopes", cHorizSlopes, zHorizSlopes);
    }
}

test "diff Player_TileDetectNearby over random coords" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("Nearby", c_Player_TileDetectNearby, Player_TileDetectNearby);
    }
}

fn cHookshot() void {
    c_Hookshot_CheckTileCollision(arg_k);
}
fn zHookshot() void {
    Hookshot_CheckTileCollision(arg_k);
}

test "diff Hookshot_CheckTileCollision over random ancilla state" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        seedBase();
        arg_k = rnd().intRangeAtMost(c_int, 0, 9);
        v.ancilla_arr1()[@intCast(arg_k)] = rnd().int(t.uint8);
        v.ancilla_dir()[@intCast(arg_k)] = rnd().intRangeAtMost(t.uint8, 0, 3);
        v.ancilla_x_lo()[@intCast(arg_k)] = rnd().int(t.uint8);
        v.ancilla_x_hi()[@intCast(arg_k)] = rnd().int(t.uint8);
        v.ancilla_y_lo()[@intCast(arg_k)] = rnd().int(t.uint8);
        v.ancilla_y_hi()[@intCast(arg_k)] = rnd().int(t.uint8);
        v.dungeon_room_index().* = rnd().int(t.uint16);
        v.link_is_on_lower_level().* = rnd().int(t.uint8);
        v.kind_of_in_room_staircase().* = rnd().int(t.uint16);
        v.dung_hdr_collision().* = rnd().intRangeAtMost(t.uint8, 0, 3);
        v.player_is_indoors().* = 1;
        v.BG1HOFS_copy2().* = rnd().int(t.uint16);
        v.BG2HOFS_copy2().* = rnd().int(t.uint16);
        v.BG1VOFS_copy2().* = rnd().int(t.uint16);
        v.BG2VOFS_copy2().* = rnd().int(t.uint16);
        try runAndDiff("Hookshot", cHookshot, zHookshot);
    }
}

fn cHookshotSingle() void {
    c_Hookshot_CheckSingleLayerTileCollision(arg_x, arg_y, arg_dirc);
}
fn zHookshotSingle() void {
    Hookshot_CheckSingleLayerTileCollision(arg_x, arg_y, arg_dirc);
}

test "diff Hookshot_CheckSingleLayerTileCollision over all dirs" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        arg_x = rnd().intRangeAtMost(t.uint16, 0, 0x1ff);
        arg_y = rnd().intRangeAtMost(t.uint16, 0, 0x1ff);
        arg_dirc = rnd().intRangeAtMost(c_int, 0, 3);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("HookshotSingle", cHookshotSingle, zHookshotSingle);
    }
}

fn cNudge() void {
    c_HandleNudgingInADoor(arg_speed);
}
fn zNudge() void {
    HandleNudgingInADoor(arg_speed);
}

test "diff HandleNudgingInADoor over random door probes" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        seedBase();
        arg_speed = rnd().int(t.int8);
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.link_last_direction_moved_towards().* = rnd().int(t.uint8);
        v.player_is_indoors().* = 1;
        try runAndDiff("Nudging", cNudge, zNudge);
    }
}

test "diff TileCheckForMirrorBonk over random coords" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("MirrorBonk", c_TileCheckForMirrorBonk, TileCheckForMirrorBonk);
    }
}

fn cSwordDoor() void {
    c_TileDetect_SwordSwingDeepInDoor(arg_dw);
}
fn zSwordDoor() void {
    TileDetect_SwordSwingDeepInDoor(arg_dw);
}

test "diff TileDetect_SwordSwingDeepInDoor over all door slots" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        seedBase();
        arg_dw = rnd().intRangeAtMost(t.uint8, 1, 2);
        v.link_x_coord().* = rnd().int(t.uint16);
        v.link_y_coord().* = rnd().int(t.uint16);
        v.player_is_indoors().* = rnd().int(t.uint8);
        try runAndDiff("SwordDoor", cSwordDoor, zSwordDoor);
    }
}
