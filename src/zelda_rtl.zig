// Port of src/zelda_rtl.c: the runtime core / frame-loop glue — ownership
// of g_ram (the WRAM mirror) and g_zenv (the runtime environment: PPU/DMA/
// SPC-player/sRAM/VRAM/dialogue assets), the per-frame loop
// (ZeldaRunFrame -> ZeldaRunFrameInternal -> Module_MainRouting / NMI),
// ZeldaDrawPpuFrame's per-line HDMA replay, the StateRecorder replay/log
// machinery, save/load (SaveLoadSlot, sram), and debug patch commands.
// Every exported function keeps its exact C-ABI name and signature
// (callconv(.c), C-pointer types) so the remaining .c callers link
// unchanged. All game state lives in g_ram, byte-for-byte where the
// original 65816 code and the RAM-compare oracle expect it.
//
// This file now owns the g_ram definition itself (previously zelda_rtl.c).
// Every remaining C translation unit already declares it via
// `extern uint8 g_ram[131072]` in variables.h, so no C-side edits were
// needed. g_zenv/g_wanted_zelda_features/frame_ctr_dbg likewise move here
// from C; variables.zig keeps its `extern var` mirrors for the ported
// Zig modules.
//
// The _DEBUG-only InputStateReadFromFile from the C file is not ported:
// the C build never defines _DEBUG either, and nothing references it.

const std = @import("std");
const builtin = @import("builtin");
const t = @import("types.zig");
const v = @import("variables.zig");

// ---------------------------------------------------------------------------
// Globals this file owns (definitions; the C side sees them via the extern
// declarations in variables.h / zelda_rtl.h / features.h).

pub export var g_ram: [0x20000]u8 = .{0} ** 0x20000;

