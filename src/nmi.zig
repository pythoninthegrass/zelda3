// Port of src/nmi.c: the per-frame NMI (vblank) handler — VRAM/CGRAM/OAM
// upload from the RAM-mirrored staging buffers, PPU scroll/mode register
// writes, joypad edge-detection, and the "NMI subroutine" dispatch table
// used by the overworld/dungeon/menu code to request one-shot VRAM uploads.
// Every exported function keeps its exact C-ABI name and signature so the
// remaining .c callers link unchanged. All game state lives in g_ram
// (variables.zig accessors), byte-for-byte where the original 65816 code
// and the RAM-compare oracle expect it.
//
// g_zenv.ppu is typed `?*anyopaque` in variables.zig (ZeldaEnv) so this file
// never needs to `@import` snes/ppu.zig just to reach `cgram`/`oam` — doing
// so would resolve relative to this file's own directory (src/, not the
// repo root) and would also pull every `pub export fn` in ppu.zig into this
// object, duplicating symbols already linked in via the "ppu" object.
// Instead, PpuCopyCgramFromBuffer/PpuCopyOamFromBuffer (added to
// snes/ppu.zig) take an opaque pointer and do the cast on that side.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

extern fn zelda_ppu_write(adr: u32, val: u8) void;
extern fn zelda_apu_write(adr: u32, val: u8) void;
extern fn zelda_apu_read(adr: u32) u8;
extern fn ZeldaIsPlayingMusicTrackWithBug(track: t.uint8) bool;
extern fn ZeldaPlayMsuAudioTrack(track: t.uint8) void;
extern fn GetLightOverworldTilemap() [*]const t.uint8;
extern var g_asset_ptrs: [165]?[*]const t.uint8;

extern fn PpuCopyCgramFromBuffer(ppu: *anyopaque, src: [*]const t.uint8) void;
extern fn PpuCopyOamFromBuffer(ppu: *anyopaque, src: [*]const t.uint8) void;

// snes/snes_regs.h register addresses used by WritePpuRegisters.
const INIDISP: u32 = 0x2100;
const BGMODE: u32 = 0x2105;
const MOSAIC: u32 = 0x2106;
const BG12NBA: u32 = 0x210b;
const BG34NBA: u32 = 0x210c;
const BG1HOFS: u32 = 0x210d;
const BG1VOFS: u32 = 0x210e;
const BG2HOFS: u32 = 0x210f;
const BG2VOFS: u32 = 0x2110;
const BG3HOFS: u32 = 0x2111;
const BG3VOFS: u32 = 0x2112;
const M7B: u32 = 0x211c;
const M7C: u32 = 0x211d;
const M7X: u32 = 0x211f;
const M7Y: u32 = 0x2120;
const W12SEL: u32 = 0x2123;
const W34SEL: u32 = 0x2124;
const WOBJSEL: u32 = 0x2125;
const TM: u32 = 0x212c;
const TS: u32 = 0x212d;
const TMW: u32 = 0x212e;
const TSW: u32 = 0x212f;
const CGWSEL: u32 = 0x2130;
const CGADSUB: u32 = 0x2131;
const COLDATA: u32 = 0x2132;
const APUI01: u32 = 0x2141;
const APUI02: u32 = 0x2142;
const APUI03: u32 = 0x2143;

// assets.h: g_asset_ptrs-indexed macros this file uses.
inline fn kLinkGraphics() [*]const t.uint8 {
    return g_asset_ptrs[57].?;
}
inline fn kBgTilemap_0() [*]const t.uint8 {
    return g_asset_ptrs[99].?;
}
inline fn kBgTilemap_1() [*]const t.uint8 {
    return g_asset_ptrs[100].?;
}
inline fn kBgTilemap_2() [*]const t.uint8 {
    return g_asset_ptrs[101].?;
}
inline fn kBgTilemap_3() [*]const t.uint8 {
    return g_asset_ptrs[102].?;
}
inline fn kBgTilemap_4() [*]const t.uint8 {
    return g_asset_ptrs[103].?;
}
inline fn kBgTilemap_5() [*]const t.uint8 {
    return g_asset_ptrs[104].?;
}

