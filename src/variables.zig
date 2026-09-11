// Port of src/variables.h: the g_ram accessor bank. Every C macro of the
// form `(*(type*)(g_ram+off))` / `((type*)(g_ram+off))` becomes an inline
// fn returning a *align(1) (or many-item) pointer into the extern g_ram
// symbol, defined in zelda_rtl.zig (moved from C in TASK-004.07; the C
// side declares it via `extern uint8 g_ram[131072]` in variables.h).
// Dereference the result to read, assign through it to write:
//   v.link_y_coord().*     <-> link_y_coord
//   v.oam_buf()[i]         <-> oam_buf[i]
//   v.room_bounds_y().a0   <-> room_bounds_y.a0
//
// Every offset is preserved exactly as in variables.h, including the
// deliberate overlays (aliased views of the same bytes, used by disjoint
// modules and never simultaneously):
//   room_bounds_y / ow_scroll_vars0        at 0x600
//   room_bounds_x / ow_scroll_vars1        at 0x608
//   mirror_vars / star_shaped_switches_tile at 0x6A0
//   uvram_screen / vram_upload_offset/data/tile_buf at 0x1000
//   attract_var12 / link_y_coord           at 0x20 (attract scratch aliases)
// plus the whole blastwall_/skullwoodsfire_/quake_/bombos_/weathervane_/
// breaktowerseal_/happiness_pond_ families sharing 0x10000 and 0x15800.
// DO NOT "deduplicate" these: moving any address breaks the RAM-compare
// oracle against the original 65816 code and savestate compatibility.
//
// Regenerate after editing variables.h with: uv run other/gen_variables_zig.py

const t = @import("types.zig");

/// Mirror of the `g_ram` symbol, defined in zelda_rtl.zig (the C side
/// declares `extern uint8 g_ram[131072]` in variables.h).
pub extern var g_ram: [0x20000]u8;

// C ABI twin of ZeldaEnv's sram member (src/zelda_rtl.h); only the one
// field variables.h's srm_var1 accessor reaches through.
pub const ZeldaEnv = extern struct {
    ram: ?[*]t.uint8,
    sram: ?[*]t.uint8,
    vram: ?[*]t.uint16,
    ppu: ?*anyopaque,
    player: ?*anyopaque,
    dma: ?*anyopaque,
    dialogue_blk: t.MemBlk,
    dialogue_font_blk: t.MemBlk,
    dialogue_flags: t.uint8,
};
pub extern var g_zenv: ZeldaEnv;

// Struct-overlay twins of the C typedefs in variables.h. Plain extern
// structs with align(1) fields: g_ram offsets are frequently odd and the
// C overlays are cast onto raw WRAM, so no natural alignment can be assumed.
// Word arrays ride in single-array structs (Words2/Words4/...) so the field
// can be align(1)'d without tripping Zig's element-alignment rules — size
// and layout are byte-identical to the C uint16[N] members.

pub const Words2 = extern struct { v: [2]t.uint16 };
pub const Words4 = extern struct { v: [4]t.uint16 };
pub const Words32 = extern struct { v: [32]t.uint16 };

pub const MovableBlockData = extern struct {
    room: t.uint16 align(1),
    tilemap: t.uint16 align(1),
};

pub const OamEntSigned = extern struct {
    x: t.int8,
    y: t.int8,
    charnum: t.uint8,
    flags: t.uint8,
};

pub const RoomBoundsFields = extern struct {
    a0: t.uint16 align(1),
    b0: t.uint16 align(1),
    a1: t.uint16 align(1),
    b1: t.uint16 align(1),
};

pub const RoomBounds = extern union {
    f: RoomBoundsFields,
    v: Words4 align(1),
};

pub const OwScrollVars = extern struct {
    ystart: t.uint16 align(1),
    yend: t.uint16 align(1),
    xstart: t.uint16 align(1),
    xend: t.uint16 align(1),
};

pub const MirrorHdmaVars = extern struct {
    var0: t.uint16 align(1),
    var1: Words2 align(1),
    var3: Words2 align(1),
    var5: t.uint16 align(1),
    var6: t.uint16 align(1),
    var7: t.uint16 align(1),
    var8: t.uint16 align(1),
    var9: t.uint16 align(1),
    var10: t.uint16 align(1),
    var11: t.uint16 align(1),
    pad: t.uint16 align(1),
    ctr2: t.uint8,
    ctr: t.uint8,
};

pub const UploadVram_Row = extern struct {
    col: Words32 align(1),
};

pub const UploadVram_32x32 = extern struct {
    row: [32]UploadVram_Row,
};

pub const UploadVram_3 = extern struct {
    pad: [256]t.uint8,
    data: Words4 align(1),
};

/// R10: *(uint16*)(g_ram+10)
pub inline fn R10() *align(1) t.uint16 {
    return @ptrCast(&g_ram[10]);
}

/// R12: *(uint16*)(g_ram+12)
pub inline fn R12() *align(1) t.uint16 {
    return @ptrCast(&g_ram[12]);
}

/// R14: *(uint16*)(g_ram+14)
pub inline fn R14() *align(1) t.uint16 {
    return @ptrCast(&g_ram[14]);
}

/// srm_var1: *(uint16*)(g_zenv.sram+0x1ffe)
pub inline fn srm_var1() *align(1) t.uint16 {
    return @ptrCast(g_zenv.sram.? + 0x1ffe);
}

/// uvram_screen: *(UploadVram_32x32*)&g_ram[0x1000]
pub inline fn uvram_screen() *align(1) UploadVram_32x32 {
    return @ptrCast(&g_ram[0x1000]);
}

/// uvram: *(UploadVram_3*)(&g_ram[0x1000])
pub inline fn uvram() *align(1) UploadVram_3 {
    return @ptrCast(&g_ram[0x1000]);
}

/// movable_block_datas: (MovableBlockData*)(g_ram+0xf940)
pub inline fn movable_block_datas() [*]align(1) MovableBlockData {
    return @ptrCast(&g_ram[0xf940]);
}

/// oam_buf: (OamEnt*)(g_ram+0x800)
pub inline fn oam_buf() [*]align(1) t.OamEnt {
    return @ptrCast(&g_ram[0x800]);
}

/// room_bounds_y: *(RoomBounds*)(g_ram+0x600) — intentional alias of ow_scroll_vars0
pub inline fn room_bounds_y() *align(1) RoomBounds {
    return @ptrCast(&g_ram[0x600]);
}

/// room_bounds_x: *(RoomBounds*)(g_ram+0x608) — intentional alias of ow_scroll_vars1
pub inline fn room_bounds_x() *align(1) RoomBounds {
    return @ptrCast(&g_ram[0x608]);
}

/// ow_scroll_vars0: *(OwScrollVars*)(g_ram+0x600) — intentional alias of room_bounds_y
pub inline fn ow_scroll_vars0() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0x600]);
}

/// ow_scroll_vars1: *(OwScrollVars*)(g_ram+0x608) — intentional alias of room_bounds_x
pub inline fn ow_scroll_vars1() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0x608]);
}

/// ow_scroll_vars0_exit: *(OwScrollVars*)(g_ram+0xC154)
pub inline fn ow_scroll_vars0_exit() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0xC154]);
}

/// mirror_vars: *(MirrorHdmaVars*)(g_ram+0x6A0) — intentional alias of star_shaped_switches_tile
pub inline fn mirror_vars() *align(1) MirrorHdmaVars {
    return @ptrCast(&g_ram[0x6A0]);
}