// v.ZeldaEnv is the layout twin of C's struct ZeldaEnv (src/zelda_rtl.h);
// the field order/widths there are what the C side links against.
pub export var g_zenv: v.ZeldaEnv = .{
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

pub export var g_wanted_zelda_features: t.uint32 = 0; // features.h
pub export var frame_ctr_dbg: c_int = 0; // zelda_rtl.h

// Exported constant tables (other modules extern them; e.g. misc.zig).
pub export const kUpperBitmasks: [16]t.uint16 = .{ 0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200, 0x100, 0x80, 0x40, 0x20, 0x10, 8, 4, 2, 1 };
pub export const kLitTorchesColorPlus: [4]t.uint8 = .{ 31, 8, 4, 0 };
pub export const kDungeonCrystalPendantBit: [13]t.uint8 = .{ 0, 0, 4, 2, 0, 16, 2, 1, 64, 4, 1, 32, 8 };
pub export const kGetBestActionToPerformOnTile_x: [4]t.int8 = .{ 7, 7, -3, 16 };
pub export const kGetBestActionToPerformOnTile_y: [4]t.int8 = .{ 6, 24, 12, 12 };

// ---------------------------------------------------------------------------
// C macros emulated.

// types.h: WORD(x) = *(uint16*)&(x) — the two bytes at |byte| as LE u16.
// The C macro is also applied to bare byte lvalues (e.g. WORD(sram[0x3e5])
// reads two bytes).
inline fn word_at(byte: *t.uint8) t.uint16 {
    const b: [*]t.uint8 = @ptrCast(byte);
    return @as(t.uint16, b[0]) | (@as(t.uint16, b[1]) << 8);
}

// types.h IntMax.
inline fn intMax(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

// variables.h: hdma_table_dynamic — the moved hdma table lives at 0x1DBA0.
inline fn hdmaTableDynamic() [*]t.uint16 {
    return @ptrCast(@alignCast(&g_ram[0x1DBA0]));
}

// features.h: enhanced_features0 is a C-only macro (not in variables.zig),
// so mirror the offset access here (load_gfx.zig precedent).
inline fn enhanced_features0() *align(1) t.uint32 {
    return @ptrCast(&g_ram[0x64c]);
}

// features.h / zelda_rtl.h / types.h / ppu.h constants.
const kRam_APUI00: usize = 0x648;
const kRam_CrystalRotateCounter: usize = 0x649;
const kRam_BugsFixed: usize = 0x64a;
const kRam_Features0: usize = 0x64c;
const kBugFix_PolyRenderer: u8 = 1;
const kBugFix_Latest: u8 = 1;
const kPpuExtraLeftRight: c_int = 96; // types.h: kEnableLargeScreen ? 96 : 0
const kPpuRenderFlags_4x4Mode7: u32 = 2;
const kPpuRenderFlags_Height240: u32 = 4;
const kSaveLoad_Save = 0;
const kSaveLoad_Load = 1;
const kSaveLoad_Replay = 2;

// snes/snes_regs.h register addresses used here.
const INIDISP: u32 = 0x2100;
const BG3HOFS: u32 = 0x2111;
const BG3VOFS: u32 = 0x2112;
const STAT78: u32 = 0x213f;
const DMAP6: u16 = 0x4360;
const BBAD6: u16 = 0x4361;
const A1T6L: u16 = 0x4362;
const A1T6H: u16 = 0x4363;
const A1B6: u16 = 0x4364;
const DAS60: u16 = 0x4367;
const DMAP7: u16 = 0x4370;
const BBAD7: u16 = 0x4371;
const A1T7L: u16 = 0x4372;
const A1T7H: u16 = 0x4373;
const A1B7: u16 = 0x4374;
const DAS70: u16 = 0x4377;

// ---------------------------------------------------------------------------
// Static HDMA table data (C static consts; AT_WORD(x) = x lo, hi).

const bAdrOffsets: [8][4]u8 = .{
    .{ 0, 0, 0, 0 }, .{ 0, 1, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 1, 1 },
    .{ 0, 1, 2, 3 }, .{ 0, 1, 0, 1 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 1, 1 },
};
const transferLength: [8]u8 = .{ 1, 2, 2, 4, 4, 4, 2, 4 };

const kAttractDmaTable0: [13]u8 = .{ 0x20, 0xff, 0x00, 0x50, 0x18, 0xe0, 0x50, 0x18, 0xe0, 1, 0xff, 0x00, 0 };
const kAttractDmaTable1: [10]u8 = .{ 0x48, 0xff, 0x00, 0x30, 0x30, 0xd8, 1, 0xff, 0x00, 0 };
const kHdmaTableForEnding: [19]u8 = .{ 0x52, 0x00, 0x06, 8, 0xe2, 0x00, 8, 0x02, 0x06, 5, 0x04, 0x06, 0x10, 0x06, 0x06, 0x81, 0xe2, 0x00, 0 };
const kSpotlightIndirectHdma: [7]u8 = .{ 0xf8, 0x00, 0x1b, 0xf8, 0xf0, 0x1b, 0 };
const kMapModeHdma0: [7]u8 = .{ 0xf0, 0x27, 0xdd, 0xf0, 0x07, 0xde, 0 };
const kMapModeHdma1: [7]u8 = .{ 0xf0, 0xe7, 0xde, 0xf0, 0xc7, 0xdf, 0 };
const kAttractIndirectHdmaTab: [7]u8 = .{ 0xf0, 0x00, 0x1b, 0xf0, 0xe0, 0x1b, 0 };
const kHdmaTableForPrayingScene: [7]u8 = .{ 0xf8, 0x00, 0x1b, 0xf8, 0xf0, 0x1b, 0 };

// attract.h — still defined in attract.c.
extern const kMapMode_Zooms1: [240]t.uint16;
extern const kMapMode_Zooms2: [240]t.uint16;

// ---------------------------------------------------------------------------
// Externs — ported Zig modules (opaque pointer params; see the
// PpuCopyCgramFromBuffer note in snes/ppu.zig for why this file does not
// @import those modules).

// src/misc.zig
extern fn Module_MainRouting() void;
extern fn NMI_PrepareSprites() void;
extern fn Sound_LoadIntroSongBank() void;
// src/nmi.zig
extern fn Interrupt_NMI(joypad_input: t.uint16) void;
// src/poly.zig
extern fn Poly_RunFrame() void;
// src/util.zig (ByteArray mirrors the C struct in util.h).
const ByteArray = extern struct {
    data: ?[*]t.uint8,
    size: usize,
    capacity: usize,
};
extern fn ByteArray_Resize(arr: *ByteArray, new_size: usize) void;
extern fn ByteArray_Destroy(arr: *ByteArray) void;
extern fn ByteArray_AppendData(arr: *ByteArray, data: [*]const t.uint8, data_size: usize) void;
extern fn ByteArray_AppendByte(arr: *ByteArray, v: t.uint8) void;
extern fn FindIndexInMemblk(data: t.MemBlk, i: usize) t.MemBlk;

// snes/dma.zig — Dma/DmaChannel mirror snes/dma.h (the C file saw them
// through the header too).
const DmaChannel = extern struct {
    bAdr: u8,
    aBank: u8,
    indBank: u8, // hdma
    repCount: u8, // hdma
    aAdr: u16,
    size: u16, // also indirect hdma adr
    tableAdr: u16, // hdma
    unusedByte: u8,
    dmaActive: bool,
    hdmaActive: bool,
    mode: u8,
    fixed: bool,
    decrement: bool,
    indirect: bool, // hdma
    fromB: bool,
    unusedBit: bool,
    doTransfer: bool, // hdma
    terminated: bool, // hdma
    offIndex: u8,
};
const Dma = extern struct {
    snes: ?*anyopaque,
    channel: [8]DmaChannel,
    hdmaTimer: u16,
    dmaTimer: u32,
    dmaBusy: bool,
};
// snes/saveload.h SaveLoadFunc, same type dma.zig/dsp.zig/ppu.zig use.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;
extern fn dma_init(snes: ?*anyopaque) ?*anyopaque;
extern fn dma_reset(dma: *Dma) void;
extern fn dma_write(dma: *Dma, adr: u16, val: u8) void;
extern fn dma_startDma(dma: *Dma, val: u8, hdma: bool) void;
extern fn dma_saveload(dma: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;

// snes/ppu.zig (+ the small opaque accessors added for this port).
extern fn ppu_init() ?*anyopaque;
extern fn ppu_reset(ppu: ?*anyopaque) void;
extern fn ppu_write(ppu: ?*anyopaque, adr: u8, val: u8) void;
extern fn ppu_runLine(ppu: ?*anyopaque, line: c_int) void;
extern fn ppu_saveload(ppu: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn PpuBeginDrawing(ppu: ?*anyopaque, pixels: ?[*]u8, pitch: usize, render_flags: u32) void;
extern fn PpuSetExtraSideSpace(ppu: ?*anyopaque, left: c_int, right: c_int, bottom: c_int) void;
extern fn PpuSetMode7PerspectiveCorrection(ppu: ?*anyopaque, low: c_int, high: c_int) void;
extern fn PpuGetCurrentMode(ppu: ?*anyopaque) u8;
extern fn PpuGetVram(ppu: ?*anyopaque) [*]u16;
extern fn PpuGetExtraSideSpace(ppu: ?*anyopaque) u8;

// snes/dsp.zig, src/spc_player.zig.
extern fn dsp_saveload(dsp: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn SpcPlayer_Create() ?*anyopaque;
extern fn SpcPlayer_Initialize(p: ?*anyopaque) void;
extern fn SpcPlayer_GetRam(p: ?*anyopaque) [*]u8;
extern fn SpcPlayer_GetDsp(p: ?*anyopaque) ?*anyopaque;

// ---------------------------------------------------------------------------
// Externs — remaining C.

// src/main.c (asset loading / apu lock); src/audio.c.
extern fn FindInAssetArray(asset: c_int, idx: c_int) t.MemBlk;
extern fn ZeldaApuLock() void;
extern fn ZeldaApuUnlock() void;
extern fn ZeldaIsMusicPlaying() bool;
extern fn ZeldaPushApuState() void;
extern fn ZeldaRestoreMusicAfterLoad_Locked(is_reset: bool) void;
extern fn ZeldaSaveMusicStateToRam_Locked() void;

// types.h / libc (util.zig style).
extern fn Die(msg: [*:0]const u8) noreturn;

// libc has no such symbol on some platforms — its `stderr` macro expands
// to `__stderrp` (config.zig precedent). Resolve the platform-correct
// symbol so this object links on both.
inline fn stderrPtr() *anyopaque {
    const name = if (builtin.os.tag.isDarwin()) "__stderrp" else "stderr";
    return @extern(*(*anyopaque), .{ .name = name }).*;
}

extern fn fopen(name: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: *anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn printf(fmt: [*:0]const u8, ...) callconv(.c) c_int;
extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) callconv(.c) c_int;
extern fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) callconv(.c) c_int;
extern fn strlen(s: [*]const u8) usize;
extern fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int;
extern fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern fn rename(old_path: [*:0]const u8, new_path: [*:0]const u8) c_int;

// ---------------------------------------------------------------------------
// PPU write helpers (zelda_rtl.h).

pub export fn zelda_ppu_write(adr: u32, val: t.uint8) callconv(.c) void {
    std.debug.assert(adr >= INIDISP and adr <= STAT78);
    ppu_write(g_zenv.ppu.?, @as(u8, @truncate(adr)), val);
}

pub export fn zelda_ppu_write_word(adr: u32, val: t.uint16) callconv(.c) void {
    zelda_ppu_write(adr, @as(t.uint8, @truncate(val)));
    zelda_ppu_write(adr + 1, @as(t.uint8, @truncate(val >> 8)));
}

// ---------------------------------------------------------------------------
// SimpleHdma: the per-line replay of the game's two HDMA channels (C statics).

const SimpleHdma = struct {
    table: ?[*]const t.uint8,
    indir_ptr: ?[*]const t.uint8,
    rep_count: t.uint8,
    mode: t.uint8,
    ppu_addr: t.uint8,
    indir_bank: t.uint8,
};
const SimpleHdmaEmpty = SimpleHdma{ .table = null, .indir_ptr = null, .rep_count = 0, .mode = 0, .ppu_addr = 0, .indir_bank = 0 };

// The C file's static SimpleHdma_GetPtr — every hdma source table the game
// configures, keyed by the 24-bit DMA source address.
inline fn simpleHdmaGetPtr(p: u32) ?[*]const t.uint8 {
    return switch (p) {
        0xCFA87 => @ptrCast(&kAttractDmaTable0[0]),
        0xCFA94 => @ptrCast(&kAttractDmaTable1[0]),
        0xebd53 => @ptrCast(&kHdmaTableForEnding[0]),
        0x0F2FB => @ptrCast(&kSpotlightIndirectHdma[0]),
        0xabdcf => @ptrCast(&kMapModeHdma0[0]), // mode7
        0xabdd6 => @ptrCast(&kMapModeHdma1[0]), // mode7
        0xABDDD => @ptrCast(&kAttractIndirectHdmaTab[0]), // mode7
        0x2c80c => @ptrCast(&kHdmaTableForPrayingScene[0]),
        0x1b00 => @ptrCast(hdmaTableDynamic()),
        0x1be0 => @as([*]const t.uint8, @ptrCast(hdmaTableDynamic())) + 0xe0,
        0x1bf0 => @as([*]const t.uint8, @ptrCast(hdmaTableDynamic())) + 0xf0,
        0xadd27 => @ptrCast(&kMapMode_Zooms1[0]),
        0xade07 => @as([*]const t.uint8, @ptrCast(&kMapMode_Zooms1[0])) + 0xe0,
        0xadee7 => @ptrCast(&kMapMode_Zooms2[0]),
        0xadfc7 => @as([*]const t.uint8, @ptrCast(&kMapMode_Zooms2[0])) + 0xe0,
        0x600 => @ptrCast(&g_ram[0x600]),
        0x602 => @ptrCast(&g_ram[0x602]),
        0x604 => @ptrCast(&g_ram[0x604]),
        0x606 => @ptrCast(&g_ram[0x606]),
        0xe2 => @ptrCast(&g_ram[0xe2]),
        else => {
            // C: assert(0); return NULL; (assert is active in the C build
            // too, so this path aborts there as well).
            @panic("SimpleHdma_GetPtr: unknown hdma table address");
        },
    };
}

inline fn simpleHdmaInit(c: *SimpleHdma, dc: *DmaChannel) void {
    if (!dc.hdmaActive) {
        c.table = null;
        return;
    }
    c.table = simpleHdmaGetPtr(@as(u32, dc.aAdr) | (@as(u32, dc.aBank) << 16));
    c.rep_count = 0;
    c.mode = dc.mode | if (dc.indirect) @as(u8, 1) << 6 else @as(u8, 0);
    c.ppu_addr = dc.bAdr;
    c.indir_bank = dc.indBank;
}

inline fn simpleHdmaDoLine(c: *SimpleHdma) void {
    if (c.table == null)
        return;
    var do_transfer = false;
    if ((c.rep_count & 0x7f) == 0) {
        c.rep_count = c.table.?[0];
        c.table = c.table.? + 1;
        if (c.rep_count == 0) {
            c.table = null;
            return;
        }
        if (c.mode & 0x40 != 0) {
            const tp = c.table.?;
            c.indir_ptr = simpleHdmaGetPtr(@as(u32, c.indir_bank) << 16 | @as(u32, tp[0]) | @as(u32, tp[1]) * 256);
            c.table = tp + 2;
        }
        do_transfer = true;
    }
    if (do_transfer or (c.rep_count & 0x80) != 0) {
        const j_end: usize = transferLength[c.mode & 7];
        var j: usize = 0;
        while (j < j_end) : (j += 1) {
            var wv: u8 = 0;
            if (c.mode & 0x40 != 0) {
                wv = c.indir_ptr.?[0];
                c.indir_ptr = c.indir_ptr.? + 1;
            } else {
                wv = c.table.?[0];
                c.table = c.table.? + 1;
            }
            zelda_ppu_write(0x2100 + @as(u32, c.ppu_addr) + @as(u32, bAdrOffsets[c.mode & 7][j]), wv);
        }
    }
    c.rep_count -= 1;
}

// ---------------------------------------------------------------------------
// Frame drawing.

inline fn configurePpuSideSpace() void {
    // Let the PPU impl know about the maximum allowed extra space on the
    // sides and bottom.
    var extra_right: c_int = 0;
    var extra_left: c_int = 0;
    var extra_bottom: c_int = 0;
    var mod: c_int = v.main_module_index().*;
    if (mod == 14)
        mod = v.saved_module_for_menu().*;
    if (mod == 9) {
        if (v.main_module_index().* == 14 and v.submodule_index().* == 7 and v.overworld_map_state().* >= 4) {
            // World map
            extra_left = kPpuExtraLeftRight;
            extra_right = kPpuExtraLeftRight;
            extra_bottom = 16;
        } else {
            // outdoors
            extra_left = @as(c_int, v.BG2HOFS_copy2().*) - @as(c_int, v.ow_scroll_vars0().xstart);
            extra_right = @as(c_int, v.ow_scroll_vars0().xend) - @as(c_int, v.BG2HOFS_copy2().*);
            extra_bottom = @as(c_int, v.ow_scroll_vars0().yend) - @as(c_int, v.BG2VOFS_copy2().*);
        }
    } else if (mod == 7) {
        // indoors, except when the light cone is in use
        if (!(v.hdr_dungeon_dark_with_lantern().* != 0 and v.TS_copy().* != 0)) {
            const qm: usize = v.quadrant_fullsize_x().* >> 1;
            extra_left = intMax(@as(c_int, v.BG2HOFS_copy2().*) - @as(c_int, v.room_bounds_x().v.v[qm]), 0);
            extra_right = intMax(@as(c_int, v.room_bounds_x().v.v[qm + 2]) - @as(c_int, v.BG2HOFS_copy2().*), 0);
        }
        const qy: usize = v.quadrant_fullsize_y().* >> 1;
        extra_bottom = intMax(@as(c_int, v.room_bounds_y().v.v[qy + 2]) - @as(c_int, v.BG2VOFS_copy2().*), 0);
    } else if (mod == 20 or mod == 0 or mod == 1) {
        extra_left = kPpuExtraLeftRight;
        extra_right = kPpuExtraLeftRight;
        extra_bottom = 16;
    }
    PpuSetExtraSideSpace(g_zenv.ppu.?, extra_left, extra_right, extra_bottom);
}

pub export fn ZeldaDrawPpuFrame(pixel_buffer: [*]t.uint8, pitch: usize, render_flags: u32) callconv(.c) void {
    var hdma_chans: [2]SimpleHdma = .{ SimpleHdmaEmpty, SimpleHdmaEmpty };
    const dma: *Dma = @ptrCast(@alignCast(g_zenv.dma.?));

    PpuBeginDrawing(g_zenv.ppu.?, pixel_buffer, pitch, render_flags);

    dma_startDma(dma, v.HDMAEN_copy().*, true);

    simpleHdmaInit(&hdma_chans[0], &dma.channel[6]);
    simpleHdmaInit(&hdma_chans[1], &dma.channel[7]);

    // Cheat: Let the PPU impl know about the hdma perspective correction so
    // it can avoid guessing.
    if ((render_flags & kPpuRenderFlags_4x4Mode7) != 0 and PpuGetCurrentMode(g_zenv.ppu.?) == 7) {
        if (hdma_chans[0].table == @as([*]const t.uint8, @ptrCast(&kMapModeHdma0[0]))) {
            PpuSetMode7PerspectiveCorrection(g_zenv.ppu.?, kMapMode_Zooms1[0], kMapMode_Zooms1[223]);
        } else if (hdma_chans[0].table == @as([*]const t.uint8, @ptrCast(&kMapModeHdma1[0]))) {
            PpuSetMode7PerspectiveCorrection(g_zenv.ppu.?, kMapMode_Zooms2[0], kMapMode_Zooms2[223]);
        } else if (hdma_chans[0].table == @as([*]const t.uint8, @ptrCast(&kAttractIndirectHdmaTab[0]))) {
            PpuSetMode7PerspectiveCorrection(g_zenv.ppu.?, @as(c_int, hdmaTableDynamic()[0]), @as(c_int, hdmaTableDynamic()[223]));
        } else {
            PpuSetMode7PerspectiveCorrection(g_zenv.ppu.?, 0, 0);
        }
    }

    if (PpuGetExtraSideSpace(g_zenv.ppu.?) != 0 or (render_flags & kPpuRenderFlags_Height240) != 0)
        configurePpuSideSpace();

    const height: c_int = if ((render_flags & kPpuRenderFlags_Height240) != 0) 240 else 224;

    var i: c_int = 0;
    while (i <= height) : (i += 1) {
        if (i == 128 and v.irq_flag().* != 0) {
            zelda_ppu_write(BG3HOFS, @as(t.uint8, @truncate(v.selectfile_var8().*)));
            zelda_ppu_write(BG3HOFS, @as(t.uint8, @truncate(v.selectfile_var8().* >> 8)));
            zelda_ppu_write(BG3VOFS, 0);
            zelda_ppu_write(BG3VOFS, 0);
            if (v.irq_flag().* & 0x80 != 0) {
                v.irq_flag().* = 0;
                // zelda_snes_dummy_write(NMITIMEN, 0x81); — C no-op inline
            }
        }
        ppu_runLine(g_zenv.ppu.?, i);
        simpleHdmaDoLine(&hdma_chans[0]);
        simpleHdmaDoLine(&hdma_chans[1]);
    }
}

pub export fn HdmaSetup(addr6: u32, addr7: u32, transfer_unit: t.uint8, reg6: t.uint8, reg7: t.uint8, indirect_bank: t.uint8) callconv(.c) void {
    const dma: *Dma = @ptrCast(@alignCast(g_zenv.dma.?));
    if (addr6 != 0) {
        dma_write(dma, DMAP6, transfer_unit);
        dma_write(dma, BBAD6, reg6);
        dma_write(dma, A1T6L, @as(u8, @truncate(addr6)));
        dma_write(dma, A1T6H, @as(u8, @truncate(addr6 >> 8)));
        dma_write(dma, A1B6, @as(u8, @truncate(addr6 >> 16)));
        dma_write(dma, DAS60, indirect_bank);
    }
    dma_write(dma, DMAP7, transfer_unit);
    dma_write(dma, BBAD7, reg7);
    dma_write(dma, A1T7L, @as(u8, @truncate(addr7)));
    dma_write(dma, A1T7H, @as(u8, @truncate(addr7 >> 8)));
    dma_write(dma, A1B7, @as(u8, @truncate(addr7 >> 16)));
    dma_write(dma, DAS70, indirect_bank);
}

// ---------------------------------------------------------------------------
// The frame loop.

inline fn startupInitializeMemory() void { // 8087c0
    @memset(g_ram[0..0x2000], 0);
    v.main_palette_buffer()[0] = 0;
    v.srm_var1().* = 0;
    const sram: [*]t.uint8 = g_zenv.sram.?;
    if (word_at(&sram[0x3e5]) != 0x55aa) {
        sram[0x3e5] = 0;
        sram[0x3e6] = 0;
    }
    if (word_at(&sram[0x8e5]) != 0x55aa) {
        sram[0x8e5] = 0;
        sram[0x8e6] = 0;
    }
    if (word_at(&sram[0xde5]) != 0x55aa) {
        sram[0xde5] = 0;
        sram[0xde6] = 0;
    }
    v.INIDISP_copy().* = 0x80;
    v.flag_update_cgram_in_nmi().* += 1;
}

pub export fn ZeldaInitialize() callconv(.c) void {
    g_zenv.dma = dma_init(null);
    g_zenv.ppu = ppu_init();
    g_zenv.ram = @ptrCast(&g_ram[0]);
    g_zenv.sram = @ptrCast(calloc(8192, 1));
    g_zenv.vram = PpuGetVram(g_zenv.ppu.?);
    g_zenv.player = SpcPlayer_Create();
    SpcPlayer_Initialize(g_zenv.player.?);
    dma_reset(@ptrCast(@alignCast(g_zenv.dma.?)));
    ppu_reset(g_zenv.ppu.?);
}

inline fn clearOamBuffer() void { // 80841e
    const buf = v.oam_buf();
    for (0..128) |i|
        buf[i].y = 0xf0;
}

inline fn zeldaRunGameLoop() void {
    v.frame_counter().* += 1;
    clearOamBuffer();
    Module_MainRouting();
    NMI_PrepareSprites();
    v.nmi_boolean().* = 0;
}

inline fn zeldaRunPolyLoop() void {
    if (v.intro_did_run_step().* != 0 and v.nmi_flag_update_polyhedral().* == 0) {
        Poly_RunFrame();
        v.intro_did_run_step().* = 0;
        v.nmi_flag_update_polyhedral().* = 0xff;
    }
}

inline fn zeldaInitializationCode() void {
    // zelda_snes_dummy_write(NMITIMEN/HDMAEN/MDMAEN, 0) — C no-op inlines
    Sound_LoadIntroSongBank();
    startupInitializeMemory();
    v.animated_tile_data_src().* = 0xa680;
    v.dma_source_addr_9().* = 0xb280;
    v.dma_source_addr_14().* = 0xb280 + 0x60;
    // zelda_snes_dummy_write(NMITIMEN, 0x81) — C no-op inline
}

pub export fn ZeldaRunFrameInternal(input: t.uint16, run_what: c_int) callconv(.c) void {
    if (v.animated_tile_data_src().* == 0)
        zeldaInitializationCode();

    if (run_what & 2 != 0)
        zeldaRunPolyLoop();
    if (run_what & 1 != 0)
        zeldaRunGameLoop();
    Interrupt_NMI(input);
}

// ---------------------------------------------------------------------------
// Save / load / state recording.

inline fn incrementCrystalCountdown(a: *t.uint8, value: c_int) c_int {
    const tt: c_int = @as(c_int, a.*) + value;
    const ttu: u32 = @intCast(tt);
    a.* = @as(t.uint8, @truncate(ttu));
    return tt >> 8;
}

var g_emu_memory_ptr: ?[*]t.uint8 = null;
const ZeldaRunFrameFunc = fn (input: t.uint16, run_what: c_int) callconv(.c) void;
const ZeldaSyncAllFunc = fn () callconv(.c) void;
var g_emu_runframe: ?*const ZeldaRunFrameFunc = null;
var g_emu_syncall: ?*const ZeldaSyncAllFunc = null;

pub export fn ZeldaSetupEmuCallbacks(emu_ram: [*]t.uint8, func: ?*const ZeldaRunFrameFunc, sync_all: ?*const ZeldaSyncAllFunc) callconv(.c) void {
    g_emu_memory_ptr = emu_ram;
    g_emu_runframe = func;
    g_emu_syncall = sync_all;
}

inline fn emuSynchronizeWholeState() void {
    if (g_emu_syncall) |f|
        f();
}

// |ptr| must be a pointer into g_ram; syncs the region with the emulator.
inline fn emuSyncMemoryRegion(ptr: ?*anyopaque, n: usize) void {
    const data: [*]t.uint8 = @ptrCast(ptr.?);
    std.debug.assert(@intFromPtr(data) >= @intFromPtr(&g_ram[0]) and @intFromPtr(data) < @intFromPtr(&g_ram[0]) + 0x20000);
    if (g_emu_memory_ptr) |dst| {
        const off: usize = @intFromPtr(data) - @intFromPtr(&g_ram[0]);
        std.mem.copyForwards(u8, dst[off .. off + n], data[0..n]);
    }
}

pub export fn ByteArray_AppendVl(arr: *ByteArray, value: u32) callconv(.c) void {
    var vv: u32 = value;
    while (vv >= 255) : (vv -= 255)
        ByteArray_AppendByte(arr, 255);
    ByteArray_AppendByte(arr, @as(t.uint8, @intCast(vv)));
}

pub export fn saveFunc(ctx_in: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    ByteArray_AppendData(@ptrCast(@alignCast(ctx_in.?)), @ptrCast(data), data_size);
}

const LoadFuncState = extern struct {
    p: [*]t.uint8,
    pend: [*]t.uint8,
};

pub export fn loadFunc(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    const st: *LoadFuncState = @ptrCast(@alignCast(ctx.?));
    std.debug.assert(st.pend - st.p >= data_size);
    const dst: [*]t.uint8 = @ptrCast(data.?);
    std.mem.copyForwards(u8, dst[0..data_size], st.p[0..data_size]);
    st.p += data_size;
}

inline fn internalSaveLoad(func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    var junk: [58]u8 = .{0} ** 58;
    func.?(ctx, @ptrCast(&junk), 27);
    func.?(ctx, @ptrCast(SpcPlayer_GetRam(g_zenv.player.?)), 0x10000); // apu ram
    func.?(ctx, @ptrCast(&junk), 40); // junk
    dsp_saveload(SpcPlayer_GetDsp(g_zenv.player.?), func, ctx); // 3024 bytes of dsp
    func.?(ctx, @ptrCast(&junk), 15); // spc junk
    dma_saveload(@ptrCast(@alignCast(g_zenv.dma.?)), func, ctx); // 192 bytes of dma state
    ppu_saveload(g_zenv.ppu.?, func, ctx); // 66619 + 512 + 174
    func.?(ctx, @ptrCast(g_zenv.sram), 0x2000); // 8192 bytes of sram
    func.?(ctx, @ptrCast(&junk), 58); // snes junk
    func.?(ctx, @ptrCast(g_zenv.ram), 0x20000); // 0x20000 bytes of ram
    func.?(ctx, @ptrCast(&junk), 4); // snes junk
}

pub export fn ZeldaReset(preserve_sram: bool) callconv(.c) void {
    frame_ctr_dbg = 0;
    dma_reset(@ptrCast(@alignCast(g_zenv.dma.?)));
    ppu_reset(g_zenv.ppu.?);
    @memset(g_zenv.ram.?[0..0x20000], 0);
    if (!preserve_sram)
        @memset(g_zenv.sram.?[0..0x2000], 0);
    ZeldaApuLock();
    ZeldaRestoreMusicAfterLoad_Locked(true);
    ZeldaApuUnlock();
    emuSynchronizeWholeState();
}

inline fn loadSnesState(func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    // Do the actual loading
    ZeldaApuLock();
    internalSaveLoad(func, ctx);
    const ram: [*]t.uint8 = g_zenv.ram.?;
    std.mem.copyForwards(u8, ram[0x1DBA0..][0..448], ram[0x1B00..][0..448]); // hdma table was moved
    ZeldaRestoreMusicAfterLoad_Locked(false);
    ZeldaApuUnlock();
    emuSynchronizeWholeState();
}

inline fn saveSnesState(func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    const ram: [*]t.uint8 = g_zenv.ram.?;
    std.mem.copyForwards(u8, ram[0x1B00..][0..448], ram[0x1DBA0..][0..448]); // hdma table was moved
    ZeldaApuLock();
    ZeldaSaveMusicStateToRam_Locked();
    internalSaveLoad(func, ctx);
    ZeldaApuUnlock();
}

const StateRecorder = extern struct {
    last_inputs: t.uint16,
    frames_since_last: u32,
    total_frames: u32,

    // For replay
    replay_pos: u32,
    replay_pos_last_complete: u32,
    replay_frame_counter: u32,
    replay_next_cmd_at: u32,
    replay_cmd: t.uint8,
    replay_mode: bool,

    log: ByteArray,
    base_snapshot: ByteArray,
};
const ByteArrayEmpty = ByteArray{ .data = null, .size = 0, .capacity = 0 };
const StateRecorderEmpty = StateRecorder{
    .last_inputs = 0,
    .frames_since_last = 0,
    .total_frames = 0,
    .replay_pos = 0,
    .replay_pos_last_complete = 0,
    .replay_frame_counter = 0,
    .replay_next_cmd_at = 0,
    .replay_cmd = 0,
    .replay_mode = false,
    .log = ByteArrayEmpty,
    .base_snapshot = ByteArrayEmpty,
};

var state_recorder: StateRecorder = StateRecorderEmpty;

pub export fn StateRecorder_Init(sr: *StateRecorder) callconv(.c) void {
    sr.* = StateRecorderEmpty;
}

pub export fn StateRecorder_RecordCmd(sr: *StateRecorder, cmd: t.uint8) callconv(.c) void {
    const frames: u32 = sr.frames_since_last;
    sr.frames_since_last = 0;
    const x: u32 = if (cmd < 0xc0) 0xf else 0x1;
    const short: u32 = if (frames < x) frames else x;
    ByteArray_AppendByte(&sr.log, cmd | @as(t.uint8, @intCast(short)));
    if (frames >= x)
        ByteArray_AppendVl(&sr.log, frames - x);
}

pub export fn StateRecorder_Record(sr: *StateRecorder, inputs: t.uint16) callconv(.c) void {
    const diff: t.uint16 = inputs ^ sr.last_inputs;
    if (diff != 0) {
        sr.last_inputs = inputs;
        var i: u4 = 0;
        while (i < 12) : (i += 1) {
            if (diff >> i & 1 != 0)
                StateRecorder_RecordCmd(sr, @as(t.uint8, i) << 4);
        }
    }
    sr.frames_since_last += 1;
    sr.total_frames += 1;
}

pub export fn StateRecorder_RecordPatchByte(sr: *StateRecorder, addr: u32, value: [*]const t.uint8, num: c_int) callconv(.c) void {
    std.debug.assert(addr < 0x20000);
    const n: u32 = @intCast(num);
    const lq: u32 = if (n - 1 <= 3) n - 1 else 3;
    const bank_bit: u8 = if ((addr & 0x10000) != 0) 2 else 0;
    StateRecorder_RecordCmd(sr, 0xc0 | bank_bit | (@as(t.uint8, @intCast(lq)) << 2));
    if (lq == 3)
        ByteArray_AppendVl(&sr.log, n - 1 - 3);
    ByteArray_AppendByte(&sr.log, @as(t.uint8, @truncate(addr >> 8)));
    ByteArray_AppendByte(&sr.log, @as(t.uint8, @truncate(addr)));
    var i: usize = 0;
    while (i < n) : (i += 1)
        ByteArray_AppendByte(&sr.log, value[i]);
}

pub export fn ReadFromFile(f: *anyopaque, data: ?*anyopaque, n: usize) callconv(.c) void {
    if (fread(@ptrCast(data.?), 1, n, f) != n)
        Die("fread failed\n");
}

pub export fn StateRecorder_Load(sr: *StateRecorder, f: *anyopaque, replay_mode: bool) callconv(.c) void {
    // todo: fix robustness on invalid data.
    var hdr: [8]u32 = .{0} ** 8;
    ReadFromFile(f, @ptrCast(&hdr), @sizeOf([8]u32));
    std.debug.assert(hdr[0] == 1);
    sr.total_frames = hdr[1];
    ByteArray_Resize(&sr.log, hdr[2]);
    ReadFromFile(f, @ptrCast(sr.log.data), sr.log.size);
    sr.last_inputs = @as(t.uint16, @truncate(hdr[3]));
    sr.frames_since_last = hdr[4];
    ByteArray_Resize(&sr.base_snapshot, if (hdr[5] & 1 != 0) hdr[6] else 0);
    ReadFromFile(f, @ptrCast(sr.base_snapshot.data), sr.base_snapshot.size);
    sr.replay_next_cmd_at = 0;
    sr.replay_mode = replay_mode;
    if (replay_mode) {
        sr.frames_since_last = 0;
        sr.last_inputs = 0;
        sr.replay_pos = 0;
        sr.replay_pos_last_complete = 0;
        sr.replay_frame_counter = 0;
        // Load snapshot from |base_snapshot|, or reset if empty.
        if (sr.base_snapshot.size != 0) {
            const bs: [*]t.uint8 = sr.base_snapshot.data.?;
            var state = LoadFuncState{ .p = bs, .pend = bs + sr.base_snapshot.size };
            loadSnesState(&loadFunc, &state);
            std.debug.assert(state.p == state.pend);
        } else {
            ZeldaReset(false);
        }
    } else {
        // Resume replay from the saved position?
        const replay_pos_resume: u32 = hdr[5] >> 1;
        sr.replay_pos = replay_pos_resume;
        sr.replay_pos_last_complete = replay_pos_resume;
        sr.replay_frame_counter = hdr[7];
        sr.replay_mode = sr.replay_frame_counter != 0;
        var arr: ByteArray = ByteArrayEmpty;
        ByteArray_Resize(&arr, hdr[6]);
        ReadFromFile(f, @ptrCast(arr.data), arr.size);
        const ad: [*]t.uint8 = arr.data.?;
        var state = LoadFuncState{ .p = ad, .pend = ad + arr.size };
        loadSnesState(&loadFunc, &state);
        ByteArray_Destroy(&arr);
        std.debug.assert(state.p == state.pend);
    }
}

pub export fn StateRecorder_Save(sr: *StateRecorder, f: *anyopaque) callconv(.c) void {
    var hdr: [8]u32 = .{0} ** 8;
    var arr: ByteArray = ByteArrayEmpty;
    saveSnesState(&saveFunc, &arr);
    std.debug.assert(sr.base_snapshot.size == 0 or sr.base_snapshot.size == arr.size);
    hdr[0] = 1;
    hdr[1] = sr.total_frames;
    hdr[2] = @intCast(sr.log.size);
    hdr[3] = sr.last_inputs;
    hdr[4] = sr.frames_since_last;
    hdr[5] = if (sr.base_snapshot.size != 0) 1 else 0;
    hdr[6] = @intCast(arr.size);
    // If saving while in replay mode, also persist replay_pos_last_complete
    // and replay_frame_counter so the replay can be resumed.
    if (sr.replay_mode) {
        hdr[5] |= sr.replay_pos_last_complete << 1;
        hdr[7] = sr.replay_frame_counter;
    }
    _ = fwrite(@ptrCast(&hdr), 1, @sizeOf([8]u32), f);
    if (sr.log.data) |d|
        _ = fwrite(@ptrCast(d), 1, hdr[2], f);
    if (sr.base_snapshot.data) |d|
        _ = fwrite(@ptrCast(d), 1, sr.base_snapshot.size, f);
    if (arr.data) |d|
        _ = fwrite(@ptrCast(d), 1, arr.size, f);
    ByteArray_Destroy(&arr);
}

pub export fn StateRecorder_ClearKeyLog(sr: *StateRecorder) callconv(.c) void {
    _ = printf("Clearing key log!\n");
    sr.base_snapshot.size = 0;
    saveSnesState(&saveFunc, &sr.base_snapshot);
    var old_log = sr.log;
    const old_frames_since_last: u32 = sr.frames_since_last;
    sr.log = ByteArrayEmpty;
    // If there are currently any active inputs, record them initially at
    // timestamp 0.
    sr.frames_since_last = 0;
    if (sr.last_inputs != 0) {
        var i: u4 = 0;
        while (i < 12) : (i += 1) {
            if (sr.last_inputs >> i & 1 != 0)
                StateRecorder_RecordCmd(sr, @as(t.uint8, i) << 4);
        }
    }
    if (sr.replay_mode) {
        // When clearing the key log while in replay mode, we want to keep
        // replaying but discarding all key history up until this point.
        if (sr.replay_next_cmd_at != 0xffffffff) {
            sr.replay_next_cmd_at -= old_frames_since_last;
            sr.frames_since_last = sr.replay_next_cmd_at;
            sr.replay_pos_last_complete = @intCast(sr.log.size);
            StateRecorder_RecordCmd(sr, sr.replay_cmd);
            const old_replay_pos: usize = sr.replay_pos;
            sr.replay_pos = @intCast(sr.log.size);
            if (old_log.data) |d|
                ByteArray_AppendData(&sr.log, d + old_replay_pos, old_log.size - old_replay_pos);
        }
        sr.total_frames -= sr.replay_frame_counter;
        sr.replay_frame_counter = 0;
    } else {
        sr.total_frames = 0;
    }
    ByteArray_Destroy(&old_log);
    sr.frames_since_last = 0;
}

pub export fn StateRecorder_ReadNextReplayState(sr: *StateRecorder) callconv(.c) t.uint16 {
    std.debug.assert(sr.replay_mode);
    var replay_pos: usize = sr.replay_pos;
    while (sr.frames_since_last >= sr.replay_next_cmd_at) {
        if (replay_pos != sr.replay_pos_last_complete) {
            // Apply next command
            sr.frames_since_last = 0;
            if (sr.replay_cmd < 0xc0) {
                sr.last_inputs ^= @as(t.uint16, 1) << @as(u4, @intCast(sr.replay_cmd >> 4));
            } else if (sr.replay_cmd < 0xd0) {
                var nb: c_int = 1 + ((sr.replay_cmd >> 2) & 3);
                if (nb == 4) {
                    // C do-while: read bytes, summing, until a non-255 byte.
                    var tb: t.uint8 = 0;
                    while (true) {
                        tb = sr.log.data.?[replay_pos];
                        replay_pos += 1;
                        nb += @as(c_int, tb);
                        if (tb != 255) break;
                    }
                }
                var addr: u32 = if ((sr.replay_cmd >> 1) & 1 != 0) @as(u32, 1) << 16 else 0;
                addr |= @as(u32, sr.log.data.?[replay_pos]) << 8;
                replay_pos += 1;
                addr |= @as(u32, sr.log.data.?[replay_pos]);
                replay_pos += 1;
                // C: do { ... } while (addr++, --nb);
                while (true) {
                    g_ram[addr & 0x1ffff] = sr.log.data.?[replay_pos];
                    replay_pos += 1;
                    emuSyncMemoryRegion(@ptrCast(&g_ram[addr & 0x1ffff]), 1);
                    addr += 1;
                    nb -= 1;
                    if (nb == 0) break;
                }
            } else {
                // C: assert(0); (active in the C build too).
                @panic("StateRecorder: unknown replay cmd");
            }
        }
        sr.replay_pos_last_complete = @intCast(replay_pos);
        if (replay_pos >= sr.log.size) {
            sr.replay_pos = @intCast(replay_pos);
            sr.replay_next_cmd_at = 0xffffffff;
            break;
        }
        // Read the next one
        const cmd: t.uint8 = sr.log.data.?[replay_pos];
        replay_pos += 1;
        const mask: u32 = if (cmd < 0xc0) 0xf else 0x1;
        var frames: u32 = @as(u32, cmd) & mask;
        if (frames == mask) {
            // C do-while: read bytes, summing, until a non-255 byte.
            var tb: t.uint8 = 0;
            while (true) {
                tb = sr.log.data.?[replay_pos];
                replay_pos += 1;
                frames += @as(u32, tb);
                if (tb != 255) break;
            }
        }
        sr.replay_next_cmd_at = frames;
        sr.replay_cmd = cmd;
        sr.replay_pos = @intCast(replay_pos);
    }
    sr.frames_since_last += 1;
    sr.replay_frame_counter += 1;
    // Turn off replay mode after we reached the final frame position
    if (sr.replay_frame_counter >= sr.total_frames) {
        sr.replay_mode = false;
    }
    return sr.last_inputs;
}

pub export fn StateRecorder_StopReplay(sr: *StateRecorder) callconv(.c) void {
    if (!sr.replay_mode)
        return;
    sr.replay_mode = false;
    sr.total_frames = sr.replay_frame_counter;
    sr.log.size = sr.replay_pos_last_complete;
}

pub export fn ZeldaRunFrame(inputs_in: c_int) callconv(.c) bool {
    var inputs: c_int = inputs_in;
    // Avoid up/down and left/right from being pressed at the same time
    if ((inputs & 0x30) == 0x30) inputs ^= 0x30;
    if ((inputs & 0xc0) == 0xc0) inputs ^= 0xc0;
    frame_ctr_dbg += 1;
    const is_replay = state_recorder.replay_mode;
    // Either copy state or apply state
    if (is_replay) {
        inputs = @as(c_int, StateRecorder_ReadNextReplayState(&state_recorder));
    } else {
        StateRecorder_Record(&state_recorder, @as(t.uint16, @intCast(inputs)));
        // This is whether APUI00 is true or false; the ancilla code uses it.
        const apui00: t.uint8 = if (ZeldaIsMusicPlaying()) 1 else 0;
        if (apui00 != g_ram[kRam_APUI00]) {
            g_ram[kRam_APUI00] = apui00;
            emuSyncMemoryRegion(@ptrCast(&g_ram[kRam_APUI00]), 1);
            StateRecorder_RecordPatchByte(&state_recorder, 0x648, @ptrCast(&apui00), 1);
        }
        if (v.animated_tile_data_src().* != 0) {
            // Whenever we're no longer replaying, we'll remember what bugs
            // were fixed, but only if the game is initialized.
            if (g_ram[kRam_BugsFixed] < kBugFix_Latest) {
                g_ram[kRam_BugsFixed] = kBugFix_Latest;
                emuSyncMemoryRegion(@ptrCast(&g_ram[kRam_BugsFixed]), 1);
                StateRecorder_RecordPatchByte(&state_recorder, kRam_BugsFixed, @ptrCast(&g_ram[kRam_BugsFixed]), 1);
            }
            if (enhanced_features0().* != g_wanted_zelda_features) {
                enhanced_features0().* = g_wanted_zelda_features;
                emuSyncMemoryRegion(@ptrCast(enhanced_features0()), @sizeOf(t.uint32));
                StateRecorder_RecordPatchByte(&state_recorder, kRam_Features0, @ptrCast(enhanced_features0()), 4);
            }
        }
    }
    var run_what: c_int = 0;
    if (g_ram[kRam_BugsFixed] < kBugFix_PolyRenderer) {
        // A previous version of this code alternated the game loop with the
        // poly renderer.
        run_what = if (v.is_nmi_thread_active().* != 0 and v.thread_other_stack().* != 0x1f31) 2 else 1;
    } else {
        // The snes seems to let poly rendering run for a little while each
        // frame until it eventually completes a frame. Simulate this by
        // rendering the poly every n:th frame.
        run_what = if (v.is_nmi_thread_active().* != 0 and incrementCrystalCountdown(&g_ram[kRam_CrystalRotateCounter], @as(c_int, v.virq_trigger().*)) != 0) 3 else 1;
        emuSyncMemoryRegion(@ptrCast(&g_ram[kRam_CrystalRotateCounter]), 1);
    }
    if (g_emu_runframe != null and enhanced_features0().* == 0 and g_zenv.dialogue_flags == 0) {
        g_emu_runframe.?(@as(t.uint16, @intCast(inputs)), run_what);
    } else {
        // can't compare against real impl when running with extra features.
        ZeldaRunFrameInternal(@as(t.uint16, @intCast(inputs)), run_what);
    }
    ZeldaPushApuState();
    return is_replay;
}

pub export fn ZeldaSetLanguage(language: ?[*:0]const u8) callconv(.c) void {
    const kDefaultConf: [3]u8 = .{ 0, 0, 0 };
    var found: t.MemBlk = .{ .ptr = @ptrCast(&kDefaultConf[0]), .size = 3 };
    if (language) |lang| {
        const n: usize = strlen(lang);
        var i: c_int = 0;
        while (true) : (i += 1) {
            const mb: t.MemBlk = FindInAssetArray(96, i); // kDialogueMap(i)
            if (mb.ptr == null) {
                _ = fprintf(stderrPtr(), "Unable to find language '%s'\n", lang);
                break;
            }
            const name: t.MemBlk = FindIndexInMemblk(mb, 0);
            if (name.size == n and memcmp(@ptrCast(name.ptr), lang, n) == 0) {
                found = FindIndexInMemblk(mb, 1);
                break;
            }
        }
    }
    g_zenv.dialogue_blk = FindInAssetArray(94, @as(c_int, found.ptr.?[0])); // kDialogue
    g_zenv.dialogue_font_blk = FindInAssetArray(95, @as(c_int, found.ptr.?[1])); // kDialogueFont
    g_zenv.dialogue_flags = found.ptr.?[2];
}

const kReferenceSaves: [13][:0]const u8 = .{
    "Chapter 1 - Zelda's Rescue.sav",
    "Chapter 2 - After Eastern Palace.sav",
    "Chapter 3 - After Desert Palace.sav",
    "Chapter 4 - After Tower of Hera.sav",
    "Chapter 5 - After Hyrule Castle Tower.sav",
    "Chapter 6 - After Dark Palace.sav",
    "Chapter 7 - After Swamp Palace.sav",
    "Chapter 8 - After Skull Woods.sav",
    "Chapter 9 - After Gargoyle's Domain.sav",
    "Chapter 10 - After Ice Palace.sav",
    "Chapter 11 - After Misery Mire.sav",
    "Chapter 12 - After Turtle Rock.sav",
    "Chapter 13 - After Ganon's Tower.sav",
};
const kSaveStrings: [3][:0]const u8 = .{ "Saving", "Loading", "Replaying" };

pub export fn SaveLoadSlot(cmd: c_int, which: c_int) callconv(.c) void {
    var name: [128]u8 = .{0} ** 128;
    if (which & 256 != 0) {
        if (cmd == kSaveLoad_Save)
            return;
        _ = sprintf(&name, "saves/ref/%s", kReferenceSaves[@intCast(which - 256)].ptr);
    } else {
        _ = sprintf(&name, "saves/save%d.sav", which);
    }
    const f = fopen(@ptrCast(&name[0]), if (cmd != kSaveLoad_Save) "rb" else "wb") orelse return;
    const what: [*:0]const u8 = if (cmd == kSaveLoad_Save) kSaveStrings[0] else if (cmd == kSaveLoad_Load) kSaveStrings[1] else kSaveStrings[2];
    _ = printf("*** %s slot %d\n", what, which);
    if (cmd != kSaveLoad_Save) {
        StateRecorder_Load(&state_recorder, f, cmd == kSaveLoad_Replay);
    } else {
        StateRecorder_Save(&state_recorder, f);
    }
    _ = fclose(f);
}

const StateRecoderMultiPatch = extern struct {
    count: u32,
    addr: u32,
    vals: [256]u8,
};

pub export fn StateRecoderMultiPatch_Init(mp: *StateRecoderMultiPatch) callconv(.c) void {
    mp.count = 0;
    mp.addr = 0;
}

pub export fn StateRecoderMultiPatch_Commit(mp: *StateRecoderMultiPatch) callconv(.c) void {
    if (mp.count != 0)
        StateRecorder_RecordPatchByte(&state_recorder, mp.addr, mp.vals[0..], @intCast(mp.count));
}

pub export fn StateRecoderMultiPatch_Patch(mp: *StateRecoderMultiPatch, addr: u32, value: t.uint8) callconv(.c) void {
    if (mp.count >= 256 or addr != mp.addr + mp.count) {
        StateRecoderMultiPatch_Commit(mp);
        mp.addr = addr;
        mp.count = 0;
    }
    mp.vals[mp.count] = value;
    mp.count += 1;
    g_ram[addr] = value;
    emuSyncMemoryRegion(@ptrCast(&g_ram[addr]), 1);
}

pub export fn PatchCommand(c: t.uint8) callconv(.c) void {
    var mp = StateRecoderMultiPatch{ .count = 0, .addr = 0, .vals = .{0} ** 256 };
    StateRecoderMultiPatch_Init(&mp);
    if (c == 'w') {
        StateRecoderMultiPatch_Patch(&mp, 0xf372, 80); // health filler
        StateRecoderMultiPatch_Patch(&mp, 0xf373, 80); // magic filler
    } else if (c == 'W') {
        StateRecoderMultiPatch_Patch(&mp, 0xf375, 10); // link_bomb_filler
        StateRecoderMultiPatch_Patch(&mp, 0xf376, 10); // link_arrow_filler
        const rupees: t.uint16 = @as(t.uint16, v.link_rupees_goal().*) +% 100;
        StateRecoderMultiPatch_Patch(&mp, 0xf360, @as(t.uint8, @truncate(rupees))); // link_rupees_goal
        StateRecoderMultiPatch_Patch(&mp, 0xf361, @as(t.uint8, @truncate(rupees >> 8)));
    } else if (c == 'k') {
        StateRecorder_ClearKeyLog(&state_recorder);
    } else if (c == 'o') {
        StateRecoderMultiPatch_Patch(&mp, 0xf36f, 1);
    } else if (c == 'l') {
        StateRecorder_StopReplay(&state_recorder);
    } else if (c == 'E') {
        StateRecoderMultiPatch_Patch(&mp, 0x37f, g_ram[0x37f] ^ 1);
    }
    StateRecoderMultiPatch_Commit(&mp);
}

pub export fn ZeldaReadSram() callconv(.c) void {
    const f = fopen("saves/sram.dat", "rb") orelse return;
    if (fread(g_zenv.sram.?, 1, 8192, f) != 8192)
        _ = fprintf(stderrPtr(), "Error reading saves/sram.dat\n");
    _ = fclose(f);
    emuSynchronizeWholeState();
}

pub export fn ZeldaWriteSram() callconv(.c) void {
    _ = rename("saves/sram.dat", "saves/sram.bak");
    const f = fopen("saves/sram.dat", "wb") orelse {
        _ = fprintf(stderrPtr(), "Unable to write saves/sram.dat\n");
        return;
    };
    _ = fwrite(@ptrCast(g_zenv.sram), 1, 8192, f);
    _ = fclose(f);
}
