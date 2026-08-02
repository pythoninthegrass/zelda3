// Tier-A unit tests for src/variables.zig. The g_ram symbol is mirrored by
// a test-local extern array so the accessors can be exercised directly:
// every accessor's returned pointer is checked against &g_ram[offset]
// (offset fidelity), reads/writes round-trip through the raw bytes
// (little-endian, unaligned-safe), and the struct overlays are verified to
// alias their scalar/pointer counterparts at the same addresses.
//
// The authoritative every-accessor check is scripts/check_variables_offsets.py,
// which cross-references each accessor's offset/type against variables.h;
// the runtime spot checks here cover a random sample of 24 plus every
// overlay/special case by hand.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

const expectEqual = std.testing.expectEqual;

// Test-local definition of the extern symbols variables.zig references.
// Same shape as the C side: extern uint8 g_ram[131072] in zelda_rtl.c.
export var g_ram: [0x20000]u8 = undefined;
var sram_storage: [0x2000]u8 = undefined;
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

fn expectAddr(comptime off: usize, actual: anytype) !void {
    try expectEqual(@intFromPtr(&g_ram[off]), @intFromPtr(actual));
}

test "struct layouts match the C ABI" {
    // Sizes of the plain C aggregates (uint16 members: no padding).
    try expectEqual(4, @sizeOf(v.MovableBlockData));
    try expectEqual(4, @sizeOf(v.OamEntSigned));
    try expectEqual(8, @sizeOf(v.RoomBounds));
    try expectEqual(8, @sizeOf(v.OwScrollVars));
    try expectEqual(28, @sizeOf(v.MirrorHdmaVars));
    try expectEqual(64, @sizeOf(v.UploadVram_Row));
    try expectEqual(2048, @sizeOf(v.UploadVram_32x32));
    try expectEqual(264, @sizeOf(v.UploadVram_3));
    // Member offsets within the overlays. RoomBoundsFields is the named
    // arm carrying the C anonymous-union members (a0..b1); both union arms
    // start at byte 0 in C, so only the struct side has offsets to pin.
    // Word-array members are single-array structs (v.WordsN): their .v
    // element offsets match the C uint16[N] layout.
    try expectEqual(0, @offsetOf(v.RoomBoundsFields, "a0"));
    try expectEqual(2, @offsetOf(v.RoomBoundsFields, "b0"));
    try expectEqual(4, @offsetOf(v.RoomBoundsFields, "a1"));
    try expectEqual(6, @offsetOf(v.RoomBoundsFields, "b1"));
    try expectEqual(6, @offsetOf(v.OwScrollVars, "xend"));
    try expectEqual(6, @offsetOf(v.MirrorHdmaVars, "var3"));
    try expectEqual(26, @offsetOf(v.MirrorHdmaVars, "ctr2"));
    try expectEqual(27, @offsetOf(v.MirrorHdmaVars, "ctr"));
    try expectEqual(256, @offsetOf(v.UploadVram_3, "data"));
}

test "scalar deref accessors land on the exact offsets" {
    // 24 random draws (fixed seed in the pick, not runtime) across the file:
    // mixed uint8/uint16, odd/even, low/high addresses.
    try expectAddr(0x10, v.main_module_index());
    try expectAddr(0x20, v.link_y_coord());
    try expectAddr(0x22, v.link_x_coord());
    try expectAddr(0x3A, v.button_mask_b_y());
    try expectAddr(0x8A, v.overworld_screen_index());
    try expectAddr(0x12C, v.music_control());
    try expectAddr(0x200, v.overworld_map_state());
    try expectAddr(0x2F1, v.link_dash_ctr());
    try expectAddr(0x399, v.boomerang_temp_y());
    try expectAddr(0x424, v.turn_on_off_water_ctr());
    try expectAddr(0x6000, v.word_7E6000());
    try expectAddr(0xC108, v.link_y_coord_spexit());
    try expectAddr(0xC1A6, v.link_direction_facing_cached());
    try expectAddr(0xF340, v.link_item_bow());
    try expectAddr(0xF36D, v.link_health_current());
    try expectAddr(0xF403, v.death_save_counter());
    try expectAddr(0x10010, v.skullwoodsfire_var4());
    try expectAddr(0x111FA, v.byte_7F11FA());
    try expectAddr(0x14440, v.map16_decode_last());
    try expectAddr(0x158B8, v.weathervane_var1());
    try expectAddr(0x1F9FE, v.garnish_oam_flags());
    try expectAddr(0x1FA5C, v.swamola_x_lo());
    try expectAddr(0x1FD02, v.word_7FFD02());
    try expectAddr(0x1FE5, v.poly_x0_frac());
}

test "pointer accessors land on the exact offsets" {
    try expectAddr(0x51, v.tiledetect_which_y_pos());
    try expectAddr(0x280, v.ancilla_objprio());
    try expectAddr(0x6A0, v.star_shaped_switches_tile());
    try expectAddr(0x800, v.oam_buf());
    try expectAddr(0x2000, v.overworld_tileattr());
    try expectAddr(0x1DBA0, v.hdma_table_dynamic());
    try expectAddr(0x1FA5C, v.alt_sprite_B());
    try expectAddr(0xC300, v.aux_palette_buffer());
    try expectAddr(0x10000, v.messaging_buf());
    try expectAddr(0x15800, v.quake_arr1());
    try expectAddr(0x1DB20, v.msu_resume_info_alt());
    try expectAddr(0xf940, v.movable_block_datas());
}

