// Port of src/tile_detect.c: tile collision detection — the per-frame scans
// that classify the map8 tiles under Link's hitbox (movement, slopes, sword
// swings, hookshot, door nudging, mirror bonks) and fold each tile's
// behavior into the tiledetect_* bitfields. Every exported symbol keeps its
// exact C-ABI name and signature so the remaining .c callers (player.c,
// ancilla.c, dungeon.c, overworld.c, tagalong.c) link unchanged. All game
// state lives in g_ram (variables.zig accessors), byte-for-byte where the
// original 65816 code and the RAM-compare oracle expect it.
//
// Overworld tile lookups go through GetMap16toMap8Table/GetMap8toTileAttr
// (still C, in overworld.c), matching tile_detect.c's cross-module calls.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

extern fn GetMap16toMap8Table() [*]const t.uint16;
extern fn GetMap8toTileAttr() [*]const t.uint8;
extern fn Ancilla_GetX(k: c_int) t.uint16;
extern fn Ancilla_GetY(k: c_int) t.uint16;

const kDetectTiles_tab0 = [4]t.uint8{ 8, 24, 0, 15 };
const kDetectTiles_tab1 = [4]t.uint8{ 0, 0, 8, 8 };
const kDetectTiles_tab2 = [4]t.uint8{ 8, 8, 16, 16 };
const kDetectTiles_tab3 = [4]t.uint8{ 15, 15, 23, 23 };
const kDetectTiles_tab4 = [4]t.int8{ 7, 24, -1, 16 };
const kDetectTiles_tab5 = [4]t.uint8{ 0, 0, 8, 8 };
const kDetectTiles_tab6 = [4]t.uint8{ 15, 15, 23, 23 };

pub export fn Overworld_GetTileAttributeAtLocation(x: t.uint16, y: t.uint16) t.uint8 { // 80882e
    var t16: t.uint16 = ((y -% v.overworld_offset_base_y().*) & v.overworld_offset_mask_y().*) *% 8;
    t16 |= (x -% v.overworld_offset_base_x().*) & v.overworld_offset_mask_x().*;
    t16 = v.overworld_tileattr()[t16 >> 1] *% 4;
    t16 |= (y & 8) >> 2;
    t16 |= x & 1;
    t16 = GetMap16toMap8Table()[t16];

    var rv = GetMap8toTileAttr()[t16 & 0x1ff];
    if (rv >= 0x10 and rv < 0x1C) {
        rv |= @intCast((t16 >> 14) & 1);
    }
    return rv;
}