const kNmiVramAddrs = [_]t.uint8{
    0,  0,  4,  8,  12, 8,  12, 0,  4,  0,  8,  4,  12, 4,  12, 0,
    8,  16, 20, 24, 28, 24, 28, 16, 20, 16, 24, 20, 28, 20, 28, 16,
    24, 96, 104,
};

const PlayerHandlerFunc = fn () callconv(.c) void;

const kNmiSubroutines: [25]*const PlayerHandlerFunc = .{
    &NMI_UploadTilemap_doNothing,
    &NMI_UploadTilemap,
    &NMI_UploadBG3Text,
    &NMI_UpdateOWScroll,
    &NMI_UpdateSubscreenOverlay,
    &NMI_UpdateBG1Wall,
    &NMI_TileMapNothing,
    &NMI_UpdateLoadLightWorldMap,
    &NMI_UpdateBG2Left,
    &NMI_UpdateBGChar3and4,
    &NMI_UpdateBGChar5and6,
    &NMI_UpdateBGCharHalf,
    &NMI_UploadSubscreenOverlayLatter,
    &NMI_UploadSubscreenOverlayFormer,
    &NMI_UpdateBGChar0,
    &NMI_UpdateBGChar1,
    &NMI_UpdateBGChar2,
    &NMI_UpdateBGChar3,
    &NMI_UpdateObjChar0,
    &NMI_UpdateObjChar2,
    &NMI_UpdateObjChar3,
    &NMI_UploadDarkWorldMap,
    &NMI_UploadGameOverText,
    &NMI_UpdatePegTiles,
    &NMI_UpdateStarTiles,
};

pub export fn NMI_UploadSubscreenOverlayFormer() void {
    NMI_HandleArbitraryTileMap(@ptrCast(&v.g_ram[0x12000]), 0, 0x40);
}

pub export fn NMI_UploadSubscreenOverlayLatter() void {
    NMI_HandleArbitraryTileMap(@ptrCast(&v.g_ram[0x13000]), 0x40, 0x80);
}

fn CopyToVram(dstv: u32, src: [*]const t.uint8, len: c_int) void {
    const dst: [*]t.uint8 = @ptrCast(v.g_zenv.vram.? + dstv);
    const l: usize = @intCast(len);
    @memcpy(dst[0..l], src[0..l]);
}

fn CopyToVramVertical(dstv: u32, src_in: [*]const t.uint8, len: c_int) void {
    std.debug.assert((len & 1) == 0);
    var dst: [*]t.uint16 = v.g_zenv.vram.? + dstv;
    var src = src_in;
    var i: c_int = 0;
    const i_end: c_int = len >> 1;
    while (i < i_end) : ({
        i += 1;
        dst += 32;
        src += 2;
    }) {
        dst[0] = t.word(&src[0]).*;
    }
}

fn CopyToVramLow(src: [*]const t.uint8, addr: u32, num: c_int) void {
    const dst: [*]t.uint16 = v.g_zenv.vram.? + addr;
    var i: usize = 0;
    while (i < @as(usize, @intCast(num))) : (i += 1) {
        dst[i] = (dst[i] & 0xff00) | @as(u16, src[i]);
    }
}

