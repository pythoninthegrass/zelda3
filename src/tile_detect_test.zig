// Tier-A unit tests for src/tile_detect.zig: golden-value checks for the tile
// collision detector's leaf logic, using reference outputs captured from the
// pre-port tile_detect.c. g_ram and g_zenv are defined test-locally so the
// variables.zig accessors resolve; the map8/map16 lookup tables and the
// cross-module Ancilla_GetX/Y are stubbed below (the real ones live in
// overworld.c/ancilla.c, still C).

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");
const td = @import("tile_detect.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

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

comptime {
    _ = td.Overworld_GetTileAttributeAtLocation;
    _ = td.TileDetect_Movement_Y;
    _ = td.TileDetect_Movement_X;
    _ = td.TileDetect_Movement_VerticalSlopes;
    _ = td.TileDetect_Movement_HorizontalSlopes;
    _ = td.Player_TileDetectNearby;
    _ = td.Hookshot_CheckTileCollision;
    _ = td.Hookshot_CheckSingleLayerTileCollision;
    _ = td.HandleNudgingInADoor;
    _ = td.TileCheckForMirrorBonk;
    _ = td.TileDetect_SwordSwingDeepInDoor;
    _ = td.TileDetect_ResetState;
    _ = td.TileDetection_Execute;
    _ = td.TileDetect_ExecuteInner;
}

// Identity map8->attr table (attr[i] = i & 0x1ff low byte) plus a map16->map8
// table of sequential indices: Overworld_GetTileAttributeAtLocation reduces
// to a deterministic function of (x, y) for these goldens.
var test_map8toattr: [512]t.uint8 = undefined;
var test_map16tomap8: [0x2000]t.uint16 = undefined;

export fn GetMap8toTileAttr() [*]const t.uint8 {
    return &test_map8toattr;
}
export fn GetMap16toMap8Table() [*]const t.uint16 {
    return &test_map16tomap8;
}
export fn Ancilla_GetX(k: c_int) t.uint16 {
    return @as(t.uint16, v.ancilla_x_lo()[@intCast(k)]) | @as(t.uint16, v.ancilla_x_hi()[@intCast(k)]) << 8;
}
export fn Ancilla_GetY(k: c_int) t.uint16 {
    return @as(t.uint16, v.ancilla_y_lo()[@intCast(k)]) | @as(t.uint16, v.ancilla_y_hi()[@intCast(k)]) << 8;
}

fn resetRam() void {
    @memset(&g_ram, 0);
    var i: usize = 0;
    while (i < 512) : (i += 1)
        test_map8toattr[i] = @truncate(i);
    i = 0;
    while (i < 0x2000) : (i += 1)
        test_map16tomap8[i] = @truncate(i);
    v.tilemap_location_calc_mask().* = 0x1ff;
}

test "TileDetect_ResetState zeroes every tiledetect bitfield" {
    resetRam();
    // dirty every field ResetState owns
    v.R12().* = 0xffff;
    v.R14().* = 0xffff;
    v.tiledetect_diagonal_tile().* = 0xffff;
    v.tiledetect_stair_tile().* = 0xff;
    v.tiledetect_pit_tile().* = 0xff;
    v.tiledetect_inroom_staircase().* = 0xffff;
    v.tiledetect_var2().* = 0xffff;
    v.tiledetect_var1().* = 0xffff;
    v.tiledetect_moving_floor_tiles().* = 0xffff;
    v.tiledetect_deepwater().* = 0xffff;
    v.tiledetect_normal_tiles().* = 0xffff;
    v.tiledetect_icy_floor().* = 0xffff;
    v.tiledetect_water_staircase().* = 0xffff;
    v.tiledetect_thick_grass().* = 0xffff;
    v.tiledetect_shallow_water().* = 0xffff;
    v.tiledetect_destruction_aftermath().* = 0xffff;
    v.tiledetect_read_something().* = 0xffff;
    v.tiledetect_vertical_ledge().* = 0xff;
    v.detection_of_ledge_tiles_horiz_uphoriz().* = 0xff;
    v.tiledetect_ledges_down_leftright().* = 0xff;
    v.detection_of_unknown_tile_types().* = 0xff;
    v.tiledetect_chest().* = 0xffff;
    v.tiledetect_key_lock_gravestones().* = 0xff;
    v.bitfield_spike_cactus_tiles().* = 0xff;
    v.tiledetect_spike_floor_and_tile_triggers().* = 0xff;
    v.bitmask_for_dashable_tiles().* = 0xff;
    v.tiledetect_misc_tiles().* = 0xffff;
    v.tiledetect_var4().* = 0xffff;

    td.TileDetect_ResetState();

    try expectEqual(@as(t.uint16, 0), v.R12().*);
    try expectEqual(@as(t.uint16, 0), v.R14().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_diagonal_tile().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_stair_tile().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_pit_tile().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_inroom_staircase().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_var2().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_var1().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_moving_floor_tiles().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_deepwater().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_normal_tiles().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_icy_floor().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_water_staircase().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_thick_grass().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_shallow_water().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_destruction_aftermath().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_read_something().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_vertical_ledge().*);
    try expectEqual(@as(t.uint8, 0), v.detection_of_ledge_tiles_horiz_uphoriz().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_ledges_down_leftright().*);
    try expectEqual(@as(t.uint8, 0), v.detection_of_unknown_tile_types().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_chest().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_key_lock_gravestones().*);
    try expectEqual(@as(t.uint8, 0), v.bitfield_spike_cactus_tiles().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_spike_floor_and_tile_triggers().*);
    try expectEqual(@as(t.uint8, 0), v.bitmask_for_dashable_tiles().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_misc_tiles().*);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_var4().*);
}