pub export fn TileDetect_Movement_Y(direction: t.uint16) void { // 87cdcb
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    v.tiledetect_pit_tile().* = 0;

    v.tiledetect_which_y_pos()[0] = v.link_y_coord().* +% kDetectTiles_tab0[direction];
    const y = v.tiledetect_which_y_pos()[0] & v.tilemap_location_calc_mask().*;
    const x0 = ((v.link_x_coord().* +% kDetectTiles_tab1[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((v.link_x_coord().* +% kDetectTiles_tab2[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    const x2 = ((v.link_x_coord().* +% kDetectTiles_tab3[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    v.scratch_1().* = x2;
    TileDetection_Execute(x0, y, 1);
    TileDetection_Execute(x1, y, 2);
    TileDetection_Execute(x2, y, 4);
}

pub export fn TileDetect_Movement_X(direction: t.uint16) void { // 87ce2a
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    v.tiledetect_pit_tile().* = 0;

    const x = ((v.link_x_coord().* +% kDetectTiles_tab0[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    const y0 = (v.link_y_coord().* +% kDetectTiles_tab1[direction]) & v.tilemap_location_calc_mask().*;
    v.tiledetect_which_y_pos()[0] = v.link_y_coord().* +% kDetectTiles_tab2[direction];
    const y1 = v.tiledetect_which_y_pos()[0] & v.tilemap_location_calc_mask().*;
    v.tiledetect_which_y_pos()[1] = v.link_y_coord().* +% kDetectTiles_tab3[direction];
    const y2 = v.tiledetect_which_y_pos()[1] & v.tilemap_location_calc_mask().*;
    TileDetection_Execute(x, y0, 1);
    TileDetection_Execute(x, y1, 2);
    TileDetection_Execute(x, y2, 4);
}

pub export fn TileDetect_Movement_VerticalSlopes(direction: t.uint16) void { // 87ce85
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    v.tiledetect_pit_tile().* = 0;

    const y = (v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDetectTiles_tab4[direction])))) & v.tilemap_location_calc_mask().*;
    const x0 = ((v.link_x_coord().* +% kDetectTiles_tab5[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((v.link_x_coord().* +% kDetectTiles_tab6[direction]) & v.tilemap_location_calc_mask().*) >> 3;
    TileDetection_Execute(x0, y, 1);
    TileDetection_Execute(x1, y, 2);
}

pub export fn TileDetect_Movement_HorizontalSlopes(direction: t.uint16) void { // 87cec9
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    v.tiledetect_pit_tile().* = 0;

    const x = ((v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDetectTiles_tab4[direction])))) & v.tilemap_location_calc_mask().*) >> 3;
    const y0 = (v.link_y_coord().* +% kDetectTiles_tab5[direction]) & v.tilemap_location_calc_mask().*;
    const y1 = (v.link_y_coord().* +% kDetectTiles_tab6[direction]) & v.tilemap_location_calc_mask().*;
    TileDetection_Execute(x, y0, 1);
    TileDetection_Execute(x, y1, 2);
}

pub export fn Player_TileDetectNearby() void { // 87cf12
    TileDetect_ResetState();
    v.tiledetect_pit_tile().* = 0;

    const x0 = ((v.link_x_coord().* +% kDetectTiles_tab1[0]) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((v.link_x_coord().* +% kDetectTiles_tab3[0]) & v.tilemap_location_calc_mask().*) >> 3;

    const y0 = (v.link_y_coord().* +% kDetectTiles_tab1[2]) & v.tilemap_location_calc_mask().*;
    const y1 = (v.link_y_coord().* +% kDetectTiles_tab3[2]) & v.tilemap_location_calc_mask().*;

    v.scratch_1().* = y0;

    TileDetection_Execute(x0, y0, 8);
    TileDetection_Execute(x0, y1, 2);
    TileDetection_Execute(x1, y0, 4);
    TileDetection_Execute(x1, y1, 1);
}

pub export fn Hookshot_CheckTileCollision(k: c_int) void { // 87d576
    const bak0 = t.byte(v.dungeon_room_index()).*;
    const bak1 = v.link_is_on_lower_level().*;

    if (v.ancilla_arr1()[@intCast(k)] != 0) {
        if (t.byte(v.kind_of_in_room_staircase()).* == 0)
            t.byte(v.dungeon_room_index()).* +%= 0x10;
        v.link_is_on_lower_level().* ^= 1;
    }

    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    const dir = v.ancilla_dir()[@intCast(k)];

    v.tiledetect_pit_tile().* = 0;
    TileDetect_ResetState();
    if (v.dung_hdr_collision().* == 2) {
        v.link_is_on_lower_level().* = 1;
        Hookshot_CheckSingleLayerTileCollision(x +% v.BG1HOFS_copy2().* -% v.BG2HOFS_copy2().*, y +% v.BG1VOFS_copy2().* -% v.BG2VOFS_copy2().*, dir);
        v.link_is_on_lower_level().* = 0;
    }
    Hookshot_CheckSingleLayerTileCollision(x, y, dir);

    v.link_is_on_lower_level().* = bak1;
    t.byte(v.dungeon_room_index()).* = bak0;
}

pub export fn Hookshot_CheckSingleLayerTileCollision(x: t.uint16, y: t.uint16, dir: c_int) void { // 87d607
    const kHookShot_CheckColl_X = [8]t.uint8{ 0, 15, 0, 15, 0, 0, 8, 8 };
    const kHookShot_CheckColl_Y = [8]t.uint8{ 0, 0, 7, 7, 0, 15, 0, 15 };
    const di: usize = @intCast(dir);
    const y0 = (y +% kHookShot_CheckColl_Y[di * 2 + 0]) & v.tilemap_location_calc_mask().*;
    const y1 = (y +% kHookShot_CheckColl_Y[di * 2 + 1]) & v.tilemap_location_calc_mask().*;
    const x0 = ((x +% kHookShot_CheckColl_X[di * 2 + 0]) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((x +% kHookShot_CheckColl_X[di * 2 + 1]) & v.tilemap_location_calc_mask().*) >> 3;
    TileDetection_Execute(x0, y0, 1);
    TileDetection_Execute(x1, y1, 2);
}

pub export fn HandleNudgingInADoor(speed: t.int8) void { // 87d667
    var y: t.uint8 = undefined;

    if (v.link_last_direction_moved_towards().* & 2 != 0) {
        y = if (t.byte(v.link_y_coord()).* < 0x80) 1 else 0;
    } else {
        y = if (t.byte(v.link_x_coord()).* < 0x80) 3 else 2;
    }
    v.tiledetect_pit_tile().* = 0;
    TileDetect_ResetState();

    const kDetectTiles_7_Y = [4]t.int8{ 8, 23, 16, 16 };
    const kDetectTiles_7_X = [4]t.int8{ 8, 8, 0, 15 };

    const x0 = ((v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDetectTiles_7_X[y])))) & v.tilemap_location_calc_mask().*) >> 3;
    const y0 = (v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDetectTiles_7_Y[y])))) & v.tilemap_location_calc_mask().*;

    TileDetection_Execute(x0, y0, 1);

    if ((v.R14().* | v.detection_of_ledge_tiles_horiz_uphoriz().*) & 3 == 0) {
        if ((v.tiledetect_vertical_ledge().* | v.detection_of_unknown_tile_types().*) & 0x33 == 0)
            return;
    }

    if (v.link_last_direction_moved_towards().* & 2 != 0) {
        v.link_y_coord().* -%= @as(t.uint16, @bitCast(@as(t.int16, speed)));
    } else {
        v.link_x_coord().* -%= @as(t.uint16, @bitCast(@as(t.int16, speed)));
    }
}

pub export fn TileCheckForMirrorBonk() void { // 87d6f4
    v.tiledetect_pit_tile().* = 0;
    TileDetect_ResetState();

    const x0 = ((v.link_x_coord().* +% 2) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((v.link_x_coord().* +% 13) & v.tilemap_location_calc_mask().*) >> 3;

    const y0 = (v.link_y_coord().* +% 10) & v.tilemap_location_calc_mask().*;
    const y1 = (v.link_y_coord().* +% 21) & v.tilemap_location_calc_mask().*;

    v.scratch_1().* = y0;

    TileDetection_Execute(x0, y0, 8);
    TileDetection_Execute(x0, y1, 2);
    TileDetection_Execute(x1, y0, 4);
    TileDetection_Execute(x1, y1, 1);
}

// Used when holding sword in doorway
pub export fn TileDetect_SwordSwingDeepInDoor(dw: t.uint8) void { // 87d73e
    v.tiledetect_pit_tile().* = 0;
    TileDetect_ResetState();

    const kDoorwayDetectX = [4]t.int8{ 8, 8, -1, 16 };
    const kDoorwayDetectY = [4]t.int8{ -1, 24, 16, 16 };
    const o: usize = @as(usize, dw - 1) * 2;
    const x0 = ((v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDoorwayDetectX[o + 0])))) & v.tilemap_location_calc_mask().*) >> 3;
    const x1 = ((v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDoorwayDetectX[o + 1])))) & v.tilemap_location_calc_mask().*) >> 3;

    const y0 = (v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDoorwayDetectY[o + 0])))) & v.tilemap_location_calc_mask().*;
    const y1 = (v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(t.int16, kDoorwayDetectY[o + 1])))) & v.tilemap_location_calc_mask().*;

    TileDetection_Execute(x0, y0, 1);
    TileDetection_Execute(x1, y1, 2);
}