pub export fn WritePpuRegisters() void {
    zelda_ppu_write(W12SEL, v.W12SEL_copy().*);
    zelda_ppu_write(W34SEL, v.W34SEL_copy().*);
    zelda_ppu_write(WOBJSEL, v.WOBJSEL_copy().*);
    zelda_ppu_write(CGWSEL, v.CGWSEL_copy().*);
    zelda_ppu_write(CGADSUB, v.CGADSUB_copy().*);
    zelda_ppu_write(COLDATA, v.COLDATA_copy0().*);
    zelda_ppu_write(COLDATA, v.COLDATA_copy1().*);
    zelda_ppu_write(COLDATA, v.COLDATA_copy2().*);
    zelda_ppu_write(TM, v.TM_copy().*);
    zelda_ppu_write(TS, v.TS_copy().*);
    zelda_ppu_write(TMW, v.TMW_copy().*);
    zelda_ppu_write(TSW, v.TSW_copy().*);
    zelda_ppu_write(BG1HOFS, @truncate(v.BG1HOFS_copy().*));
    zelda_ppu_write(BG1HOFS, @truncate(v.BG1HOFS_copy().* >> 8));
    zelda_ppu_write(BG1VOFS, @truncate(v.BG1VOFS_copy().*));
    zelda_ppu_write(BG1VOFS, @truncate(v.BG1VOFS_copy().* >> 8));
    zelda_ppu_write(BG2HOFS, @truncate(v.BG2HOFS_copy().*));
    zelda_ppu_write(BG2HOFS, @truncate(v.BG2HOFS_copy().* >> 8));
    zelda_ppu_write(BG2VOFS, @truncate(v.BG2VOFS_copy().*));
    zelda_ppu_write(BG2VOFS, @truncate(v.BG2VOFS_copy().* >> 8));
    zelda_ppu_write(BG3HOFS, @truncate(v.BG3HOFS_copy2().*));
    zelda_ppu_write(BG3HOFS, @truncate(v.BG3HOFS_copy2().* >> 8));
    zelda_ppu_write(BG3VOFS, @truncate(v.BG3VOFS_copy2().*));
    zelda_ppu_write(BG3VOFS, @truncate(v.BG3VOFS_copy2().* >> 8));
    zelda_ppu_write(INIDISP, v.INIDISP_copy().*);
    zelda_ppu_write(MOSAIC, v.MOSAIC_copy().*);
    zelda_ppu_write(BGMODE, v.BGMODE_copy().*);
    if ((v.BGMODE_copy().* & 7) == 7) {
        zelda_ppu_write(M7B, 0);
        zelda_ppu_write(M7B, 0);
        zelda_ppu_write(M7C, 0);
        zelda_ppu_write(M7C, 0);
        zelda_ppu_write(M7X, @truncate(v.M7X_copy().*));
        zelda_ppu_write(M7X, @truncate(v.M7X_copy().* >> 8));
        zelda_ppu_write(M7Y, @truncate(v.M7Y_copy().*));
        zelda_ppu_write(M7Y, @truncate(v.M7Y_copy().* >> 8));
    }
    zelda_ppu_write(BG12NBA, 0x22);
    zelda_ppu_write(BG34NBA, 7);
}

fn Interrupt_NMI_AudioParts_Locked() void {
    if (v.music_control().* == 0) {
        //    if (zelda_apu_read(APUI00) == last_music_control)
        //      zelda_apu_write(APUI00, 0);
        // Zelda causes unwanted music change when going in a portal. last_music_control doesn't hold the
        // song but the last applied effect
    } else if (!ZeldaIsPlayingMusicTrackWithBug(v.music_control().*)) {
        v.last_music_control().* = v.music_control().*;
        ZeldaPlayMsuAudioTrack(v.music_control().*);
        if (v.music_control().* < 0xf2)
            v.music_unk1().* = v.music_control().*;
        v.music_control().* = 0;
    }

    if (v.sound_effect_ambient().* == 0) {
        if (zelda_apu_read(APUI01) == v.sound_effect_ambient_last().*)
            zelda_apu_write(APUI01, 0);
    } else {
        v.sound_effect_ambient_last().* = v.sound_effect_ambient().*;
        zelda_apu_write(APUI01, v.sound_effect_ambient().*);
        v.sound_effect_ambient().* = 0;
    }
    zelda_apu_write(APUI02, v.sound_effect_1().*);
    zelda_apu_write(APUI03, v.sound_effect_2().*);
    v.sound_effect_1().* = 0;
    v.sound_effect_2().* = 0;
}