/// variables.h:3 — main_module_index: (*(uint8*)(g_ram+0x10))
pub inline fn main_module_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10]);
}
/// variables.h:4 — submodule_index: (*(uint8*)(g_ram+0x11))
pub inline fn submodule_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x11]);
}
/// variables.h:5 — nmi_boolean: (*(uint8*)(g_ram+0x12))
pub inline fn nmi_boolean() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12]);
}
/// variables.h:6 — INIDISP_copy: (*(uint8*)(g_ram+0x13))
pub inline fn INIDISP_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x13]);
}
/// variables.h:7 — nmi_load_bg_from_vram: (*(uint8*)(g_ram+0x14))
pub inline fn nmi_load_bg_from_vram() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x14]);
}
/// variables.h:8 — flag_update_cgram_in_nmi: (*(uint8*)(g_ram+0x15))
pub inline fn flag_update_cgram_in_nmi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15]);
}
/// variables.h:9 — flag_update_hud_in_nmi: (*(uint8*)(g_ram+0x16))
pub inline fn flag_update_hud_in_nmi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x16]);
}
/// variables.h:10 — nmi_subroutine_index: (*(uint8*)(g_ram+0x17))
pub inline fn nmi_subroutine_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x17]);
}
/// variables.h:11 — nmi_copy_packets_flag: (*(uint8*)(g_ram+0x18))
pub inline fn nmi_copy_packets_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x18]);
}
/// variables.h:12 — nmi_update_tilemap_dst: (*(uint8*)(g_ram+0x19))
pub inline fn nmi_update_tilemap_dst() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x19]);
}
/// variables.h:13 — frame_counter: (*(uint8*)(g_ram+0x1A))
pub inline fn frame_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A]);
}
/// variables.h:14 — player_is_indoors: (*(uint8*)(g_ram+0x1B))
pub inline fn player_is_indoors() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1B]);
}
/// variables.h:15 — TM_copy: (*(uint8*)(g_ram+0x1C))
pub inline fn TM_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1C]);
}
/// variables.h:16 — TS_copy: (*(uint8*)(g_ram+0x1D))
pub inline fn TS_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D]);
}
/// variables.h:17 — TMW_copy: (*(uint8*)(g_ram+0x1E))
pub inline fn TMW_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E]);
}
/// variables.h:18 — TSW_copy: (*(uint8*)(g_ram+0x1F))
pub inline fn TSW_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F]);
}
/// variables.h:19 — link_y_coord: (*(uint16*)(g_ram+0x20))
pub inline fn link_y_coord() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x20]);
}
/// variables.h:20 — link_x_coord: (*(uint16*)(g_ram+0x22))
pub inline fn link_x_coord() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x22]);
}
/// variables.h:21 — link_z_coord: (*(uint16*)(g_ram+0x24))
pub inline fn link_z_coord() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x24]);
}
/// variables.h:22 — link_direction_last: (*(uint8*)(g_ram+0x26))
pub inline fn link_direction_last() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x26]);
}
/// variables.h:23 — link_actual_vel_y: (*(uint8*)(g_ram+0x27))
pub inline fn link_actual_vel_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x27]);
}
/// variables.h:24 — link_actual_vel_x: (*(uint8*)(g_ram+0x28))
pub inline fn link_actual_vel_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x28]);
}
/// variables.h:25 — link_actual_vel_z: (*(uint8*)(g_ram+0x29))
pub inline fn link_actual_vel_z() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x29]);
}
/// variables.h:26 — link_subpixel_y: (*(uint8*)(g_ram+0x2A))
pub inline fn link_subpixel_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2A]);
}
/// variables.h:27 — link_subpixel_x: (*(uint8*)(g_ram+0x2B))
pub inline fn link_subpixel_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2B]);
}
/// variables.h:28 — link_subpixel_z: (*(uint8*)(g_ram+0x2C))
pub inline fn link_subpixel_z() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C]);
}
/// variables.h:29 — link_counter_var1: (*(uint8*)(g_ram+0x2D))
pub inline fn link_counter_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D]);
}
/// variables.h:30 — link_animation_steps: (*(uint8*)(g_ram+0x2E))
pub inline fn link_animation_steps() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E]);
}
/// variables.h:31 — link_direction_facing: (*(uint8*)(g_ram+0x2F))
pub inline fn link_direction_facing() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F]);
}
/// variables.h:32 — link_y_vel: (*(uint8*)(g_ram+0x30))
pub inline fn link_y_vel() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x30]);
}
/// variables.h:33 — link_x_vel: (*(uint8*)(g_ram+0x31))
pub inline fn link_x_vel() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x31]);
}
/// variables.h:34 — link_y_coord_original: (*(uint16*)(g_ram+0x32))
pub inline fn link_y_coord_original() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x32]);
}
/// variables.h:35 — byte_7E0034: (*(uint8*)(g_ram+0x34))
pub inline fn byte_7E0034() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34]);
}
/// variables.h:36 — byte_7E0035: (*(uint8*)(g_ram+0x35))
pub inline fn byte_7E0035() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x35]);
}
/// variables.h:37 — tiledetect_diagonal_tile: (*(uint16*)(g_ram+0x38))
pub inline fn tiledetect_diagonal_tile() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x38]);
}
/// variables.h:38 — button_mask_b_y: (*(uint8*)(g_ram+0x3A))
pub inline fn button_mask_b_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3A]);
}
/// variables.h:39 — bitfield_for_a_button: (*(uint8*)(g_ram+0x3B))
pub inline fn bitfield_for_a_button() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3B]);
}
/// variables.h:40 — button_b_frames: (*(uint8*)(g_ram+0x3C))
pub inline fn button_b_frames() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3C]);
}
/// variables.h:41 — link_delay_timer_spin_attack: (*(uint8*)(g_ram+0x3D))
pub inline fn link_delay_timer_spin_attack() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3D]);
}
/// variables.h:42 — link_y_coord_safe_return_lo: (*(uint8*)(g_ram+0x3E))
pub inline fn link_y_coord_safe_return_lo() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3E]);
}
/// variables.h:43 — link_x_coord_safe_return_lo: (*(uint8*)(g_ram+0x3F))
pub inline fn link_x_coord_safe_return_lo() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F]);
}
/// variables.h:44 — link_y_coord_safe_return_hi: (*(uint8*)(g_ram+0x40))
pub inline fn link_y_coord_safe_return_hi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x40]);
}
/// variables.h:45 — link_x_coord_safe_return_hi: (*(uint8*)(g_ram+0x41))
pub inline fn link_x_coord_safe_return_hi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x41]);
}
/// variables.h:46 — link_direction_mask_a: (*(uint8*)(g_ram+0x42))
pub inline fn link_direction_mask_a() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x42]);
}
/// variables.h:47 — link_direction_mask_b: (*(uint8*)(g_ram+0x43))
pub inline fn link_direction_mask_b() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x43]);
}
/// variables.h:48 — player_oam_y_offset: (*(uint8*)(g_ram+0x44))
pub inline fn player_oam_y_offset() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x44]);
}
/// variables.h:49 — player_oam_x_offset: (*(uint8*)(g_ram+0x45))
pub inline fn player_oam_x_offset() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x45]);
}
/// variables.h:50 — link_incapacitated_timer: (*(uint8*)(g_ram+0x46))
pub inline fn link_incapacitated_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x46]);
}
/// variables.h:51 — set_when_damaging_enemies: (*(uint8*)(g_ram+0x47))
pub inline fn set_when_damaging_enemies() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x47]);
}
/// variables.h:52 — bitmask_of_dragstate: (*(uint8*)(g_ram+0x48))
pub inline fn bitmask_of_dragstate() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x48]);
}
/// variables.h:53 — force_move_any_direction: (*(uint16*)(g_ram+0x49))
pub inline fn force_move_any_direction() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x49]);
}
/// variables.h:54 — link_visibility_status: (*(uint8*)(g_ram+0x4B))
pub inline fn link_visibility_status() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4B]);
}
/// variables.h:55 — cape_decrement_counter: (*(uint8*)(g_ram+0x4C))
pub inline fn cape_decrement_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C]);
}
/// variables.h:56 — link_auxiliary_state: (*(uint8*)(g_ram+0x4D))
pub inline fn link_auxiliary_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4D]);
}
/// variables.h:57 — byte_7E004E: (*(uint8*)(g_ram+0x4E))
pub inline fn byte_7E004E() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4E]);
}
/// variables.h:58 — index_of_dashing_sfx: (*(uint8*)(g_ram+0x4F))
pub inline fn index_of_dashing_sfx() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4F]);
}
/// variables.h:59 — link_cant_change_direction: (*(uint8*)(g_ram+0x50))
pub inline fn link_cant_change_direction() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x50]);
}
/// variables.h:60 — tiledetect_which_y_pos: ((uint16*)(g_ram+0x51))
pub inline fn tiledetect_which_y_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x51]);
}
/// variables.h:61 — link_cape_mode: (*(uint8*)(g_ram+0x55))
pub inline fn link_cape_mode() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x55]);
}
/// variables.h:62 — link_is_bunny: (*(uint8*)(g_ram+0x56))
pub inline fn link_is_bunny() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x56]);
}
/// variables.h:63 — link_speed_modifier: (*(uint8*)(g_ram+0x57))
pub inline fn link_speed_modifier() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x57]);
}
/// variables.h:64 — tiledetect_stair_tile: (*(uint8*)(g_ram+0x58))
pub inline fn tiledetect_stair_tile() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x58]);
}
/// variables.h:65 — tiledetect_pit_tile: (*(uint8*)(g_ram+0x59))
pub inline fn tiledetect_pit_tile() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x59]);
}
/// variables.h:66 — link_this_controls_sprite_oam: (*(uint8*)(g_ram+0x5A))
pub inline fn link_this_controls_sprite_oam() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5A]);
}
/// variables.h:67 — player_near_pit_state: (*(uint8*)(g_ram+0x5B))
pub inline fn player_near_pit_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5B]);
}
/// variables.h:68 — byte_7E005C: (*(uint8*)(g_ram+0x5C))
pub inline fn byte_7E005C() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5C]);
}
/// variables.h:69 — link_player_handler_state: (*(uint8*)(g_ram+0x5D))
pub inline fn link_player_handler_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5D]);
}
/// variables.h:70 — link_speed_setting: (*(uint8*)(g_ram+0x5E))
pub inline fn link_speed_setting() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5E]);
}
/// variables.h:71 — tiledetect_var2: (*(uint16*)(g_ram+0x5F))
pub inline fn tiledetect_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5F]);
}
/// variables.h:72 — gravestone_push_timeout: (*(uint8*)(g_ram+0x61))
pub inline fn gravestone_push_timeout() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x61]);
}
/// variables.h:73 — tiledetect_var1: (*(uint16*)(g_ram+0x62))
pub inline fn tiledetect_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x62]);
}
/// variables.h:74 — oam_priority_value: (*(uint16*)(g_ram+0x64))
pub inline fn oam_priority_value() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x64]);
}
/// variables.h:75 — link_last_direction_moved_towards: (*(uint8*)(g_ram+0x66))
pub inline fn link_last_direction_moved_towards() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x66]);
}
/// variables.h:76 — link_direction: (*(uint8*)(g_ram+0x67))
pub inline fn link_direction() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x67]);
}
/// variables.h:77 — link_y_page_movement_delta: (*(uint8*)(g_ram+0x68))
pub inline fn link_y_page_movement_delta() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x68]);
}
/// variables.h:78 — link_x_page_movement_delta: (*(uint8*)(g_ram+0x69))
pub inline fn link_x_page_movement_delta() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x69]);
}
/// variables.h:79 — link_num_orthogonal_directions: (*(uint8*)(g_ram+0x6A))
pub inline fn link_num_orthogonal_directions() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x6A]);
}
/// variables.h:80 — link_moving_against_diag_tile: (*(uint8*)(g_ram+0x6B))
pub inline fn link_moving_against_diag_tile() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x6B]);
}
/// variables.h:81 — is_standing_in_doorway: (*(uint8*)(g_ram+0x6C))
pub inline fn is_standing_in_doorway() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x6C]);
}
/// variables.h:82 — moving_against_diag_deadlocked: (*(uint8*)(g_ram+0x6D))
pub inline fn moving_against_diag_deadlocked() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x6D]);
}
/// variables.h:83 — tiledetect_diag_state: (*(uint16*)(g_ram+0x6E))
pub inline fn tiledetect_diag_state() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6E]);
}
/// variables.h:84 — byte_7E0071: (*(uint8*)(g_ram+0x71))
pub inline fn byte_7E0071() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x71]);
}
/// variables.h:85 — scratch_b: (*(uint8*)(g_ram+0x72))
pub inline fn scratch_b() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x72]);
}
/// variables.h:86 — scratch_a: (*(uint8*)(g_ram+0x73))
pub inline fn scratch_a() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x73]);
}
/// variables.h:87 — scratch_c: (*(uint8*)(g_ram+0x74))
pub inline fn scratch_c() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x74]);
}
/// variables.h:88 — scratch_d: (*(uint8*)(g_ram+0x75))
pub inline fn scratch_d() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x75]);
}
/// variables.h:89 — index_of_interacting_tile: (*(uint16*)(g_ram+0x76))
pub inline fn index_of_interacting_tile() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x76]);
}
/// variables.h:90 — allow_scroll_z: (*(uint8*)(g_ram+0x78))
pub inline fn allow_scroll_z() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x78]);
}
/// variables.h:91 — link_spin_attack_step_counter: (*(uint8*)(g_ram+0x79))
pub inline fn link_spin_attack_step_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x79]);
}
/// variables.h:92 — last_light_vs_dark_world: (*(uint8*)(g_ram+0x7B))
pub inline fn last_light_vs_dark_world() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x7B]);
}
/// variables.h:93 — word_7E007E: (*(uint16*)(g_ram+0x7E))
pub inline fn word_7E007E() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x7E]);
}
/// variables.h:94 — map16_load_src_off: (*(uint16*)(g_ram+0x84))
pub inline fn map16_load_src_off() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x84]);
}
/// variables.h:95 — map16_load_dst_off: (*(uint16*)(g_ram+0x86))
pub inline fn map16_load_dst_off() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x86]);
}
/// variables.h:96 — map16_load_var2: (*(uint16*)(g_ram+0x88))
pub inline fn map16_load_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x88]);
}
/// variables.h:97 — overworld_screen_index: (*(uint16*)(g_ram+0x8A))
pub inline fn overworld_screen_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x8A]);
}
/// variables.h:98 — overlay_index: (*(uint16*)(g_ram+0x8C))
pub inline fn overlay_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x8C]);
}
/// variables.h:99 — oam_cur_ptr: (*(uint16*)(g_ram+0x90))
pub inline fn oam_cur_ptr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x90]);
}
/// variables.h:100 — oam_ext_cur_ptr: (*(uint16*)(g_ram+0x92))
pub inline fn oam_ext_cur_ptr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x92]);
}
/// variables.h:101 — BGMODE_copy: (*(uint8*)(g_ram+0x94))
pub inline fn BGMODE_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x94]);
}
/// variables.h:102 — MOSAIC_copy: (*(uint8*)(g_ram+0x95))
pub inline fn MOSAIC_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x95]);
}
/// variables.h:103 — W12SEL_copy: (*(uint8*)(g_ram+0x96))
pub inline fn W12SEL_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x96]);
}
/// variables.h:104 — W34SEL_copy: (*(uint8*)(g_ram+0x97))
pub inline fn W34SEL_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x97]);
}
/// variables.h:105 — WOBJSEL_copy: (*(uint8*)(g_ram+0x98))
pub inline fn WOBJSEL_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x98]);
}
/// variables.h:106 — CGWSEL_copy: (*(uint8*)(g_ram+0x99))
pub inline fn CGWSEL_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x99]);
}
/// variables.h:107 — CGADSUB_copy: (*(uint8*)(g_ram+0x9A))
pub inline fn CGADSUB_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x9A]);
}
/// variables.h:108 — HDMAEN_copy: (*(uint8*)(g_ram+0x9B))
pub inline fn HDMAEN_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x9B]);
}
/// variables.h:109 — COLDATA_copy0: (*(uint8*)(g_ram+0x9C))
pub inline fn COLDATA_copy0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x9C]);
}
/// variables.h:110 — COLDATA_copy1: (*(uint8*)(g_ram+0x9D))
pub inline fn COLDATA_copy1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x9D]);
}
/// variables.h:111 — COLDATA_copy2: (*(uint8*)(g_ram+0x9E))
pub inline fn COLDATA_copy2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x9E]);
}
/// variables.h:112 — dungeon_room_index: (*(uint16*)(g_ram+0xA0))
pub inline fn dungeon_room_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xA0]);
}
/// variables.h:113 — dungeon_room_index_prev: (*(uint16*)(g_ram+0xA2))
pub inline fn dungeon_room_index_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xA2]);
}
/// variables.h:114 — dung_cur_floor: (*(uint8*)(g_ram+0xA4))
pub inline fn dung_cur_floor() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA4]);
}
/// variables.h:115 — quadrant_fullsize_x: (*(uint8*)(g_ram+0xA6))
pub inline fn quadrant_fullsize_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA6]);
}
/// variables.h:116 — quadrant_fullsize_y: (*(uint8*)(g_ram+0xA7))
pub inline fn quadrant_fullsize_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA7]);
}
/// variables.h:117 — composite_of_layout_and_quadrant: (*(uint8*)(g_ram+0xA8))
pub inline fn composite_of_layout_and_quadrant() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA8]);
}
/// variables.h:118 — link_quadrant_x: (*(uint8*)(g_ram+0xA9))
pub inline fn link_quadrant_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA9]);
}
/// variables.h:119 — link_quadrant_y: (*(uint8*)(g_ram+0xAA))
pub inline fn link_quadrant_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA]);
}
/// variables.h:120 — dung_hdr_collision_2: (*(uint8*)(g_ram+0xAD))
pub inline fn dung_hdr_collision_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAD]);
}
/// variables.h:121 — dung_hdr_tag: ((uint8*)(g_ram+0xAE))
pub inline fn dung_hdr_tag() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAE]);
}
/// variables.h:122 — subsubmodule_index: (*(uint8*)(g_ram+0xB0))
pub inline fn subsubmodule_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB0]);
}
/// variables.h:123 — subsubmodule_index_PADDING: (*(uint8*)(g_ram+0xB1))
pub inline fn subsubmodule_index_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB1]);
}
/// variables.h:124 — dung_draw_width_indicator: (*(uint16*)(g_ram+0xB2))
pub inline fn dung_draw_width_indicator() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB2]);
}
/// variables.h:125 — dung_draw_height_indicator: (*(uint16*)(g_ram+0xB4))
pub inline fn dung_draw_height_indicator() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB4]);
}
/// variables.h:126 — dung_load_ptr: (*(uint16*)(g_ram+0xB7))
pub inline fn dung_load_ptr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB7]);
}
/// variables.h:127 — dung_load_ptr_bank: (*(uint8*)(g_ram+0xB9))
pub inline fn dung_load_ptr_bank() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB9]);
}
/// variables.h:128 — dung_load_ptr_offs: (*(uint16*)(g_ram+0xBA))
pub inline fn dung_load_ptr_offs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xBA]);
}
/// variables.h:129 — hud_tmp1: (*(uint16*)(g_ram+0xBD))
pub inline fn hud_tmp1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xBD]);
}
/// variables.h:131 — some_menu_ctr: (*(uint8*)(g_ram+0xc8))
pub inline fn some_menu_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xc8]);
}
/// variables.h:132 — dung_line_ptrs_row3: (*(uint16*)(g_ram+0xDA))
pub inline fn dung_line_ptrs_row3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xDA]);
}
/// variables.h:133 — dung_line_ptrs_row4: (*(uint16*)(g_ram+0xDD))
pub inline fn dung_line_ptrs_row4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xDD]);
}
/// variables.h:134 — BG1HOFS_copy2: (*(uint16*)(g_ram+0xE0))
pub inline fn BG1HOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE0]);
}
/// variables.h:135 — BG2HOFS_copy2: (*(uint16*)(g_ram+0xE2))
pub inline fn BG2HOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE2]);
}
/// variables.h:136 — BG3HOFS_copy2: (*(uint16*)(g_ram+0xE4))
pub inline fn BG3HOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE4]);
}
/// variables.h:137 — BG1VOFS_copy2: (*(uint16*)(g_ram+0xE6))
pub inline fn BG1VOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE6]);
}
/// variables.h:138 — BG2VOFS_copy2: (*(uint16*)(g_ram+0xE8))
pub inline fn BG2VOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE8]);
}
/// variables.h:139 — BG3VOFS_copy2: (*(uint16*)(g_ram+0xEA))
pub inline fn BG3VOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xEA]);
}
/// variables.h:140 — tilemap_location_calc_mask: (*(uint16*)(g_ram+0xEC))
pub inline fn tilemap_location_calc_mask() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xEC]);
}
/// variables.h:141 — link_is_on_lower_level: (*(uint8*)(g_ram+0xEE))
pub inline fn link_is_on_lower_level() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEE]);
}
/// variables.h:142 — room_transitioning_flags: (*(uint8*)(g_ram+0xEF))
pub inline fn room_transitioning_flags() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEF]);
}
/// variables.h:143 — joypad1H_last: (*(uint8*)(g_ram+0xF0))
pub inline fn joypad1H_last() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF0]);
}
/// variables.h:144 — joypad1L_last: (*(uint8*)(g_ram+0xF2))
pub inline fn joypad1L_last() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF2]);
}
/// variables.h:145 — filtered_joypad_H: (*(uint8*)(g_ram+0xF4))
pub inline fn filtered_joypad_H() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF4]);
}
/// variables.h:146 — filtered_joypad_L: (*(uint8*)(g_ram+0xF6))
pub inline fn filtered_joypad_L() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF6]);
}
/// variables.h:147 — joypad1H_last2: (*(uint8*)(g_ram+0xF8))
pub inline fn joypad1H_last2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF8]);
}
/// variables.h:148 — byte_7E00F9: (*(uint8*)(g_ram+0xF9))
pub inline fn byte_7E00F9() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF9]);
}
/// variables.h:149 — joypad1L_last2: (*(uint8*)(g_ram+0xFA))
pub inline fn joypad1L_last2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFA]);
}
/// variables.h:150 — dung_unk2: (*(uint16*)(g_ram+0xFC))
pub inline fn dung_unk2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFC]);
}
/// variables.h:151 — virq_trigger: (*(uint8*)(g_ram+0xFF))
pub inline fn virq_trigger() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFF]);
}
/// variables.h:152 — link_dma_graphics_index: (*(uint16*)(g_ram+0x100))
pub inline fn link_dma_graphics_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x100]);
}
/// variables.h:153 — link_dma_var1: (*(uint16*)(g_ram+0x102))
pub inline fn link_dma_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x102]);
}
/// variables.h:154 — link_dma_var2: (*(uint16*)(g_ram+0x104))
pub inline fn link_dma_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x104]);
}
/// variables.h:155 — link_dma_var3: (*(uint8*)(g_ram+0x107))
pub inline fn link_dma_var3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x107]);
}
/// variables.h:156 — link_dma_var4: (*(uint8*)(g_ram+0x108))
pub inline fn link_dma_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x108]);
}
/// variables.h:157 — link_dma_var5: (*(uint8*)(g_ram+0x109))
pub inline fn link_dma_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x109]);
}
/// variables.h:158 — death_var5: (*(uint8*)(g_ram+0x10A))
pub inline fn death_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10A]);
}
/// variables.h:159 — saved_module_for_menu: (*(uint8*)(g_ram+0x10C))
pub inline fn saved_module_for_menu() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10C]);
}
/// variables.h:160 — which_entrance: (*(uint8*)(g_ram+0x10E))
pub inline fn which_entrance() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10E]);
}
/// variables.h:161 — byte_7E010F: (*(uint8*)(g_ram+0x10F))
pub inline fn byte_7E010F() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10F]);
}
/// variables.h:162 — dung_index_x3: (*(uint16*)(g_ram+0x110))
pub inline fn dung_index_x3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x110]);
}
/// variables.h:163 — flag_custom_spell_anim_active: (*(uint8*)(g_ram+0x112))
pub inline fn flag_custom_spell_anim_active() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x112]);
}
/// variables.h:164 — link_tile_below: (*(uint8*)(g_ram+0x114))
pub inline fn link_tile_below() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x114]);
}
/// variables.h:165 — link_tile_below_PADDING: (*(uint8*)(g_ram+0x115))
pub inline fn link_tile_below_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x115]);
}
/// variables.h:166 — nmi_load_target_addr: (*(uint16*)(g_ram+0x116))
pub inline fn nmi_load_target_addr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x116]);
}
/// variables.h:167 — nmi_update_tilemap_src: (*(uint16*)(g_ram+0x118))
pub inline fn nmi_update_tilemap_src() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x118]);
}
/// variables.h:168 — bg1_x_offset: (*(uint16*)(g_ram+0x11A))
pub inline fn bg1_x_offset() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11A]);
}
/// variables.h:169 — bg1_y_offset: (*(uint16*)(g_ram+0x11C))
pub inline fn bg1_y_offset() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11C]);
}
/// variables.h:170 — BG2HOFS_copy: (*(uint16*)(g_ram+0x11E))
pub inline fn BG2HOFS_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11E]);
}
/// variables.h:171 — BG1HOFS_copy: (*(uint16*)(g_ram+0x120))
pub inline fn BG1HOFS_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x120]);
}
/// variables.h:172 — BG2VOFS_copy: (*(uint16*)(g_ram+0x122))
pub inline fn BG2VOFS_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x122]);
}
/// variables.h:173 — BG1VOFS_copy: (*(uint16*)(g_ram+0x124))
pub inline fn BG1VOFS_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x124]);
}
/// variables.h:174 — transition_counter: (*(uint8*)(g_ram+0x126))
pub inline fn transition_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x126]);
}
/// variables.h:175 — irq_flag: (*(uint8*)(g_ram+0x128))
pub inline fn irq_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x128]);
}
/// variables.h:176 — is_nmi_thread_active: (*(uint8*)(g_ram+0x12A))
pub inline fn is_nmi_thread_active() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12A]);
}
/// variables.h:177 — music_control: (*(uint8*)(g_ram+0x12C))
pub inline fn music_control() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12C]);
}
/// variables.h:178 — sound_effect_ambient: (*(uint8*)(g_ram+0x12D))
pub inline fn sound_effect_ambient() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12D]);
}
/// variables.h:179 — sound_effect_1: (*(uint8*)(g_ram+0x12E))
pub inline fn sound_effect_1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12E]);
}
/// variables.h:180 — sound_effect_2: (*(uint8*)(g_ram+0x12F))
pub inline fn sound_effect_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12F]);
}
/// variables.h:181 — music_unk1: (*(uint8*)(g_ram+0x130))
pub inline fn music_unk1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x130]);
}
/// variables.h:182 — sound_effect_ambient_last: (*(uint8*)(g_ram+0x131))
pub inline fn sound_effect_ambient_last() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x131]);
}
/// variables.h:183 — queued_music_control: (*(uint8*)(g_ram+0x132))
pub inline fn queued_music_control() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x132]);
}
/// variables.h:184 — last_music_control: (*(uint8*)(g_ram+0x133))
pub inline fn last_music_control() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x133]);
}
/// variables.h:185 — animated_tile_vram_addr: (*(uint16*)(g_ram+0x134))
pub inline fn animated_tile_vram_addr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x134]);
}
/// variables.h:186 — flag_which_music_type: (*(uint8*)(g_ram+0x136))
pub inline fn flag_which_music_type() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x136]);
}
/// variables.h:187 — stk_return_addr: (*(uint16*)(g_ram+0x1FE))
pub inline fn stk_return_addr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FE]);
}
/// variables.h:188 — overworld_map_state: (*(uint8*)(g_ram+0x200))
pub inline fn overworld_map_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x200]);
}
/// variables.h:189 — hud_cur_item: (*(uint8*)(g_ram+0x202))
pub inline fn hud_cur_item() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x202]);
}
/// variables.h:191 — hud_var1: (*(uint8*)(g_ram+0x204))
pub inline fn hud_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x204]);
}
/// variables.h:192 — bottle_menu_expand_row: (*(uint8*)(g_ram+0x205))
pub inline fn bottle_menu_expand_row() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x205]);
}
/// variables.h:193 — byte_7E0206: (*(uint8*)(g_ram+0x206))
pub inline fn byte_7E0206() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x206]);
}
/// variables.h:194 — timer_for_flashing_circle: (*(uint8*)(g_ram+0x207))
pub inline fn timer_for_flashing_circle() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x207]);
}
/// variables.h:195 — animate_heart_refill_countdown: (*(uint8*)(g_ram+0x208))
pub inline fn animate_heart_refill_countdown() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x208]);
}
/// variables.h:196 — animate_heart_refill_countdown_subpos: (*(uint8*)(g_ram+0x209))
pub inline fn animate_heart_refill_countdown_subpos() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x209]);
}
/// variables.h:197 — is_doing_heart_animation: (*(uint8*)(g_ram+0x20A))
pub inline fn is_doing_heart_animation() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x20A]);
}
/// variables.h:198 — link_debug_value_1: (*(uint8*)(g_ram+0x20B))
pub inline fn link_debug_value_1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x20B]);
}
/// variables.h:199 — dungmap_init_state: (*(uint8*)(g_ram+0x20D))
pub inline fn dungmap_init_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x20D]);
}
/// variables.h:200 — dungmap_cur_floor: (*(uint16*)(g_ram+0x20E))
pub inline fn dungmap_cur_floor() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x20E]);
}
/// variables.h:201 — dungmap_var2: (*(uint8*)(g_ram+0x210))
pub inline fn dungmap_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x210]);
}
/// variables.h:202 — dungmap_idx: (*(uint16*)(g_ram+0x211))
pub inline fn dungmap_idx() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x211]);
}
/// variables.h:203 — dungmap_var4: (*(uint16*)(g_ram+0x213))
pub inline fn dungmap_var4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x213]);
}
/// variables.h:204 — dungmap_var3: (*(uint16*)(g_ram+0x215))
pub inline fn dungmap_var3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x215]);
}
/// variables.h:205 — dungmap_var5: (*(uint16*)(g_ram+0x217))
pub inline fn dungmap_var5() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x217]);
}
/// variables.h:206 — word_7E0219: (*(uint16*)(g_ram+0x219))
pub inline fn word_7E0219() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x219]);
}
/// variables.h:207 — word_7E021D: (*(uint16*)(g_ram+0x21D))
pub inline fn word_7E021D() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x21D]);
}
/// variables.h:208 — word_7E021F: (*(uint16*)(g_ram+0x21F))
pub inline fn word_7E021F() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x21F]);
}
/// variables.h:209 — word_7E0221: (*(uint16*)(g_ram+0x221))
pub inline fn word_7E0221() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x221]);
}
/// variables.h:210 — byte_7E0223: (*(uint8*)(g_ram+0x223))
pub inline fn byte_7E0223() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x223]);
}
/// variables.h:211 — ancilla_objprio: ((uint8*)(g_ram+0x280))
pub inline fn ancilla_objprio() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x280]);
}
/// variables.h:212 — ancilla_U: ((uint8*)(g_ram+0x28A))
pub inline fn ancilla_U() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x28A]);
}
/// variables.h:213 — ancilla_z_vel: ((uint8*)(g_ram+0x294))
pub inline fn ancilla_z_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x294]);
}
/// variables.h:214 — ancilla_z: ((uint8*)(g_ram+0x29E))
pub inline fn ancilla_z() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x29E]);
}
/// variables.h:215 — ancilla_z_subpixel: ((uint8*)(g_ram+0x2A8))
pub inline fn ancilla_z_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2A8]);
}
/// variables.h:216 — tiledetect_inroom_staircase: (*(uint16*)(g_ram+0x2C0))
pub inline fn tiledetect_inroom_staircase() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2C0]);
}
/// variables.h:217 — byte_7E02C2: (*(uint8*)(g_ram+0x2C2))
pub inline fn byte_7E02C2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C2]);
}
/// variables.h:218 — pushedblocks_some_index: (*(uint8*)(g_ram+0x2C3))
pub inline fn pushedblocks_some_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C3]);
}
/// variables.h:219 — pushedblocks_maybe_timeout: (*(uint8*)(g_ram+0x2C4))
pub inline fn pushedblocks_maybe_timeout() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C4]);
}
/// variables.h:220 — byte_7E02C5: (*(uint8*)(g_ram+0x2C5))
pub inline fn byte_7E02C5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C5]);
}
/// variables.h:221 — link_recoilmode_timer: (*(uint8*)(g_ram+0x2C6))
pub inline fn link_recoilmode_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C6]);
}
/// variables.h:222 — link_actual_vel_z_copy: (*(uint8*)(g_ram+0x2C7))
pub inline fn link_actual_vel_z_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C7]);
}
/// variables.h:223 — byte_7E02C9: (*(uint8*)(g_ram+0x2C9))
pub inline fn byte_7E02C9() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C9]);
}
/// variables.h:224 — fallhole_var2: (*(uint8*)(g_ram+0x2CA))
pub inline fn fallhole_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2CA]);
}
/// variables.h:225 — swimming_countdown: (*(uint8*)(g_ram+0x2CB))
pub inline fn swimming_countdown() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2CB]);
}
/// variables.h:226 — byte_7E02CC: (*(uint8*)(g_ram+0x2CC))
pub inline fn byte_7E02CC() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2CC]);
}
/// variables.h:227 — word_7E02CD: (*(uint16*)(g_ram+0x2CD))
pub inline fn word_7E02CD() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2CD]);
}
/// variables.h:228 — tagalong_var2: (*(uint8*)(g_ram+0x2CF))
pub inline fn tagalong_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2CF]);
}
/// variables.h:229 — tagalong_var3: (*(uint8*)(g_ram+0x2D0))
pub inline fn tagalong_var3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D0]);
}
/// variables.h:230 — tagalong_var7: (*(uint8*)(g_ram+0x2D1))
pub inline fn tagalong_var7() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D1]);
}
/// variables.h:231 — timer_tagalong_reacquire: (*(uint8*)(g_ram+0x2D2))
pub inline fn timer_tagalong_reacquire() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D2]);
}
/// variables.h:232 — tagalong_var1: (*(uint8*)(g_ram+0x2D3))
pub inline fn tagalong_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D3]);
}
/// variables.h:233 — byte_7E02D4: (*(uint8*)(g_ram+0x2D4))
pub inline fn byte_7E02D4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D4]);
}
/// variables.h:234 — tagalong_var4: (*(uint8*)(g_ram+0x2D6))
pub inline fn tagalong_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D6]);
}
/// variables.h:235 — byte_7E02D7: (*(uint8*)(g_ram+0x2D7))
pub inline fn byte_7E02D7() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D7]);
}
/// variables.h:236 — link_receiveitem_index: (*(uint8*)(g_ram+0x2D8))
pub inline fn link_receiveitem_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D8]);
}
/// variables.h:237 — link_receiveitem_var1: (*(uint8*)(g_ram+0x2D9))
pub inline fn link_receiveitem_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2D9]);
}
/// variables.h:238 — link_pose_for_item: (*(uint8*)(g_ram+0x2DA))
pub inline fn link_pose_for_item() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2DA]);
}
/// variables.h:239 — link_triggered_by_whirlpool_sprite: (*(uint8*)(g_ram+0x2DB))
pub inline fn link_triggered_by_whirlpool_sprite() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2DB]);
}
/// variables.h:240 — link_x_coord_copy: (*(uint16*)(g_ram+0x2DC))
pub inline fn link_x_coord_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2DC]);
}
/// variables.h:241 — link_y_coord_copy: (*(uint16*)(g_ram+0x2DE))
pub inline fn link_y_coord_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2DE]);
}
/// variables.h:242 — link_is_bunny_mirror: (*(uint8*)(g_ram+0x2E0))
pub inline fn link_is_bunny_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E0]);
}
/// variables.h:243 — link_is_transforming: (*(uint8*)(g_ram+0x2E1))
pub inline fn link_is_transforming() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E1]);
}
/// variables.h:244 — link_bunny_transform_timer: (*(uint8*)(g_ram+0x2E2))
pub inline fn link_bunny_transform_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E2]);
}
/// variables.h:245 — link_sword_delay_timer: (*(uint8*)(g_ram+0x2E3))
pub inline fn link_sword_delay_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E3]);
}
/// variables.h:246 — flag_is_link_immobilized: (*(uint8*)(g_ram+0x2E4))
pub inline fn flag_is_link_immobilized() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E4]);
}
/// variables.h:247 — tiledetect_chest: (*(uint16*)(g_ram+0x2E5))
pub inline fn tiledetect_chest() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2E5]);
}
/// variables.h:248 — tiledetect_key_lock_gravestones: (*(uint8*)(g_ram+0x2E7))
pub inline fn tiledetect_key_lock_gravestones() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E7]);
}
/// variables.h:249 — bitfield_spike_cactus_tiles: (*(uint8*)(g_ram+0x2E8))
pub inline fn bitfield_spike_cactus_tiles() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E8]);
}
/// variables.h:250 — item_receipt_method: (*(uint8*)(g_ram+0x2E9))
pub inline fn item_receipt_method() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2E9]);
}
/// variables.h:251 — tiledetect_tile_type: (*(uint16*)(g_ram+0x2EA))
pub inline fn tiledetect_tile_type() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2EA]);
}
/// variables.h:252 — flag_is_ancilla_to_pick_up: (*(uint8*)(g_ram+0x2EC))
pub inline fn flag_is_ancilla_to_pick_up() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2EC]);
}
/// variables.h:253 — byte_7E02ED: (*(uint8*)(g_ram+0x2ED))
pub inline fn byte_7E02ED() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2ED]);
}
/// variables.h:254 — tiledetect_spike_floor_and_tile_triggers: (*(uint8*)(g_ram+0x2EE))
pub inline fn tiledetect_spike_floor_and_tile_triggers() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2EE]);
}
/// variables.h:255 — bitmask_for_dashable_tiles: (*(uint8*)(g_ram+0x2EF))
pub inline fn bitmask_for_dashable_tiles() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2EF]);
}
/// variables.h:256 — byte_7E02F0: (*(uint8*)(g_ram+0x2F0))
pub inline fn byte_7E02F0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F0]);
}
/// variables.h:257 — link_dash_ctr: (*(uint8*)(g_ram+0x2F1))
pub inline fn link_dash_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F1]);
}
/// variables.h:258 — tagalong_event_flags: (*(uint8*)(g_ram+0x2F2))
pub inline fn tagalong_event_flags() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F2]);
}
/// variables.h:259 — byte_7E02F3: (*(uint8*)(g_ram+0x2F3))
pub inline fn byte_7E02F3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F3]);
}
/// variables.h:260 — flag_is_sprite_to_pick_up_cached: (*(uint8*)(g_ram+0x2F4))
pub inline fn flag_is_sprite_to_pick_up_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F4]);
}
/// variables.h:261 — player_on_somaria_platform: (*(uint8*)(g_ram+0x2F5))
pub inline fn player_on_somaria_platform() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F5]);
}
/// variables.h:262 — tiledetect_misc_tiles: (*(uint16*)(g_ram+0x2F6))
pub inline fn tiledetect_misc_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2F6]);
}
/// variables.h:263 — link_want_make_noise_when_dashed: (*(uint8*)(g_ram+0x2F8))
pub inline fn link_want_make_noise_when_dashed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F8]);
}
/// variables.h:264 — tagalong_var5: (*(uint8*)(g_ram+0x2F9))
pub inline fn tagalong_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2F9]);
}
/// variables.h:265 — link_is_near_moveable_statue: (*(uint8*)(g_ram+0x2FA))
pub inline fn link_is_near_moveable_statue() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2FA]);
}
/// variables.h:266 — player_handler_timer: (*(uint8*)(g_ram+0x300))
pub inline fn player_handler_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x300]);
}
/// variables.h:267 — link_item_in_hand: (*(uint8*)(g_ram+0x301))
pub inline fn link_item_in_hand() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x301]);
}
/// variables.h:268 — fallhole_var1: (*(uint8*)(g_ram+0x302))
pub inline fn fallhole_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x302]);
}
/// variables.h:269 — current_item_y: (*(uint8*)(g_ram+0x303))
pub inline fn current_item_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x303]);
}
/// variables.h:270 — current_item_active: (*(uint8*)(g_ram+0x304))
pub inline fn current_item_active() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x304]);
}
/// variables.h:271 — debug_var2: (*(uint8*)(g_ram+0x305))
pub inline fn debug_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x305]);
}
/// variables.h:272 — unused_2: (*(uint8*)(g_ram+0x306))
pub inline fn unused_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x306]);
}
/// variables.h:273 — eq_selected_rod: (*(uint8*)(g_ram+0x307))
pub inline fn eq_selected_rod() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x307]);
}
/// variables.h:274 — link_state_bits: (*(uint8*)(g_ram+0x308))
pub inline fn link_state_bits() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x308]);
}
/// variables.h:275 — link_picking_throw_state: (*(uint8*)(g_ram+0x309))
pub inline fn link_picking_throw_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x309]);
}
/// variables.h:276 — some_animation_timer_steps: (*(uint8*)(g_ram+0x30A))
pub inline fn some_animation_timer_steps() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x30A]);
}
/// variables.h:277 — some_animation_timer: (*(uint8*)(g_ram+0x30B))
pub inline fn some_animation_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x30B]);
}
/// variables.h:278 — link_var30d: (*(uint8*)(g_ram+0x30D))
pub inline fn link_var30d() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x30D]);
}
/// variables.h:279 — link_var30e: (*(uint8*)(g_ram+0x30E))
pub inline fn link_var30e() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x30E]);
}
/// variables.h:280 — dung_floor_y_vel: (*(uint16*)(g_ram+0x310))
pub inline fn dung_floor_y_vel() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x310]);
}
/// variables.h:281 — dung_floor_x_vel: (*(uint16*)(g_ram+0x312))
pub inline fn dung_floor_x_vel() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x312]);
}
/// variables.h:282 — flag_is_sprite_to_pick_up: (*(uint8*)(g_ram+0x314))
pub inline fn flag_is_sprite_to_pick_up() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x314]);
}
/// variables.h:283 — tile_coll_flag: (*(uint8*)(g_ram+0x315))
pub inline fn tile_coll_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x315]);
}
/// variables.h:284 — byte_7E0316: (*(uint8*)(g_ram+0x316))
pub inline fn byte_7E0316() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x316]);
}
/// variables.h:285 — byte_7E0317: (*(uint8*)(g_ram+0x317))
pub inline fn byte_7E0317() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x317]);
}
/// variables.h:286 — related_to_moving_floor_y: (*(uint16*)(g_ram+0x318))
pub inline fn related_to_moving_floor_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x318]);
}
/// variables.h:287 — related_to_moving_floor_x: (*(uint16*)(g_ram+0x31A))
pub inline fn related_to_moving_floor_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x31A]);
}
/// variables.h:288 — state_for_spin_attack: (*(uint8*)(g_ram+0x31C))
pub inline fn state_for_spin_attack() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x31C]);
}
/// variables.h:289 — step_counter_for_spin_attack: (*(uint8*)(g_ram+0x31D))
pub inline fn step_counter_for_spin_attack() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x31D]);
}
/// variables.h:290 — link_spin_offsets: (*(uint8*)(g_ram+0x31E))
pub inline fn link_spin_offsets() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x31E]);
}
/// variables.h:291 — countdown_for_blink: (*(uint8*)(g_ram+0x31F))
pub inline fn countdown_for_blink() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x31F]);
}
/// variables.h:292 — tiledetect_moving_floor_tiles: (*(uint16*)(g_ram+0x320))
pub inline fn tiledetect_moving_floor_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x320]);
}
/// variables.h:293 — byte_7E0322: (*(uint8*)(g_ram+0x322))
pub inline fn byte_7E0322() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x322]);
}
/// variables.h:294 — link_direction_facing_mirror: (*(uint8*)(g_ram+0x323))
pub inline fn link_direction_facing_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x323]);
}
/// variables.h:295 — byte_7E0324: (*(uint8*)(g_ram+0x324))
pub inline fn byte_7E0324() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x324]);
}
/// variables.h:296 — byte_7E0325: (*(uint8*)(g_ram+0x325))
pub inline fn byte_7E0325() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x325]);
}
/// variables.h:297 — swimcoll_var3: ((uint16*)(g_ram+0x326))
pub inline fn swimcoll_var3() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x326]);
}
/// variables.h:298 — link_maybe_swim_faster: (*(uint8*)(g_ram+0x32A))
pub inline fn link_maybe_swim_faster() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x32A]);
}
/// variables.h:299 — swimcoll_var5: ((uint16*)(g_ram+0x32B))
pub inline fn swimcoll_var5() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x32B]);
}
/// variables.h:300 — swimcoll_var1: ((uint16*)(g_ram+0x32F))
pub inline fn swimcoll_var1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x32F]);
}
/// variables.h:301 — byte_7E0333: (*(uint8*)(g_ram+0x333))
pub inline fn byte_7E0333() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x333]);
}
/// variables.h:302 — swimcoll_var9: ((uint16*)(g_ram+0x334))
pub inline fn swimcoll_var9() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x334]);
}
/// variables.h:303 — swimcoll_var11: ((uint16*)(g_ram+0x338))
pub inline fn swimcoll_var11() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x338]);
}
/// variables.h:304 — swimcoll_var7: ((uint16*)(g_ram+0x33C))
pub inline fn swimcoll_var7() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x33C]);
}
/// variables.h:305 — link_some_direction_bits: (*(uint8*)(g_ram+0x340))
pub inline fn link_some_direction_bits() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x340]);
}
/// variables.h:306 — tiledetect_deepwater: (*(uint16*)(g_ram+0x341))
pub inline fn tiledetect_deepwater() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x341]);
}
/// variables.h:307 — tiledetect_normal_tiles: (*(uint16*)(g_ram+0x343))
pub inline fn tiledetect_normal_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x343]);
}
/// variables.h:308 — link_is_in_deep_water: (*(uint8*)(g_ram+0x345))
pub inline fn link_is_in_deep_water() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x345]);
}
/// variables.h:309 — link_palette_bits_of_oam: (*(uint16*)(g_ram+0x346))
pub inline fn link_palette_bits_of_oam() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x346]);
}
/// variables.h:310 — tiledetect_icy_floor: (*(uint16*)(g_ram+0x348))
pub inline fn tiledetect_icy_floor() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x348]);
}
/// variables.h:311 — link_flag_moving: (*(uint8*)(g_ram+0x34A))
pub inline fn link_flag_moving() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34A]);
}
/// variables.h:312 — eq_debug_variable: (*(uint8*)(g_ram+0x34B))
pub inline fn eq_debug_variable() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34B]);
}
/// variables.h:313 — tiledetect_water_staircase: (*(uint16*)(g_ram+0x34C))
pub inline fn tiledetect_water_staircase() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x34C]);
}
/// variables.h:314 — byte_7E034E: (*(uint8*)(g_ram+0x34E))
pub inline fn byte_7E034E() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34E]);
}
/// variables.h:315 — link_swim_hard_stroke: (*(uint8*)(g_ram+0x34F))
pub inline fn link_swim_hard_stroke() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34F]);
}
/// variables.h:316 — link_debug_value_2: (*(uint8*)(g_ram+0x350))
pub inline fn link_debug_value_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x350]);
}
/// variables.h:317 — draw_water_ripples_or_grass: (*(uint8*)(g_ram+0x351))
pub inline fn draw_water_ripples_or_grass() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x351]);
}
/// variables.h:318 — sort_sprites_offset_into_oam_buffer: (*(uint16*)(g_ram+0x352))
pub inline fn sort_sprites_offset_into_oam_buffer() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x352]);
}
/// variables.h:319 — value_computed_for_player_oam: (*(uint8*)(g_ram+0x354))
pub inline fn value_computed_for_player_oam() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x354]);
}
/// variables.h:320 — secondary_water_grass_timer: (*(uint8*)(g_ram+0x355))
pub inline fn secondary_water_grass_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x355]);
}
/// variables.h:321 — primary_water_grass_timer: (*(uint8*)(g_ram+0x356))
pub inline fn primary_water_grass_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x356]);
}
/// variables.h:322 — tiledetect_thick_grass: (*(uint16*)(g_ram+0x357))
pub inline fn tiledetect_thick_grass() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x357]);
}
/// variables.h:323 — tiledetect_shallow_water: (*(uint16*)(g_ram+0x359))
pub inline fn tiledetect_shallow_water() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x359]);
}
/// variables.h:324 — tiledetect_destruction_aftermath: (*(uint16*)(g_ram+0x35B))
pub inline fn tiledetect_destruction_aftermath() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x35B]);
}
/// variables.h:325 — oam_priority_value_2: (*(uint16*)(g_ram+0x35D))
pub inline fn oam_priority_value_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x35D]);
}
/// variables.h:326 — flag_for_boomerang_in_place: (*(uint8*)(g_ram+0x35F))
pub inline fn flag_for_boomerang_in_place() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x35F]);
}
/// variables.h:327 — link_electrocute_on_touch: (*(uint8*)(g_ram+0x360))
pub inline fn link_electrocute_on_touch() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x360]);
}
/// variables.h:328 — link_actual_vel_z_mirror: (*(uint8*)(g_ram+0x362))
pub inline fn link_actual_vel_z_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x362]);
}
/// variables.h:329 — link_actual_vel_z_copy_mirror: (*(uint8*)(g_ram+0x363))
pub inline fn link_actual_vel_z_copy_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x363]);
}
/// variables.h:330 — link_z_coord_mirror: (*(uint16*)(g_ram+0x364))
pub inline fn link_z_coord_mirror() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x364]);
}
/// variables.h:331 — tiledetect_read_something: (*(uint16*)(g_ram+0x366))
pub inline fn tiledetect_read_something() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x366]);
}
/// variables.h:332 — interacting_with_liftable_tile_x1: (*(uint8*)(g_ram+0x368))
pub inline fn interacting_with_liftable_tile_x1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x368]);
}
/// variables.h:333 — interacting_with_liftable_tile_x1b: (*(uint8*)(g_ram+0x369))
pub inline fn interacting_with_liftable_tile_x1b() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x369]);
}
/// variables.h:334 — interacting_with_liftable_tile_x2: (*(uint8*)(g_ram+0x36A))
pub inline fn interacting_with_liftable_tile_x2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36A]);
}
/// variables.h:335 — player_unk1: (*(uint8*)(g_ram+0x36B))
pub inline fn player_unk1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36B]);
}
/// variables.h:336 — tile_action_index: (*(uint8*)(g_ram+0x36C))
pub inline fn tile_action_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36C]);
}
/// variables.h:337 — tiledetect_vertical_ledge: (*(uint8*)(g_ram+0x36D))
pub inline fn tiledetect_vertical_ledge() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36D]);
}
/// variables.h:338 — detection_of_ledge_tiles_horiz_uphoriz: (*(uint8*)(g_ram+0x36E))
pub inline fn detection_of_ledge_tiles_horiz_uphoriz() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36E]);
}
/// variables.h:339 — tiledetect_ledges_down_leftright: (*(uint8*)(g_ram+0x36F))
pub inline fn tiledetect_ledges_down_leftright() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x36F]);
}
/// variables.h:340 — detection_of_unknown_tile_types: (*(uint8*)(g_ram+0x370))
pub inline fn detection_of_unknown_tile_types() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x370]);
}
/// variables.h:341 — link_timer_push_get_tired: (*(uint8*)(g_ram+0x371))
pub inline fn link_timer_push_get_tired() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x371]);
}
/// variables.h:342 — link_is_running: (*(uint8*)(g_ram+0x372))
pub inline fn link_is_running() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x372]);
}
/// variables.h:343 — link_give_damage: (*(uint8*)(g_ram+0x373))
pub inline fn link_give_damage() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x373]);
}
/// variables.h:344 — link_countdown_for_dash: (*(uint8*)(g_ram+0x374))
pub inline fn link_countdown_for_dash() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x374]);
}
/// variables.h:345 — link_timer_jump_ledge: (*(uint8*)(g_ram+0x375))
pub inline fn link_timer_jump_ledge() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x375]);
}
/// variables.h:346 — link_grabbing_wall: (*(uint8*)(g_ram+0x376))
pub inline fn link_grabbing_wall() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x376]);
}
/// variables.h:347 — link_unk_master_sword: (*(uint8*)(g_ram+0x377))
pub inline fn link_unk_master_sword() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x377]);
}
/// variables.h:348 — countdown_timer_for_staircases: (*(uint8*)(g_ram+0x378))
pub inline fn countdown_timer_for_staircases() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x378]);
}
/// variables.h:349 — byte_7E0379: (*(uint8*)(g_ram+0x379))
pub inline fn byte_7E0379() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x379]);
}
/// variables.h:350 — link_position_mode: (*(uint8*)(g_ram+0x37A))
pub inline fn link_position_mode() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37A]);
}
/// variables.h:351 — link_disable_sprite_damage: (*(uint8*)(g_ram+0x37B))
pub inline fn link_disable_sprite_damage() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37B]);
}
/// variables.h:352 — player_sleep_in_bed_state: (*(uint8*)(g_ram+0x37C))
pub inline fn player_sleep_in_bed_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37C]);
}
/// variables.h:353 — link_pose_during_opening: (*(uint8*)(g_ram+0x37D))
pub inline fn link_pose_during_opening() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37D]);
}
/// variables.h:354 — related_to_hookshot: (*(uint8*)(g_ram+0x37E))
pub inline fn related_to_hookshot() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37E]);
}
/// variables.h:355 — cheatWalkThroughWalls: (*(uint8*)(g_ram+0x37F))
pub inline fn cheatWalkThroughWalls() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x37F]);
}
/// variables.h:356 — ancilla_K: ((uint8*)(g_ram+0x380))
pub inline fn ancilla_K() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x380]);
}
/// variables.h:357 — ancilla_L: ((uint8*)(g_ram+0x385))
pub inline fn ancilla_L() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x385]);
}
/// variables.h:358 — ancilla_A: ((uint8*)(g_ram+0x38A))
pub inline fn ancilla_A() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x38A]);
}
/// variables.h:359 — ancilla_B: ((uint8*)(g_ram+0x38F))
pub inline fn ancilla_B() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x38F]);
}
/// variables.h:360 — ancilla_G: ((uint8*)(g_ram+0x394))
pub inline fn ancilla_G() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x394]);
}
/// variables.h:361 — boomerang_temp_y: (*(uint16*)(g_ram+0x399))
pub inline fn boomerang_temp_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x399]);
}
/// variables.h:362 — boomerang_temp_x: (*(uint16*)(g_ram+0x39B))
pub inline fn boomerang_temp_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x39B]);
}
/// variables.h:363 — hookshot_effect_index: (*(uint8*)(g_ram+0x39D))
pub inline fn hookshot_effect_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x39D]);
}
/// variables.h:364 — ancilla_arr3: ((uint8*)(g_ram+0x39F))
pub inline fn ancilla_arr3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x39F]);
}
/// variables.h:365 — ancilla_arr1: ((uint8*)(g_ram+0x3A4))
pub inline fn ancilla_arr1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3A4]);
}
/// variables.h:366 — ancilla_S: ((uint8*)(g_ram+0x3A9))
pub inline fn ancilla_S() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3A9]);
}
/// variables.h:367 — ancilla_aux_timer: ((uint8*)(g_ram+0x3B1))
pub inline fn ancilla_aux_timer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3B1]);
}
/// variables.h:370 — door_debris_x: ((uint16*)(g_ram+0x728))
pub inline fn door_debris_x() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x728]);
}
/// variables.h:371 — door_debris_y: ((uint16*)(g_ram+0x732))
pub inline fn door_debris_y() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x732]);
}
/// variables.h:372 — door_debris_direction: ((uint8*)(g_ram+0x73c))
pub inline fn door_debris_direction() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x73c]);
}
/// variables.h:373 — ancilla_arr26: ((uint8*)(g_ram+0x741))
pub inline fn ancilla_arr26() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x741]);
}
/// variables.h:374 — ancilla_arr25: ((uint8*)(g_ram+0x746))
pub inline fn ancilla_arr25() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x746]);
}
/// variables.h:375 — ancilla_arr22: ((uint8*)(g_ram+0x74b))
pub inline fn ancilla_arr22() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x74b]);
}
/// variables.h:377 — ancilla_alloc_rotate: (*(uint8*)(g_ram+0x3C4))
pub inline fn ancilla_alloc_rotate() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3C4]);
}
/// variables.h:378 — ancilla_H: ((uint8*)(g_ram+0x3C5))
pub inline fn ancilla_H() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3C5]);
}
/// variables.h:379 — ancilla_floor2: ((uint8*)(g_ram+0x3CA))
pub inline fn ancilla_floor2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3CA]);
}
/// variables.h:382 — ancilla_arr23: ((uint8*)(g_ram+0x3CF))
pub inline fn ancilla_arr23() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3CF]);
}
/// variables.h:383 — ancilla_T: ((uint8*)(g_ram+0x3D5))
pub inline fn ancilla_T() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3D5]);
}
/// variables.h:384 — ancilla_arr24: ((uint8*)(g_ram+0x3DB))
pub inline fn ancilla_arr24() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3DB]);
}
/// variables.h:385 — ancilla_tile_attr: ((uint8*)(g_ram+0x3E4))
pub inline fn ancilla_tile_attr() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3E4]);
}
/// variables.h:386 — link_something_with_hookshot: (*(uint8*)(g_ram+0x3E9))
pub inline fn link_something_with_hookshot() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3E9]);
}
/// variables.h:387 — ancilla_R: ((uint8*)(g_ram+0x3EA))
pub inline fn ancilla_R() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3EA]);
}
/// variables.h:388 — link_force_hold_sword_up: (*(uint8*)(g_ram+0x3EF))
pub inline fn link_force_hold_sword_up() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3EF]);
}
/// variables.h:389 — flute_countdown: (*(uint8*)(g_ram+0x3F0))
pub inline fn flute_countdown() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F0]);
}
/// variables.h:390 — tiledetect_var4: (*(uint16*)(g_ram+0x3F1))
pub inline fn tiledetect_var4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x3F1]);
}
/// variables.h:391 — link_on_conveyor_belt: (*(uint8*)(g_ram+0x3F3))
pub inline fn link_on_conveyor_belt() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F3]);
}
/// variables.h:392 — dung_unk6: (*(uint8*)(g_ram+0x3F4))
pub inline fn dung_unk6() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F4]);
}
/// variables.h:393 — link_timer_tempbunny: (*(uint16*)(g_ram+0x3F5))
pub inline fn link_timer_tempbunny() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x3F5]);
}
/// variables.h:394 — link_need_for_poof_for_transform: (*(uint8*)(g_ram+0x3F7))
pub inline fn link_need_for_poof_for_transform() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F7]);
}
/// variables.h:395 — link_need_for_pullforrupees_sprite: (*(uint8*)(g_ram+0x3F8))
pub inline fn link_need_for_pullforrupees_sprite() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F8]);
}
/// variables.h:396 — hookshot_var1: (*(uint8*)(g_ram+0x3F9))
pub inline fn hookshot_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3F9]);
}
/// variables.h:397 — bit9_of_xcoord: (*(uint16*)(g_ram+0x3FA))
pub inline fn bit9_of_xcoord() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x3FA]);
}
/// variables.h:398 — is_archer_or_shovel_game: (*(uint8*)(g_ram+0x3FC))
pub inline fn is_archer_or_shovel_game() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3FC]);
}
/// variables.h:399 — byte_7E03FD: (*(uint8*)(g_ram+0x3FD))
pub inline fn byte_7E03FD() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x3FD]);
}
/// variables.h:400 — dung_door_opened: (*(uint16*)(g_ram+0x400))
pub inline fn dung_door_opened() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x400]);
}
/// variables.h:401 — dung_savegame_state_bits: (*(uint16*)(g_ram+0x402))
pub inline fn dung_savegame_state_bits() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x402]);
}
/// variables.h:402 — word_7E0405: (*(uint16*)(g_ram+0x405))
pub inline fn word_7E0405() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x405]);
}
/// variables.h:403 — dung_quadrants_visited: (*(uint16*)(g_ram+0x408))
pub inline fn dung_quadrants_visited() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x408]);
}
/// variables.h:404 — overworld_area_index: (*(uint16*)(g_ram+0x40A))
pub inline fn overworld_area_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x40A]);
}
/// variables.h:405 — cur_palace_index_x2: (*(uint16*)(g_ram+0x40C))
pub inline fn cur_palace_index_x2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x40C]);
}
/// variables.h:406 — dung_layout_and_starting_quadrant: (*(uint16*)(g_ram+0x40E))
pub inline fn dung_layout_and_starting_quadrant() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x40E]);
}
/// variables.h:407 — overworld_screen_trans_dir_bits: (*(uint16*)(g_ram+0x410))
pub inline fn overworld_screen_trans_dir_bits() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x410]);
}
/// variables.h:408 — incremental_counter_for_vram: (*(uint8*)(g_ram+0x412))
pub inline fn incremental_counter_for_vram() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x412]);
}
/// variables.h:409 — dung_hdr_bg2_properties: (*(uint8*)(g_ram+0x414))
pub inline fn dung_hdr_bg2_properties() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x414]);
}
/// variables.h:410 — dung_hdr_bg2_properties_PADDING: (*(uint8*)(g_ram+0x415))
pub inline fn dung_hdr_bg2_properties_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x415]);
}
/// variables.h:411 — overworld_screen_trans_dir_bits2: (*(uint16*)(g_ram+0x416))
pub inline fn overworld_screen_trans_dir_bits2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x416]);
}
/// variables.h:412 — overworld_screen_transition: (*(uint8*)(g_ram+0x418))
pub inline fn overworld_screen_transition() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x418]);
}
/// variables.h:413 — overworld_screen_transition_ALWAYSZERO: (*(uint8*)(g_ram+0x419))
pub inline fn overworld_screen_transition_ALWAYSZERO() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x419]);
}
/// variables.h:414 — dung_floor_move_flags: (*(uint16*)(g_ram+0x41A))
pub inline fn dung_floor_move_flags() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x41A]);
}
/// variables.h:415 — dung_some_subpixel: ((uint8*)(g_ram+0x41C))
pub inline fn dung_some_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x41C]);
}
/// variables.h:416 — moving_wall_var2: (*(uint8*)(g_ram+0x41E))
pub inline fn moving_wall_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x41E]);
}
/// variables.h:417 — word_7E0420: (*(uint16*)(g_ram+0x420))
pub inline fn word_7E0420() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x420]);
}
/// variables.h:418 — dung_floor_x_offs: (*(uint16*)(g_ram+0x422))
pub inline fn dung_floor_x_offs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x422]);
}
/// variables.h:419 — dung_floor_y_offs: (*(uint16*)(g_ram+0x424))
pub inline fn dung_floor_y_offs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x424]);
}
/// variables.h:420 — dung_hdr_collision_2_mirror: (*(uint8*)(g_ram+0x428))
pub inline fn dung_hdr_collision_2_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x428]);
}
/// variables.h:421 — dung_hdr_collision_2_mirror_PADDING: (*(uint8*)(g_ram+0x429))
pub inline fn dung_hdr_collision_2_mirror_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x429]);
}
/// variables.h:422 — moving_wall_var1: (*(uint16*)(g_ram+0x42A))
pub inline fn moving_wall_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x42A]);
}
/// variables.h:423 — dung_misc_objs_index: (*(uint16*)(g_ram+0x42C))
pub inline fn dung_misc_objs_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x42C]);
}
/// variables.h:424 — dung_index_of_torches: (*(uint16*)(g_ram+0x42E))
pub inline fn dung_index_of_torches() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x42E]);
}
/// variables.h:425 — dung_door_switch_triggered: (*(uint8*)(g_ram+0x430))
pub inline fn dung_door_switch_triggered() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x430]);
}
/// variables.h:426 — dung_num_star_shaped_switches: (*(uint16*)(g_ram+0x432))
pub inline fn dung_num_star_shaped_switches() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x432]);
}
/// variables.h:427 — invisible_door_dir_and_index_x2: (*(uint16*)(g_ram+0x436))
pub inline fn invisible_door_dir_and_index_x2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x436]);
}
/// variables.h:428 — dung_num_inter_room_upnorth_stairs: (*(uint16*)(g_ram+0x438))
pub inline fn dung_num_inter_room_upnorth_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x438]);
}
/// variables.h:429 — dung_num_inter_room_southdown_stairs: (*(uint16*)(g_ram+0x43A))
pub inline fn dung_num_inter_room_southdown_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x43A]);
}
/// variables.h:430 — dung_num_inroom_upnorth_stairs: (*(uint16*)(g_ram+0x43C))
pub inline fn dung_num_inroom_upnorth_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x43C]);
}
/// variables.h:431 — dung_num_inroom_southdown_stairs: (*(uint16*)(g_ram+0x43E))
pub inline fn dung_num_inroom_southdown_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x43E]);
}
/// variables.h:432 — dung_num_interpseudo_upnorth_stairs: (*(uint16*)(g_ram+0x440))
pub inline fn dung_num_interpseudo_upnorth_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x440]);
}
/// variables.h:433 — dung_num_inroom_upnorth_stairs_water: (*(uint16*)(g_ram+0x442))
pub inline fn dung_num_inroom_upnorth_stairs_water() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x442]);
}
/// variables.h:434 — dung_num_activated_water_ladders: (*(uint16*)(g_ram+0x444))
pub inline fn dung_num_activated_water_ladders() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x444]);
}
/// variables.h:435 — dung_num_water_ladders: (*(uint16*)(g_ram+0x446))
pub inline fn dung_num_water_ladders() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x446]);
}
/// variables.h:436 — dung_some_stairs_unk4: (*(uint16*)(g_ram+0x448))
pub inline fn dung_some_stairs_unk4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x448]);
}
/// variables.h:437 — kind_of_in_room_staircase: (*(uint16*)(g_ram+0x44A))
pub inline fn kind_of_in_room_staircase() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x44A]);
}
/// variables.h:438 — dung_num_toggle_floor: (*(uint16*)(g_ram+0x44E))
pub inline fn dung_num_toggle_floor() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x44E]);
}
/// variables.h:439 — dung_num_toggle_palace: (*(uint16*)(g_ram+0x450))
pub inline fn dung_num_toggle_palace() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x450]);
}
/// variables.h:440 — dung_blastwall_flag_x: (*(uint8*)(g_ram+0x452))
pub inline fn dung_blastwall_flag_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x452]);
}
/// variables.h:441 — dung_blastwall_flag_y: (*(uint8*)(g_ram+0x453))
pub inline fn dung_blastwall_flag_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x453]);
}
/// variables.h:442 — dung_unk_blast_walls_2: (*(uint16*)(g_ram+0x454))
pub inline fn dung_unk_blast_walls_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x454]);
}
/// variables.h:443 — dung_unk_blast_walls_3: (*(uint16*)(g_ram+0x456))
pub inline fn dung_unk_blast_walls_3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x456]);
}
/// variables.h:444 — hdr_dungeon_dark_with_lantern: (*(uint8*)(g_ram+0x458))
pub inline fn hdr_dungeon_dark_with_lantern() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x458]);
}
/// variables.h:445 — hdr_dungeon_dark_with_lantern_PADDING: (*(uint8*)(g_ram+0x459))
pub inline fn hdr_dungeon_dark_with_lantern_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x459]);
}
/// variables.h:446 — dung_num_lit_torches: (*(uint8*)(g_ram+0x45A))
pub inline fn dung_num_lit_torches() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x45A]);
}
/// variables.h:447 — dung_num_lit_torches_PADDING: (*(uint8*)(g_ram+0x45B))
pub inline fn dung_num_lit_torches_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x45B]);
}
/// variables.h:448 — dung_cur_quadrant_upload: (*(uint8*)(g_ram+0x45C))
pub inline fn dung_cur_quadrant_upload() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x45C]);
}
/// variables.h:449 — dung_cur_quadrant_upload_PADDING: (*(uint8*)(g_ram+0x45D))
pub inline fn dung_cur_quadrant_upload_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x45D]);
}
/// variables.h:450 — word_7E045E: (*(uint16*)(g_ram+0x45E))
pub inline fn word_7E045E() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x45E]);
}
/// variables.h:451 — dung_cur_door_idx: (*(uint16*)(g_ram+0x460))
pub inline fn dung_cur_door_idx() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x460]);
}
/// variables.h:452 — which_staircase_index: (*(uint8*)(g_ram+0x462))
pub inline fn which_staircase_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x462]);
}
/// variables.h:453 — which_staircase_index_PADDING: (*(uint8*)(g_ram+0x463))
pub inline fn which_staircase_index_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x463]);
}
/// variables.h:454 — staircase_var1: (*(uint8*)(g_ram+0x464))
pub inline fn staircase_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x464]);
}
/// variables.h:455 — related_to_trapdoors_somehow: (*(uint16*)(g_ram+0x466))
pub inline fn related_to_trapdoors_somehow() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x466]);
}
/// variables.h:456 — dung_flag_trapdoors_down: (*(uint16*)(g_ram+0x468))
pub inline fn dung_flag_trapdoors_down() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x468]);
}
/// variables.h:457 — dung_floor_2_filler_tiles: (*(uint16*)(g_ram+0x46A))
pub inline fn dung_floor_2_filler_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x46A]);
}
/// variables.h:458 — dung_hdr_collision: (*(uint8*)(g_ram+0x46C))
pub inline fn dung_hdr_collision() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x46C]);
}
/// variables.h:459 — watergate_var1: (*(uint8*)(g_ram+0x470))
pub inline fn watergate_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x470]);
}
/// variables.h:460 — watergate_var1_PADDING: (*(uint8*)(g_ram+0x471))
pub inline fn watergate_var1_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x471]);
}
/// variables.h:461 — watergate_pos: (*(uint16*)(g_ram+0x472))
pub inline fn watergate_pos() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x472]);
}
/// variables.h:462 — push_block_direction: (*(uint8*)(g_ram+0x474))
pub inline fn push_block_direction() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x474]);
}
/// variables.h:463 — link_is_on_lower_level_mirror: (*(uint8*)(g_ram+0x476))
pub inline fn link_is_on_lower_level_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x476]);
}
/// variables.h:464 — dung_index_of_torches_start: (*(uint16*)(g_ram+0x478))
pub inline fn dung_index_of_torches_start() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x478]);
}
/// variables.h:465 — about_to_jump_off_ledge: (*(uint8*)(g_ram+0x47A))
pub inline fn about_to_jump_off_ledge() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x47A]);
}
/// variables.h:466 — word_7E047C: (*(uint16*)(g_ram+0x47C))
pub inline fn word_7E047C() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x47C]);
}
/// variables.h:467 — dung_num_wall_upnorth_spiral_stairs: (*(uint16*)(g_ram+0x47E))
pub inline fn dung_num_wall_upnorth_spiral_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x47E]);
}
/// variables.h:468 — dung_num_wall_downnorth_spiral_stairs: (*(uint16*)(g_ram+0x480))
pub inline fn dung_num_wall_downnorth_spiral_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x480]);
}
/// variables.h:469 — dung_num_wall_upnorth_spiral_stairs_2: (*(uint16*)(g_ram+0x482))
pub inline fn dung_num_wall_upnorth_spiral_stairs_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x482]);
}
/// variables.h:470 — dung_num_wall_downnorth_spiral_stairs_2: (*(uint16*)(g_ram+0x484))
pub inline fn dung_num_wall_downnorth_spiral_stairs_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x484]);
}
/// variables.h:471 — word_7E0486: (*(uint16*)(g_ram+0x486))
pub inline fn word_7E0486() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x486]);
}
/// variables.h:472 — word_7E0488: (*(uint16*)(g_ram+0x488))
pub inline fn word_7E0488() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x488]);
}
/// variables.h:473 — cur_staircase_plane: (*(uint8*)(g_ram+0x48A))
pub inline fn cur_staircase_plane() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x48A]);
}
/// variables.h:474 — word_7E048C: (*(uint16*)(g_ram+0x48C))
pub inline fn word_7E048C() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x48C]);
}
/// variables.h:475 — dungeon_room_index2: (*(uint16*)(g_ram+0x48E))
pub inline fn dungeon_room_index2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x48E]);
}
/// variables.h:476 — dung_floor_1_filler_tiles: (*(uint16*)(g_ram+0x490))
pub inline fn dung_floor_1_filler_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x490]);
}
/// variables.h:477 — byte_7E0492: (*(uint8*)(g_ram+0x492))
pub inline fn byte_7E0492() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x492]);
}
/// variables.h:478 — move_overlay_ctr: (*(uint8*)(g_ram+0x494))
pub inline fn move_overlay_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x494]);
}
/// variables.h:479 — dung_num_chests_x2: (*(uint16*)(g_ram+0x496))
pub inline fn dung_num_chests_x2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x496]);
}
/// variables.h:480 — dung_num_bigkey_locks_x2: (*(uint16*)(g_ram+0x498))
pub inline fn dung_num_bigkey_locks_x2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x498]);
}
/// variables.h:481 — dung_num_stairs_1: (*(uint16*)(g_ram+0x49A))
pub inline fn dung_num_stairs_1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x49A]);
}
/// variables.h:482 — dung_num_stairs_2: (*(uint16*)(g_ram+0x49C))
pub inline fn dung_num_stairs_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x49C]);
}
/// variables.h:483 — dung_num_stairs_wet: (*(uint16*)(g_ram+0x49E))
pub inline fn dung_num_stairs_wet() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x49E]);
}
/// variables.h:484 — hud_floor_changed_timer: (*(uint8*)(g_ram+0x4A0))
pub inline fn hud_floor_changed_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4A0]);
}
/// variables.h:485 — dung_num_inter_room_upnorth_straight_stairs: (*(uint16*)(g_ram+0x4A2))
pub inline fn dung_num_inter_room_upnorth_straight_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4A2]);
}
/// variables.h:486 — dung_num_inter_room_upsouth_straight_stairs: (*(uint16*)(g_ram+0x4A4))
pub inline fn dung_num_inter_room_upsouth_straight_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4A4]);
}
/// variables.h:487 — dung_num_inter_room_downnorth_straight_stairs: (*(uint16*)(g_ram+0x4A6))
pub inline fn dung_num_inter_room_downnorth_straight_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4A6]);
}
/// variables.h:488 — dung_num_inter_room_downsouth_straight_stairs: (*(uint16*)(g_ram+0x4A8))
pub inline fn dung_num_inter_room_downsouth_straight_stairs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4A8]);
}
/// variables.h:489 — death_var4: (*(uint8*)(g_ram+0x4AA))
pub inline fn death_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4AA]);
}
/// variables.h:490 — num_memorized_tiles: (*(uint16*)(g_ram+0x4AC))
pub inline fn num_memorized_tiles() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4AC]);
}
/// variables.h:491 — dung_num_inroom_upsouth_stairs_water: (*(uint16*)(g_ram+0x4AE))
pub inline fn dung_num_inroom_upsouth_stairs_water() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4AE]);
}
/// variables.h:492 — dung_unk5: (*(uint16*)(g_ram+0x4B0))
pub inline fn dung_unk5() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4B0]);
}
/// variables.h:493 — word_7E04B2: (*(uint16*)(g_ram+0x4B2))
pub inline fn word_7E04B2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4B2]);
}
/// variables.h:494 — super_bomb_indicator_unk2: (*(uint8*)(g_ram+0x4B4))
pub inline fn super_bomb_indicator_unk2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4B4]);
}
/// variables.h:495 — super_bomb_indicator_unk1: (*(uint8*)(g_ram+0x4B5))
pub inline fn super_bomb_indicator_unk1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4B5]);
}
/// variables.h:496 — word_7E04B6: (*(uint16*)(g_ram+0x4B6))
pub inline fn word_7E04B6() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4B6]);
}
/// variables.h:497 — big_key_door_message_triggered: (*(uint16*)(g_ram+0x4B8))
pub inline fn big_key_door_message_triggered() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4B8]);
}
/// variables.h:498 — dung_overlay_to_load: (*(uint8*)(g_ram+0x4BA))
pub inline fn dung_overlay_to_load() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4BA]);
}
/// variables.h:499 — byte_7E04BC: (*(uint8*)(g_ram+0x4BC))
pub inline fn byte_7E04BC() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4BC]);
}
/// variables.h:500 — byte_7E04BE: (*(uint8*)(g_ram+0x4BE))
pub inline fn byte_7E04BE() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4BE]);
}
/// variables.h:501 — byte_7E04BF: (*(uint8*)(g_ram+0x4BF))
pub inline fn byte_7E04BF() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4BF]);
}
/// variables.h:502 — byte_7E04C0: (*(uint8*)(g_ram+0x4C0))
pub inline fn byte_7E04C0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C0]);
}
/// variables.h:503 — byte_7E04C1: (*(uint8*)(g_ram+0x4C1))
pub inline fn byte_7E04C1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C1]);
}
/// variables.h:504 — byte_7E04C2: (*(uint8*)(g_ram+0x4C2))
pub inline fn byte_7E04C2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C2]);
}
/// variables.h:505 — minigame_credits: (*(uint8*)(g_ram+0x4C4))
pub inline fn minigame_credits() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C4]);
}
/// variables.h:506 — byte_7E04C5: (*(uint8*)(g_ram+0x4C5))
pub inline fn byte_7E04C5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C5]);
}
/// variables.h:507 — trigger_special_entrance: (*(uint8*)(g_ram+0x4C6))
pub inline fn trigger_special_entrance() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C6]);
}
/// variables.h:508 — flag_skip_call_tag_routines: (*(uint8*)(g_ram+0x4C7))
pub inline fn flag_skip_call_tag_routines() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4C7]);
}
/// variables.h:509 — word_7E04C8: (*(uint16*)(g_ram+0x4C8))
pub inline fn word_7E04C8() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4C8]);
}
/// variables.h:510 — link_lowlife_countdown_timer_beep: (*(uint8*)(g_ram+0x4CA))
pub inline fn link_lowlife_countdown_timer_beep() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4CA]);
}
/// variables.h:511 — dung_torch_timers: ((uint8*)(g_ram+0x4F0))
pub inline fn dung_torch_timers() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x4F0]);
}
/// variables.h:512 — dung_replacement_tile_state: ((uint16*)(g_ram+0x500))
pub inline fn dung_replacement_tile_state() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x500]);
}
/// variables.h:513 — dung_object_pos_in_objdata: ((uint16*)(g_ram+0x520))
pub inline fn dung_object_pos_in_objdata() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x520]);
}
/// variables.h:514 — dung_object_tilemap_pos: ((uint16*)(g_ram+0x540))
pub inline fn dung_object_tilemap_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x540]);
}
/// variables.h:515 — replacement_tilemap_UL: ((uint16*)(g_ram+0x560))
pub inline fn replacement_tilemap_UL() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x560]);
}
/// variables.h:516 — replacement_tilemap_LL: ((uint16*)(g_ram+0x580))
pub inline fn replacement_tilemap_LL() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x580]);
}
/// variables.h:517 — replacement_tilemap_UR: ((uint16*)(g_ram+0x5A0))
pub inline fn replacement_tilemap_UR() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5A0]);
}
/// variables.h:518 — replacement_tilemap_LR: ((uint16*)(g_ram+0x5C0))
pub inline fn replacement_tilemap_LR() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5C0]);
}
/// variables.h:519 — pushedblocks_x_hi: ((uint16*)(g_ram+0x5E0))
pub inline fn pushedblocks_x_hi() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5E0]);
}
/// variables.h:520 — pushedblocks_x_lo: ((uint16*)(g_ram+0x5E4))
pub inline fn pushedblocks_x_lo() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5E4]);
}
/// variables.h:521 — pushedblocks_target: ((uint16*)(g_ram+0x5E8))
pub inline fn pushedblocks_target() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5E8]);
}
/// variables.h:522 — pushedblocks_y_hi: ((uint16*)(g_ram+0x5EC))
pub inline fn pushedblocks_y_hi() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5EC]);
}
/// variables.h:523 — pushedblocks_y_lo: ((uint16*)(g_ram+0x5F0))
pub inline fn pushedblocks_y_lo() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5F0]);
}
/// variables.h:524 — pushedblocks_subpixel: ((uint16*)(g_ram+0x5F4))
pub inline fn pushedblocks_subpixel() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5F4]);
}
/// variables.h:525 — pushedblock_facing: ((uint16*)(g_ram+0x5F8))
pub inline fn pushedblock_facing() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x5F8]);
}
/// variables.h:526 — index_of_changable_dungeon_objs: ((uint8*)(g_ram+0x5FC))
pub inline fn index_of_changable_dungeon_objs() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5FC]);
}
/// variables.h:527 — up_down_scroll_target: (*(uint16*)(g_ram+0x610))
pub inline fn up_down_scroll_target() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x610]);
}
/// variables.h:528 — up_down_scroll_target_end: (*(uint16*)(g_ram+0x612))
pub inline fn up_down_scroll_target_end() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x612]);
}
/// variables.h:529 — left_right_scroll_target: (*(uint16*)(g_ram+0x614))
pub inline fn left_right_scroll_target() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x614]);
}
/// variables.h:530 — left_right_scroll_target_end: (*(uint16*)(g_ram+0x616))
pub inline fn left_right_scroll_target_end() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x616]);
}
/// variables.h:531 — camera_y_coord_scroll_low: (*(uint16*)(g_ram+0x618))
pub inline fn camera_y_coord_scroll_low() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x618]);
}
/// variables.h:532 — camera_y_coord_scroll_hi: (*(uint16*)(g_ram+0x61A))
pub inline fn camera_y_coord_scroll_hi() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x61A]);
}
/// variables.h:533 — camera_x_coord_scroll_low: (*(uint16*)(g_ram+0x61C))
pub inline fn camera_x_coord_scroll_low() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x61C]);
}
/// variables.h:534 — camera_x_coord_scroll_hi: (*(uint16*)(g_ram+0x61E))
pub inline fn camera_x_coord_scroll_hi() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x61E]);
}
/// variables.h:535 — BG1HOFS_subpixel: (*(uint16*)(g_ram+0x620))
pub inline fn BG1HOFS_subpixel() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x620]);
}
/// variables.h:536 — BG1VOFS_subpixel: (*(uint16*)(g_ram+0x622))
pub inline fn BG1VOFS_subpixel() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x622]);
}
/// variables.h:537 — overworld_unk1: (*(uint16*)(g_ram+0x624))
pub inline fn overworld_unk1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x624]);
}
/// variables.h:538 — overworld_unk1_neg: (*(uint16*)(g_ram+0x626))
pub inline fn overworld_unk1_neg() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x626]);
}
/// variables.h:539 — overworld_unk3: (*(uint16*)(g_ram+0x628))
pub inline fn overworld_unk3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x628]);
}
/// variables.h:540 — overworld_unk3_neg: (*(uint16*)(g_ram+0x62A))
pub inline fn overworld_unk3_neg() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x62A]);
}
/// variables.h:541 — dung_loade_bgoffs_h_copy: (*(uint16*)(g_ram+0x62C))
pub inline fn dung_loade_bgoffs_h_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x62C]);
}
/// variables.h:542 — dung_loade_bgoffs_v_copy: (*(uint16*)(g_ram+0x62E))
pub inline fn dung_loade_bgoffs_v_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x62E]);
}
/// variables.h:543 — byte_7E0630: (*(uint8*)(g_ram+0x630))
pub inline fn byte_7E0630() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x630]);
}
/// variables.h:544 — byte_7E0631: (*(uint8*)(g_ram+0x631))
pub inline fn byte_7E0631() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x631]);
}
/// variables.h:545 — byte_7E0635: (*(uint8*)(g_ram+0x635))
pub inline fn byte_7E0635() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x635]);
}
/// variables.h:546 — overworld_map_flags: (*(uint8*)(g_ram+0x636))
pub inline fn overworld_map_flags() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x636]);
}
/// variables.h:547 — timer_for_mode7_zoom: (*(uint8*)(g_ram+0x637))
pub inline fn timer_for_mode7_zoom() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x637]);
}
/// variables.h:548 — M7X_copy: (*(uint16*)(g_ram+0x638))
pub inline fn M7X_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x638]);
}
/// variables.h:549 — M7Y_copy: (*(uint16*)(g_ram+0x63A))
pub inline fn M7Y_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x63A]);
}
/// variables.h:550 — dung_hdr_hole_teleporter_plane: (*(uint8*)(g_ram+0x63C))
pub inline fn dung_hdr_hole_teleporter_plane() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x63C]);
}
/// variables.h:551 — dung_hdr_staircase_plane: ((uint8*)(g_ram+0x63D))
pub inline fn dung_hdr_staircase_plane() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x63D]);
}
/// variables.h:552 — dung_flag_movable_block_was_pushed: (*(uint8*)(g_ram+0x641))
pub inline fn dung_flag_movable_block_was_pushed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x641]);
}
/// variables.h:553 — dung_flag_statechange_waterpuzzle: (*(uint8*)(g_ram+0x642))
pub inline fn dung_flag_statechange_waterpuzzle() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x642]);
}
/// variables.h:554 — dung_flag_somaria_block_switch: (*(uint8*)(g_ram+0x646))
pub inline fn dung_flag_somaria_block_switch() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x646]);
}
/// variables.h:555 — mosaic_inc_or_dec: (*(uint8*)(g_ram+0x647))
pub inline fn mosaic_inc_or_dec() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x647]);
}
/// variables.h:556 — spotlight_var3: (*(uint16*)(g_ram+0x670))
pub inline fn spotlight_var3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x670]);
}
/// variables.h:557 — spotlight_y_lower: (*(uint16*)(g_ram+0x674))
pub inline fn spotlight_y_lower() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x674]);
}
/// variables.h:558 — spotlight_y_upper: (*(uint16*)(g_ram+0x676))
pub inline fn spotlight_y_upper() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x676]);
}
/// variables.h:559 — word_7E0678: (*(uint16*)(g_ram+0x678))
pub inline fn word_7E0678() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x678]);
}
/// variables.h:560 — spotlight_var4: (*(uint16*)(g_ram+0x67A))
pub inline fn spotlight_var4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x67A]);
}
/// variables.h:561 — spotlight_var1: (*(uint16*)(g_ram+0x67C))
pub inline fn spotlight_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x67C]);
}
/// variables.h:562 — spotlight_var2: (*(uint16*)(g_ram+0x67E))
pub inline fn spotlight_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x67E]);
}
/// variables.h:563 — water_hdma_var0: (*(uint16*)(g_ram+0x680))
pub inline fn water_hdma_var0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x680]);
}
/// variables.h:564 — water_hdma_var1: (*(uint16*)(g_ram+0x682))
pub inline fn water_hdma_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x682]);
}
/// variables.h:565 — water_hdma_var2: (*(uint16*)(g_ram+0x684))
pub inline fn water_hdma_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x684]);
}
/// variables.h:566 — water_hdma_var3: (*(uint16*)(g_ram+0x686))
pub inline fn water_hdma_var3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x686]);
}
/// variables.h:567 — water_hdma_var4: (*(uint16*)(g_ram+0x688))
pub inline fn water_hdma_var4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x688]);
}
/// variables.h:568 — water_hdma_var5: (*(uint16*)(g_ram+0x68A))
pub inline fn water_hdma_var5() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x68A]);
}
/// variables.h:569 — dung_door_opened_incl_adjacent: (*(uint16*)(g_ram+0x68C))
pub inline fn dung_door_opened_incl_adjacent() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x68C]);
}
/// variables.h:570 — dung_cur_door_pos: (*(uint16*)(g_ram+0x68E))
pub inline fn dung_cur_door_pos() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x68E]);
}
/// variables.h:571 — door_animation_step_indicator: (*(uint16*)(g_ram+0x690))
pub inline fn door_animation_step_indicator() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x690]);
}
/// variables.h:572 — door_open_closed_counter: (*(uint16*)(g_ram+0x692))
pub inline fn door_open_closed_counter() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x692]);
}
/// variables.h:573 — dung_which_key_x2: (*(uint16*)(g_ram+0x694))
pub inline fn dung_which_key_x2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x694]);
}
/// variables.h:574 — ow_entrance_value: (*(uint16*)(g_ram+0x696))
pub inline fn ow_entrance_value() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x696]);
}
/// variables.h:575 — big_rock_starting_address: (*(uint16*)(g_ram+0x698))
pub inline fn big_rock_starting_address() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x698]);
}
/// variables.h:576 — ow_countdown_transition: (*(uint8*)(g_ram+0x69A))
pub inline fn ow_countdown_transition() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x69A]);
}
/// variables.h:577 — byte_7E069C: (*(uint8*)(g_ram+0x69C))
pub inline fn byte_7E069C() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x69C]);
}
/// variables.h:578 — byte_7E069E: ((uint8*)(g_ram+0x69E))
pub inline fn byte_7E069E() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x69E]);
}
/// variables.h:579 — dung_toggle_floor_pos: ((uint16*)(g_ram+0x6C0))
pub inline fn dung_toggle_floor_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6C0]);
}
/// variables.h:580 — dung_toggle_palace_pos: ((uint16*)(g_ram+0x6D0))
pub inline fn dung_toggle_palace_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6D0]);
}
/// variables.h:581 — dung_chest_locations: ((uint16*)(g_ram+0x6E0))
pub inline fn dung_chest_locations() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6E0]);
}
/// variables.h:582 — dung_stairs_table_2: ((uint16*)(g_ram+0x6EC))
pub inline fn dung_stairs_table_2() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6EC]);
}
/// variables.h:583 — current_area_of_player: (*(uint16*)(g_ram+0x700))
pub inline fn current_area_of_player() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x700]);
}
/// variables.h:584 — overworld_offset_base_y: (*(uint16*)(g_ram+0x708))
pub inline fn overworld_offset_base_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x708]);
}
/// variables.h:585 — overworld_offset_mask_y: (*(uint16*)(g_ram+0x70A))
pub inline fn overworld_offset_mask_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x70A]);
}
/// variables.h:586 — overworld_offset_base_x: (*(uint16*)(g_ram+0x70C))
pub inline fn overworld_offset_base_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x70C]);
}
/// variables.h:587 — overworld_offset_mask_x: (*(uint16*)(g_ram+0x70E))
pub inline fn overworld_offset_mask_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x70E]);
}
/// variables.h:588 — nmi_disable_core_updates: (*(uint8*)(g_ram+0x710))
pub inline fn nmi_disable_core_updates() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x710]);
}
/// variables.h:589 — overworld_area_is_big: (*(uint16*)(g_ram+0x712))
pub inline fn overworld_area_is_big() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x712]);
}
/// variables.h:590 — overworld_area_is_big_backup: (*(uint8*)(g_ram+0x714))
pub inline fn overworld_area_is_big_backup() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x714]);
}
/// variables.h:591 — overworld_right_bottom_bound_for_scroll: (*(uint16*)(g_ram+0x716))
pub inline fn overworld_right_bottom_bound_for_scroll() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x716]);
}
/// variables.h:592 — vwf_flag_next_line: (*(uint16*)(g_ram+0x720))
pub inline fn vwf_flag_next_line() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x720]);
}
/// variables.h:593 — vwf_curline: (*(uint16*)(g_ram+0x722))
pub inline fn vwf_curline() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x722]);
}
/// variables.h:594 — vwf_var1: (*(uint16*)(g_ram+0x724))
pub inline fn vwf_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x724]);
}
/// variables.h:595 — vwf_line_ptr: (*(uint16*)(g_ram+0x726))
pub inline fn vwf_line_ptr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x726]);
}
/// variables.h:596 — extended_oam: ((uint8*)(g_ram+0xA00))
pub inline fn extended_oam() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA00]);
}
/// variables.h:597 — bytewise_extended_oam: ((uint8*)(g_ram+0xA20))
pub inline fn bytewise_extended_oam() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xA20]);
}
/// variables.h:598 — byte_7E0AA0: (*(uint8*)(g_ram+0xAA0))
pub inline fn byte_7E0AA0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA0]);
}
/// variables.h:599 — main_tile_theme_index: (*(uint8*)(g_ram+0xAA1))
pub inline fn main_tile_theme_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA1]);
}
/// variables.h:600 — aux_tile_theme_index: (*(uint8*)(g_ram+0xAA2))
pub inline fn aux_tile_theme_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA2]);
}
/// variables.h:601 — sprite_graphics_index: (*(uint8*)(g_ram+0xAA3))
pub inline fn sprite_graphics_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA3]);
}
/// variables.h:602 — misc_sprites_graphics_index: (*(uint8*)(g_ram+0xAA4))
pub inline fn misc_sprites_graphics_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAA4]);
}
/// variables.h:603 — unused_config_gfx: (*(uint16*)(g_ram+0xAA6))
pub inline fn unused_config_gfx() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAA6]);
}
/// variables.h:604 — overworld_palette_aux_or_main: (*(uint16*)(g_ram+0xAA8))
pub inline fn overworld_palette_aux_or_main() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAA8]);
}
/// variables.h:605 — load_chr_halfslot_even_odd: (*(uint8*)(g_ram+0xAAA))
pub inline fn load_chr_halfslot_even_odd() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAAA]);
}
/// variables.h:606 — palette_sp0l: (*(uint8*)(g_ram+0xAAC))
pub inline fn palette_sp0l() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAAC]);
}
/// variables.h:607 — palette_sp5l: (*(uint8*)(g_ram+0xAAD))
pub inline fn palette_sp5l() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAAD]);
}
/// variables.h:608 — palette_sp6l: (*(uint8*)(g_ram+0xAAE))
pub inline fn palette_sp6l() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAAE]);
}
/// variables.h:609 — byte_7E0AB0: (*(uint8*)(g_ram+0xAB0))
pub inline fn byte_7E0AB0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB0]);
}
/// variables.h:610 — palette_sp6r_indoors: (*(uint8*)(g_ram+0xAB1))
pub inline fn palette_sp6r_indoors() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB1]);
}
/// variables.h:611 — hud_palette: (*(uint8*)(g_ram+0xAB2))
pub inline fn hud_palette() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB2]);
}
/// variables.h:612 — overworld_palette_mode: (*(uint8*)(g_ram+0xAB3))
pub inline fn overworld_palette_mode() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB3]);
}
/// variables.h:613 — overworld_palette_aux1_bp2to4_hi: (*(uint8*)(g_ram+0xAB4))
pub inline fn overworld_palette_aux1_bp2to4_hi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB4]);
}
/// variables.h:614 — overworld_palette_aux2_bp5to7_hi: (*(uint8*)(g_ram+0xAB5))
pub inline fn overworld_palette_aux2_bp5to7_hi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB5]);
}
/// variables.h:615 — palette_main_indoors: (*(uint8*)(g_ram+0xAB6))
pub inline fn palette_main_indoors() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB6]);
}
/// variables.h:616 — byte_7E0AB7: (*(uint8*)(g_ram+0xAB7))
pub inline fn byte_7E0AB7() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB7]);
}
/// variables.h:617 — overworld_palette_aux3_bp7_lo: (*(uint8*)(g_ram+0xAB8))
pub inline fn overworld_palette_aux3_bp7_lo() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xAB8]);
}
/// variables.h:618 — palette_swap_flag: (*(uint8*)(g_ram+0xABD))
pub inline fn palette_swap_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xABD]);
}
/// variables.h:619 — flag_overworld_area_did_change: (*(uint8*)(g_ram+0xABF))
pub inline fn flag_overworld_area_did_change() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xABF]);
}
/// variables.h:620 — dma_source_addr_6: (*(uint16*)(g_ram+0xAC0))
pub inline fn dma_source_addr_6() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAC0]);
}
/// variables.h:621 — dma_source_addr_11: (*(uint16*)(g_ram+0xAC2))
pub inline fn dma_source_addr_11() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAC2]);
}
/// variables.h:622 — dma_source_addr_7: (*(uint16*)(g_ram+0xAC4))
pub inline fn dma_source_addr_7() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAC4]);
}
/// variables.h:623 — dma_source_addr_12: (*(uint16*)(g_ram+0xAC6))
pub inline fn dma_source_addr_12() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAC6]);
}
/// variables.h:624 — dma_source_addr_8: (*(uint16*)(g_ram+0xAC8))
pub inline fn dma_source_addr_8() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAC8]);
}
/// variables.h:625 — dma_source_addr_13: (*(uint16*)(g_ram+0xACA))
pub inline fn dma_source_addr_13() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xACA]);
}
/// variables.h:626 — dma_source_addr_3: (*(uint16*)(g_ram+0xACC))
pub inline fn dma_source_addr_3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xACC]);
}
/// variables.h:627 — dma_source_addr_0: (*(uint16*)(g_ram+0xACE))
pub inline fn dma_source_addr_0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xACE]);
}
/// variables.h:628 — dma_source_addr_4: (*(uint16*)(g_ram+0xAD0))
pub inline fn dma_source_addr_4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAD0]);
}
/// variables.h:629 — dma_source_addr_1: (*(uint16*)(g_ram+0xAD2))
pub inline fn dma_source_addr_1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAD2]);
}
/// variables.h:630 — dma_source_addr_5: (*(uint16*)(g_ram+0xAD4))
pub inline fn dma_source_addr_5() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAD4]);
}
/// variables.h:631 — dma_source_addr_2: (*(uint16*)(g_ram+0xAD6))
pub inline fn dma_source_addr_2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAD6]);
}
/// variables.h:632 — dma_source_addr_10: (*(uint16*)(g_ram+0xAD8))
pub inline fn dma_source_addr_10() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAD8]);
}
/// variables.h:633 — dma_source_addr_15: (*(uint16*)(g_ram+0xADA))
pub inline fn dma_source_addr_15() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xADA]);
}
/// variables.h:634 — animated_tile_data_src: (*(uint16*)(g_ram+0xADC))
pub inline fn animated_tile_data_src() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xADC]);
}
/// variables.h:635 — dma_source_addr_9: (*(uint16*)(g_ram+0xAE0))
pub inline fn dma_source_addr_9() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAE0]);
}
/// variables.h:636 — dma_source_addr_14: (*(uint16*)(g_ram+0xAE2))
pub inline fn dma_source_addr_14() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAE2]);
}
/// variables.h:637 — dma_var6: (*(uint16*)(g_ram+0xAE8))
pub inline fn dma_var6() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAE8]);
}
/// variables.h:638 — dma_var7: (*(uint16*)(g_ram+0xAEA))
pub inline fn dma_var7() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAEA]);
}
/// variables.h:639 — dma_source_addr_16: (*(uint16*)(g_ram+0xAEC))
pub inline fn dma_source_addr_16() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAEC]);
}
/// variables.h:640 — dma_source_addr_18: (*(uint16*)(g_ram+0xAEE))
pub inline fn dma_source_addr_18() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAEE]);
}
/// variables.h:641 — dma_source_addr_17: (*(uint16*)(g_ram+0xAF0))
pub inline fn dma_source_addr_17() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAF0]);
}
/// variables.h:642 — dma_source_addr_19: (*(uint16*)(g_ram+0xAF2))
pub inline fn dma_source_addr_19() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAF2]);
}
/// variables.h:643 — flag_travel_bird: (*(uint16*)(g_ram+0xAF4))
pub inline fn flag_travel_bird() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAF4]);
}
/// variables.h:644 — dma_source_addr_20: (*(uint16*)(g_ram+0xAF6))
pub inline fn dma_source_addr_20() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAF6]);
}
/// variables.h:645 — dma_source_addr_21: (*(uint16*)(g_ram+0xAF8))
pub inline fn dma_source_addr_21() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xAF8]);
}
/// variables.h:646 — overlord_type: ((uint8*)(g_ram+0xB00))
pub inline fn overlord_type() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB00]);
}
/// variables.h:647 — overlord_x_lo: ((uint8*)(g_ram+0xB08))
pub inline fn overlord_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB08]);
}
/// variables.h:648 — overlord_x_hi: ((uint8*)(g_ram+0xB10))
pub inline fn overlord_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB10]);
}
/// variables.h:649 — overlord_y_lo: ((uint8*)(g_ram+0xB18))
pub inline fn overlord_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB18]);
}
/// variables.h:650 — overlord_y_hi: ((uint8*)(g_ram+0xB20))
pub inline fn overlord_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB20]);
}
/// variables.h:651 — overlord_gen1: ((uint8*)(g_ram+0xB28))
pub inline fn overlord_gen1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB28]);
}
/// variables.h:652 — overlord_gen2: ((uint8*)(g_ram+0xB30))
pub inline fn overlord_gen2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB30]);
}
/// variables.h:653 — overlord_gen3: ((uint8*)(g_ram+0xB38))
pub inline fn overlord_gen3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB38]);
}
/// variables.h:654 — overlord_floor: ((uint8*)(g_ram+0xB40))
pub inline fn overlord_floor() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB40]);
}
/// variables.h:655 — overlord_offset_sprite_pos: ((uint16*)(g_ram+0xB48))
pub inline fn overlord_offset_sprite_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB48]);
}
/// variables.h:656 — sprite_stunned: ((uint8*)(g_ram+0xB58))
pub inline fn sprite_stunned() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB58]);
}
/// variables.h:657 — repulsespark_floor_status: (*(uint8*)(g_ram+0xB68))
pub inline fn repulsespark_floor_status() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB68]);
}
/// variables.h:658 — byte_7E0B69: (*(uint8*)(g_ram+0xB69))
pub inline fn byte_7E0B69() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB69]);
}
/// variables.h:659 — sprite_limit_instance: (*(uint8*)(g_ram+0xB6A))
pub inline fn sprite_limit_instance() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB6A]);
}
/// variables.h:660 — sprite_flags: ((uint8*)(g_ram+0xB6B))
pub inline fn sprite_flags() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB6B]);
}
/// variables.h:661 — link_prevent_from_moving: (*(uint8*)(g_ram+0xB7B))
pub inline fn link_prevent_from_moving() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB7B]);
}
/// variables.h:662 — drag_player_x: (*(uint16*)(g_ram+0xB7C))
pub inline fn drag_player_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB7C]);
}
/// variables.h:663 — drag_player_y: (*(uint16*)(g_ram+0xB7E))
pub inline fn drag_player_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB7E]);
}
/// variables.h:664 — dungeon_room_history: ((uint16*)(g_ram+0xB80))
pub inline fn dungeon_room_history() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB80]);
}
/// variables.h:665 — byte_7E0B88: (*(uint8*)(g_ram+0xB88))
pub inline fn byte_7E0B88() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB88]);
}
/// variables.h:666 — sprite_obj_prio: ((uint8*)(g_ram+0xB89))
pub inline fn sprite_obj_prio() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB89]);
}
/// variables.h:667 — archery_game_arrows_left: (*(uint8*)(g_ram+0xB99))
pub inline fn archery_game_arrows_left() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB99]);
}
/// variables.h:668 — archery_game_out_of_arrows: (*(uint8*)(g_ram+0xB9A))
pub inline fn archery_game_out_of_arrows() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB9A]);
}
/// variables.h:669 — byte_7E0B9B: (*(uint8*)(g_ram+0xB9B))
pub inline fn byte_7E0B9B() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB9B]);
}
/// variables.h:670 — dung_secrets_unk1: (*(uint16*)(g_ram+0xB9C))
pub inline fn dung_secrets_unk1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xB9C]);
}
/// variables.h:671 — byte_7E0B9E: (*(uint8*)(g_ram+0xB9E))
pub inline fn byte_7E0B9E() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB9E]);
}
/// variables.h:672 — sprite_ignore_projectile: ((uint8*)(g_ram+0xBA0))
pub inline fn sprite_ignore_projectile() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBA0]);
}
/// variables.h:673 — sprite_unk2: ((uint8*)(g_ram+0xBB0))
pub inline fn sprite_unk2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBB0]);
}
/// variables.h:674 — sprite_N: ((uint8*)(g_ram+0xBC0))
pub inline fn sprite_N() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBC0]);
}
/// variables.h:675 — sprite_flags5: ((uint8*)(g_ram+0xBE0))
pub inline fn sprite_flags5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBE0]);
}
/// variables.h:676 — ancilla_arr4: ((uint8*)(g_ram+0xBF0))
pub inline fn ancilla_arr4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBF0]);
}
/// variables.h:677 — ancilla_y_lo: ((uint8*)(g_ram+0xBFA))
pub inline fn ancilla_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xBFA]);
}
/// variables.h:678 — ancilla_x_lo: ((uint8*)(g_ram+0xC04))
pub inline fn ancilla_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC04]);
}
/// variables.h:679 — ancilla_y_hi: ((uint8*)(g_ram+0xC0E))
pub inline fn ancilla_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC0E]);
}
/// variables.h:680 — ancilla_x_hi: ((uint8*)(g_ram+0xC18))
pub inline fn ancilla_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC18]);
}
/// variables.h:681 — ancilla_y_vel: ((uint8*)(g_ram+0xC22))
pub inline fn ancilla_y_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC22]);
}
/// variables.h:682 — ancilla_x_vel: ((uint8*)(g_ram+0xC2C))
pub inline fn ancilla_x_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2C]);
}
/// variables.h:683 — ancilla_y_subpixel: ((uint8*)(g_ram+0xC36))
pub inline fn ancilla_y_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC36]);
}
/// variables.h:684 — ancilla_x_subpixel: ((uint8*)(g_ram+0xC40))
pub inline fn ancilla_x_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC40]);
}
/// variables.h:685 — ancilla_type: ((uint8*)(g_ram+0xC4A))
pub inline fn ancilla_type() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC4A]);
}
/// variables.h:686 — ancilla_step: ((uint8*)(g_ram+0xC54))
pub inline fn ancilla_step() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC54]);
}
/// variables.h:687 — ancilla_item_to_link: ((uint8*)(g_ram+0xC5E))
pub inline fn ancilla_item_to_link() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC5E]);
}
/// variables.h:688 — ancilla_timer: ((uint8*)(g_ram+0xC68))
pub inline fn ancilla_timer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC68]);
}
/// variables.h:689 — ancilla_dir: ((uint8*)(g_ram+0xC72))
pub inline fn ancilla_dir() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC72]);
}
/// variables.h:690 — ancilla_floor: ((uint8*)(g_ram+0xC7C))
pub inline fn ancilla_floor() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC7C]);
}
/// variables.h:691 — ancilla_oam_idx: ((uint8*)(g_ram+0xC86))
pub inline fn ancilla_oam_idx() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC86]);
}
/// variables.h:692 — ancilla_numspr: ((uint8*)(g_ram+0xC90))
pub inline fn ancilla_numspr() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC90]);
}
/// variables.h:693 — sprite_room: ((uint8*)(g_ram+0xC9A))
pub inline fn sprite_room() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC9A]);
}
/// variables.h:694 — sprite_defl_bits: ((uint8*)(g_ram+0xCAA))
pub inline fn sprite_defl_bits() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCAA]);
}
/// variables.h:695 — sprite_die_action: ((uint8*)(g_ram+0xCBA))
pub inline fn sprite_die_action() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCBA]);
}
/// variables.h:696 — overlord_spawned_in_area: ((uint8*)(g_ram+0xCCA))
pub inline fn overlord_spawned_in_area() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCCA]);
}
/// variables.h:697 — sprite_bump_damage: ((uint8*)(g_ram+0xCD2))
pub inline fn sprite_bump_damage() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCD2]);
}
/// variables.h:698 — sprite_give_damage: ((uint8*)(g_ram+0xCE2))
pub inline fn sprite_give_damage() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCE2]);
}
/// variables.h:699 — damage_type_determiner: (*(uint8*)(g_ram+0xCF2))
pub inline fn damage_type_determiner() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF2]);
}
/// variables.h:700 — damage_type_determiner_PADDING: (*(uint8*)(g_ram+0xCF3))
pub inline fn damage_type_determiner_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF3]);
}
/// variables.h:701 — activate_bomb_trap_overlord: (*(uint8*)(g_ram+0xCF4))
pub inline fn activate_bomb_trap_overlord() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF4]);
}
/// variables.h:702 — dungmap_var6: (*(uint16*)(g_ram+0xCF5))
pub inline fn dungmap_var6() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xCF5]);
}
/// variables.h:703 — overworld_secret_subst_ctr: (*(uint8*)(g_ram+0xCF7))
pub inline fn overworld_secret_subst_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF7]);
}
/// variables.h:704 — byte_7E0CF8: (*(uint8*)(g_ram+0xCF8))
pub inline fn byte_7E0CF8() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF8]);
}
/// variables.h:705 — item_drop_luck: (*(uint8*)(g_ram+0xCF9))
pub inline fn item_drop_luck() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCF9]);
}
/// variables.h:706 — luck_kill_counter: (*(uint8*)(g_ram+0xCFA))
pub inline fn luck_kill_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCFA]);
}
/// variables.h:707 — num_sprites_killed: (*(uint8*)(g_ram+0xCFB))
pub inline fn num_sprites_killed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCFB]);
}
/// variables.h:708 — number_of_times_hurt_by_sprites: (*(uint8*)(g_ram+0xCFC))
pub inline fn number_of_times_hurt_by_sprites() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCFC]);
}
/// variables.h:709 — rupee_sfx_sound_delay: (*(uint8*)(g_ram+0xCFD))
pub inline fn rupee_sfx_sound_delay() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCFD]);
}
/// variables.h:710 — word_7E0CFE: (*(uint16*)(g_ram+0xCFE))
pub inline fn word_7E0CFE() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xCFE]);
}
/// variables.h:711 — sprite_y_lo: ((uint8*)(g_ram+0xD00))
pub inline fn sprite_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD00]);
}
/// variables.h:712 — sprite_x_lo: ((uint8*)(g_ram+0xD10))
pub inline fn sprite_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD10]);
}
/// variables.h:713 — sprite_y_hi: ((uint8*)(g_ram+0xD20))
pub inline fn sprite_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD20]);
}
/// variables.h:714 — sprite_x_hi: ((uint8*)(g_ram+0xD30))
pub inline fn sprite_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD30]);
}
/// variables.h:715 — sprite_y_vel: ((uint8*)(g_ram+0xD40))
pub inline fn sprite_y_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD40]);
}
/// variables.h:716 — sprite_x_vel: ((uint8*)(g_ram+0xD50))
pub inline fn sprite_x_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD50]);
}
/// variables.h:717 — sprite_y_subpixel: ((uint8*)(g_ram+0xD60))
pub inline fn sprite_y_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD60]);
}
/// variables.h:718 — sprite_x_subpixel: ((uint8*)(g_ram+0xD70))
pub inline fn sprite_x_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD70]);
}
/// variables.h:719 — sprite_ai_state: ((uint8*)(g_ram+0xD80))
pub inline fn sprite_ai_state() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD80]);
}
/// variables.h:720 — sprite_A: ((uint8*)(g_ram+0xD90))
pub inline fn sprite_A() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xD90]);
}
/// variables.h:721 — sprite_B: ((uint8*)(g_ram+0xDA0))
pub inline fn sprite_B() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDA0]);
}
/// variables.h:722 — sprite_C: ((uint8*)(g_ram+0xDB0))
pub inline fn sprite_C() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDB0]);
}
/// variables.h:723 — sprite_graphics: ((uint8*)(g_ram+0xDC0))
pub inline fn sprite_graphics() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDC0]);
}
/// variables.h:724 — sprite_state: ((uint8*)(g_ram+0xDD0))
pub inline fn sprite_state() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDD0]);
}
/// variables.h:725 — sprite_D: ((uint8*)(g_ram+0xDE0))
pub inline fn sprite_D() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDE0]);
}
/// variables.h:726 — sprite_delay_main: ((uint8*)(g_ram+0xDF0))
pub inline fn sprite_delay_main() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xDF0]);
}
/// variables.h:727 — sprite_delay_aux1: ((uint8*)(g_ram+0xE00))
pub inline fn sprite_delay_aux1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE00]);
}
/// variables.h:728 — sprite_delay_aux2: ((uint8*)(g_ram+0xE10))
pub inline fn sprite_delay_aux2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE10]);
}
/// variables.h:729 — sprite_type: ((uint8*)(g_ram+0xE20))
pub inline fn sprite_type() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE20]);
}
/// variables.h:730 — sprite_subtype: ((uint8*)(g_ram+0xE30))
pub inline fn sprite_subtype() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE30]);
}
/// variables.h:731 — sprite_flags2: ((uint8*)(g_ram+0xE40))
pub inline fn sprite_flags2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE40]);
}
/// variables.h:732 — sprite_health: ((uint8*)(g_ram+0xE50))
pub inline fn sprite_health() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE50]);
}
/// variables.h:733 — sprite_flags3: ((uint8*)(g_ram+0xE60))
pub inline fn sprite_flags3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE60]);
}
/// variables.h:734 — sprite_wallcoll: ((uint8*)(g_ram+0xE70))
pub inline fn sprite_wallcoll() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE70]);
}
/// variables.h:735 — sprite_subtype2: ((uint8*)(g_ram+0xE80))
pub inline fn sprite_subtype2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE80]);
}
/// variables.h:736 — sprite_E: ((uint8*)(g_ram+0xE90))
pub inline fn sprite_E() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE90]);
}
/// variables.h:737 — sprite_F: ((uint8*)(g_ram+0xEA0))
pub inline fn sprite_F() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEA0]);
}
/// variables.h:738 — sprite_head_dir: ((uint8*)(g_ram+0xEB0))
pub inline fn sprite_head_dir() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEB0]);
}
/// variables.h:739 — sprite_anim_clock: ((uint8*)(g_ram+0xEC0))
pub inline fn sprite_anim_clock() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEC0]);
}
/// variables.h:740 — sprite_G: ((uint8*)(g_ram+0xED0))
pub inline fn sprite_G() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xED0]);
}
/// variables.h:741 — sprite_delay_aux3: ((uint8*)(g_ram+0xEE0))
pub inline fn sprite_delay_aux3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEE0]);
}
/// variables.h:742 — sprite_hit_timer: ((uint8*)(g_ram+0xEF0))
pub inline fn sprite_hit_timer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xEF0]);
}
/// variables.h:743 — sprite_pause: ((uint8*)(g_ram+0xF00))
pub inline fn sprite_pause() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF00]);
}
/// variables.h:744 — sprite_delay_aux4: ((uint8*)(g_ram+0xF10))
pub inline fn sprite_delay_aux4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF10]);
}
/// variables.h:745 — sprite_floor: ((uint8*)(g_ram+0xF20))
pub inline fn sprite_floor() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF20]);
}
/// variables.h:746 — sprite_y_recoil: ((uint8*)(g_ram+0xF30))
pub inline fn sprite_y_recoil() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF30]);
}
/// variables.h:747 — sprite_x_recoil: ((uint8*)(g_ram+0xF40))
pub inline fn sprite_x_recoil() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF40]);
}
/// variables.h:748 — sprite_oam_flags: ((uint8*)(g_ram+0xF50))
pub inline fn sprite_oam_flags() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF50]);
}
/// variables.h:749 — sprite_flags4: ((uint8*)(g_ram+0xF60))
pub inline fn sprite_flags4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF60]);
}
/// variables.h:750 — sprite_z: ((uint8*)(g_ram+0xF70))
pub inline fn sprite_z() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF70]);
}
/// variables.h:751 — sprite_z_vel: ((uint8*)(g_ram+0xF80))
pub inline fn sprite_z_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF80]);
}
/// variables.h:752 — sprite_z_subpos: ((uint8*)(g_ram+0xF90))
pub inline fn sprite_z_subpos() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF90]);
}
/// variables.h:753 — cur_object_index: (*(uint8*)(g_ram+0xFA0))
pub inline fn cur_object_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFA0]);
}
/// variables.h:754 — byte_7E0FA1: (*(uint8*)(g_ram+0xFA1))
pub inline fn byte_7E0FA1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFA1]);
}
/// variables.h:755 — sprite_tiletype: (*(uint8*)(g_ram+0xFA5))
pub inline fn sprite_tiletype() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFA5]);
}
/// variables.h:756 — dungmap_var7: (*(uint16*)(g_ram+0xFA8))
pub inline fn dungmap_var7() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFA8]);
}
/// variables.h:757 — dungmap_var8: (*(uint16*)(g_ram+0xFAA))
pub inline fn dungmap_var8() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFAA]);
}
/// variables.h:758 — repulsespark_timer: (*(uint8*)(g_ram+0xFAC))
pub inline fn repulsespark_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFAC]);
}
/// variables.h:759 — repulsespark_x_lo: (*(uint8*)(g_ram+0xFAD))
pub inline fn repulsespark_x_lo() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFAD]);
}
/// variables.h:760 — repulsespark_y_lo: (*(uint8*)(g_ram+0xFAE))
pub inline fn repulsespark_y_lo() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFAE]);
}
/// variables.h:761 — repulsespark_anim_delay: (*(uint8*)(g_ram+0xFAF))
pub inline fn repulsespark_anim_delay() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFAF]);
}
/// variables.h:762 — byte_7E0FB0: (*(uint8*)(g_ram+0xFB0))
pub inline fn byte_7E0FB0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB0]);
}
/// variables.h:763 — byte_7E0FB1: (*(uint8*)(g_ram+0xFB1))
pub inline fn byte_7E0FB1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB1]);
}
/// variables.h:764 — byte_7E0FB2: (*(uint8*)(g_ram+0xFB2))
pub inline fn byte_7E0FB2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB2]);
}
/// variables.h:765 — sort_sprites_setting: (*(uint8*)(g_ram+0xFB3))
pub inline fn sort_sprites_setting() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB3]);
}
/// variables.h:766 — garnish_active: (*(uint8*)(g_ram+0xFB4))
pub inline fn garnish_active() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB4]);
}
/// variables.h:767 — tmp_counter: (*(uint8*)(g_ram+0xFB5))
pub inline fn tmp_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB5]);
}
/// variables.h:768 — byte_7E0FB6: (*(uint8*)(g_ram+0xFB6))
pub inline fn byte_7E0FB6() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB6]);
}
/// variables.h:769 — spr_ranged_based_toggler: (*(uint8*)(g_ram+0xFB7))
pub inline fn spr_ranged_based_toggler() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFB7]);
}
/// variables.h:770 — sprcoll_x_size: (*(uint16*)(g_ram+0xFB8))
pub inline fn sprcoll_x_size() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFB8]);
}
/// variables.h:771 — sprcoll_y_size: (*(uint16*)(g_ram+0xFBA))
pub inline fn sprcoll_y_size() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFBA]);
}
/// variables.h:772 — sprcoll_x_base: (*(uint16*)(g_ram+0xFBC))
pub inline fn sprcoll_x_base() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFBC]);
}
/// variables.h:773 — sprcoll_y_base: (*(uint16*)(g_ram+0xFBE))
pub inline fn sprcoll_y_base() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFBE]);
}
/// variables.h:774 — flag_unk1: (*(uint8*)(g_ram+0xFC1))
pub inline fn flag_unk1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFC1]);
}
/// variables.h:775 — link_x_coord_prev: (*(uint16*)(g_ram+0xFC2))
pub inline fn link_x_coord_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFC2]);
}
/// variables.h:776 — link_y_coord_prev: (*(uint16*)(g_ram+0xFC4))
pub inline fn link_y_coord_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFC4]);
}
/// variables.h:777 — byte_7E0FC6: (*(uint8*)(g_ram+0xFC6))
pub inline fn byte_7E0FC6() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFC6]);
}
/// variables.h:778 — prizes_arr1: ((uint8*)(g_ram+0xFC7))
pub inline fn prizes_arr1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFC7]);
}
/// variables.h:779 — debug_game_frozen: (*(uint8*)(g_ram+0xFD7))
pub inline fn debug_game_frozen() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFD7]);
}
/// variables.h:780 — cur_sprite_x: (*(uint16*)(g_ram+0xFD8))
pub inline fn cur_sprite_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFD8]);
}
/// variables.h:781 — cur_sprite_y: (*(uint16*)(g_ram+0xFDA))
pub inline fn cur_sprite_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFDA]);
}
/// variables.h:782 — sprite_alert_flag: (*(uint8*)(g_ram+0xFDC))
pub inline fn sprite_alert_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFDC]);
}
/// variables.h:783 — byte_7E0FDD: (*(uint8*)(g_ram+0xFDD))
pub inline fn byte_7E0FDD() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFDD]);
}
/// variables.h:784 — byte_7E0FDE: (*(uint8*)(g_ram+0xFDE))
pub inline fn byte_7E0FDE() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFDE]);
}
/// variables.h:785 — oam_region_base: ((uint16*)(g_ram+0xFE0))
pub inline fn oam_region_base() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFE0]);
}
/// variables.h:786 — oam_alloc_arr1: ((uint16*)(g_ram+0xFEC))
pub inline fn oam_alloc_arr1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFEC]);
}
/// variables.h:787 — byte_7E0FF8: (*(uint8*)(g_ram+0xFF8))
pub inline fn byte_7E0FF8() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFF8]);
}
/// variables.h:788 — intro_times_pal_flash: (*(uint8*)(g_ram+0xFF9))
pub inline fn intro_times_pal_flash() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFF9]);
}
/// variables.h:789 — alt_sprites_flag: (*(uint8*)(g_ram+0xFFA))
pub inline fn alt_sprites_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFA]);
}
/// variables.h:790 — byte_7E0FFB: (*(uint8*)(g_ram+0xFFB))
pub inline fn byte_7E0FFB() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFB]);
}
/// variables.h:791 — flag_block_link_menu: (*(uint8*)(g_ram+0xFFC))
pub inline fn flag_block_link_menu() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFC]);
}
/// variables.h:792 — byte_7E0FFD: (*(uint8*)(g_ram+0xFFD))
pub inline fn byte_7E0FFD() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFD]);
}
/// variables.h:793 — byte_7E0FFE: (*(uint8*)(g_ram+0xFFE))
pub inline fn byte_7E0FFE() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFE]);
}
/// variables.h:794 — is_in_dark_world: (*(uint8*)(g_ram+0xFFF))
pub inline fn is_in_dark_world() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFFF]);
}
/// variables.h:795 — word_7E1800: (*(uint16*)(g_ram+0x1800))
pub inline fn word_7E1800() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1800]);
}
/// variables.h:796 — word_7E1806: (*(uint16*)(g_ram+0x1806))
pub inline fn word_7E1806() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1806]);
}
/// variables.h:797 — word_7E197E: (*(uint16*)(g_ram+0x197E))
pub inline fn word_7E197E() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x197E]);
}
/// variables.h:798 — door_type_and_slot: ((uint16*)(g_ram+0x1980))
pub inline fn door_type_and_slot() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1980]);
}
/// variables.h:799 — dung_door_tilemap_address: ((uint16*)(g_ram+0x19A0))
pub inline fn dung_door_tilemap_address() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19A0]);
}
/// variables.h:800 — dung_door_direction: ((uint16*)(g_ram+0x19C0))
pub inline fn dung_door_direction() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19C0]);
}
/// variables.h:801 — dung_exit_door_count: (*(uint16*)(g_ram+0x19E0))
pub inline fn dung_exit_door_count() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19E0]);
}
/// variables.h:802 — dung_exit_door_addresses: ((uint16*)(g_ram+0x19E2))
pub inline fn dung_exit_door_addresses() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19E2]);
}
/// variables.h:803 — tagalong_y_lo: ((uint8*)(g_ram+0x1A00))
pub inline fn tagalong_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A00]);
}
/// variables.h:804 — tagalong_y_hi: ((uint8*)(g_ram+0x1A14))
pub inline fn tagalong_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A14]);
}
/// variables.h:805 — tagalong_x_lo: ((uint8*)(g_ram+0x1A28))
pub inline fn tagalong_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A28]);
}
/// variables.h:806 — tagalong_x_hi: ((uint8*)(g_ram+0x1A3C))
pub inline fn tagalong_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A3C]);
}
/// variables.h:807 — tagalong_z: ((uint8*)(g_ram+0x1A50))
pub inline fn tagalong_z() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A50]);
}
/// variables.h:808 — tagalong_layerbits: ((uint8*)(g_ram+0x1A64))
pub inline fn tagalong_layerbits() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1A64]);
}
/// variables.h:809 — bird_travel_x_lo: ((uint8*)(g_ram+0x1AB0))
pub inline fn bird_travel_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1AB0]);
}
/// variables.h:810 — bird_travel_x_hi: ((uint8*)(g_ram+0x1AC0))
pub inline fn bird_travel_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1AC0]);
}
/// variables.h:811 — bird_travel_y_lo: ((uint8*)(g_ram+0x1AD0))
pub inline fn bird_travel_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1AD0]);
}
/// variables.h:812 — bird_travel_y_hi: ((uint8*)(g_ram+0x1AE0))
pub inline fn bird_travel_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1AE0]);
}
/// variables.h:813 — birdtravel_var1: ((uint8*)(g_ram+0x1AF0))
pub inline fn birdtravel_var1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1AF0]);
}
/// variables.h:814 — text_msgbox_topleft_copy: (*(uint16*)(g_ram+0x1CD0))
pub inline fn text_msgbox_topleft_copy() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CD0]);
}
/// variables.h:815 — text_msgbox_topleft: (*(uint16*)(g_ram+0x1CD2))
pub inline fn text_msgbox_topleft() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CD2]);
}
/// variables.h:816 — text_render_state: (*(uint8*)(g_ram+0x1CD4))
pub inline fn text_render_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CD4]);
}
/// variables.h:817 — vwf_line_speed_cur: (*(uint8*)(g_ram+0x1CD5))
pub inline fn vwf_line_speed_cur() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CD5]);
}
/// variables.h:818 — vwf_line_speed: (*(uint8*)(g_ram+0x1CD6))
pub inline fn vwf_line_speed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CD6]);
}
/// variables.h:819 — text_incremental_state: (*(uint8*)(g_ram+0x1CD7))
pub inline fn text_incremental_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CD7]);
}
/// variables.h:820 — messaging_module: (*(uint8*)(g_ram+0x1CD8))
pub inline fn messaging_module() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CD8]);
}
/// variables.h:821 — dialogue_msg_read_pos: (*(uint16*)(g_ram+0x1CD9))
pub inline fn dialogue_msg_read_pos() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CD9]);
}
/// variables.h:822 — dialogue_text_color: (*(uint8*)(g_ram+0x1CDC))
pub inline fn dialogue_text_color() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CDC]);
}
/// variables.h:823 — dialogue_msg_src_offs: (*(uint16*)(g_ram+0x1CDD))
pub inline fn dialogue_msg_src_offs() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CDD]);
}
/// variables.h:824 — byte_7E1CDF: (*(uint8*)(g_ram+0x1CDF))
pub inline fn byte_7E1CDF() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CDF]);
}
/// variables.h:825 — text_wait_countdown: (*(uint16*)(g_ram+0x1CE0))
pub inline fn text_wait_countdown() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CE0]);
}
/// variables.h:826 — text_tilemap_cur: (*(uint16*)(g_ram+0x1CE2))
pub inline fn text_tilemap_cur() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CE2]);
}
/// variables.h:827 — text_next_position: (*(uint8*)(g_ram+0x1CE6))
pub inline fn text_next_position() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CE6]);
}
/// variables.h:828 — choice_in_multiselect_box: (*(uint8*)(g_ram+0x1CE8))
pub inline fn choice_in_multiselect_box() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CE8]);
}
/// variables.h:829 — text_wait_countdown2: (*(uint8*)(g_ram+0x1CE9))
pub inline fn text_wait_countdown2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CE9]);
}
/// variables.h:832 — dialogue_scroll_speed: (*(uint8*)(g_ram+0x1CEA))
pub inline fn dialogue_scroll_speed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CEA]);
}
/// variables.h:833 — dialogue_message_index: (*(uint16*)(g_ram+0x1CF0))
pub inline fn dialogue_message_index() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1CF0]);
}
/// variables.h:834 — dialogue_number: ((uint8*)(g_ram+0x1CF2))
pub inline fn dialogue_number() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CF2]);
}
/// variables.h:835 — choice_in_multiselect_box_bak: (*(uint8*)(g_ram+0x1CF4))
pub inline fn choice_in_multiselect_box_bak() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1CF4]);
}
/// variables.h:836 — alt_sprite_state: ((uint8*)(g_ram+0x1D00))
pub inline fn alt_sprite_state() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D00]);
}
/// variables.h:837 — alt_sprite_type: ((uint8*)(g_ram+0x1D10))
pub inline fn alt_sprite_type() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D10]);
}
/// variables.h:838 — alt_sprite_x_lo: ((uint8*)(g_ram+0x1D20))
pub inline fn alt_sprite_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D20]);
}
/// variables.h:839 — alt_sprite_x_hi: ((uint8*)(g_ram+0x1D30))
pub inline fn alt_sprite_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D30]);
}
/// variables.h:840 — alt_sprite_y_lo: ((uint8*)(g_ram+0x1D40))
pub inline fn alt_sprite_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D40]);
}
/// variables.h:841 — alt_sprite_y_hi: ((uint8*)(g_ram+0x1D50))
pub inline fn alt_sprite_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D50]);
}
/// variables.h:842 — alt_sprite_graphics: ((uint8*)(g_ram+0x1D60))
pub inline fn alt_sprite_graphics() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D60]);
}
/// variables.h:843 — alt_sprite_A: ((uint8*)(g_ram+0x1D70))
pub inline fn alt_sprite_A() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D70]);
}
/// variables.h:844 — alt_sprite_head_dir: ((uint8*)(g_ram+0x1D80))
pub inline fn alt_sprite_head_dir() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D80]);
}
/// variables.h:845 — alt_sprite_oam_flags: ((uint8*)(g_ram+0x1D90))
pub inline fn alt_sprite_oam_flags() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1D90]);
}
/// variables.h:846 — alt_sprite_obj_prio: ((uint8*)(g_ram+0x1DA0))
pub inline fn alt_sprite_obj_prio() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DA0]);
}
/// variables.h:847 — alt_sprite_D: ((uint8*)(g_ram+0x1DB0))
pub inline fn alt_sprite_D() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DB0]);
}
/// variables.h:848 — alt_sprite_flags2: ((uint8*)(g_ram+0x1DC0))
pub inline fn alt_sprite_flags2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DC0]);
}
/// variables.h:849 — alt_sprite_floor: ((uint8*)(g_ram+0x1DD0))
pub inline fn alt_sprite_floor() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DD0]);
}
/// variables.h:850 — alt_sprite_spawned_flag: ((uint8*)(g_ram+0x1DE0))
pub inline fn alt_sprite_spawned_flag() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DE0]);
}
/// variables.h:851 — alt_sprite_flags3: ((uint8*)(g_ram+0x1DF0))
pub inline fn alt_sprite_flags3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DF0]);
}
/// variables.h:852 — intro_step_index: (*(uint8*)(g_ram+0x1E00))
pub inline fn intro_step_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E00]);
}
/// variables.h:853 — intro_step_timer: (*(uint8*)(g_ram+0x1E01))
pub inline fn intro_step_timer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E01]);
}
/// variables.h:854 — intro_want_double_ret: (*(uint8*)(g_ram+0x1E02))
pub inline fn intro_want_double_ret() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E02]);
}
/// variables.h:855 — intro_sprite_alloc: (*(uint16*)(g_ram+0x1E08))
pub inline fn intro_sprite_alloc() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1E08]);
}
/// variables.h:856 — intro_frame_ctr: (*(uint8*)(g_ram+0x1E0A))
pub inline fn intro_frame_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E0A]);
}
/// variables.h:857 — triforce_ctr: (*(uint16*)(g_ram+0x1E0C))
pub inline fn triforce_ctr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1E0C]);
}
/// variables.h:858 — intro_sprite_isinited: ((uint8*)(g_ram+0x1E10))
pub inline fn intro_sprite_isinited() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E10]);
}
/// variables.h:859 — intro_sprite_subtype: ((uint8*)(g_ram+0x1E18))
pub inline fn intro_sprite_subtype() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E18]);
}
/// variables.h:860 — intro_sprite_state: ((uint8*)(g_ram+0x1E20))
pub inline fn intro_sprite_state() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E20]);
}
/// variables.h:861 — intro_x_subpixel: ((uint8*)(g_ram+0x1E28))
pub inline fn intro_x_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E28]);
}
/// variables.h:862 — intro_x_lo: ((uint8*)(g_ram+0x1E30))
pub inline fn intro_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E30]);
}
/// variables.h:863 — intro_x_hi: ((uint8*)(g_ram+0x1E38))
pub inline fn intro_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E38]);
}
/// variables.h:864 — intro_y_subpixel: ((uint8*)(g_ram+0x1E40))
pub inline fn intro_y_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E40]);
}
/// variables.h:865 — intro_y_lo: ((uint8*)(g_ram+0x1E48))
pub inline fn intro_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E48]);
}
/// variables.h:866 — intro_y_hi: ((uint8*)(g_ram+0x1E50))
pub inline fn intro_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E50]);
}
/// variables.h:867 — intro_x_vel: ((uint8*)(g_ram+0x1E58))
pub inline fn intro_x_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E58]);
}
/// variables.h:868 — intro_y_vel: ((uint8*)(g_ram+0x1E60))
pub inline fn intro_y_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1E60]);
}
/// variables.h:869 — intro_did_run_step: (*(uint8*)(g_ram+0x1F00))
pub inline fn intro_did_run_step() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F00]);
}
/// variables.h:870 — poly_config_color_mode: (*(uint8*)(g_ram+0x1F01))
pub inline fn poly_config_color_mode() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F01]);
}
/// variables.h:871 — poly_config1: (*(uint8*)(g_ram+0x1F02))
pub inline fn poly_config1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F02]);
}
/// variables.h:872 — poly_which_model: (*(uint8*)(g_ram+0x1F03))
pub inline fn poly_which_model() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F03]);
}
/// variables.h:873 — poly_a: (*(uint8*)(g_ram+0x1F04))
pub inline fn poly_a() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F04]);
}
/// variables.h:874 — poly_b: (*(uint8*)(g_ram+0x1F05))
pub inline fn poly_b() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F05]);
}
/// variables.h:875 — poly_base_x: (*(uint8*)(g_ram+0x1F06))
pub inline fn poly_base_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F06]);
}
/// variables.h:876 — poly_base_y: (*(uint8*)(g_ram+0x1F07))
pub inline fn poly_base_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F07]);
}
/// variables.h:877 — poly_var1: (*(uint16*)(g_ram+0x1F08))
pub inline fn poly_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F08]);
}
/// variables.h:878 — thread_other_stack: (*(uint16*)(g_ram+0x1F0A))
pub inline fn thread_other_stack() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F0A]);
}
/// variables.h:879 — nmi_flag_update_polyhedral: (*(uint8*)(g_ram+0x1F0C))
pub inline fn nmi_flag_update_polyhedral() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F0C]);
}
/// variables.h:880 — poly_config_num_vertex: (*(uint8*)(g_ram+0x1F3F))
pub inline fn poly_config_num_vertex() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F3F]);
}
/// variables.h:881 — poly_config_num_polys: (*(uint8*)(g_ram+0x1F40))
pub inline fn poly_config_num_polys() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F40]);
}
/// variables.h:882 — poly_fromlut_ptr2: (*(uint16*)(g_ram+0x1F41))
pub inline fn poly_fromlut_ptr2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F41]);
}
/// variables.h:883 — poly_fromlut_ptr4: (*(uint16*)(g_ram+0x1F43))
pub inline fn poly_fromlut_ptr4() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F43]);
}
/// variables.h:884 — poly_fromlut_z: (*(uint8*)(g_ram+0x1F45))
pub inline fn poly_fromlut_z() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F45]);
}
/// variables.h:885 — poly_fromlut_y: (*(uint8*)(g_ram+0x1F46))
pub inline fn poly_fromlut_y() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F46]);
}
/// variables.h:886 — poly_fromlut_x: (*(uint8*)(g_ram+0x1F47))
pub inline fn poly_fromlut_x() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F47]);
}
/// variables.h:887 — poly_f0: (*(uint16*)(g_ram+0x1F48))
pub inline fn poly_f0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F48]);
}
/// variables.h:888 — poly_f1: (*(uint16*)(g_ram+0x1F4A))
pub inline fn poly_f1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F4A]);
}
/// variables.h:889 — poly_f2: (*(uint16*)(g_ram+0x1F4C))
pub inline fn poly_f2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F4C]);
}
/// variables.h:890 — poly_num_vertex_in_poly: (*(uint8*)(g_ram+0x1F4E))
pub inline fn poly_num_vertex_in_poly() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F4E]);
}
/// variables.h:891 — poly_raster_color_config: (*(uint8*)(g_ram+0x1F4F))
pub inline fn poly_raster_color_config() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F4F]);
}
/// variables.h:892 — poly_sin_a: (*(uint16*)(g_ram+0x1F50))
pub inline fn poly_sin_a() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F50]);
}
/// variables.h:893 — poly_cos_a: (*(uint16*)(g_ram+0x1F52))
pub inline fn poly_cos_a() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F52]);
}
/// variables.h:894 — poly_sin_b: (*(uint16*)(g_ram+0x1F54))
pub inline fn poly_sin_b() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F54]);
}
/// variables.h:895 — poly_cos_b: (*(uint16*)(g_ram+0x1F56))
pub inline fn poly_cos_b() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F56]);
}
/// variables.h:896 — poly_e0: (*(uint16*)(g_ram+0x1F58))
pub inline fn poly_e0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F58]);
}
/// variables.h:897 — poly_e2: (*(uint16*)(g_ram+0x1F5A))
pub inline fn poly_e2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F5A]);
}
/// variables.h:898 — poly_e3: (*(uint16*)(g_ram+0x1F5C))
pub inline fn poly_e3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F5C]);
}
/// variables.h:899 — poly_e1: (*(uint16*)(g_ram+0x1F5E))
pub inline fn poly_e1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1F5E]);
}
/// variables.h:900 — poly_arr_x: ((uint8*)(g_ram+0x1F60))
pub inline fn poly_arr_x() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F60]);
}
/// variables.h:901 — poly_arr_y: ((uint8*)(g_ram+0x1F88))
pub inline fn poly_arr_y() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F88]);
}
/// variables.h:902 — poly_tmp0: (*(uint16*)(g_ram+0x1FB0))
pub inline fn poly_tmp0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FB0]);
}
/// variables.h:903 — poly_tmp1: (*(uint16*)(g_ram+0x1FB2))
pub inline fn poly_tmp1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FB2]);
}
/// variables.h:904 — poly_raster_color0: (*(uint16*)(g_ram+0x1FB5))
pub inline fn poly_raster_color0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FB5]);
}
/// variables.h:905 — poly_raster_color1: (*(uint16*)(g_ram+0x1FB7))
pub inline fn poly_raster_color1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FB7]);
}
/// variables.h:906 — poly_raster_dst_ptr: (*(uint16*)(g_ram+0x1FB9))
pub inline fn poly_raster_dst_ptr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FB9]);
}
/// variables.h:907 — poly_tmp2: (*(uint8*)(g_ram+0x1FBC))
pub inline fn poly_tmp2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FBC]);
}
/// variables.h:908 — poly_arr_xy_coords_minus1: (*(uint8*)(g_ram+0x1FBF))
pub inline fn poly_arr_xy_coords_minus1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FBF]);
}
/// variables.h:909 — poly_xy_coords: ((uint8*)(g_ram+0x1FC0))
pub inline fn poly_xy_coords() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FC0]);
}
/// variables.h:910 — poly_total_num_steps: (*(uint8*)(g_ram+0x1FE0))
pub inline fn poly_total_num_steps() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE0]);
}
/// variables.h:911 — poly_x0_cur: (*(uint8*)(g_ram+0x1FE1))
pub inline fn poly_x0_cur() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE1]);
}
/// variables.h:912 — poly_y0_cur: (*(uint8*)(g_ram+0x1FE2))
pub inline fn poly_y0_cur() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE2]);
}
/// variables.h:913 — poly_x0_target: (*(uint8*)(g_ram+0x1FE3))
pub inline fn poly_x0_target() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE3]);
}
/// variables.h:914 — poly_y0_trig: (*(uint8*)(g_ram+0x1FE4))
pub inline fn poly_y0_trig() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE4]);
}
/// variables.h:915 — poly_x0_frac: (*(uint16*)(g_ram+0x1FE5))
pub inline fn poly_x0_frac() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FE5]);
}
/// variables.h:916 — poly_x0_step: (*(uint16*)(g_ram+0x1FE7))
pub inline fn poly_x0_step() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FE7]);
}
/// variables.h:917 — poly_cur_vertex_idx0: (*(uint8*)(g_ram+0x1FE9))
pub inline fn poly_cur_vertex_idx0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE9]);
}
/// variables.h:918 — poly_x1_cur: (*(uint8*)(g_ram+0x1FEA))
pub inline fn poly_x1_cur() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FEA]);
}
/// variables.h:919 — poly_y1_cur: (*(uint8*)(g_ram+0x1FEB))
pub inline fn poly_y1_cur() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FEB]);
}
/// variables.h:920 — poly_x1_target: (*(uint8*)(g_ram+0x1FEC))
pub inline fn poly_x1_target() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FEC]);
}
/// variables.h:921 — poly_y1_trig: (*(uint8*)(g_ram+0x1FED))
pub inline fn poly_y1_trig() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FED]);
}
/// variables.h:922 — poly_x1_frac: (*(uint16*)(g_ram+0x1FEE))
pub inline fn poly_x1_frac() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FEE]);
}
/// variables.h:923 — poly_x1_step: (*(uint16*)(g_ram+0x1FF0))
pub inline fn poly_x1_step() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FF0]);
}
/// variables.h:924 — poly_cur_vertex_idx1: (*(uint8*)(g_ram+0x1FF2))
pub inline fn poly_cur_vertex_idx1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FF2]);
}
/// variables.h:925 — poly_raster_numfull: (*(uint16*)(g_ram+0x1FFA))
pub inline fn poly_raster_numfull() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FFA]);
}
/// variables.h:926 — dung_bg2: ((uint16*)(g_ram+0x2000))
pub inline fn dung_bg2() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2000]);
}
/// variables.h:927 — dung_bg1: ((uint16*)(g_ram+0x4000))
pub inline fn dung_bg1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x4000]);
}
/// variables.h:928 — word_7E6000: (*(uint16*)(g_ram+0x6000))
pub inline fn word_7E6000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6000]);
}
/// variables.h:929 — word_7E8000: (*(uint16*)(g_ram+0x8000))
pub inline fn word_7E8000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x8000]);
}
/// variables.h:930 — dung_hdr_travel_destinations: ((uint8*)(g_ram+0xC000))
pub inline fn dung_hdr_travel_destinations() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC000]);
}
/// variables.h:931 — dung_want_lights_out: (*(uint8*)(g_ram+0xC005))
pub inline fn dung_want_lights_out() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC005]);
}
/// variables.h:932 — dung_want_lights_out_copy: (*(uint8*)(g_ram+0xC006))
pub inline fn dung_want_lights_out_copy() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC006]);
}
/// variables.h:933 — palette_filter_countdown: (*(uint16*)(g_ram+0xC007))
pub inline fn palette_filter_countdown() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC007]);
}
/// variables.h:934 — darkening_or_lightening_screen: (*(uint16*)(g_ram+0xC009))
pub inline fn darkening_or_lightening_screen() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC009]);
}
/// variables.h:935 — mosaic_target_level: (*(uint8*)(g_ram+0xC00B))
pub inline fn mosaic_target_level() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC00B]);
}
/// variables.h:936 — mosaic_target_level_PADDING: (*(uint8*)(g_ram+0xC00C))
pub inline fn mosaic_target_level_PADDING() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC00C]);
}
/// variables.h:937 — bg_tile_animation_countdown: (*(uint16*)(g_ram+0xC00D))
pub inline fn bg_tile_animation_countdown() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC00D]);
}
/// variables.h:938 — word_7EC00F: (*(uint16*)(g_ram+0xC00F))
pub inline fn word_7EC00F() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC00F]);
}
/// variables.h:939 — mosaic_level: (*(uint8*)(g_ram+0xC011))
pub inline fn mosaic_level() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC011]);
}
/// variables.h:940 — word_7EC013: (*(uint16*)(g_ram+0xC013))
pub inline fn word_7EC013() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC013]);
}
/// variables.h:941 — word_7EC015: (*(uint16*)(g_ram+0xC015))
pub inline fn word_7EC015() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC015]);
}
/// variables.h:942 — overworld_fixed_color_plusminus: (*(uint8*)(g_ram+0xC017))
pub inline fn overworld_fixed_color_plusminus() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC017]);
}
/// variables.h:943 — agahnim_pal_setting: ((uint16*)(g_ram+0xC019))
pub inline fn agahnim_pal_setting() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC019]);
}
/// variables.h:944 — overworld_area_index_spexit: (*(uint16*)(g_ram+0xC100))
pub inline fn overworld_area_index_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC100]);
}
/// variables.h:945 — TM_copy_spexit: (*(uint8*)(g_ram+0xC102))
pub inline fn TM_copy_spexit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC102]);
}
/// variables.h:946 — BG2VOFS_copy2_spexit: (*(uint16*)(g_ram+0xC104))
pub inline fn BG2VOFS_copy2_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC104]);
}
/// variables.h:947 — BG2HOFS_copy2_spexit: (*(uint16*)(g_ram+0xC106))
pub inline fn BG2HOFS_copy2_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC106]);
}
/// variables.h:948 — link_y_coord_spexit: (*(uint16*)(g_ram+0xC108))
pub inline fn link_y_coord_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC108]);
}
/// variables.h:949 — link_x_coord_spexit: (*(uint16*)(g_ram+0xC10A))
pub inline fn link_x_coord_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC10A]);
}
/// variables.h:950 — overworld_screen_index_spexit: (*(uint16*)(g_ram+0xC10C))
pub inline fn overworld_screen_index_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC10C]);
}
/// variables.h:951 — map16_load_src_off_spexit: (*(uint16*)(g_ram+0xC10E))
pub inline fn map16_load_src_off_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC10E]);
}
/// variables.h:952 — camera_y_coord_scroll_low_spexit: (*(uint16*)(g_ram+0xC110))
pub inline fn camera_y_coord_scroll_low_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC110]);
}
/// variables.h:953 — camera_x_coord_scroll_low_spexit: (*(uint16*)(g_ram+0xC112))
pub inline fn camera_x_coord_scroll_low_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC112]);
}
/// variables.h:954 — room_scroll_vars0_ystart_spexit: (*(uint16*)(g_ram+0xC114))
pub inline fn room_scroll_vars0_ystart_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC114]);
}
/// variables.h:955 — room_scroll_vars0_yend_spexit: (*(uint16*)(g_ram+0xC116))
pub inline fn room_scroll_vars0_yend_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC116]);
}
/// variables.h:956 — room_scroll_vars0_xstart_spexit: (*(uint16*)(g_ram+0xC118))
pub inline fn room_scroll_vars0_xstart_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC118]);
}
/// variables.h:957 — room_scroll_vars0_xend_spexit: (*(uint16*)(g_ram+0xC11A))
pub inline fn room_scroll_vars0_xend_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC11A]);
}
/// variables.h:958 — up_down_scroll_target_spexit: (*(uint16*)(g_ram+0xC11C))
pub inline fn up_down_scroll_target_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC11C]);
}
/// variables.h:959 — up_down_scroll_target_end_spexit: (*(uint16*)(g_ram+0xC11E))
pub inline fn up_down_scroll_target_end_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC11E]);
}
/// variables.h:960 — left_right_scroll_target_spexit: (*(uint16*)(g_ram+0xC120))
pub inline fn left_right_scroll_target_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC120]);
}
/// variables.h:961 — left_right_scroll_target_end_spexit: (*(uint16*)(g_ram+0xC122))
pub inline fn left_right_scroll_target_end_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC122]);
}
/// variables.h:962 — byte_7EC124: (*(uint8*)(g_ram+0xC124))
pub inline fn byte_7EC124() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC124]);
}
/// variables.h:963 — main_tile_theme_index_spexit: (*(uint8*)(g_ram+0xC125))
pub inline fn main_tile_theme_index_spexit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC125]);
}
/// variables.h:964 — aux_tile_theme_index_spexit: (*(uint8*)(g_ram+0xC126))
pub inline fn aux_tile_theme_index_spexit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC126]);
}
/// variables.h:965 — sprite_graphics_index_spexit: (*(uint8*)(g_ram+0xC127))
pub inline fn sprite_graphics_index_spexit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC127]);
}
/// variables.h:966 — overworld_unk1_spexit: (*(uint16*)(g_ram+0xC12A))
pub inline fn overworld_unk1_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC12A]);
}
/// variables.h:967 — overworld_unk1_neg_spexit: (*(uint16*)(g_ram+0xC12C))
pub inline fn overworld_unk1_neg_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC12C]);
}
/// variables.h:968 — overworld_unk3_spexit: (*(uint16*)(g_ram+0xC12E))
pub inline fn overworld_unk3_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC12E]);
}
/// variables.h:969 — overworld_unk3_neg_spexit: (*(uint16*)(g_ram+0xC130))
pub inline fn overworld_unk3_neg_spexit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC130]);
}
/// variables.h:970 — overworld_area_index_exit: (*(uint16*)(g_ram+0xC140))
pub inline fn overworld_area_index_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC140]);
}
/// variables.h:971 — TM_copy_exit: (*(uint16*)(g_ram+0xC142))
pub inline fn TM_copy_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC142]);
}
/// variables.h:972 — BG2VOFS_copy2_exit: (*(uint16*)(g_ram+0xC144))
pub inline fn BG2VOFS_copy2_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC144]);
}
/// variables.h:973 — BG2HOFS_copy2_exit: (*(uint16*)(g_ram+0xC146))
pub inline fn BG2HOFS_copy2_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC146]);
}
/// variables.h:974 — link_y_coord_exit: (*(uint16*)(g_ram+0xC148))
pub inline fn link_y_coord_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC148]);
}
/// variables.h:975 — link_x_coord_exit: (*(uint16*)(g_ram+0xC14A))
pub inline fn link_x_coord_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC14A]);
}
/// variables.h:976 — overworld_screen_index_exit: (*(uint16*)(g_ram+0xC14C))
pub inline fn overworld_screen_index_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC14C]);
}
/// variables.h:977 — map16_load_src_off_exit: (*(uint16*)(g_ram+0xC14E))
pub inline fn map16_load_src_off_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC14E]);
}
/// variables.h:978 — camera_y_coord_scroll_low_exit: (*(uint16*)(g_ram+0xC150))
pub inline fn camera_y_coord_scroll_low_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC150]);
}
/// variables.h:979 — camera_x_coord_scroll_low_exit: (*(uint16*)(g_ram+0xC152))
pub inline fn camera_x_coord_scroll_low_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC152]);
}
/// variables.h:980 — up_down_scroll_target_exit: (*(uint16*)(g_ram+0xC15C))
pub inline fn up_down_scroll_target_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC15C]);
}
/// variables.h:981 — up_down_scroll_target_end_exit: (*(uint16*)(g_ram+0xC15E))
pub inline fn up_down_scroll_target_end_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC15E]);
}
/// variables.h:982 — left_right_scroll_target_exit: (*(uint16*)(g_ram+0xC160))
pub inline fn left_right_scroll_target_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC160]);
}
/// variables.h:983 — left_right_scroll_target_end_exit: (*(uint16*)(g_ram+0xC162))
pub inline fn left_right_scroll_target_end_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC162]);
}
/// variables.h:984 — byte_7EC164: (*(uint8*)(g_ram+0xC164))
pub inline fn byte_7EC164() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC164]);
}
/// variables.h:985 — main_tile_theme_index_exit: (*(uint8*)(g_ram+0xC165))
pub inline fn main_tile_theme_index_exit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC165]);
}
/// variables.h:986 — aux_tile_theme_index_exit: (*(uint8*)(g_ram+0xC166))
pub inline fn aux_tile_theme_index_exit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC166]);
}
/// variables.h:987 — sprite_graphics_index_exit: (*(uint8*)(g_ram+0xC167))
pub inline fn sprite_graphics_index_exit() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC167]);
}
/// variables.h:988 — overworld_unk1_exit: (*(uint16*)(g_ram+0xC16A))
pub inline fn overworld_unk1_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC16A]);
}
/// variables.h:989 — overworld_unk1_neg_exit: (*(uint16*)(g_ram+0xC16C))
pub inline fn overworld_unk1_neg_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC16C]);
}
/// variables.h:990 — overworld_unk3_exit: (*(uint16*)(g_ram+0xC16E))
pub inline fn overworld_unk3_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC16E]);
}
/// variables.h:991 — overworld_unk3_neg_exit: (*(uint16*)(g_ram+0xC170))
pub inline fn overworld_unk3_neg_exit() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC170]);
}
/// variables.h:992 — orange_blue_barrier_state: (*(uint16*)(g_ram+0xC172))
pub inline fn orange_blue_barrier_state() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC172]);
}
/// variables.h:993 — word_7EC174: (*(uint16*)(g_ram+0xC174))
pub inline fn word_7EC174() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC174]);
}
/// variables.h:994 — word_7EC176: (*(uint16*)(g_ram+0xC176))
pub inline fn word_7EC176() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC176]);
}
/// variables.h:995 — BG2HOFS_copy2_cached: (*(uint16*)(g_ram+0xC180))
pub inline fn BG2HOFS_copy2_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC180]);
}
/// variables.h:996 — BG2VOFS_copy2_cached: (*(uint16*)(g_ram+0xC182))
pub inline fn BG2VOFS_copy2_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC182]);
}
/// variables.h:997 — link_y_coord_cached: (*(uint16*)(g_ram+0xC184))
pub inline fn link_y_coord_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC184]);
}
/// variables.h:998 — link_x_coord_cached: (*(uint16*)(g_ram+0xC186))
pub inline fn link_x_coord_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC186]);
}
/// variables.h:999 — room_scroll_vars_y_vofs1_cached: (*(uint16*)(g_ram+0xC188))
pub inline fn room_scroll_vars_y_vofs1_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC188]);
}
/// variables.h:1000 — room_scroll_vars_y_vofs2_cached: (*(uint16*)(g_ram+0xC18A))
pub inline fn room_scroll_vars_y_vofs2_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC18A]);
}
/// variables.h:1001 — room_scroll_vars_x_vofs1_cached: (*(uint16*)(g_ram+0xC18C))
pub inline fn room_scroll_vars_x_vofs1_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC18C]);
}
/// variables.h:1002 — room_scroll_vars_x_vofs2_cached: (*(uint16*)(g_ram+0xC18E))
pub inline fn room_scroll_vars_x_vofs2_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC18E]);
}
/// variables.h:1003 — up_down_scroll_target_cached: (*(uint16*)(g_ram+0xC190))
pub inline fn up_down_scroll_target_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC190]);
}
/// variables.h:1004 — up_down_scroll_target_end_cached: (*(uint16*)(g_ram+0xC192))
pub inline fn up_down_scroll_target_end_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC192]);
}
/// variables.h:1005 — left_right_scroll_target_cached: (*(uint16*)(g_ram+0xC194))
pub inline fn left_right_scroll_target_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC194]);
}
/// variables.h:1006 — left_right_scroll_target_end_cached: (*(uint16*)(g_ram+0xC196))
pub inline fn left_right_scroll_target_end_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC196]);
}
/// variables.h:1007 — camera_y_coord_scroll_low_cached: (*(uint16*)(g_ram+0xC198))
pub inline fn camera_y_coord_scroll_low_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC198]);
}
/// variables.h:1008 — camera_x_coord_scroll_low_cached: (*(uint16*)(g_ram+0xC19A))
pub inline fn camera_x_coord_scroll_low_cached() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC19A]);
}
/// variables.h:1009 — quadrant_fullsize_x_cached: (*(uint8*)(g_ram+0xC19C))
pub inline fn quadrant_fullsize_x_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC19C]);
}
/// variables.h:1010 — quadrant_fullsize_y_cached: (*(uint8*)(g_ram+0xC19D))
pub inline fn quadrant_fullsize_y_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC19D]);
}
/// variables.h:1011 — link_quadrant_x_cached: (*(uint8*)(g_ram+0xC19E))
pub inline fn link_quadrant_x_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC19E]);
}
/// variables.h:1012 — link_quadrant_y_cached: (*(uint8*)(g_ram+0xC19F))
pub inline fn link_quadrant_y_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC19F]);
}
/// variables.h:1013 — link_direction_facing_cached: (*(uint8*)(g_ram+0xC1A6))
pub inline fn link_direction_facing_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC1A6]);
}
/// variables.h:1014 — link_is_on_lower_level_cached: (*(uint8*)(g_ram+0xC1A7))
pub inline fn link_is_on_lower_level_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC1A7]);
}
/// variables.h:1015 — link_is_on_lower_level_mirror_cached: (*(uint8*)(g_ram+0xC1A8))
pub inline fn link_is_on_lower_level_mirror_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC1A8]);
}
/// variables.h:1016 — is_standing_in_doorway_cahed: (*(uint8*)(g_ram+0xC1A9))
pub inline fn is_standing_in_doorway_cahed() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC1A9]);
}
/// variables.h:1017 — dung_cur_floor_cached: (*(uint8*)(g_ram+0xC1AA))
pub inline fn dung_cur_floor_cached() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC1AA]);
}
/// variables.h:1018 — mapbak_BG1HOFS_copy2: (*(uint16*)(g_ram+0xC200))
pub inline fn mapbak_BG1HOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC200]);
}
/// variables.h:1019 — mapbak_BG2HOFS_copy2: (*(uint16*)(g_ram+0xC202))
pub inline fn mapbak_BG2HOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC202]);
}
/// variables.h:1020 — mapbak_BG1VOFS_copy2: (*(uint16*)(g_ram+0xC204))
pub inline fn mapbak_BG1VOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC204]);
}
/// variables.h:1021 — mapbak_BG2VOFS_copy2: (*(uint16*)(g_ram+0xC206))
pub inline fn mapbak_BG2VOFS_copy2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC206]);
}
/// variables.h:1022 — dung_bg2_properties_backup: (*(uint8*)(g_ram+0xC208))
pub inline fn dung_bg2_properties_backup() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC208]);
}
/// variables.h:1023 — overworld_pal_unk1: (*(uint8*)(g_ram+0xC20A))
pub inline fn overworld_pal_unk1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC20A]);
}
/// variables.h:1024 — overworld_pal_unk2: (*(uint8*)(g_ram+0xC20B))
pub inline fn overworld_pal_unk2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC20B]);
}
/// variables.h:1025 — overworld_pal_unk3: (*(uint8*)(g_ram+0xC20C))
pub inline fn overworld_pal_unk3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC20C]);
}
/// variables.h:1026 — mapbak_main_tile_theme_index: (*(uint8*)(g_ram+0xC20E))
pub inline fn mapbak_main_tile_theme_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC20E]);
}
/// variables.h:1027 — mapbak_sprite_graphics_index: (*(uint8*)(g_ram+0xC20F))
pub inline fn mapbak_sprite_graphics_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC20F]);
}
/// variables.h:1028 — mapbak_aux_tile_theme_index: (*(uint8*)(g_ram+0xC210))
pub inline fn mapbak_aux_tile_theme_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC210]);
}
/// variables.h:1029 — mapbak_TM: (*(uint8*)(g_ram+0xC211))
pub inline fn mapbak_TM() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC211]);
}
/// variables.h:1030 — mapbak_TS: (*(uint8*)(g_ram+0xC212))
pub inline fn mapbak_TS() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC212]);
}
/// variables.h:1031 — overworld_screen_index_prev: (*(uint16*)(g_ram+0xC213))
pub inline fn overworld_screen_index_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC213]);
}
/// variables.h:1032 — map16_load_src_off_prev: (*(uint16*)(g_ram+0xC215))
pub inline fn map16_load_src_off_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC215]);
}
/// variables.h:1033 — map16_load_var2_prev: (*(uint16*)(g_ram+0xC217))
pub inline fn map16_load_var2_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC217]);
}
/// variables.h:1034 — map16_load_dst_off_prev: (*(uint16*)(g_ram+0xC219))
pub inline fn map16_load_dst_off_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC219]);
}
/// variables.h:1035 — overworld_screen_transition_prev: (*(uint8*)(g_ram+0xC21B))
pub inline fn overworld_screen_transition_prev() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC21B]);
}
/// variables.h:1036 — overworld_screen_trans_dir_bits_prev: (*(uint16*)(g_ram+0xC21D))
pub inline fn overworld_screen_trans_dir_bits_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC21D]);
}
/// variables.h:1037 — overworld_screen_trans_dir_bits2_prev: (*(uint16*)(g_ram+0xC21F))
pub inline fn overworld_screen_trans_dir_bits2_prev() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC21F]);
}
/// variables.h:1038 — mapbak_bg1_x_offset: (*(uint16*)(g_ram+0xC221))
pub inline fn mapbak_bg1_x_offset() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC221]);
}
/// variables.h:1039 — mapbak_bg1_y_offset: (*(uint16*)(g_ram+0xC223))
pub inline fn mapbak_bg1_y_offset() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC223]);
}
/// variables.h:1040 — mapbak_CGWSEL: (*(uint16*)(g_ram+0xC225))
pub inline fn mapbak_CGWSEL() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC225]);
}
/// variables.h:1041 — music_unk1_death: (*(uint8*)(g_ram+0xC227))
pub inline fn music_unk1_death() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC227]);
}
/// variables.h:1042 — sound_effect_ambient_last_death: (*(uint8*)(g_ram+0xC228))
pub inline fn sound_effect_ambient_last_death() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC228]);
}
/// variables.h:1043 — mapbak_HDMAEN: (*(uint8*)(g_ram+0xC229))
pub inline fn mapbak_HDMAEN() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC229]);
}
/// variables.h:1044 — byte_7EC22F: (*(uint8*)(g_ram+0xC22F))
pub inline fn byte_7EC22F() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC22F]);
}
/// variables.h:1045 — vwf_arr: ((uint8*)(g_ram+0xC230))
pub inline fn vwf_arr() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC230]);
}
/// variables.h:1046 — aux_bg_subset_0: (*(uint8*)(g_ram+0xC2F8))
pub inline fn aux_bg_subset_0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2F8]);
}
/// variables.h:1047 — aux_bg_subset_1: (*(uint8*)(g_ram+0xC2F9))
pub inline fn aux_bg_subset_1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2F9]);
}
/// variables.h:1048 — aux_bg_subset_2: (*(uint8*)(g_ram+0xC2FA))
pub inline fn aux_bg_subset_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FA]);
}
/// variables.h:1049 — aux_bg_subset_3: (*(uint8*)(g_ram+0xC2FB))
pub inline fn aux_bg_subset_3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FB]);
}
/// variables.h:1050 — sprite_gfx_subset_0: (*(uint8*)(g_ram+0xC2FC))
pub inline fn sprite_gfx_subset_0() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FC]);
}
/// variables.h:1051 — sprite_gfx_subset_1: (*(uint8*)(g_ram+0xC2FD))
pub inline fn sprite_gfx_subset_1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FD]);
}
/// variables.h:1052 — sprite_gfx_subset_2: (*(uint8*)(g_ram+0xC2FE))
pub inline fn sprite_gfx_subset_2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FE]);
}
/// variables.h:1053 — sprite_gfx_subset_3: (*(uint8*)(g_ram+0xC2FF))
pub inline fn sprite_gfx_subset_3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xC2FF]);
}
/// variables.h:1054 — aux_palette_buffer: ((uint16*)(g_ram+0xC300))
pub inline fn aux_palette_buffer() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC300]);
}
/// variables.h:1055 — main_palette_buffer: ((uint16*)(g_ram+0xC500))
pub inline fn main_palette_buffer() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC500]);
}
/// variables.h:1056 — hud_tile_indices_buffer: ((uint16*)(g_ram+0xC700))
pub inline fn hud_tile_indices_buffer() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC700]);
}
/// variables.h:1057 — moving_wall_arr1: ((uint16*)(g_ram+0xC880))
pub inline fn moving_wall_arr1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xC880]);
}
/// variables.h:1058 — word_7EE000: (*(uint16*)(g_ram+0xE000))
pub inline fn word_7EE000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xE000]);
}
/// variables.h:1059 — polyhedral_buffer: ((uint8*)(g_ram+0xE800))
pub inline fn polyhedral_buffer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xE800]);
}
/// variables.h:1060 — save_dung_info: ((uint16*)(g_ram+0xF000))
pub inline fn save_dung_info() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF000]);
}
/// variables.h:1061 — save_ow_event_info: ((uint8*)(g_ram+0xF280))
pub inline fn save_ow_event_info() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF280]);
}
/// variables.h:1062 — savegame_has_master_sword_flags: (*(uint16*)(g_ram+0xF300))
pub inline fn savegame_has_master_sword_flags() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF300]);
}
/// variables.h:1063 — byte_7EF33F: (*(uint8*)(g_ram+0xF33F))
pub inline fn byte_7EF33F() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF33F]);
}
/// variables.h:1064 — link_item_bow: (*(uint8*)(g_ram+0xF340))
pub inline fn link_item_bow() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF340]);
}
/// variables.h:1065 — link_item_boomerang: (*(uint8*)(g_ram+0xF341))
pub inline fn link_item_boomerang() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF341]);
}
/// variables.h:1066 — link_item_hookshot: (*(uint8*)(g_ram+0xF342))
pub inline fn link_item_hookshot() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF342]);
}
/// variables.h:1067 — link_item_bombs: (*(uint8*)(g_ram+0xF343))
pub inline fn link_item_bombs() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF343]);
}
/// variables.h:1068 — link_item_mushroom: (*(uint8*)(g_ram+0xF344))
pub inline fn link_item_mushroom() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF344]);
}
/// variables.h:1069 — link_item_fire_rod: (*(uint8*)(g_ram+0xF345))
pub inline fn link_item_fire_rod() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF345]);
}
/// variables.h:1070 — link_item_ice_rod: (*(uint8*)(g_ram+0xF346))
pub inline fn link_item_ice_rod() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF346]);
}
/// variables.h:1071 — link_item_bombos_medallion: (*(uint8*)(g_ram+0xF347))
pub inline fn link_item_bombos_medallion() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF347]);
}
/// variables.h:1072 — link_item_ether_medallion: (*(uint8*)(g_ram+0xF348))
pub inline fn link_item_ether_medallion() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF348]);
}
/// variables.h:1073 — link_item_quake_medallion: (*(uint8*)(g_ram+0xF349))
pub inline fn link_item_quake_medallion() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF349]);
}
/// variables.h:1074 — link_item_torch: (*(uint8*)(g_ram+0xF34A))
pub inline fn link_item_torch() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34A]);
}
/// variables.h:1075 — link_item_hammer: (*(uint8*)(g_ram+0xF34B))
pub inline fn link_item_hammer() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34B]);
}
/// variables.h:1076 — link_item_flute: (*(uint8*)(g_ram+0xF34C))
pub inline fn link_item_flute() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34C]);
}
/// variables.h:1077 — link_item_bug_net: (*(uint8*)(g_ram+0xF34D))
pub inline fn link_item_bug_net() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34D]);
}
/// variables.h:1078 — link_item_book_of_mudora: (*(uint8*)(g_ram+0xF34E))
pub inline fn link_item_book_of_mudora() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34E]);
}
/// variables.h:1079 — link_item_bottle_index: (*(uint8*)(g_ram+0xF34F))
pub inline fn link_item_bottle_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF34F]);
}
/// variables.h:1080 — link_item_cane_somaria: (*(uint8*)(g_ram+0xF350))
pub inline fn link_item_cane_somaria() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF350]);
}
/// variables.h:1081 — link_item_cane_byrna: (*(uint8*)(g_ram+0xF351))
pub inline fn link_item_cane_byrna() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF351]);
}
/// variables.h:1082 — link_item_cape: (*(uint8*)(g_ram+0xF352))
pub inline fn link_item_cape() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF352]);
}
/// variables.h:1083 — link_item_mirror: (*(uint8*)(g_ram+0xF353))
pub inline fn link_item_mirror() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF353]);
}
/// variables.h:1084 — link_item_gloves: (*(uint8*)(g_ram+0xF354))
pub inline fn link_item_gloves() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF354]);
}
/// variables.h:1085 — link_item_boots: (*(uint8*)(g_ram+0xF355))
pub inline fn link_item_boots() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF355]);
}
/// variables.h:1086 — link_item_flippers: (*(uint8*)(g_ram+0xF356))
pub inline fn link_item_flippers() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF356]);
}
/// variables.h:1087 — link_item_moon_pearl: (*(uint8*)(g_ram+0xF357))
pub inline fn link_item_moon_pearl() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF357]);
}
/// variables.h:1088 — link_sword_type: (*(uint8*)(g_ram+0xF359))
pub inline fn link_sword_type() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF359]);
}
/// variables.h:1089 — link_shield_type: (*(uint8*)(g_ram+0xF35A))
pub inline fn link_shield_type() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF35A]);
}
/// variables.h:1090 — link_armor: (*(uint8*)(g_ram+0xF35B))
pub inline fn link_armor() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF35B]);
}
/// variables.h:1091 — link_bottle_info: ((uint8*)(g_ram+0xF35C))
pub inline fn link_bottle_info() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF35C]);
}
/// variables.h:1092 — link_rupees_goal: (*(uint16*)(g_ram+0xF360))
pub inline fn link_rupees_goal() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF360]);
}
/// variables.h:1093 — link_rupees_actual: (*(uint16*)(g_ram+0xF362))
pub inline fn link_rupees_actual() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF362]);
}
/// variables.h:1094 — link_compass: (*(uint16*)(g_ram+0xF364))
pub inline fn link_compass() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF364]);
}
/// variables.h:1095 — link_bigkey: (*(uint16*)(g_ram+0xF366))
pub inline fn link_bigkey() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF366]);
}
/// variables.h:1096 — link_dungeon_map: (*(uint16*)(g_ram+0xF368))
pub inline fn link_dungeon_map() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF368]);
}
/// variables.h:1097 — link_rupees_in_pond: (*(uint8*)(g_ram+0xF36A))
pub inline fn link_rupees_in_pond() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36A]);
}
/// variables.h:1098 — link_heart_pieces: (*(uint8*)(g_ram+0xF36B))
pub inline fn link_heart_pieces() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36B]);
}
/// variables.h:1099 — link_health_capacity: (*(uint8*)(g_ram+0xF36C))
pub inline fn link_health_capacity() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36C]);
}
/// variables.h:1100 — link_health_current: (*(uint8*)(g_ram+0xF36D))
pub inline fn link_health_current() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36D]);
}
/// variables.h:1101 — link_magic_power: (*(uint8*)(g_ram+0xF36E))
pub inline fn link_magic_power() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36E]);
}
/// variables.h:1102 — link_num_keys: (*(uint8*)(g_ram+0xF36F))
pub inline fn link_num_keys() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF36F]);
}
/// variables.h:1103 — link_bomb_upgrades: (*(uint8*)(g_ram+0xF370))
pub inline fn link_bomb_upgrades() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF370]);
}
/// variables.h:1104 — link_arrow_upgrades: (*(uint8*)(g_ram+0xF371))
pub inline fn link_arrow_upgrades() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF371]);
}
/// variables.h:1105 — link_hearts_filler: (*(uint8*)(g_ram+0xF372))
pub inline fn link_hearts_filler() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF372]);
}
/// variables.h:1106 — link_magic_filler: (*(uint8*)(g_ram+0xF373))
pub inline fn link_magic_filler() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF373]);
}
/// variables.h:1107 — link_which_pendants: (*(uint8*)(g_ram+0xF374))
pub inline fn link_which_pendants() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF374]);
}
/// variables.h:1108 — link_bomb_filler: (*(uint8*)(g_ram+0xF375))
pub inline fn link_bomb_filler() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF375]);
}
/// variables.h:1109 — link_arrow_filler: (*(uint8*)(g_ram+0xF376))
pub inline fn link_arrow_filler() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF376]);
}
/// variables.h:1110 — link_num_arrows: (*(uint8*)(g_ram+0xF377))
pub inline fn link_num_arrows() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF377]);
}
/// variables.h:1111 — link_ability_flags: (*(uint8*)(g_ram+0xF379))
pub inline fn link_ability_flags() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF379]);
}
/// variables.h:1112 — link_has_crystals: (*(uint8*)(g_ram+0xF37A))
pub inline fn link_has_crystals() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF37A]);
}
/// variables.h:1113 — link_magic_consumption: (*(uint8*)(g_ram+0xF37B))
pub inline fn link_magic_consumption() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF37B]);
}
/// variables.h:1114 — link_keys_earned_per_dungeon: ((uint8*)(g_ram+0xF37C))
pub inline fn link_keys_earned_per_dungeon() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF37C]);
}
/// variables.h:1115 — sram_progress_indicator: (*(uint8*)(g_ram+0xF3C5))
pub inline fn sram_progress_indicator() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3C5]);
}
/// variables.h:1116 — sram_progress_flags: (*(uint8*)(g_ram+0xF3C6))
pub inline fn sram_progress_flags() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3C6]);
}
/// variables.h:1117 — savegame_map_icons_indicator: (*(uint8*)(g_ram+0xF3C7))
pub inline fn savegame_map_icons_indicator() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3C7]);
}
/// variables.h:1118 — which_starting_point: (*(uint8*)(g_ram+0xF3C8))
pub inline fn which_starting_point() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3C8]);
}
/// variables.h:1119 — sram_progress_indicator_3: (*(uint8*)(g_ram+0xF3C9))
pub inline fn sram_progress_indicator_3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3C9]);
}
/// variables.h:1120 — savegame_is_darkworld: (*(uint8*)(g_ram+0xF3CA))
pub inline fn savegame_is_darkworld() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3CA]);
}
/// variables.h:1121 — follower_indicator: (*(uint8*)(g_ram+0xF3CC))
pub inline fn follower_indicator() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3CC]);
}
/// variables.h:1122 — saved_tagalong_y: (*(uint16*)(g_ram+0xF3CD))
pub inline fn saved_tagalong_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF3CD]);
}
/// variables.h:1123 — saved_tagalong_x: (*(uint16*)(g_ram+0xF3CF))
pub inline fn saved_tagalong_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF3CF]);
}
/// variables.h:1124 — saved_tagalong_indoors: (*(uint8*)(g_ram+0xF3D1))
pub inline fn saved_tagalong_indoors() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3D1]);
}
/// variables.h:1125 — saved_tagalong_floor: (*(uint8*)(g_ram+0xF3D2))
pub inline fn saved_tagalong_floor() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3D2]);
}
/// variables.h:1126 — follower_dropped: (*(uint8*)(g_ram+0xF3D3))
pub inline fn follower_dropped() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xF3D3]);
}
/// variables.h:1127 — deaths_per_palace: ((uint16*)(g_ram+0xF3E7))
pub inline fn deaths_per_palace() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF3E7]);
}
/// variables.h:1128 — death_save_counter: (*(uint16*)(g_ram+0xF403))
pub inline fn death_save_counter() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF403]);
}
/// variables.h:1129 — death_var2: (*(uint16*)(g_ram+0xF405))
pub inline fn death_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF405]);
}
/// variables.h:1130 — word_7EF4FE: (*(uint16*)(g_ram+0xF4FE))
pub inline fn word_7EF4FE() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF4FE]);
}
/// variables.h:1131 — pots_revealed_in_room: ((uint16*)(g_ram+0xF580))
pub inline fn pots_revealed_in_room() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF580]);
}
/// variables.h:1132 — memorized_tile_addr: ((uint16*)(g_ram+0xF800))
pub inline fn memorized_tile_addr() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xF800]);
}
/// variables.h:1133 — memorized_tile_value: ((uint16*)(g_ram+0xFA00))
pub inline fn memorized_tile_value() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFA00]);
}
/// variables.h:1134 — word_7EFA40: ((uint16*)(g_ram+0xFA40))
pub inline fn word_7EFA40() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFA40]);
}
/// variables.h:1135 — dung_torch_data: ((uint16*)(g_ram+0xFB40))
pub inline fn dung_torch_data() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xFB40]);
}
/// variables.h:1136 — overworld_sprite_gfx: ((uint8*)(g_ram+0xFCC0))
pub inline fn overworld_sprite_gfx() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFCC0]);
}
/// variables.h:1137 — overworld_sprite_palettes: ((uint8*)(g_ram+0xFD40))
pub inline fn overworld_sprite_palettes() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFD40]);
}
/// variables.h:1138 — attributes_for_tile: ((uint8*)(g_ram+0xFE00))
pub inline fn attributes_for_tile() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xFE00]);
}
///   also defined at variables.h:1331 (identical alias)
/// variables.h:1139 — skullwoodsfire_var0: ((uint8*)(g_ram+0x10000))
pub inline fn skullwoodsfire_var0() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10000]);
}
///   also defined at variables.h:1332 (identical alias)
/// variables.h:1140 — skullwoodsfire_var5: ((uint8*)(g_ram+0x10008))
pub inline fn skullwoodsfire_var5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10008]);
}
///   also defined at variables.h:1333 (identical alias)
/// variables.h:1141 — skullwoodsfire_var4: (*(uint8*)(g_ram+0x10010))
pub inline fn skullwoodsfire_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10010]);
}
///   also defined at variables.h:1291 (identical alias)
/// variables.h:1142 — blastwall_var4: (*(uint8*)(g_ram+0x10011))
pub inline fn blastwall_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10011]);
}
///   also defined at variables.h:1334 (identical alias)
/// variables.h:1143 — skullwoodsfire_var9: (*(uint16*)(g_ram+0x10018))
pub inline fn skullwoodsfire_var9() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10018]);
}
///   also defined at variables.h:1335 (identical alias)
/// variables.h:1144 — skullwoodsfire_var11: (*(uint16*)(g_ram+0x1001A))
pub inline fn skullwoodsfire_var11() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1001A]);
}
///   also defined at variables.h:1294 (identical alias)
/// variables.h:1145 — blastwall_var7: (*(uint8*)(g_ram+0x1001C))
pub inline fn blastwall_var7() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1001C]);
}
///   also defined at variables.h:1336 (identical alias)
/// variables.h:1146 — skullwoodsfire_y_arr: ((uint16*)(g_ram+0x10020))
pub inline fn skullwoodsfire_y_arr() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10020]);
}
///   also defined at variables.h:1337 (identical alias)
/// variables.h:1147 — skullwoodsfire_var10: (*(uint16*)(g_ram+0x10026))
pub inline fn skullwoodsfire_var10() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10026]);
}
///   also defined at variables.h:1338 (identical alias)
/// variables.h:1148 — skullwoodsfire_x_arr: ((uint16*)(g_ram+0x10030))
pub inline fn skullwoodsfire_x_arr() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10030]);
}
///   also defined at variables.h:1339 (identical alias)
/// variables.h:1149 — skullwoodsfire_var12: (*(uint16*)(g_ram+0x10036))
pub inline fn skullwoodsfire_var12() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10036]);
}
///   also defined at variables.h:1297 (identical alias)
/// variables.h:1150 — blastwall_var12: ((uint8*)(g_ram+0x10040))
pub inline fn blastwall_var12() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10040]);
}
/// variables.h:1151 — word_7F1000: (*(uint16*)(g_ram+0x11000))
pub inline fn word_7F1000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11000]);
}
/// variables.h:1152 — word_7F1010: (*(uint16*)(g_ram+0x11010))
pub inline fn word_7F1010() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11010]);
}
/// variables.h:1153 — byte_7F11FA: (*(uint8*)(g_ram+0x111FA))
pub inline fn byte_7F11FA() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FA]);
}
/// variables.h:1154 — byte_7F11FB: (*(uint8*)(g_ram+0x111FB))
pub inline fn byte_7F11FB() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FB]);
}
/// variables.h:1155 — byte_7F11FC: (*(uint8*)(g_ram+0x111FC))
pub inline fn byte_7F11FC() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FC]);
}
/// variables.h:1156 — byte_7F11FD: (*(uint8*)(g_ram+0x111FD))
pub inline fn byte_7F11FD() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FD]);
}
/// variables.h:1157 — byte_7F11FE: (*(uint8*)(g_ram+0x111FE))
pub inline fn byte_7F11FE() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FE]);
}
/// variables.h:1158 — byte_7F11FF: (*(uint8*)(g_ram+0x111FF))
pub inline fn byte_7F11FF() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x111FF]);
}
/// variables.h:1159 — messaging_text_buffer: ((uint8*)(g_ram+0x11200))
pub inline fn messaging_text_buffer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x11200]);
}
/// variables.h:1160 — word_7F1FC0: (*(uint16*)(g_ram+0x11FC0))
pub inline fn word_7F1FC0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x11FC0]);
}
/// variables.h:1161 — dung_bg2_attr_table: ((uint8*)(g_ram+0x12000))
pub inline fn dung_bg2_attr_table() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x12000]);
}
/// variables.h:1162 — dung_bg1_attr_table: ((uint8*)(g_ram+0x13000))
pub inline fn dung_bg1_attr_table() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x13000]);
}
/// variables.h:1163 — word_7F4000: (*(uint16*)(g_ram+0x14000))
pub inline fn word_7F4000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14000]);
}
/// variables.h:1164 — word_7F4002: (*(uint16*)(g_ram+0x14002))
pub inline fn word_7F4002() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14002]);
}
/// variables.h:1165 — word_7F4004: (*(uint16*)(g_ram+0x14004))
pub inline fn word_7F4004() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14004]);
}
/// variables.h:1166 — word_7F4006: (*(uint16*)(g_ram+0x14006))
pub inline fn word_7F4006() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14006]);
}
/// variables.h:1167 — map16_decode_0: ((uint8*)(g_ram+0x14400))
pub inline fn map16_decode_0() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x14400]);
}
/// variables.h:1168 — map16_decode_1: ((uint8*)(g_ram+0x14410))
pub inline fn map16_decode_1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x14410]);
}
/// variables.h:1169 — map16_decode_2: ((uint8*)(g_ram+0x14420))
pub inline fn map16_decode_2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x14420]);
}
/// variables.h:1170 — map16_decode_3: ((uint8*)(g_ram+0x14430))
pub inline fn map16_decode_3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x14430]);
}
/// variables.h:1171 — map16_decode_last: (*(uint16*)(g_ram+0x14440))
pub inline fn map16_decode_last() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14440]);
}
/// variables.h:1172 — map16_decode_tmp: (*(uint16*)(g_ram+0x14442))
pub inline fn map16_decode_tmp() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x14442]);
}
///   also defined at variables.h:1299 (identical alias)
/// variables.h:1173 — breaktowerseal_var3: ((uint8*)(g_ram+0x15800))
pub inline fn breaktowerseal_var3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15800]);
}
///   also defined at variables.h:1300 (identical alias)
/// variables.h:1174 — breaktowerseal_var4: (*(uint8*)(g_ram+0x15808))
pub inline fn breaktowerseal_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15808]);
}
///   also defined at variables.h:1301 (identical alias)
/// variables.h:1175 — breaktowerseal_x: (*(uint16*)(g_ram+0x1580E))
pub inline fn breaktowerseal_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1580E]);
}
///   also defined at variables.h:1302 (identical alias)
/// variables.h:1176 — breaktowerseal_y: (*(uint16*)(g_ram+0x15810))
pub inline fn breaktowerseal_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15810]);
}
///   also defined at variables.h:1303 (identical alias)
/// variables.h:1177 — breaktowerseal_var5: (*(uint8*)(g_ram+0x15812))
pub inline fn breaktowerseal_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15812]);
}
///   also defined at variables.h:1304 (identical alias)
/// variables.h:1178 — breaktowerseal_base_sparkle_y_lo: ((uint8*)(g_ram+0x15817))
pub inline fn breaktowerseal_base_sparkle_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15817]);
}
///   also defined at variables.h:1305 (identical alias)
/// variables.h:1179 — breaktowerseal_base_sparkle_y_hi: ((uint8*)(g_ram+0x1581F))
pub inline fn breaktowerseal_base_sparkle_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1581F]);
}
///   also defined at variables.h:1306 (identical alias)
/// variables.h:1180 — breaktowerseal_base_sparkle_x_lo: ((uint8*)(g_ram+0x15827))
pub inline fn breaktowerseal_base_sparkle_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15827]);
}
///   also defined at variables.h:1307 (identical alias)
/// variables.h:1181 — breaktowerseal_base_sparkle_x_hi: ((uint8*)(g_ram+0x1582F))
pub inline fn breaktowerseal_base_sparkle_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1582F]);
}
///   also defined at variables.h:1308 (identical alias)
/// variables.h:1182 — breaktowerseal_sparkle_var1: ((uint8*)(g_ram+0x15837))
pub inline fn breaktowerseal_sparkle_var1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15837]);
}
///   also defined at variables.h:1309 (identical alias)
/// variables.h:1183 — breaktowerseal_sparkle_y_lo: ((uint8*)(g_ram+0x1584F))
pub inline fn breaktowerseal_sparkle_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1584F]);
}
///   also defined at variables.h:1310 (identical alias)
/// variables.h:1184 — breaktowerseal_sparkle_y_hi: ((uint8*)(g_ram+0x15867))
pub inline fn breaktowerseal_sparkle_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15867]);
}
///   also defined at variables.h:1311 (identical alias)
/// variables.h:1185 — breaktowerseal_sparkle_x_lo: ((uint8*)(g_ram+0x1587F))
pub inline fn breaktowerseal_sparkle_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1587F]);
}
///   also defined at variables.h:1312 (identical alias)
/// variables.h:1186 — breaktowerseal_sparkle_x_hi: ((uint8*)(g_ram+0x15897))
pub inline fn breaktowerseal_sparkle_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15897]);
}
///   also defined at variables.h:1313 (identical alias)
/// variables.h:1187 — breaktowerseal_sparkle_var2: ((uint8*)(g_ram+0x158AF))
pub inline fn breaktowerseal_sparkle_var2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x158AF]);
}
/// variables.h:1188 — overworld_music: ((uint8*)(g_ram+0x15B00))
pub inline fn overworld_music() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15B00]);
}
/// variables.h:1189 — freeRam: ((uint8*)(g_ram+0x15BA0))
pub inline fn freeRam() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15BA0]);
}
/// variables.h:1190 — enemy_damage_data: ((uint8*)(g_ram+0x16000))
pub inline fn enemy_damage_data() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x16000]);
}
/// variables.h:1191 — hdma_table_unused: ((uint16*)(g_ram+0x17000))
pub inline fn hdma_table_unused() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x17000]);
}
/// variables.h:1192 — kTextDialoguePointers: ((uint8*)(g_ram+0x171C0))
pub inline fn kTextDialoguePointers() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x171C0]);
}
/// variables.h:1193 — word_7F8000: (*(uint16*)(g_ram+0x18000))
pub inline fn word_7F8000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x18000]);
}
/// variables.h:1194 — word_7F9B52: (*(uint16*)(g_ram+0x19B52))
pub inline fn word_7F9B52() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19B52]);
}
/// variables.h:1195 — word_7F9B54: (*(uint16*)(g_ram+0x19B54))
pub inline fn word_7F9B54() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19B54]);
}
/// variables.h:1196 — word_7F9B56: (*(uint16*)(g_ram+0x19B56))
pub inline fn word_7F9B56() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19B56]);
}
/// variables.h:1197 — word_7F9B58: (*(uint16*)(g_ram+0x19B58))
pub inline fn word_7F9B58() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x19B58]);
}
/// variables.h:1198 — word_7FA000: (*(uint16*)(g_ram+0x1A000))
pub inline fn word_7FA000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1A000]);
}
/// variables.h:1199 — word_7FC000: (*(uint16*)(g_ram+0x1C000))
pub inline fn word_7FC000() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1C000]);
}
/// variables.h:1200 — mapbak_palette: ((uint16*)(g_ram+0x1DD80))
pub inline fn mapbak_palette() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1DD80]);
}
/// variables.h:1201 — sprite_where_in_room: ((uint16*)(g_ram+0x1DF80))
pub inline fn sprite_where_in_room() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1DF80]);
}
/// variables.h:1202 — overworld_sprite_was_loaded: ((uint8*)(g_ram+0x1EF80))
pub inline fn overworld_sprite_was_loaded() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1EF80]);
}
/// variables.h:1203 — garnish_type: ((uint8*)(g_ram+0x1F800))
pub inline fn garnish_type() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F800]);
}
/// variables.h:1204 — garnish_y_lo: ((uint8*)(g_ram+0x1F81E))
pub inline fn garnish_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F81E]);
}
/// variables.h:1205 — garnish_x_lo: ((uint8*)(g_ram+0x1F83C))
pub inline fn garnish_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F83C]);
}
/// variables.h:1206 — garnish_y_hi: ((uint8*)(g_ram+0x1F85A))
pub inline fn garnish_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F85A]);
}
/// variables.h:1207 — garnish_x_hi: ((uint8*)(g_ram+0x1F878))
pub inline fn garnish_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F878]);
}
/// variables.h:1208 — garnish_y_vel: ((uint8*)(g_ram+0x1F896))
pub inline fn garnish_y_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F896]);
}
/// variables.h:1209 — garnish_x_vel: ((uint8*)(g_ram+0x1F8B4))
pub inline fn garnish_x_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F8B4]);
}
/// variables.h:1210 — garnish_y_subpixel: ((uint8*)(g_ram+0x1F8D2))
pub inline fn garnish_y_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F8D2]);
}
/// variables.h:1211 — garnish_x_subpixel: ((uint8*)(g_ram+0x1F8F0))
pub inline fn garnish_x_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F8F0]);
}
/// variables.h:1212 — garnish_countdown: ((uint8*)(g_ram+0x1F90E))
pub inline fn garnish_countdown() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F90E]);
}
/// variables.h:1213 — garnish_sprite: ((uint8*)(g_ram+0x1F92C))
pub inline fn garnish_sprite() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F92C]);
}
/// variables.h:1214 — garnish_anim_5: ((uint8*)(g_ram+0x1F94A))
pub inline fn garnish_anim_5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F94A]);
}
/// variables.h:1215 — garnish_floor: ((uint8*)(g_ram+0x1F968))
pub inline fn garnish_floor() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F968]);
}
/// variables.h:1216 — sprite_I: ((uint8*)(g_ram+0x1F9C2))
pub inline fn sprite_I() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F9C2]);
}
/// variables.h:1217 — garnish_oam_flags: ((uint8*)(g_ram+0x1F9FE))
pub inline fn garnish_oam_flags() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1F9FE]);
}
/// variables.h:1218 — sprite_unk3: ((uint8*)(g_ram+0x1FA1C))
pub inline fn sprite_unk3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA1C]);
}
/// variables.h:1219 — sprite_unk4: ((uint8*)(g_ram+0x1FA2C))
pub inline fn sprite_unk4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA2C]);
}
/// variables.h:1220 — sprite_unk5: ((uint8*)(g_ram+0x1FA3C))
pub inline fn sprite_unk5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA3C]);
}
/// variables.h:1221 — sprite_unk1: ((uint8*)(g_ram+0x1FA4C))
pub inline fn sprite_unk1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA4C]);
}
/// variables.h:1222 — swamola_x_lo: ((uint8*)(g_ram+0x1FA5C))
pub inline fn swamola_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA5C]);
}
/// variables.h:1223 — alt_sprite_C: ((uint8*)(g_ram+0x1FA6C))
pub inline fn alt_sprite_C() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA6C]);
}
/// variables.h:1224 — alt_sprite_E: ((uint8*)(g_ram+0x1FA7C))
pub inline fn alt_sprite_E() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA7C]);
}
/// variables.h:1225 — alt_sprite_subtype2: ((uint8*)(g_ram+0x1FA8C))
pub inline fn alt_sprite_subtype2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA8C]);
}
/// variables.h:1226 — alt_sprite_height_above_shadow: ((uint8*)(g_ram+0x1FA9C))
pub inline fn alt_sprite_height_above_shadow() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA9C]);
}
/// variables.h:1227 — alt_sprite_delay_main: ((uint8*)(g_ram+0x1FAAC))
pub inline fn alt_sprite_delay_main() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FAAC]);
}
/// variables.h:1228 — byte_7FFABC: ((uint8*)(g_ram+0x1FABC))
pub inline fn byte_7FFABC() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FABC]);
}
/// variables.h:1229 — alt_sprite_I: ((uint8*)(g_ram+0x1FACC))
pub inline fn alt_sprite_I() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FACC]);
}
/// variables.h:1230 — alt_sprite_maybe_ignore_projectile: ((uint8*)(g_ram+0x1FADC))
pub inline fn alt_sprite_maybe_ignore_projectile() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FADC]);
}
/// variables.h:1231 — swamola_x_hi: ((uint8*)(g_ram+0x1FB1C))
pub inline fn swamola_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FB1C]);
}
/// variables.h:1232 — swamola_y_lo: ((uint8*)(g_ram+0x1FBDC))
pub inline fn swamola_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FBDC]);
}
/// variables.h:1233 — moldorm_x_lo: ((uint8*)(g_ram+0x1FC00))
pub inline fn moldorm_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FC00]);
}
/// variables.h:1234 — moldorm_x_hi_: ((uint8*)(g_ram+0x1FC80))
pub inline fn moldorm_x_hi_() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FC80]);
}
/// variables.h:1235 — swamola_y_hi: ((uint8*)(g_ram+0x1FC9C))
pub inline fn swamola_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FC9C]);
}
/// variables.h:1236 — moldorm_y_lo: ((uint8*)(g_ram+0x1FD00))
pub inline fn moldorm_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD00]);
}
/// variables.h:1237 — word_7FFD02: (*(uint16*)(g_ram+0x1FD02))
pub inline fn word_7FFD02() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1FD02]);
}
/// variables.h:1238 — swamola_target_x_lo: ((uint8*)(g_ram+0x1FD5C))
pub inline fn swamola_target_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD5C]);
}
/// variables.h:1239 — swamola_target_x_hi: ((uint8*)(g_ram+0x1FD62))
pub inline fn swamola_target_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD62]);
}
/// variables.h:1240 — swamola_target_y_lo: ((uint8*)(g_ram+0x1FD68))
pub inline fn swamola_target_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD68]);
}
/// variables.h:1241 — swamola_target_y_hi: ((uint8*)(g_ram+0x1FD6E))
pub inline fn swamola_target_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD6E]);
}
/// variables.h:1242 — beamos_x_lo: ((uint8*)(g_ram+0x1FD80))
pub inline fn beamos_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FD80]);
}
/// variables.h:1243 — beamos_x_hi: ((uint8*)(g_ram+0x1FE00))
pub inline fn beamos_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE00]);
}
/// variables.h:1244 — beamos_y_lo: ((uint8*)(g_ram+0x1FE80))
pub inline fn beamos_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FE80]);
}
/// variables.h:1245 — beamos_y_hi: ((uint8*)(g_ram+0x1FF00))
pub inline fn beamos_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FF00]);
}
/// variables.h:1247 — attract_var12: (*(uint16*)(g_ram+0x20))
pub inline fn attract_var12() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x20]);
}
/// variables.h:1248 — attract_state: (*(uint8*)(g_ram+0x22))
pub inline fn attract_state() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x22]);
}
/// variables.h:1249 — attract_sequence: (*(uint8*)(g_ram+0x23))
pub inline fn attract_sequence() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x23]);
}
/// variables.h:1250 — attract_var10: (*(uint8*)(g_ram+0x25))
pub inline fn attract_var10() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x25]);
}
/// variables.h:1251 — attract_next_legend_gfx: (*(uint8*)(g_ram+0x26))
pub inline fn attract_next_legend_gfx() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x26]);
}
/// variables.h:1252 — attract_legend_flag: (*(uint8*)(g_ram+0x27))
pub inline fn attract_legend_flag() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x27]);
}
/// variables.h:1253 — attract_x_base: (*(uint8*)(g_ram+0x28))
pub inline fn attract_x_base() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x28]);
}
/// variables.h:1254 — attract_y_base: (*(uint8*)(g_ram+0x29))
pub inline fn attract_y_base() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x29]);
}
/// variables.h:1255 — attract_oam_idx: (*(uint8*)(g_ram+0x2A))
pub inline fn attract_oam_idx() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2A]);
}
/// variables.h:1256 — attract_var9: (*(uint8*)(g_ram+0x2B))
pub inline fn attract_var9() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2B]);
}
/// variables.h:1257 — attract_var13: (*(uint8*)(g_ram+0x2C))
pub inline fn attract_var13() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x2C]);
}
/// variables.h:1258 — attract_var7: (*(uint16*)(g_ram+0x2D))
pub inline fn attract_var7() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2D]);
}
/// variables.h:1259 — attract_vram_dst: (*(uint16*)(g_ram+0x30))
pub inline fn attract_vram_dst() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x30]);
}
/// variables.h:1260 — attract_var1: (*(uint8*)(g_ram+0x32))
pub inline fn attract_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x32]);
}
/// variables.h:1261 — attract_var3: (*(uint8*)(g_ram+0x33))
pub inline fn attract_var3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x33]);
}
/// variables.h:1262 — attract_var4: (*(uint8*)(g_ram+0x34))
pub inline fn attract_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x34]);
}
/// variables.h:1263 — attract_x_base_hi: (*(uint8*)(g_ram+0x40))
pub inline fn attract_x_base_hi() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x40]);
}
/// variables.h:1264 — attract_var17: (*(uint8*)(g_ram+0x50))
pub inline fn attract_var17() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x50]);
}
/// variables.h:1265 — attract_var21: (*(uint8*)(g_ram+0x51))
pub inline fn attract_var21() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x51]);
}
/// variables.h:1266 — attract_var15: (*(uint8*)(g_ram+0x52))
pub inline fn attract_var15() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x52]);
}
/// variables.h:1267 — attract_var22: (*(uint8*)(g_ram+0x5D))
pub inline fn attract_var22() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5D]);
}
/// variables.h:1268 — attract_var18: (*(uint8*)(g_ram+0x5F))
pub inline fn attract_var18() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x5F]);
}
/// variables.h:1269 — attract_var5: (*(uint8*)(g_ram+0x60))
pub inline fn attract_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x60]);
}
/// variables.h:1270 — attract_var11: (*(uint8*)(g_ram+0x61))
pub inline fn attract_var11() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x61]);
}
/// variables.h:1271 — attract_var19: (*(uint8*)(g_ram+0x62))
pub inline fn attract_var19() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x62]);
}
/// variables.h:1272 — attract_var20: (*(uint8*)(g_ram+0x63))
pub inline fn attract_var20() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x63]);
}
/// variables.h:1273 — selectfile_arr1: ((uint16*)(g_ram+0xBF))
pub inline fn selectfile_arr1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xBF]);
}
/// variables.h:1274 — selectfile_arr2: ((uint8*)(g_ram+0xCA))
pub inline fn selectfile_arr2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCA]);
}
/// variables.h:1275 — selectfile_var6: (*(uint8*)(g_ram+0xCC))
pub inline fn selectfile_var6() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xCC]);
}
/// variables.h:1276 — attract_room_index: (*(uint8*)(g_ram+0x10E))
pub inline fn attract_room_index() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10E]);
}
/// variables.h:1277 — attract_legend_ctr: (*(uint16*)(g_ram+0x200))
pub inline fn attract_legend_ctr() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x200]);
}
///   also defined at variables.h:1422 (identical alias)
/// variables.h:1278 — selectfile_var8: (*(uint16*)(g_ram+0x630))
pub inline fn selectfile_var8() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x630]);
}
/// variables.h:1279 — selectfile_var3: (*(uint8*)(g_ram+0xB10))
pub inline fn selectfile_var3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB10]);
}
/// variables.h:1280 — selectfile_var7: (*(uint8*)(g_ram+0xB11))
pub inline fn selectfile_var7() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB11]);
}
/// variables.h:1281 — selectfile_var4: (*(uint8*)(g_ram+0xB12))
pub inline fn selectfile_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB12]);
}
/// variables.h:1282 — selectfile_var9: (*(uint8*)(g_ram+0xB13))
pub inline fn selectfile_var9() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB13]);
}
/// variables.h:1283 — selectfile_var11: (*(uint8*)(g_ram+0xB14))
pub inline fn selectfile_var11() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB14]);
}
/// variables.h:1284 — selectfile_var5: (*(uint8*)(g_ram+0xB15))
pub inline fn selectfile_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB15]);
}
/// variables.h:1285 — selectfile_var10: (*(uint8*)(g_ram+0xB16))
pub inline fn selectfile_var10() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB16]);
}
/// variables.h:1286 — selectfile_var2: (*(uint8*)(g_ram+0xB9D))
pub inline fn selectfile_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xB9D]);
}
/// variables.h:1288 — blastwall_var5: ((uint8*)(g_ram+0x10000))
pub inline fn blastwall_var5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10000]);
}
/// variables.h:1289 — blastwall_var6: ((uint8*)(g_ram+0x10008))
pub inline fn blastwall_var6() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10008]);
}
/// variables.h:1290 — blastwall_var1: (*(uint8*)(g_ram+0x10010))
pub inline fn blastwall_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x10010]);
}
/// variables.h:1292 — blastwall_var8: (*(uint16*)(g_ram+0x10018))
pub inline fn blastwall_var8() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10018]);
}
/// variables.h:1293 — blastwall_var9: (*(uint16*)(g_ram+0x1001A))
pub inline fn blastwall_var9() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1001A]);
}
/// variables.h:1295 — blastwall_var10: ((uint16*)(g_ram+0x10020))
pub inline fn blastwall_var10() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10020]);
}
/// variables.h:1296 — blastwall_var11: ((uint16*)(g_ram+0x10030))
pub inline fn blastwall_var11() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10030]);
}
///   also defined at variables.h:1388 (identical alias)
/// variables.h:1315 — happiness_pond_y_vel: ((uint8*)(g_ram+0x15800))
pub inline fn happiness_pond_y_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15800]);
}
///   also defined at variables.h:1389 (identical alias)
/// variables.h:1316 — happiness_pond_x_vel: ((uint8*)(g_ram+0x1580C))
pub inline fn happiness_pond_x_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1580C]);
}
///   also defined at variables.h:1390 (identical alias)
/// variables.h:1317 — happiness_pond_z_vel: ((uint8*)(g_ram+0x15818))
pub inline fn happiness_pond_z_vel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15818]);
}
///   also defined at variables.h:1391 (identical alias)
/// variables.h:1318 — happiness_pond_y_lo: ((uint8*)(g_ram+0x15824))
pub inline fn happiness_pond_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15824]);
}
///   also defined at variables.h:1392 (identical alias)
/// variables.h:1319 — happiness_pond_y_hi: ((uint8*)(g_ram+0x15830))
pub inline fn happiness_pond_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15830]);
}
///   also defined at variables.h:1393 (identical alias)
/// variables.h:1320 — happiness_pond_x_lo: ((uint8*)(g_ram+0x1583C))
pub inline fn happiness_pond_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1583C]);
}
///   also defined at variables.h:1394 (identical alias)
/// variables.h:1321 — happiness_pond_x_hi: ((uint8*)(g_ram+0x15848))
pub inline fn happiness_pond_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15848]);
}
///   also defined at variables.h:1395 (identical alias)
/// variables.h:1322 — happiness_pond_z: ((uint8*)(g_ram+0x15854))
pub inline fn happiness_pond_z() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15854]);
}
///   also defined at variables.h:1396 (identical alias)
/// variables.h:1323 — happiness_pond_timer: ((uint8*)(g_ram+0x15860))
pub inline fn happiness_pond_timer() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15860]);
}
///   also defined at variables.h:1397 (identical alias)
/// variables.h:1324 — happiness_pond_arr1: ((uint8*)(g_ram+0x1586C))
pub inline fn happiness_pond_arr1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1586C]);
}
///   also defined at variables.h:1398 (identical alias)
/// variables.h:1325 — happiness_pond_item_to_link: ((uint8*)(g_ram+0x1587A))
pub inline fn happiness_pond_item_to_link() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1587A]);
}
///   also defined at variables.h:1399 (identical alias)
/// variables.h:1326 — happiness_pond_y_subpixel: ((uint8*)(g_ram+0x15886))
pub inline fn happiness_pond_y_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15886]);
}
///   also defined at variables.h:1400 (identical alias)
/// variables.h:1327 — happiness_pond_x_subpixel: ((uint8*)(g_ram+0x15892))
pub inline fn happiness_pond_x_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15892]);
}
///   also defined at variables.h:1401 (identical alias)
/// variables.h:1328 — happiness_pond_z_subpixel: ((uint8*)(g_ram+0x1589E))
pub inline fn happiness_pond_z_subpixel() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1589E]);
}
///   also defined at variables.h:1402 (identical alias)
/// variables.h:1329 — happiness_pond_step: ((uint8*)(g_ram+0x158AA))
pub inline fn happiness_pond_step() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x158AA]);
}
/// variables.h:1341 — weathervane_arr3: ((uint8*)(g_ram+0x15800))
pub inline fn weathervane_arr3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15800]);
}
/// variables.h:1342 — weathervane_arr4: ((uint8*)(g_ram+0x1580C))
pub inline fn weathervane_arr4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1580C]);
}
/// variables.h:1343 — weathervane_arr5: ((uint8*)(g_ram+0x15818))
pub inline fn weathervane_arr5() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15818]);
}
/// variables.h:1344 — weathervane_arr6: ((uint8*)(g_ram+0x15824))
pub inline fn weathervane_arr6() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15824]);
}
/// variables.h:1345 — weathervane_arr7: ((uint8*)(g_ram+0x15830))
pub inline fn weathervane_arr7() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15830]);
}
/// variables.h:1346 — weathervane_arr8: ((uint8*)(g_ram+0x1583C))
pub inline fn weathervane_arr8() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1583C]);
}
/// variables.h:1347 — weathervane_arr9: ((uint8*)(g_ram+0x15848))
pub inline fn weathervane_arr9() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15848]);
}
/// variables.h:1348 — weathervane_arr10: ((uint8*)(g_ram+0x15854))
pub inline fn weathervane_arr10() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15854]);
}
/// variables.h:1349 — weathervane_arr11: ((uint8*)(g_ram+0x15860))
pub inline fn weathervane_arr11() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15860]);
}
/// variables.h:1350 — weathervane_arr12: ((uint8*)(g_ram+0x1586C))
pub inline fn weathervane_arr12() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1586C]);
}
/// variables.h:1351 — weathervane_var13: (*(uint8*)(g_ram+0x15878))
pub inline fn weathervane_var13() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15878]);
}
/// variables.h:1352 — weathervane_var14: (*(uint8*)(g_ram+0x15879))
pub inline fn weathervane_var14() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15879]);
}
/// variables.h:1353 — weathervane_var2: (*(uint16*)(g_ram+0x158B6))
pub inline fn weathervane_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x158B6]);
}
/// variables.h:1354 — weathervane_var1: (*(uint8*)(g_ram+0x158B8))
pub inline fn weathervane_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x158B8]);
}
/// variables.h:1357 — scratch_0: (*(uint16*)(g_ram+0x72))
pub inline fn scratch_0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x72]);
}
/// variables.h:1358 — scratch_1: (*(uint16*)(g_ram+0x74))
pub inline fn scratch_1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x74]);
}
/// variables.h:1360 — messaging_buf: ((uint16*)(g_ram+0x10000))
pub inline fn messaging_buf() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x10000]);
}
/// variables.h:1361 — quake_arr1: ((uint8*)(g_ram+0x15800))
pub inline fn quake_arr1() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15800]);
}
/// variables.h:1362 — quake_arr2: ((uint8*)(g_ram+0x15805))
pub inline fn quake_arr2() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15805]);
}
/// variables.h:1363 — quake_var5: (*(uint8*)(g_ram+0x1580A))
pub inline fn quake_var5() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1580A]);
}
/// variables.h:1364 — quake_var1: (*(uint16*)(g_ram+0x1580B))
pub inline fn quake_var1() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1580B]);
}
/// variables.h:1365 — quake_var2: (*(uint16*)(g_ram+0x1580D))
pub inline fn quake_var2() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1580D]);
}
/// variables.h:1366 — quake_var4: (*(uint8*)(g_ram+0x1580F))
pub inline fn quake_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1580F]);
}
/// variables.h:1367 — ether_y3: (*(uint16*)(g_ram+0x15810))
pub inline fn ether_y3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15810]);
}
/// variables.h:1368 — ether_var1: (*(uint8*)(g_ram+0x15812))
pub inline fn ether_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15812]);
}
/// variables.h:1369 — ether_y: (*(uint16*)(g_ram+0x15813))
pub inline fn ether_y() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15813]);
}
/// variables.h:1370 — ether_x: (*(uint16*)(g_ram+0x15815))
pub inline fn ether_x() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15815]);
}
/// variables.h:1371 — quake_var3: (*(uint16*)(g_ram+0x1581E))
pub inline fn quake_var3() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1581E]);
}
/// variables.h:1372 — bombos_arr7: ((uint8*)(g_ram+0x15820))
pub inline fn bombos_arr7() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15820]);
}
/// variables.h:1373 — bombos_y_lo: ((uint8*)(g_ram+0x15824))
pub inline fn bombos_y_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15824]);
}
/// variables.h:1374 — bombos_y_hi: ((uint8*)(g_ram+0x15864))
pub inline fn bombos_y_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15864]);
}
/// variables.h:1375 — bombos_x_lo: ((uint8*)(g_ram+0x158A4))
pub inline fn bombos_x_lo() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x158A4]);
}
/// variables.h:1376 — bombos_x_hi: ((uint8*)(g_ram+0x158E4))
pub inline fn bombos_x_hi() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x158E4]);
}
/// variables.h:1377 — bombos_y_coord2: ((uint16*)(g_ram+0x15924))
pub inline fn bombos_y_coord2() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15924]);
}
/// variables.h:1378 — bombos_x_coord2: ((uint16*)(g_ram+0x1592C))
pub inline fn bombos_x_coord2() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1592C]);
}
/// variables.h:1379 — bombos_var4: (*(uint8*)(g_ram+0x15934))
pub inline fn bombos_var4() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15934]);
}
/// variables.h:1380 — bombos_arr3: ((uint8*)(g_ram+0x15935))
pub inline fn bombos_arr3() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15935]);
}
/// variables.h:1381 — bombos_arr4: ((uint8*)(g_ram+0x15945))
pub inline fn bombos_arr4() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15945]);
}
/// variables.h:1382 — bombos_y_coord: ((uint16*)(g_ram+0x15955))
pub inline fn bombos_y_coord() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x15955]);
}
/// variables.h:1383 — bombos_x_coord: ((uint16*)(g_ram+0x159D5))
pub inline fn bombos_x_coord() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x159D5]);
}
/// variables.h:1384 — bombos_var3: (*(uint8*)(g_ram+0x15A55))
pub inline fn bombos_var3() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15A55]);
}
/// variables.h:1385 — bombos_var2: (*(uint8*)(g_ram+0x15A56))
pub inline fn bombos_var2() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15A56]);
}
/// variables.h:1386 — bombos_var1: (*(uint8*)(g_ram+0x15A57))
pub inline fn bombos_var1() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x15A57]);
}
/// variables.h:1405 — turn_on_off_water_ctr: (*(uint8*)(g_ram+0x424))
pub inline fn turn_on_off_water_ctr() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0x424]);
}
/// variables.h:1406 — sprite_N_word: ((uint16*)(g_ram+0xBC0))
pub inline fn sprite_N_word() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0xBC0]);
}
/// variables.h:1407 — sprite_where_in_overworld: ((uint8*)(g_ram+0x1DF80))
pub inline fn sprite_where_in_overworld() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DF80]);
}
/// variables.h:1408 — alt_sprite_B: ((uint8*)(g_ram+0x1FA5C))
pub inline fn alt_sprite_B() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1FA5C]);
}
/// variables.h:1410 — vram_upload_offset: (*(uint16*)(g_ram+0x1000))
pub inline fn vram_upload_offset() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1000]);
}
/// variables.h:1411 — vram_upload_data: ((uint16*)(g_ram+0x1002))
pub inline fn vram_upload_data() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1002]);
}
/// variables.h:1412 — vram_upload_tile_buf: ((uint16*)(g_ram+0x1100))
pub inline fn vram_upload_tile_buf() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1100]);
}
/// variables.h:1413 — overworld_entrance_sequence_counter: (*(uint8*)(g_ram+0xc8))
pub inline fn overworld_entrance_sequence_counter() *align(1) t.uint8 {
    return @ptrCast(&g_ram[0xc8]);
}
/// variables.h:1416 — overworld_tileattr: ((uint16*)(g_ram+0x2000))
pub inline fn overworld_tileattr() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x2000]);
}
/// variables.h:1418 — dung_line_ptrs_row0: (*(uint16*)(g_ram+0xbf))
pub inline fn dung_line_ptrs_row0() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xbf]);
}
/// variables.h:1419 — star_shaped_switches_tile: ((uint16*)(g_ram+0x6A0))
pub inline fn star_shaped_switches_tile() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6A0]);
}
/// variables.h:1420 — dung_inter_starcases: ((uint16*)(g_ram+0x6B0))
pub inline fn dung_inter_starcases() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6B0]);
}
/// variables.h:1421 — dung_stairs_table_1: ((uint16*)(g_ram+0x6B8))
pub inline fn dung_stairs_table_1() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x6B8]);
}
/// variables.h:1427 — R16: (*(uint16*)(g_ram+0xc8))
pub inline fn R16() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xc8]);
}
/// variables.h:1428 — R18: (*(uint16*)(g_ram+0xca))
pub inline fn R18() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xca]);
}
/// variables.h:1429 — R20: (*(uint16*)(g_ram+0xcc))
pub inline fn R20() *align(1) t.uint16 {
    return @ptrCast(&g_ram[0xcc]);
}
/// variables.h:1432 — hdma_table_dynamic_orig_pos: ((uint16*)(g_ram+0x1B00))
pub inline fn hdma_table_dynamic_orig_pos() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1B00]);
}
/// variables.h:1433 — hdma_table_dynamic: ((uint16*)(g_ram+0x1DBA0))
pub inline fn hdma_table_dynamic() [*]align(1) t.uint16 {
    return @ptrCast(&g_ram[0x1DBA0]);
}
/// variables.h:1436 — msu_resume_info: ((uint8*)(g_ram+0x1DB60))
pub inline fn msu_resume_info() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DB60]);
}
/// variables.h:1438 — msu_resume_info_alt: ((uint8*)(g_ram+0x1DB20))
pub inline fn msu_resume_info_alt() [*]align(1) t.uint8 {
    return @ptrCast(&g_ram[0x1DB20]);
}