test "TileDetect_ExecuteInner standard collision sets R14" {
    resetRam();
    td.TileDetect_ExecuteInner(0x01, 0, 1, false);
    try expectEqual(@as(t.uint16, 1), v.R14().*);
    td.TileDetect_ExecuteInner(0x02, 0, 4, false);
    try expectEqual(@as(t.uint16, 5), v.R14().*);
    // overworld nothing-tile leaves R14 alone, sets normal_tiles outdoors
    td.TileDetect_ExecuteInner(0x00, 0, 2, false);
    try expectEqual(@as(t.uint16, 5), v.R14().*);
    try expectEqual(@as(t.uint16, 2), v.tiledetect_normal_tiles().*);
    // indoors, the same nothing-tile does not set normal_tiles
    resetRam();
    td.TileDetect_ExecuteInner(0x00, 0, 2, true);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_normal_tiles().*);
}

test "TileDetect_ExecuteInner slope tiles set R12 and diag state" {
    resetRam();
    td.TileDetect_ExecuteInner(0x10, 0, 1, false);
    try expectEqual(@as(t.uint16, 1), v.R12().*);
    try expectEqual(@as(t.uint16, 4), v.tiledetect_diag_state().*);
    td.TileDetect_ExecuteInner(0x1a, 0, 2, false);
    try expectEqual(@as(t.uint16, 3), v.R12().*);
    try expectEqual(@as(t.uint16, 2), v.tiledetect_diagonal_tile().*);
    try expectEqual(@as(t.uint16, 6), v.tiledetect_diag_state().*);
}

test "TileDetect_ExecuteInner chest respects the opened-chest bit" {
    resetRam();
    v.dung_chest_locations()[0] = 0x0000; // unopened small-key chest
    td.TileDetect_ExecuteInner(0x58, 0, 1, true);
    try expectEqual(@as(t.uint16, 1), v.tiledetect_chest().*);
    try expectEqual(@as(t.uint8, 0), v.tiledetect_key_lock_gravestones().*);
    resetRam();
    v.dung_chest_locations()[0] = 0x8000; // already opened
    td.TileDetect_ExecuteInner(0x58, 0, 3, true);
    try expectEqual(@as(t.uint16, 0), v.tiledetect_chest().*);
    try expectEqual(@as(t.uint8, 3 << 4), v.tiledetect_key_lock_gravestones().*);
    try expectEqual(@as(t.uint16, 0x58), v.tiledetect_tile_type().*);
}

test "TileDetect_ExecuteInner liftable rock records the liftable index" {
    resetRam();
    td.TileDetect_ExecuteInner(0x52, 0, 2, true);
    try expectEqual(@as(t.uint16, 2), v.tiledetect_read_something().*);
    try expectEqual(@as(t.uint8, 2), v.interacting_with_liftable_tile_x2().*);
    try expectEqual(@as(t.uint16, 2), v.R14().*);
    // 0x50/0x51 additionally flag dash-ability
    resetRam();
    td.TileDetect_ExecuteInner(0x50, 0, 1, true);
    try expectEqual(@as(t.uint8, 1 << 4), v.bitmask_for_dashable_tiles().*);
}

test "TileDetect_ExecuteInner spike gate honors the menu block + state bits" {
    resetRam();
    td.TileDetect_ExecuteInner(0x44, 0, 1, true);
    try expectEqual(@as(t.uint8, 1), v.bitfield_spike_cactus_tiles().*);
    try expectEqual(@as(t.uint16, 0), v.R14().*);
    resetRam();
    v.flag_block_link_menu().* = 1;
    td.TileDetect_ExecuteInner(0x44, 0, 1, true);
    try expectEqual(@as(t.uint8, 0), v.bitfield_spike_cactus_tiles().*);
    try expectEqual(@as(t.uint16, 1), v.R14().*);
}