pub export fn Interrupt_NMI(joypad_input: t.uint16) void { // 8080c9
    Interrupt_NMI_AudioParts_Locked();

    if (v.nmi_boolean().* == 0) {
        v.nmi_boolean().* = 1;
        NMI_DoUpdates();
        NMI_ReadJoypads(joypad_input);
    }

    if (v.is_nmi_thread_active().* != 0) {
        NMI_UpdateIRQGFX();
        v.thread_other_stack().* = if (v.thread_other_stack().* != 0x1f31) 0x1f31 else 0x1f2;
    }
    WritePpuRegisters();
}

pub export fn NMI_ReadJoypads(joypad_input: t.uint16) void { // 8083d1
    var both: u16 = joypad_input;
    var reversed: u16 = 0;
    var i: u32 = 0;
    while (i < 16) : ({
        i += 1;
        both >>= 1;
    }) {
        reversed = reversed *% 2 +% (both & 1);
    }
    const r0: u8 = @truncate(reversed);
    const r1: u8 = @truncate(reversed >> 8);

    v.joypad1L_last().* = r0;
    v.filtered_joypad_L().* = (r0 ^ v.joypad1L_last2().*) & r0;
    v.joypad1L_last2().* = r0;

    v.joypad1H_last().* = r1;
    v.filtered_joypad_H().* = (r1 ^ v.joypad1H_last2().*) & r1;
    v.joypad1H_last2().* = r1;
}