test "reads/writes round-trip through raw g_ram bytes" {
    @memset(&g_ram, 0);
    v.link_y_coord().* = 0x1234;
    try expectEqual(@as(t.uint8, 0x34), g_ram[0x20]);
    try expectEqual(@as(t.uint8, 0x12), g_ram[0x21]);

    // Odd-offset uint16 write must not assume alignment (g_ram+0xBD).
    v.hud_tmp1().* = 0xBEEF;
    try expectEqual(@as(t.uint8, 0xEF), g_ram[0xBD]);
    try expectEqual(@as(t.uint8, 0xBE), g_ram[0xBE]);
    try expectEqual(@as(t.uint16, 0xBEEF), v.hud_tmp1().*);

    v.link_item_bow().* = 3;
    try expectEqual(@as(t.uint8, 3), g_ram[0xF340]);

    // Many-item pointer indexing matches C's oam_buf[i] / ancilla_K[i].
    v.oam_buf()[7].x = 9;
    try expectEqual(@as(t.uint8, 9), g_ram[0x800 + 7 * 4]);
    v.ancilla_K()[2] = 0xA5;
    try expectEqual(@as(t.uint8, 0xA5), g_ram[0x380 + 2]);
    v.movable_block_datas()[99].tilemap = 0x1234;
    try expectEqual(@as(t.uint8, 0x34), g_ram[0xf940 + 99 * 4 + 2]);
}

test "struct overlays alias the scalar/pointer views of the same bytes" {
    @memset(&g_ram, 0);

    // room_bounds_y / ow_scroll_vars0 share 0x600..0x607.
    v.room_bounds_y().f.a0 = 0x1111;
    try expectEqual(@as(t.uint16, 0x1111), v.ow_scroll_vars0().ystart);
    v.ow_scroll_vars0().xend = 0x2222;
    try expectEqual(@as(t.uint16, 0x2222), v.room_bounds_y().f.b1);
    try expectEqual(@as(t.uint16, 0x2222), v.room_bounds_y().v.v[3]);
    try expectAddr(0x600, v.room_bounds_y());
    try expectAddr(0x608, v.room_bounds_x());
    try expectAddr(0x600, v.ow_scroll_vars0());
    try expectAddr(0x608, v.ow_scroll_vars1());
    try expectAddr(0xC154, v.ow_scroll_vars0_exit());

    // mirror_vars / star_shaped_switches_tile share 0x6A0.
    v.mirror_vars().ctr2 = 32;
    try expectEqual(@as(t.uint8, 32), g_ram[0x6A0 + 26]);
    v.star_shaped_switches_tile()[3] = 0x4321;
    try expectEqual(@as(t.uint16, 0x4321), v.mirror_vars().var3.v[0]);
    v.mirror_vars().var1.v[0] = 0x1234;
    try expectEqual(@as(t.uint16, 0x1234), v.star_shaped_switches_tile()[1]);
    try expectAddr(0x6A0, v.mirror_vars());

    // uvram / uvram_screen / vram_upload_* share 0x1000.
    v.uvram().data.v[0] = 0x7777;
    try expectEqual(@as(t.uint8, 0x77), g_ram[0x1000 + 256]);
    v.uvram_screen().row[0].col.v[0] = 0x5555;
    try expectEqual(@as(t.uint16, 0x5555), v.vram_upload_offset().*);
    v.vram_upload_data()[1] = 0x1234;
    try expectEqual(@as(t.uint16, 0x1234), v.uvram_screen().row[0].col.v[2]);
    try expectAddr(0x1000, v.uvram());
    try expectAddr(0x1000, v.uvram_screen());
    try expectAddr(0x1000, v.vram_upload_offset());
    try expectAddr(0x1002, v.vram_upload_data());
    try expectAddr(0x1100, v.vram_upload_tile_buf());
}

test "scratch-region redefinitions keep the first definition, like C" {
    // attract_* names alias the module scratch at 0x20.. (same bytes as the
    // link_* view); the first variables.h definition wins in both ports.
    try expectAddr(0x20, v.attract_var12());
    try expectAddr(0x22, v.attract_state());
    try expectAddr(0x630, v.selectfile_var8());
    try expectAddr(0x10000, v.blastwall_var5());
    try expectAddr(0x10000, v.skullwoodsfire_var0());
    try expectAddr(0x15800, v.happiness_pond_y_vel());
    try expectAddr(0x15800, v.breaktowerseal_var3());
    try expectAddr(0x15800, v.weathervane_arr3());
    v.attract_var12().* = 0xABCD;
    try expectEqual(@as(t.uint16, 0xABCD), v.link_y_coord().*);
}

test "decimal-offset aliases R10/R12/R14" {
    try expectAddr(10, v.R10());
    try expectAddr(12, v.R12());
    try expectAddr(14, v.R14());
    // R16/R18/R20 are the same scratch bytes as 0xc8/0xca/0xcc.
    try expectAddr(0xc8, v.R16());
    try expectAddr(0xca, v.R18());
    try expectAddr(0xcc, v.R20());
}

test "srm_var1 reaches into g_zenv.sram+0x1ffe" {
    g_zenv.sram = &sram_storage;
    v.srm_var1().* = 0x2468;
    try expectEqual(@as(t.uint8, 0x68), sram_storage[0x1ffe]);
    try expectEqual(@as(t.uint8, 0x24), sram_storage[0x1fff]);
}