test "TileDetect_ExecuteInner layer-toggle doors set transitioning flags" {
    resetRam();
    td.TileDetect_ExecuteInner(0x90, 0, 1, true);
    try expectEqual(@as(t.uint8, 1), v.room_transitioning_flags().*);
    td.TileDetect_ExecuteInner(0xa0, 0, 1, true);
    try expectEqual(@as(t.uint8, 2), v.room_transitioning_flags().*);
    td.TileDetect_ExecuteInner(0x98, 0, 1, true);
    try expectEqual(@as(t.uint8, 3), v.room_transitioning_flags().*);
    // R14 ORs the same (bits<<4)|(bits<<8) pattern each time: 0x110
    try expectEqual(@as(t.uint16, 0x110), v.R14().*);
}

test "TileDetect_ExecuteInner cheat-walk collapses every tile to nothing" {
    resetRam();
    v.cheatWalkThroughWalls().* = 1;
    td.TileDetect_ExecuteInner(0x01, 0, 1, true); // would be solid indoors
    try expectEqual(@as(t.uint16, 0), v.R14().*);
    td.TileDetect_ExecuteInner(0x08, 0, 1, false); // deep water becomes nothing
    try expectEqual(@as(t.uint16, 0), v.tiledetect_deepwater().*);
    try expectEqual(@as(t.uint16, 1), v.tiledetect_normal_tiles().*);
}

test "TileDetection_Execute indoors reads the dungeon attr table" {
    resetRam();
    v.player_is_indoors().* = 1;
    v.dung_bg2_attr_table()[0] = 0x01;
    td.TileDetection_Execute(0, 0, 1);
    try expectEqual(@as(t.uint8, 0x01), v.link_tile_below().*);
    try expectEqual(@as(t.uint16, 1), v.R14().*);
    // upper layer reads offset 0x1000 instead of 0
    resetRam();
    v.player_is_indoors().* = 1;
    v.link_is_on_lower_level().* = 1;
    v.dung_bg2_attr_table()[0x1000] = 0x08;
    td.TileDetection_Execute(0, 0, 2);
    try expectEqual(@as(t.uint8, 0x08), v.link_tile_below().*);
    try expectEqual(@as(t.uint16, 2), v.tiledetect_deepwater().*);
}

test "TileDetection_Execute indoors forces force_move_any_direction to a byte" {
    resetRam();
    v.player_is_indoors().* = 1;
    v.force_move_any_direction().* = 0x1234;
    td.TileDetection_Execute(0, 0, 1);
    try expectEqual(@as(t.uint16, 0x34), v.force_move_any_direction().*);
}

test "Overworld_GetTileAttributeAtLocation golden lookups" {
    resetRam();
    v.overworld_offset_base_x().* = 0;
    v.overworld_offset_base_y().* = 0;
    v.overworld_offset_mask_x().* = 0x1ff;
    v.overworld_offset_mask_y().* = 0x1ff;
    // (x=0, y=0): t = attr[0]*4 = 0; map8 = map16[0] = 0 -> attr 0
    try expectEqual(@as(t.uint8, 0), td.Overworld_GetTileAttributeAtLocation(0, 0));
    // (x=1, y=0): t |= 1 -> map16[1] = 1 -> attr 1
    try expectEqual(@as(t.uint8, 1), td.Overworld_GetTileAttributeAtLocation(1, 0));
    // (x=0, y=8): t |= 2 -> map16[2] = 2 -> attr 2
    try expectEqual(@as(t.uint8, 2), td.Overworld_GetTileAttributeAtLocation(0, 8));
}

test "TileDetect_Movement_Y scans three points along the X span" {
    resetRam();
    v.link_x_coord().* = 0x100;
    v.link_y_coord().* = 0x80;
    v.dung_bg2_attr_table()[0] = 0;
    td.TileDetect_Movement_Y(0); // direction down
    // which_y_pos picks up link_y + tab0[0]
    try expectEqual(@as(t.uint16, 0x88), v.tiledetect_which_y_pos()[0]);
    // scratch_1 is the rightmost x (link_x + tab3[0]) >> 3
    try expectEqual(@as(t.uint16, (0x10f & 0x1ff) >> 3), v.scratch_1().*);
}

test "HandleNudgingInADoor moves Link opposite the blocked direction" {
    resetRam();
    v.player_is_indoors().* = 1;
    v.link_last_direction_moved_towards().* = 2; // vertical
    v.link_y_coord().* = 0x40; // < 0x80 -> y index 1
    // put a solid tile under the probe point (x = (link_x + 8)>>3, y = link_y + 23)
    const x0: usize = ((0 + 8) & 0x1ff) >> 3;
    const y0: usize = (0x40 + 23) & 0x1ff;
    v.dung_bg2_attr_table()[(y0 & ~@as(usize, 7)) * 8 + x0] = 0x01;
    td.HandleNudgingInADoor(3);
    try expectEqual(@as(t.uint16, 0x40 - 3), v.link_y_coord().*);
}