pub export fn NMI_DoUpdates() void { // 8089e0
    if (v.nmi_disable_core_updates().* == 0) {
        CopyToVram(0x4100, kLinkGraphics() + (v.dma_source_addr_0().* - 0x8000), 0x40);
        CopyToVram(0x4120, kLinkGraphics() + (v.dma_source_addr_1().* - 0x8000), 0x40);
        CopyToVram(0x4140, kLinkGraphics() + (v.dma_source_addr_2().* - 0x8000), 0x20);

        CopyToVram(0x4000, kLinkGraphics() + (v.dma_source_addr_3().* - 0x8000), 0x40);
        CopyToVram(0x4020, kLinkGraphics() + (v.dma_source_addr_4().* - 0x8000), 0x40);
        CopyToVram(0x4040, kLinkGraphics() + (v.dma_source_addr_5().* - 0x8000), 0x20);

        CopyToVram(0x4050, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_6().*)]), 0x40);
        CopyToVram(0x4070, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_7().*)]), 0x40);
        CopyToVram(0x4090, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_8().*)]), 0x40);
        CopyToVram(0x40b0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_9().*)]), 0x20);
        CopyToVram(0x40c0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_10().*)]), 0x40);
        CopyToVram(0x4150, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_11().*)]), 0x40);
        CopyToVram(0x4170, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_12().*)]), 0x40);
        CopyToVram(0x4190, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_13().*)]), 0x40);
        CopyToVram(0x41b0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_14().*)]), 0x20);
        CopyToVram(0x41c0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_15().*)]), 0x40);
        CopyToVram(0x4200, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_16().*)]), 0x40);
        CopyToVram(0x4220, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_17().*)]), 0x40);
        CopyToVram(0x4240, @ptrCast(&v.g_ram[0xbd40]), 0x40);
        CopyToVram(0x4300, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_18().*)]), 0x40);
        CopyToVram(0x4320, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_19().*)]), 0x40);
        CopyToVram(0x4340, @ptrCast(&v.g_ram[0xbd80]), 0x40);

        if (t.byte(v.flag_travel_bird()).* != 0) {
            CopyToVram(0x40e0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_20().*)]), 0x40);
            CopyToVram(0x41e0, @ptrCast(&v.g_ram[@as(usize, v.dma_source_addr_21().*)]), 0x40);
        }

        CopyToVram(v.animated_tile_vram_addr().*, @ptrCast(&v.g_ram[@as(usize, v.animated_tile_data_src().*)]), 0x400);
    }

    if (v.flag_update_hud_in_nmi().* != 0) {
        CopyToVram(v.word_7E0219().*, @ptrCast(v.hud_tile_indices_buffer()), 165 * @sizeOf(t.uint16));
    }

    if (v.flag_update_cgram_in_nmi().* != 0) {
        PpuCopyCgramFromBuffer(v.g_zenv.ppu.?, @ptrCast(v.main_palette_buffer()));
    }

    v.flag_update_hud_in_nmi().* = 0;
    v.flag_update_cgram_in_nmi().* = 0;

    PpuCopyOamFromBuffer(v.g_zenv.ppu.?, @ptrCast(&v.g_ram[0x800]));

    if (v.nmi_load_bg_from_vram().* != 0) {
        const p: [*]const t.uint8 = switch (v.nmi_load_bg_from_vram().*) {
            1 => @ptrCast(&v.g_ram[0x1002]),
            2 => @ptrCast(&v.g_ram[0x1000]),
            3 => kBgTilemap_0(),
            4 => @ptrCast(&v.g_ram[0x21b]),
            5 => kBgTilemap_1(),
            6 => kBgTilemap_2(),
            7 => kBgTilemap_3(),
            8 => kBgTilemap_4(),
            9 => kBgTilemap_5(),
            else => @panic("NMI_DoUpdates: bad nmi_load_bg_from_vram"),
        };
        HandleStripes14(p);
        if (v.nmi_load_bg_from_vram().* == 1)
            v.vram_upload_offset().* = 0;
        v.nmi_load_bg_from_vram().* = 0;
    }

    if (v.nmi_update_tilemap_dst().* != 0) {
        const dstv: u32 = @as(u32, v.nmi_update_tilemap_dst().*) * 256;
        const src: [*]const t.uint8 = @ptrCast(&v.g_ram[0x10000 + @as(usize, v.nmi_update_tilemap_src().*)]);
        CopyToVram(dstv, src, 0x200);
        v.nmi_update_tilemap_dst().* = 0;
    }

    if (v.nmi_copy_packets_flag().* != 0) {
        var p: [*]t.uint8 = @ptrCast(&v.uvram().data);
        while (true) {
            const dst: u32 = t.word(&p[0]).*;
            const vmain: u8 = p[2];
            const len: usize = p[3];
            p += 4;
            if (vmain == 0x80) {
                // plain copy
                CopyToVram(dst, p, @intCast(len));
            } else if (vmain == 0x81) {
                // copy with other increment
                std.debug.assert((len & 1) == 0);
                var dp: [*]t.uint16 = v.g_zenv.vram.? + dst;
                var i: usize = 0;
                while (i < len) : ({
                    i += 2;
                    dp += 32;
                }) {
                    dp[0] = t.word(&p[i]).*;
                }
            } else {
                @panic("NMI_DoUpdates: bad vmain in copy-packets");
            }
            p += len;
            if (t.word(&p[0]).* == 0xffff) break;
        }
        v.nmi_copy_packets_flag().* = 0;
        v.nmi_disable_core_updates().* = 0;
    }

    const idx: usize = v.nmi_subroutine_index().*;
    v.nmi_subroutine_index().* = 0;
    kNmiSubroutines[idx]();
}