pub export fn TileDetect_ResetState() void { // 87d798
    v.R12().* = 0;
    v.R14().* = 0;
    v.tiledetect_diagonal_tile().* = 0;
    v.tiledetect_stair_tile().* = 0;
    v.tiledetect_pit_tile().* = 0;
    v.tiledetect_inroom_staircase().* = 0;
    v.tiledetect_var2().* = 0;
    v.tiledetect_var1().* = 0;
    v.tiledetect_moving_floor_tiles().* = 0;
    v.tiledetect_deepwater().* = 0;
    v.tiledetect_normal_tiles().* = 0;
    v.tiledetect_icy_floor().* = 0;
    v.tiledetect_water_staircase().* = 0;
    v.tiledetect_thick_grass().* = 0;
    v.tiledetect_shallow_water().* = 0;
    v.tiledetect_destruction_aftermath().* = 0;
    v.tiledetect_read_something().* = 0;
    v.tiledetect_vertical_ledge().* = 0;
    v.detection_of_ledge_tiles_horiz_uphoriz().* = 0;
    v.tiledetect_ledges_down_leftright().* = 0;
    v.detection_of_unknown_tile_types().* = 0;
    v.tiledetect_chest().* = 0;
    v.tiledetect_key_lock_gravestones().* = 0;
    v.bitfield_spike_cactus_tiles().* = 0;
    v.tiledetect_spike_floor_and_tile_triggers().* = 0;
    v.bitmask_for_dashable_tiles().* = 0;
    v.tiledetect_misc_tiles().* = 0;
    v.tiledetect_var4().* = 0;
}