pub export fn NMI_UploadTilemap() void { // 808cb0
    const idx: usize = t.byte(v.nmi_load_target_addr()).*;
    const dstv: u32 = @as(u32, kNmiVramAddrs[idx]) << 8;
    CopyToVram(dstv, @ptrCast(&v.g_ram[0x1000]), 0x800);

    t.word(&v.g_ram[0x1000]).* = 0;
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UploadTilemap_doNothing() void {} // 808ce3

pub export fn NMI_UploadBG3Text() void { // 808ce4
    CopyToVram(0x7c00, @ptrCast(&v.g_ram[0x10000]), 0x7e0);
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateOWScroll() void { // 808d13
    var src: [*]t.uint8 = @ptrCast(&v.uvram().data);
    const f: u32 = t.word(&src[0]).*;
    const step: u32 = if ((f & 0x8000) != 0) 32 else 1;
    const len: u32 = f & 0x3fff;
    src += 2;
    while (true) {
        var dst: [*]t.uint16 = v.g_zenv.vram.? + t.word(&src[0]).*;
        src += 2;
        var i: u32 = 0;
        const i_end: u32 = len >> 1;
        while (i < i_end) : ({
            i += 1;
            dst += step;
            src += 2;
        }) {
            dst[0] = t.word(&src[0]).*;
        }
        if ((src[1] & 0x80) != 0) break;
    }
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateSubscreenOverlay() void { // 808d62
    NMI_HandleArbitraryTileMap(@ptrCast(&v.g_ram[0x12000]), 0, 0x80);
}

pub export fn NMI_HandleArbitraryTileMap(src_in: [*]const t.uint8, i_in: c_int, i_end: c_int) void { // 808dae
    var src = src_in;
    var i = i_in;
    const r10: [*]align(1) t.uint16 = @ptrCast(v.word_7F4000());
    while (true) {
        const dstv: u32 = r10[@as(usize, @intCast(i >> 1))];
        CopyToVram(dstv, src, 0x80);
        src += 0x80;
        i += 2;
        if (i == i_end) break;
    }
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateBG1Wall() void { // 808e09
    // Secret Wall Right
    CopyToVramVertical(v.nmi_load_target_addr().*, @ptrCast(&v.g_ram[0xc880]), 0x40);
    CopyToVramVertical(@as(u32, v.nmi_load_target_addr().*) + 0x800, @ptrCast(&v.g_ram[0xc8c0]), 0x40);
}

pub export fn NMI_TileMapNothing() void {} // 808e4b

const kLightWorldTileMapDsts = [_]t.uint16{ 0, 0x20, 0x1000, 0x1020 };

pub export fn NMI_UpdateLoadLightWorldMap() void { // 808e54
    var src: [*]const t.uint8 = GetLightOverworldTilemap();
    for (kLightWorldTileMapDsts) |dst0| {
        var dstv: u32 = dst0;
        var i: u32 = 0x20;
        while (i != 0) : (i -= 1) {
            CopyToVramLow(src, dstv, 0x20);
            src += 32;
            dstv += 0x80;
        }
    }
}

pub export fn NMI_UpdateBG2Left() void { // 808ea9
    CopyToVram(0, @ptrCast(&v.g_ram[0x10000]), 0x800);
    CopyToVram(0x800, @ptrCast(&v.g_ram[0x10800]), 0x800);
}

pub export fn NMI_UpdateBGChar3and4() void { // 808ee7
    CopyToVram(0x2c00, @ptrCast(&v.g_ram[0x10000]), 0x1000);
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateBGChar5and6() void { // 808f16
    CopyToVram(0x3400, @ptrCast(&v.g_ram[0x11000]), 0x1000);
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateBGCharHalf() void { // 808f45
    const dstv: u32 = @as(u32, t.byte(v.nmi_load_target_addr()).*) * 256;
    CopyToVram(dstv, @ptrCast(&v.g_ram[0x11000]), 0x400);
}

pub export fn NMI_UpdateBGChar0() void { // 808f72
    NMI_RunTileMapUpdateDMA(0x2000);
}

pub export fn NMI_UpdateBGChar1() void { // 808f79
    NMI_RunTileMapUpdateDMA(0x2800);
}

pub export fn NMI_UpdateBGChar2() void { // 808f80
    NMI_RunTileMapUpdateDMA(0x3000);
}

pub export fn NMI_UpdateBGChar3() void { // 808f87
    NMI_RunTileMapUpdateDMA(0x3800);
}

pub export fn NMI_UpdateObjChar0() void { // 808f8e
    CopyToVram(0x4400, @ptrCast(&v.g_ram[0x10000]), 0x800);
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UpdateObjChar2() void { // 808fbd
    NMI_RunTileMapUpdateDMA(0x5000);
}

pub export fn NMI_UpdateObjChar3() void { // 808fc4
    NMI_RunTileMapUpdateDMA(0x5800);
}

pub export fn NMI_RunTileMapUpdateDMA(dst: c_int) void { // 808fc9
    CopyToVram(@intCast(dst), @ptrCast(&v.g_ram[0x10000]), 0x1000);
    v.nmi_disable_core_updates().* = 0;
}

pub export fn NMI_UploadDarkWorldMap() void { // 808ff3
    var src: [*]const t.uint8 = @ptrCast(&v.g_ram[0x1000]);
    var dstv: u32 = 0x810;
    var i: u32 = 0x20;
    while (i != 0) : (i -= 1) {
        CopyToVramLow(src, dstv, 0x20);
        src += 32;
        dstv += 0x80;
    }
}

pub export fn NMI_UploadGameOverText() void { // 809038
    CopyToVram(0x7800, @ptrCast(&v.g_ram[0x2000]), 0x800);
    CopyToVram(0x7d00, @ptrCast(&v.g_ram[0x3400]), 0x600);
}

pub export fn NMI_UpdatePegTiles() void { // 80908b
    CopyToVram(0x3d00, @ptrCast(&v.g_ram[0x10000]), 0x100);
}

pub export fn NMI_UpdateStarTiles() void { // 8090b7
    CopyToVram(0x3ed0, @ptrCast(&v.g_ram[0x10000]), 0x40);
}

pub export fn HandleStripes14(p_in: [*]const t.uint8) void { // 8092a1
    var p = p_in;
    while ((p[0] & 0x80) == 0) {
        const vmem_addr: usize = t.swap16(t.word(&p[0]).*);
        const vram_incr_amount: u8 = (p[2] & 0x80) >> 7;
        const is_memset: u8 = p[2] & 0x40; // Cpu BUS Address Step  (0=Increment, 2=Decrement, 1/3=Fixed) (DMA only)
        var len: usize = @as(usize, t.swap16(t.word(&p[2]).*) & 0x3fff) + 1;
        p += 4;

        if (vram_incr_amount == 0) {
            const dst: [*]t.uint16 = v.g_zenv.vram.? + vmem_addr;
            if (is_memset != 0) {
                const val: u16 = @as(u16, p[0]) | (@as(u16, p[1]) << 8);
                len = (len + 1) >> 1;
                var i: usize = 0;
                while (i < len) : (i += 1) dst[i] = val;
                p += 2;
            } else {
                const dstb: [*]t.uint8 = @ptrCast(dst);
                @memcpy(dstb[0..len], p[0..len]);
                p += len;
            }
        } else {
            // increment vram by 32 instead of 1
            var dst: [*]t.uint16 = v.g_zenv.vram.? + vmem_addr;
            if (is_memset != 0) {
                const val: u16 = @as(u16, p[0]) | (@as(u16, p[1]) << 8);
                len = (len + 1) >> 1;
                var i: usize = 0;
                while (i < len) : ({
                    i += 1;
                    dst += 32;
                }) dst[0] = val;
                p += 2;
            } else {
                std.debug.assert((len & 1) == 0);
                len >>= 1;
                var i: usize = 0;
                while (i < len) : ({
                    i += 1;
                    dst += 32;
                    p += 2;
                }) {
                    dst[0] = t.word(&p[0]).*;
                }
            }
        }
    }
}

pub export fn NMI_UpdateIRQGFX() void { // 809347
    if (v.nmi_flag_update_polyhedral().* != 0) {
        CopyToVram(0x5800, @ptrCast(&v.g_ram[0xe800]), 0x800);
        v.nmi_flag_update_polyhedral().* = 0;
    }
}