pub export fn TileDetection_Execute(x: t.uint16, y: t.uint16, bits: t.uint16) void { // 87d9d8
    var tile: t.uint8 = undefined;
    var offs: t.uint16 = 0;
    if (v.player_is_indoors().* != 0) {
        v.force_move_any_direction().* &= 0xff;
        offs = (y & ~@as(t.uint16, 7)) *% 8 + (x & 63) + if (v.link_is_on_lower_level().* != 0) @as(t.uint16, 0x1000) else 0;
        tile = v.dung_bg2_attr_table()[offs];
        if (v.cheatWalkThroughWalls().* != 0)
            tile = 0;
        v.link_tile_below().* = tile;
    } else {
        tile = Overworld_GetTileAttributeAtLocation(x, y);
    }
    TileDetect_ExecuteInner(tile, offs, bits, v.player_is_indoors().* != 0);
}

pub export fn TileDetect_ExecuteInner(tile_in: t.uint8, offs: t.uint16, bits: t.uint16, is_indoors: bool) void { // 87dc2e
    const word_87DC55 = [4]t.uint8{ 4, 0, 6, 2 };
    var tile = tile_in;
    if (v.cheatWalkThroughWalls().* != 0)
        tile = 0;

    switch (tile) {
        // TileBehavior_NothingOW
        0x00, 0x05, 0x06, 0x07, 0x14, 0x15, 0x16, 0x17, 0x21, 0x23, 0x24, 0x25, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x41, 0x45, 0x47, 0x49, 0x5e, 0x5f, 0x61, 0x62, 0x64, 0x65, 0x66, 0xa6, 0xa7, 0xbe, 0xbf, 0xd0...0xef => {
            if (!is_indoors)
                v.tiledetect_normal_tiles().* |= bits;
        },
        // TileBehavior_StandardCollision
        0x01, 0x02, 0x03, 0x26, 0x43 => {
            v.R14().* |= bits;
        },
        0x6c, 0x6d, 0x6e, 0x6f => {
            if (is_indoors) {
                v.R14().* |= bits;
            } else {
                v.tiledetect_normal_tiles().* |= bits;
            }
        },
        0x04 => {
            if (is_indoors) {
                v.R14().* |= bits;
            } else {
                v.tiledetect_thick_grass().* |= bits;
            }
        },
        0x0b => {
            if (is_indoors) {
                v.R14().* |= bits;
            } else {
                v.index_of_interacting_tile().* = tile;
                v.tiledetect_deepwater().* |= bits << 4;
            }
        },
        0x08 => // TileBehavior_DeepWater
        v.tiledetect_deepwater().* |= bits,
        0x09 => // TileBehavior_ShallowWater
        v.tiledetect_shallow_water().* |= bits,
        0x0a => // TileBehavior_ShortWaterLadder
        v.tiledetect_normal_tiles().* |= bits,
        0x0c => // TileBehavior_OverlayMask_0C
        v.tiledetect_moving_floor_tiles().* |= bits,
        0x0d => { // TileBehavior_SpikeFloor
            if (v.flag_block_link_menu().* == 0 and (v.dung_savegame_state_bits().* & 0x8000) == 0)
                v.tiledetect_spike_floor_and_tile_triggers().* |= @intCast(bits << 4);
        },
        0x0e => // TileBehavior_GanonIce
        v.tiledetect_icy_floor().* |= bits,
        0x0f => // TileBehavior_PalaceIce
        v.tiledetect_icy_floor().* |= bits << 4,
        // TileBehavior_Slope
        0x10, 0x11, 0x12, 0x13 => {
            v.R12().* |= bits;
            v.tiledetect_diag_state().* = word_87DC55[tile & 3];
        },
        // TileBehavior_SlopeOuter
        0x18, 0x19, 0x1a, 0x1b => {
            v.tiledetect_diagonal_tile().* |= bits;
            v.R12().* |= bits;
            v.tiledetect_diag_state().* = word_87DC55[tile & 3];
        },
        0x1c => // TileBehavior_OverlayMask_1C
        v.tiledetect_water_staircase().* |= bits,
        0x1d => { // TileBehavior_NorthSingleLayerStairs
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_inroom_staircase().* |= bits;
            v.tiledetect_stair_tile().* |= @intCast(bits);
        },
        // TileBehavior_NorthSwapLayerStairs
        0x1e, 0x1f => {
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_inroom_staircase().* |= bits;
            v.tiledetect_stair_tile().* |= @intCast(bits);
        },
        // TileBehavior_Pit
        0x20, 0xb0...0xbd => {
            if (v.player_on_somaria_platform().* == 0)
                v.tiledetect_pit_tile().* |= @intCast(bits);
        },
        // TileHandlerIndoor_22
        0x22, 0x30...0x37 => {
            v.tiledetect_stair_tile().* |= @intCast(bits);
        },
        0x27 => { // TileBehavior_Hookshottables
            v.R14().* |= bits;
            v.tiledetect_misc_tiles().* |= bits;
        },
        0x28 => { // TileBehavior_Ledge_North
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_vertical_ledge().* |= @intCast(bits);
        },
        0x29 => { // TileBehavior_Ledge_South
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_vertical_ledge().* |= @intCast(bits << 4);
        },
        // TileBehavior_Ledge_EastWest
        0x2a, 0x2b => {
            v.index_of_interacting_tile().* = tile;
            v.detection_of_ledge_tiles_horiz_uphoriz().* |= @intCast(bits);
        },
        // TileBehavior_Ledge_NorthDiagonal
        0x2c, 0x2e => {
            v.index_of_interacting_tile().* = tile;
            v.detection_of_ledge_tiles_horiz_uphoriz().* |= @intCast(bits << 4);
        },
        // TileBehavior_Ledge_SouthDiagonal
        0x2d, 0x2f => {
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_ledges_down_leftright().* |= @intCast(bits);
        },
        // TileHandlerIndoor_3E
        0x3d, 0x3e, 0x3f => {
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_inroom_staircase().* |= bits << 4;
            v.tiledetect_stair_tile().* |= @intCast(bits);
        },
        0x40 => // TileBehavior_ThickGrass
        v.tiledetect_thick_grass().* |= bits,
        0x44 => { // TileBehavior_Spike
            if (v.flag_block_link_menu().* == 0 and (v.dung_savegame_state_bits().* & 0x8000) == 0) {
                v.bitfield_spike_cactus_tiles().* |= @intCast(bits);
            } else {
                v.R14().* |= bits;
            }
        },
        0x46 => { // TileBehavior_HylianPlaque
            v.tiledetect_spike_floor_and_tile_triggers().* |= @intCast(bits);
            v.R14().* |= bits;
        },
        // TileBehavior_DiggableGround
        0x48, 0x4a => {
            v.tiledetect_destruction_aftermath().* |= bits;
            v.tiledetect_normal_tiles().* |= bits;
        },
        0x4b => // TileBehavior_Warp
        v.tiledetect_thick_grass().* |= bits << 4,
        // TileBehavior_Liftable
        0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56 => {
            const kTile50data = [7]t.uint8{ 0x54, 0x52, 0x50, 0x51, 0x53, 0x55, 0x56 };
            var i: isize = 6;
            while (i >= 0) : (i -= 1) {
                if (kTile50data[@intCast(i)] == tile) {
                    if (tile == 0x50 or tile == 0x51)
                        v.bitmask_for_dashable_tiles().* |= @intCast(bits << 4);
                    v.tiledetect_read_something().* |= bits;
                    v.interacting_with_liftable_tile_x2().* = @intCast(i * 2);
                    v.R14().* |= bits;
                    v.tiledetect_misc_tiles().* |= bits;
                    break;
                }
            }
        },
        0x57 => { // TileBehavior_BonkRocks
            v.R14().* |= bits;
            v.bitmask_for_dashable_tiles().* |= @intCast(bits << 4);
        },
        // TileBehavior_Chest
        0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d => {
            v.tiledetect_misc_tiles().* |= bits;
            v.index_of_interacting_tile().* = tile;
            if (v.dung_chest_locations()[tile - 0x58] >= 0x8000) {
                v.R14().* |= bits;
                v.tiledetect_key_lock_gravestones().* |= @intCast(bits << 4);
                if (bits & 2 != 0)
                    v.tiledetect_tile_type().* = tile;
            } else {
                v.tiledetect_chest().* |= bits; // small key lock
                v.R14().* |= bits;
            }
        },
        0x60 => { // TileBehavior_RupeeTile
            if (is_indoors) {
                if (v.dung_bg2_attr_table()[@as(usize, offs) + 64] == 0x60) {
                    v.tiledetect_misc_tiles().* |= bits << 8;
                } else {
                    v.tiledetect_misc_tiles().* |= bits << 12;
                }
            } else {
                v.tiledetect_normal_tiles().* |= bits;
            }
        },
        0x63 => { // TileBehavior_MinigameChest
            v.tiledetect_misc_tiles().* |= bits;
            v.index_of_interacting_tile().* = tile;
            v.tiledetect_chest().* |= bits; // small key lock
            v.R14().* |= bits;
        },
        0x67 => { // TileBehavior_CrystalPeg_Up
            v.R14().* |= bits;
            v.tiledetect_misc_tiles().* |= bits;
            v.bitfield_spike_cactus_tiles().* |= @intCast(bits << 4);
        },
        0x68 => // TileBehavior_Conveyor_Upwards
        v.tiledetect_var4().* |= bits,
        0x69 => // TileBehavior_Conveyor_Downwards
        v.tiledetect_var4().* |= bits << 4,
        0x6a => // TileBehavior_Conveyor_Leftwards
        v.tiledetect_var4().* |= bits << 8,
        0x6b => // TileBehavior_Conveyor_Rightwards
        v.tiledetect_var4().* |= bits << 12,
        // TileBehavior_ManipulablyReplaced
        0x70...0x7f => {
            if (bits & 2 != 0)
                v.tiledetect_var2().* |= @as(t.uint16, 1) << @intCast(tile & 0xf);
            v.R14().* |= bits;
            v.tiledetect_misc_tiles().* |= bits;
        },
        // TileHandlerIndoor_80
        0x80, 0x81, 0x84...0x8d => {
            v.R14().* |= bits << 4;
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileHandlerIndoor_82
        0x82, 0x83 => {
            v.R14().* |= (bits << 4) | (bits << 8);
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileBehavior_Entrance
        0x8e, 0x8f => {
            v.R14().* |= bits << 4;
            v.bitmask_for_dashable_tiles().* |= @intCast(bits);
            v.tiledetect_var1().* = 0;
        },
        // TileBehavior_LayerToggleShutterDoor
        0x90...0x97 => {
            v.room_transitioning_flags().* = 1;
            v.R14().* |= (bits << 4) | (bits << 8);
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileBehavior_LayerAndDungeonToggleShutterDoor
        0x98...0x9f, 0xa8...0xaf => {
            v.room_transitioning_flags().* = 3;
            v.R14().* |= (bits << 4) | (bits << 8);
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileBehavior_DungeonToggleManualDoor
        0xa0, 0xa1, 0xa4, 0xa5 => {
            v.room_transitioning_flags().* = 2;
            v.R14().* |= bits << 4;
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileBehavior_DungeonToggleShutterDoor
        0xa2, 0xa3 => {
            v.room_transitioning_flags().* = 2;
            v.R14().* |= (bits << 4) | (bits << 8);
            v.tiledetect_var1().* = 2 * (tile & 1);
        },
        // TileBehavior_LightableTorch
        0xc0...0xcf => {
            v.R14().* |= bits;
            v.tiledetect_misc_tiles().* |= bits;
        },
        // TileBehavior_FlaggableDoor
        0xf0...0xff => {
            v.R14().* |= bits;
            v.tiledetect_misc_tiles().* |= bits << 4;
        },
        0x42 => { // TileBehavior_GraveStone
            if (!is_indoors) {
                v.tiledetect_key_lock_gravestones().* |= @intCast(bits);
                v.R14().* |= bits;
            }
        },
        // TileBehavior_UnusedCornerType
        0x4c, 0x4d => {
            if (!is_indoors) {
                v.index_of_interacting_tile().* = tile;
                v.detection_of_unknown_tile_types().* |= @intCast(bits);
            }
        },
        // TileBehavior_EasternRuinsCorner
        0x4e, 0x4f => {
            if (!is_indoors) {
                v.index_of_interacting_tile().* = tile;
                v.detection_of_unknown_tile_types().* |= @intCast(bits << 4);
            }
        },
    }
}
