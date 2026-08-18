// Port of snes/ppu.c: the SNES PPU (picture processing unit) — background
// tile rendering (4bpp/2bpp, mosaic variants), sprite evaluation/drawing,
// mode 7 (including the 4x4-upsampled fast path), window/clip-region math,
// and per-scanline color composition into the RGBA render buffer. Every
// exported function keeps its exact C-ABI name and signature (callconv(.c),
// C-pointer types) so the remaining .c callers (src/main.c, src/zelda_rtl.c,
// src/nmi.c, src/zelda_cpu_infra.c, snes/snes.c) link unchanged. The Ppu
// struct layout mirrors snes/ppu.h field-for-field: zelda_cpu_infra.c's
// RAM-compare oracle snapshots ppu->vram directly, so byte-identical layout
// is mandatory.
//
// ppu_handleVblank is declared in ppu.h but has no definition or caller
// anywhere in the C codebase (confirmed by exhaustive grep) — it is not
// ported.

const std = @import("std");

pub const kPpuExtraLeftRight: u32 = 96; // kEnableLargeScreen ? 96 : 0, see src/types.h
pub const kPpuXPixels: u32 = 256 + kPpuExtraLeftRight * 2;

pub const PpuZbufType = u16;

pub const BgLayer = extern struct {
    hScroll: u16,
    vScroll: u16,
    // -- snapshot starts here
    tilemapWider: bool,
    tilemapHigher: bool,
    tilemapAdr: u16,
    // -- snapshot ends here
    tileAdr: u16,
};

pub const PpuPixelPrioBufs = extern struct {
    data: [kPpuXPixels]PpuZbufType,
};

pub const kPpuRenderFlags_NewRenderer: u32 = 1;
pub const kPpuRenderFlags_4x4Mode7: u32 = 2;
pub const kPpuRenderFlags_Height240: u32 = 4;
pub const kPpuRenderFlags_NoSpriteLimits: u32 = 8;

pub const Ppu = extern struct {
    lineHasSprites: bool,
    lastBrightnessMult: u8,
    lastMosaicModulo: u8,
    renderFlags: u8,
    renderPitch: u32,
    renderBuffer: ?[*]u8,
    extraLeftCur: u8,
    extraRightCur: u8,
    extraLeftRight: u8,
    extraBottomCur: u8,
    mode7PerspectiveLow: f32,
    mode7PerspectiveHigh: f32,

    screenEnabled: [2]u8,
    screenWindowed: [2]u8,
    mosaicEnabled: u8,
    mosaicSize: u8,
    objTileAdr1: u16,
    objTileAdr2: u16,
    objSize: u8,
    window1left: u8,
    window1right: u8,
    window2left: u8,
    window2right: u8,
    windowsel: u32,

    clipMode: u8,
    preventMathMode: u8,
    addSubscreen: bool,
    subtractColor: bool,
    halfColor: bool,
    mathEnabled: u8,
    fixedColorR: u8,
    fixedColorG: u8,
    fixedColorB: u8,
    forcedBlank: bool,
    brightness: u8,
    mode: u8,

    vramPointer: u16,
    vramIncrement: u16,
    vramIncrementOnHigh: bool,
    cgramPointer: u8,
    cgramSecondWrite: bool,
    cgramBuffer: u8,
    oamAdr: u16,
    oamSecondWrite: bool,
    oamBuffer: u8,

    bgLayer: [4]BgLayer,
    scrollPrev: u8,
    scrollPrev2: u8,

    m7matrix: [8]i16,
    m7prev: u8,
    m7largeField: bool,
    m7charFill: bool,
    m7xFlip: bool,
    m7yFlip: bool,
    m7extBg_always_zero: bool,

    m7startX: i32,
    m7startY: i32,

    oam: [0x110]u16,

    brightnessMult: [32 + 31]u8,
    brightnessMultHalf: [32 * 2]u8,
    cgram: [0x100]u16,
    mosaicModulo: [kPpuXPixels]u8,
    colorMapRgb: [256]u32,
    bgBuffers: [2]PpuPixelPrioBufs,
    objBuffer: PpuPixelPrioBufs,
    vram: [0x8000]u16,
};

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

pub fn main() callconv(.c) c_int {
    return 0;
}

const kWindow1Inversed: u32 = 1;
const kWindow1Enabled: u32 = 2;
const kWindow2Inversed: u32 = 4;
const kWindow2Enabled: u32 = 8;

const kSpriteSizes: [8][2]u8 = .{
    .{ 8, 16 },  .{ 8, 32 },  .{ 8, 64 },  .{ 16, 32 },
    .{ 16, 64 }, .{ 32, 64 }, .{ 16, 32 }, .{ 16, 32 },
};

inline fn isScreenEnabled(ppu: *Ppu, sub: usize, layer: usize) bool {
    return ppu.screenEnabled[sub] & (@as(u8, 1) << @as(u3, @intCast(layer))) != 0;
}
inline fn isScreenWindowed(ppu: *Ppu, sub: usize, layer: usize) bool {
    return ppu.screenWindowed[sub] & (@as(u8, 1) << @as(u3, @intCast(layer))) != 0;
}
inline fn isMosaicEnabled(ppu: *Ppu, layer: usize) bool {
    return ppu.mosaicEnabled & (@as(u8, 1) << @as(u3, @intCast(layer))) != 0;
}
inline fn getWindowFlags(ppu: *Ppu, layer: u32) u32 {
    return ppu.windowsel >> @as(u5, @intCast(layer * 4));
}

pub export fn ppu_init() ?*Ppu {
    const ppu: *Ppu = @ptrCast(@alignCast(malloc(@sizeOf(Ppu)) orelse return null));
    ppu.extraLeftRight = @intCast(kPpuExtraLeftRight);
    return ppu;
}

pub export fn ppu_free(ppu: ?*Ppu) void {
    free(ppu);
}

// g_zenv.ppu is typed `?*anyopaque` in variables.zig (ZeldaEnv) so that
// callers outside this compilation unit (e.g. src/nmi.zig) don't need to
// `@import` this file's module graph just to reach `cgram`/`oam` — doing so
// would pull every `pub export fn` in this file into the importer's own
// object, duplicating symbols already linked in via the "ppu" object.
pub export fn PpuCopyCgramFromBuffer(ppu: *anyopaque, src: [*]const u8) void {
    const p: *Ppu = @ptrCast(@alignCast(ppu));
    @memcpy(std.mem.asBytes(&p.cgram), src[0..@sizeOf(@TypeOf(p.cgram))]);
}

pub export fn PpuCopyOamFromBuffer(ppu: *anyopaque, src: [*]const u8) void {
    const p: *Ppu = @ptrCast(@alignCast(ppu));
    @memcpy(std.mem.asBytes(&p.oam), src[0..@sizeOf(@TypeOf(p.oam))]);
}

// More opaque accessors for the src/zelda_rtl.zig port (ZeldaDrawPpuFrame /
// ZeldaInitialize reach a few Ppu fields): mode, the vram array base, and
// extraLeftRight.
pub export fn PpuGetCurrentMode(ppu: *anyopaque) u8 {
    const p: *Ppu = @ptrCast(@alignCast(ppu));
    return p.mode;
}

pub export fn PpuGetVram(ppu: *anyopaque) [*]u16 {
    const p: *Ppu = @ptrCast(@alignCast(ppu));
    return @ptrCast(&p.vram[0]);
}

pub export fn PpuGetExtraSideSpace(ppu: *anyopaque) u8 {
    const p: *Ppu = @ptrCast(@alignCast(ppu));
    return p.extraLeftRight;
}

pub export fn ppu_reset(ppu: *Ppu) void {
    @memset(&ppu.vram, 0);
    ppu.lastBrightnessMult = 0xff;
    ppu.lastMosaicModulo = 0xff;
    ppu.extraLeftCur = 0;
    ppu.extraRightCur = 0;
    ppu.extraBottomCur = 0;
    ppu.vramPointer = 0;
    ppu.vramIncrementOnHigh = false;
    ppu.vramIncrement = 1;
    @memset(&ppu.cgram, 0);
    ppu.cgramPointer = 0;
    ppu.cgramSecondWrite = false;
    ppu.cgramBuffer = 0;
    @memset(&ppu.oam, 0);
    ppu.oamAdr = 0;
    ppu.oamSecondWrite = false;
    ppu.oamBuffer = 0;
    ppu.objTileAdr1 = 0x4000;
    ppu.objTileAdr2 = 0x5000;
    ppu.objSize = 0;
    ppu.objBuffer = std.mem.zeroes(PpuPixelPrioBufs);
    for (0..4) |i| {
        ppu.bgLayer[i] = .{
            .hScroll = 0,
            .vScroll = 0,
            .tilemapWider = false,
            .tilemapHigher = false,
            .tilemapAdr = 0,
            .tileAdr = 0,
        };
    }
    ppu.scrollPrev = 0;
    ppu.scrollPrev2 = 0;
    ppu.mosaicSize = 1;
    ppu.screenEnabled = .{ 0, 0 };
    ppu.screenWindowed = .{ 0, 0 };
    @memset(&ppu.m7matrix, 0);
    ppu.m7prev = 0;
    ppu.m7largeField = true;
    ppu.m7charFill = false;
    ppu.m7xFlip = false;
    ppu.m7yFlip = false;
    ppu.m7extBg_always_zero = false;
    ppu.m7startX = 0;
    ppu.m7startY = 0;
    ppu.windowsel = 0;
    ppu.window1left = 0;
    ppu.window1right = 0;
    ppu.window2left = 0;
    ppu.window2right = 0;
    ppu.clipMode = 0;
    ppu.preventMathMode = 0;
    ppu.addSubscreen = false;
    ppu.subtractColor = false;
    ppu.halfColor = false;
    ppu.mathEnabled = 0;
    ppu.fixedColorR = 0;
    ppu.fixedColorG = 0;
    ppu.fixedColorB = 0;
    ppu.forcedBlank = true;
    ppu.brightness = 0;
    ppu.mode = 0;
}

pub export fn ppu_saveload(ppu: *Ppu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void {
    var tmp: [556]u8 = [_]u8{0} ** 556;
    const f = func.?;
    f(ctx, &ppu.vram, 0x8000 * 2);
    f(ctx, &tmp, 10);
    f(ctx, &ppu.cgram, 512);
    f(ctx, &tmp, 556);
    f(ctx, &tmp, 520);
    for (0..4) |i| {
        f(ctx, &tmp, 4);
        f(ctx, &ppu.bgLayer[i].tilemapWider, 4);
        f(ctx, &tmp, 4);
    }
    f(ctx, &tmp, 123);
}

pub export fn PpuGetCurrentRenderScale(ppu: *Ppu, render_flags: u32) c_int {
    const hq = ppu.mode == 7 and !ppu.forcedBlank and
        (render_flags & (kPpuRenderFlags_4x4Mode7 | kPpuRenderFlags_NewRenderer)) == (kPpuRenderFlags_4x4Mode7 | kPpuRenderFlags_NewRenderer);
    return if (hq) 4 else 1;
}

pub export fn PpuBeginDrawing(ppu: *Ppu, pixels: ?[*]u8, pitch: usize, render_flags: u32) void {
    ppu.renderFlags = @truncate(render_flags);
    ppu.renderPitch = @intCast(pitch);
    ppu.renderBuffer = pixels;

    if (ppu.brightness != ppu.lastBrightnessMult) {
        const ppu_brightness: u32 = ppu.brightness;
        ppu.lastBrightnessMult = ppu.brightness;
        for (0..32) |i| {
            const val: u8 = @intCast(((@as(u32, @intCast(i)) << 3) | (@as(u32, @intCast(i)) >> 2)) * ppu_brightness / 15);
            ppu.brightnessMultHalf[i * 2] = val;
            ppu.brightnessMultHalf[i * 2 + 1] = val;
            ppu.brightnessMult[i] = val;
        }
        @memset(ppu.brightnessMult[32..63], ppu.brightnessMult[31]);
    }

    if (PpuGetCurrentRenderScale(ppu, ppu.renderFlags) == 4) {
        for (0..256) |i| {
            const color: u32 = ppu.cgram[i];
            ppu.colorMapRgb[i] = @as(u32, ppu.brightnessMult[color & 0x1f]) << 16 |
                @as(u32, ppu.brightnessMult[(color >> 5) & 0x1f]) << 8 |
                @as(u32, ppu.brightnessMult[(color >> 10) & 0x1f]);
        }
    }
}

inline fn clearBackdrop(buf: *PpuPixelPrioBufs) void {
    var i: usize = 0;
    while (i < buf.data.len) : (i += 4) {
        const p: *u64 = @ptrCast(@alignCast(&buf.data[i]));
        p.* = 0x0500050005000500;
    }
}

inline fn wrapU8(v: i32) u8 {
    return @truncate(@as(u32, @bitCast(v)));
}

pub export fn ppu_runLine(ppu: *Ppu, line: c_int) void {
    if (line == 0) return;
    if (ppu.mosaicSize != ppu.lastMosaicModulo) {
        const mod: i32 = ppu.mosaicSize;
        ppu.lastMosaicModulo = ppu.mosaicSize;
        var j: i32 = 0;
        for (0..ppu.mosaicModulo.len) |i| {
            ppu.mosaicModulo[i] = wrapU8(@as(i32, @intCast(i)) - j);
            j = if (j + 1 == mod) 0 else j + 1;
        }
    }

    clearBackdrop(&ppu.objBuffer);
    ppu.lineHasSprites = !ppu.forcedBlank and ppuEvaluateSprites(ppu, line - 1);

    if (line >= 225 + @as(c_int, ppu.extraBottomCur)) {
        const dst_off: usize = @intCast((line - 1) * @as(c_int, @intCast(ppu.renderPitch)));
        const n: usize = 4 * (256 + @as(usize, ppu.extraLeftRight) * 2);
        @memset(ppu.renderBuffer.?[dst_off..][0..n], 0);
        return;
    }

    if (ppu.renderFlags & wrapU8(@bitCast(kPpuRenderFlags_NewRenderer)) != 0) {
        ppuDrawWholeLine(ppu, @intCast(line));
    } else {
        if (ppu.mode == 7) ppuCalculateMode7Starts(ppu, line);
        for (0..256) |x| ppuHandlePixel(ppu, @intCast(x), line);

        const dst_off: usize = @intCast((line - 1) * @as(c_int, @intCast(ppu.renderPitch)));
        if (ppu.extraLeftRight != 0) {
            @memset(ppu.renderBuffer.?[dst_off..][0 .. 4 * @as(usize, ppu.extraLeftRight)], 0);
            @memset(ppu.renderBuffer.?[dst_off + 4 * (256 + @as(usize, ppu.extraLeftRight)) ..][0 .. 4 * @as(usize, ppu.extraLeftRight)], 0);
        }
    }
}

const PpuWindows = struct {
    edges: [6]i16 = undefined,
    nr: u8 = 0,
    bits: u8 = 0,
};

fn ppuWindowsClear(win: *PpuWindows, ppu: *Ppu, layer: u32) void {
    const extra_left: i16 = if (layer != 2) @as(i16, ppu.extraLeftCur) else 0;
    const extra_right: i16 = if (layer != 2) @as(i16, ppu.extraRightCur) else 0;
    win.edges[0] = -extra_left;
    win.edges[1] = 256 + extra_right;
    win.nr = 1;
    win.bits = 0;
}

fn insertEdge(win: *PpuWindows, nr: *i32, t: i16) void {
    var i: i32 = 0;
    while (i <= nr.*) : (i += 1) {
        const e = win.edges[@intCast(i)];
        if (t == e) return;
        if (t < e) {
            var j: i32 = nr.*;
            nr.* += 1;
            while (j >= i) : (j -= 1) {
                win.edges[@intCast(j + 1)] = win.edges[@intCast(j)];
            }
            win.edges[@intCast(i)] = t;
            return;
        }
    }
}

fn edgeMask(win: *PpuWindows, left: i16, right: i16) u32 {
    var i: i32 = 0;
    while (win.edges[@intCast(i)] != left) : (i += 1) {}
    var j: i32 = i;
    while (win.edges[@intCast(j)] != right) : (j += 1) {}
    const width: u5 = @intCast(j - i);
    const mask: u32 = (@as(u32, 1) << width) - 1;
    return mask << @as(u5, @intCast(i));
}

fn ppuWindowsCalc(win: *PpuWindows, ppu: *Ppu, layer: u32) void {
    const winflags: u32 = getWindowFlags(ppu, layer);
    var nr: i32 = 1;
    const extra_left: i16 = if (layer != 2) @as(i16, ppu.extraLeftCur) else 0;
    const extra_right: i16 = if (layer != 2) @as(i16, ppu.extraRightCur) else 0;
    const window_right: i16 = 256 + extra_right;
    win.edges[0] = -extra_left;
    win.edges[1] = window_right;

    const w1_ena = (winflags & kWindow1Enabled != 0) and ppu.window1left <= ppu.window1right;
    if (w1_ena) {
        if (@as(i16, ppu.window1left) > win.edges[0]) {
            win.edges[@intCast(nr)] = @as(i16, ppu.window1left);
            nr += 1;
            win.edges[@intCast(nr)] = window_right;
        }
        if (@as(i16, ppu.window1right) + 1 < window_right) {
            win.edges[@intCast(nr)] = @as(i16, ppu.window1right) + 1;
            nr += 1;
            win.edges[@intCast(nr)] = window_right;
        }
    }
    const w2_ena = (winflags & kWindow2Enabled != 0) and ppu.window2left <= ppu.window2right;
    if (w2_ena) {
        insertEdge(win, &nr, @as(i16, ppu.window2left));
        insertEdge(win, &nr, @as(i16, ppu.window2right) + 1);
    }
    win.nr = @intCast(nr);

    var w1_bits: u32 = 0;
    var w2_bits: u32 = 0;
    if (w1_ena) w1_bits = edgeMask(win, @as(i16, ppu.window1left), @as(i16, ppu.window1right) + 1);
    if ((winflags & (kWindow1Enabled | kWindow1Inversed)) == (kWindow1Enabled | kWindow1Inversed))
        w1_bits = ~w1_bits;
    if (w2_ena) w2_bits = edgeMask(win, @as(i16, ppu.window2left), @as(i16, ppu.window2right) + 1);
    if ((winflags & (kWindow2Enabled | kWindow2Inversed)) == (kWindow2Enabled | kWindow2Inversed))
        w2_bits = ~w2_bits;
    win.bits = @truncate(w1_bits | w2_bits);
}

// ---- Pixel-plane helpers shared by the background drawers ----
// C's DO_PIXEL(i)/DO_PIXEL_HFLIP(i) macros are invoked either with a fixed
// `bits` across indices 0..7 (full tile) or with `bits` pre-shifted by the
// clip offset `s` and a fixed index 0 repeated (clipped runs, dstz++ each
// step). Both forms are algebraically identical to evaluating the
// unshifted-bits formula at real index (s + k): the pre-shift variants only
// ever consume indices where s+k <= 7, so no bits are lost off either end.
// Using a single real-index form avoids needing to special-case clipped
// vs. full-tile runs.
const Px = struct { valid: bool, pixel: u32 };

inline fn px4bpp(bits: u32, i: u5) Px {
    const pixel = ((bits >> i) & 1) | ((bits >> (i + 7)) & 2) | ((bits >> (i + 14)) & 4) | ((bits >> (i + 21)) & 8);
    return .{ .valid = (bits & (@as(u32, 0x01010101) << i)) != 0, .pixel = pixel };
}
inline fn px4bppHflip(bits: u32, i: u5) Px {
    const pixel = ((bits >> (7 - i)) & 1) | ((bits >> (14 - i)) & 2) | ((bits >> (21 - i)) & 4) | ((bits >> (28 - i)) & 8);
    return .{ .valid = (bits & (@as(u32, 0x80808080) >> i)) != 0, .pixel = pixel };
}
inline fn px2bpp(bits: u32, i: u5) Px {
    const pixel = ((bits >> i) & 1) | ((bits >> (i + 7)) & 2);
    return .{ .valid = pixel != 0, .pixel = pixel };
}
inline fn px2bppHflip(bits: u32, i: u5) Px {
    const pixel = ((bits >> (7 - i)) & 1) | ((bits >> (14 - i)) & 2);
    return .{ .valid = pixel != 0, .pixel = pixel };
}

// tps[which]+col model of the C tp/tp_last/tp_next pointer chase: `which`
// selects one of the two (for wide tilemaps) 32-column tile rows, `col` is
// the column (0..31) within it. NEXT_TP() advances col, wrapping to the
// other row (and resetting col) every 32 columns.
inline fn nextTp(which: *u1, col: *u5) void {
    if (col.* != 31) {
        col.* += 1;
    } else {
        which.* +%= 1;
        col.* = 0;
    }
}

fn readBits4(ppu: *Ppu, ta: i32, tile_num: u32) u32 {
    const base: u32 = (@as(u32, @bitCast(ta)) +% tile_num *% 16) & 0x7fff;
    return @as(u32, ppu.vram[base]) | (@as(u32, ppu.vram[(base +% 8) & 0x7fff]) << 16);
}

fn readBits2(ppu: *Ppu, ta: i32, tile_num: u32) u32 {
    const base: u32 = (@as(u32, @bitCast(ta)) +% tile_num *% 8) & 0x7fff;
    return ppu.vram[base];
}

fn bgTileAddrs(ppu: *Ppu, y: u32, layer: usize) struct { tps: [2]u32, tileadr0: i32, tileadr1: i32 } {
    const bglayer = &ppu.bgLayer[layer];
    var sc_offs: u32 = @as(u32, bglayer.tilemapAdr) +% (((y >> 3) & 0x1f) << 5);
    if ((y & 0x100) != 0 and bglayer.tilemapHigher)
        sc_offs +%= if (bglayer.tilemapWider) @as(u32, 0x800) else 0x400;
    const tps: [2]u32 = .{
        sc_offs & 0x7fff,
        (sc_offs +% (if (bglayer.tilemapWider) @as(u32, 0x400) else 0)) & 0x7fff,
    };
    const tileadr: i32 = @intCast(bglayer.tileAdr);
    const row: i32 = @intCast(y & 0x7);
    return .{ .tps = tps, .tileadr0 = tileadr + row, .tileadr1 = tileadr + 7 - row };
}

fn ppuDrawBackground4bpp(ppu: *Ppu, y0: u32, sub: usize, layer: usize, zhi: PpuZbufType, zlo: PpuZbufType) void {
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, @intCast(layer)) else ppuWindowsClear(&win, ppu, @intCast(layer));

    const bglayer = &ppu.bgLayer[layer];
    const y: u32 = y0 +% bglayer.vScroll;
    const addrs = bgTileAddrs(ppu, y, layer);
    const tps = addrs.tps;
    const tileadr0 = addrs.tileadr0;
    const tileadr1 = addrs.tileadr1;

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const left = win.edges[windex];
        const right = win.edges[windex + 1];
        var x: i32 = @as(i32, left) + @as(i32, bglayer.hScroll);
        var w: i32 = @as(i32, right) - @as(i32, left);
        var dst_off: usize = @intCast(@as(i32, left) + @as(i32, @intCast(kPpuExtraLeftRight)));
        var which: u1 = @intCast(@as(u32, @bitCast(x)) >> 8 & 1);
        var col: u5 = @intCast(@as(u32, @bitCast(x)) >> 3 & 0x1f);
        const dst = ppu.bgBuffers[sub].data[0..];

        if ((x & 7) != 0) {
            const shift: u5 = @intCast(x & 7);
            const curw: i32 = @min(8 - @as(i32, shift), w);
            w -= curw;
            const tile: u32 = ppu.vram[tps[which] +% col];
            nextTp(&which, &col);
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits4(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 6));
                const hflip = tile & 0x4000 == 0;
                var k: i32 = 0;
                while (k < curw) : (k += 1) {
                    const idx: u5 = shift + @as(u5, @intCast(k));
                    const pr = if (!hflip) px4bpp(bits, idx) else px4bppHflip(bits, idx);
                    const off = dst_off + @as(usize, @intCast(k));
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
            dst_off +%= @intCast(curw);
            x += curw;
        }

        while (w >= 8) {
            const tile: u32 = ppu.vram[tps[which] +% col];
            nextTp(&which, &col);
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits4(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 6));
                const hflip = tile & 0x4000 == 0;
                var k: u5 = 0;
                while (k < 8) : (k += 1) {
                    const pr = if (!hflip) px4bpp(bits, k) else px4bppHflip(bits, k);
                    const off = dst_off + k;
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
            dst_off += 8;
            w -= 8;
        }

        if (w != 0) {
            const tile: u32 = ppu.vram[tps[which] +% col];
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits4(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 6));
                const hflip = tile & 0x4000 == 0;
                var k: i32 = 0;
                while (k < w) : (k += 1) {
                    const idx: u5 = @intCast(k);
                    const pr = if (!hflip) px4bpp(bits, idx) else px4bppHflip(bits, idx);
                    const off = dst_off + @as(usize, @intCast(k));
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
        }
    }
}

fn ppuDrawBackground2bpp(ppu: *Ppu, y0: u32, sub: usize, layer: usize, zhi: PpuZbufType, zlo: PpuZbufType) void {
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, @intCast(layer)) else ppuWindowsClear(&win, ppu, @intCast(layer));

    const bglayer = &ppu.bgLayer[layer];
    const y: u32 = y0 +% bglayer.vScroll;
    const addrs = bgTileAddrs(ppu, y, layer);
    const tps = addrs.tps;
    const tileadr0 = addrs.tileadr0;
    const tileadr1 = addrs.tileadr1;

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const left = win.edges[windex];
        const right = win.edges[windex + 1];
        var x: i32 = @as(i32, left) + @as(i32, bglayer.hScroll);
        var w: i32 = @as(i32, right) - @as(i32, left);
        var dst_off: usize = @intCast(@as(i32, left) + @as(i32, @intCast(kPpuExtraLeftRight)));
        var which: u1 = @intCast(@as(u32, @bitCast(x)) >> 8 & 1);
        var col: u5 = @intCast(@as(u32, @bitCast(x)) >> 3 & 0x1f);
        const dst = ppu.bgBuffers[sub].data[0..];

        if ((x & 7) != 0) {
            const shift: u5 = @intCast(x & 7);
            const curw: i32 = @min(8 - @as(i32, shift), w);
            w -= curw;
            const tile: u32 = ppu.vram[tps[which] +% col];
            nextTp(&which, &col);
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits2(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 8));
                const hflip = tile & 0x4000 == 0;
                var k: i32 = 0;
                while (k < curw) : (k += 1) {
                    const idx: u5 = shift + @as(u5, @intCast(k));
                    const pr = if (!hflip) px2bpp(bits, idx) else px2bppHflip(bits, idx);
                    const off = dst_off + @as(usize, @intCast(k));
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
            dst_off +%= @intCast(curw);
            x += curw;
        }

        while (w >= 8) {
            const tile: u32 = ppu.vram[tps[which] +% col];
            nextTp(&which, &col);
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits2(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 8));
                const hflip = tile & 0x4000 == 0;
                var k: u5 = 0;
                while (k < 8) : (k += 1) {
                    const pr = if (!hflip) px2bpp(bits, k) else px2bppHflip(bits, k);
                    const off = dst_off + k;
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
            dst_off += 8;
            w -= 8;
        }

        if (w != 0) {
            const tile: u32 = ppu.vram[tps[which] +% col];
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits2(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 8));
                const hflip = tile & 0x4000 == 0;
                var k: i32 = 0;
                while (k < w) : (k += 1) {
                    const idx: u5 = @intCast(k);
                    const pr = if (!hflip) px2bpp(bits, idx) else px2bppHflip(bits, idx);
                    const off = dst_off + @as(usize, @intCast(k));
                    if (pr.valid and zbase > dst[off]) dst[off] = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                }
            }
        }
    }
}

fn ppuDrawBackground4bppMosaic(ppu: *Ppu, y0: u32, sub: usize, layer: usize, zhi: PpuZbufType, zlo: PpuZbufType) void {
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, @intCast(layer)) else ppuWindowsClear(&win, ppu, @intCast(layer));

    const bglayer = &ppu.bgLayer[layer];
    const y: u32 = @as(u32, ppu.mosaicModulo[y0]) +% bglayer.vScroll;
    const addrs = bgTileAddrs(ppu, y, layer);
    const tps = addrs.tps;
    const tileadr0 = addrs.tileadr0;
    const tileadr1 = addrs.tileadr1;
    const dst = ppu.bgBuffers[sub].data[0..];

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const sx: i32 = win.edges[windex];
        var dst_off: usize = @intCast(sx + @as(i32, @intCast(kPpuExtraLeftRight)));
        const dst_end: usize = @intCast(@as(i32, win.edges[windex + 1]) + @as(i32, @intCast(kPpuExtraLeftRight)));
        const x: i32 = sx + @as(i32, bglayer.hScroll);
        var which: u1 = @intCast(@as(u32, @bitCast(x)) >> 8 & 1);
        var col: u5 = @intCast(@as(u32, @bitCast(x)) >> 3 & 0x1f);
        var xr: i32 = x & 7;
        var w: i32 = @as(i32, ppu.mosaicSize) - (sx - @as(i32, ppu.mosaicModulo[@intCast(sx)]));

        while (true) {
            w = @min(w, @as(i32, @intCast(dst_end - dst_off)));
            const tile: u32 = ppu.vram[tps[which] +% col];
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits4(ppu, ta, tile & 0x3ff);
            const hflip = tile & 0x4000 == 0;
            const shift: u5 = @intCast(xr & 7);
            const pr = if (!hflip) px4bpp(bits, shift) else px4bppHflip(bits, shift);
            if (pr.valid) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 6));
                const pixel: PpuZbufType = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                var i: i32 = 0;
                while (i < w) : (i += 1) {
                    const off = dst_off + @as(usize, @intCast(i));
                    if (zbase > dst[off]) dst[off] = pixel;
                }
            }
            dst_off += @intCast(w);
            xr += w;
            while (xr >= 8) : (xr -= 8) nextTp(&which, &col);
            w = ppu.mosaicSize;
            if (dst_off == dst_end) break;
        }
    }
}

fn ppuDrawBackground2bppMosaic(ppu: *Ppu, y0: u32, sub: usize, layer: usize, zhi: PpuZbufType, zlo: PpuZbufType) void {
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, @intCast(layer)) else ppuWindowsClear(&win, ppu, @intCast(layer));

    const bglayer = &ppu.bgLayer[layer];
    const y: u32 = @as(u32, ppu.mosaicModulo[y0]) +% bglayer.vScroll;
    const addrs = bgTileAddrs(ppu, y, layer);
    const tps = addrs.tps;
    const tileadr0 = addrs.tileadr0;
    const tileadr1 = addrs.tileadr1;
    const dst = ppu.bgBuffers[sub].data[0..];

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const sx: i32 = win.edges[windex];
        var dst_off: usize = @intCast(sx + @as(i32, @intCast(kPpuExtraLeftRight)));
        const dst_end: usize = @intCast(@as(i32, win.edges[windex + 1]) + @as(i32, @intCast(kPpuExtraLeftRight)));
        const x: i32 = sx + @as(i32, bglayer.hScroll);
        var which: u1 = @intCast(@as(u32, @bitCast(x)) >> 8 & 1);
        var col: u5 = @intCast(@as(u32, @bitCast(x)) >> 3 & 0x1f);
        var xr: i32 = x & 7;
        var w: i32 = @as(i32, ppu.mosaicSize) - (sx - @as(i32, ppu.mosaicModulo[@intCast(sx)]));

        while (true) {
            w = @min(w, @as(i32, @intCast(dst_end - dst_off)));
            const tile: u32 = ppu.vram[tps[which] +% col];
            const ta: i32 = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z: PpuZbufType = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = readBits2(ppu, ta, tile & 0x3ff);
            const hflip = tile & 0x4000 == 0;
            const shift: u5 = @intCast(xr & 7);
            const pr = if (!hflip) px2bpp(bits, shift) else px2bppHflip(bits, shift);
            if (pr.valid) {
                const zbase: PpuZbufType = z +% @as(PpuZbufType, @intCast((tile & 0x1c00) >> 8));
                const pixel: PpuZbufType = zbase + @as(PpuZbufType, @intCast(pr.pixel));
                var i: i32 = 0;
                while (i < w) : (i += 1) {
                    const off = dst_off + @as(usize, @intCast(i));
                    if (zbase > dst[off]) dst[off] = pixel;
                }
            }
            dst_off += @intCast(w);
            xr += w;
            while (xr >= 8) : (xr -= 8) nextTp(&which, &col);
            w = ppu.mosaicSize;
            if (dst_off == dst_end) break;
        }
    }
}

inline fn spritePrioToPrio(prio: u32, level6: bool) u32 {
    return (prio * 4 + 2) * 16 + 4 + (if (level6) @as(u32, 2) else 0);
}
inline fn spritePrioToPrioHi(prio: u32) u32 {
    return prio * 4 + 2;
}

fn ppuDrawSprites(ppu: *Ppu, sub: usize, clear_backdrop: bool) void {
    const layer: usize = 4;
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, layer) else ppuWindowsClear(&win, ppu, layer);

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const left: i32 = win.edges[windex];
        const width: usize = @intCast(win.edges[windex + 1] - left);
        const src_off: usize = @intCast(left + @as(i32, @intCast(kPpuExtraLeftRight)));
        const src = ppu.objBuffer.data[src_off..][0..width];
        const dst = ppu.bgBuffers[sub].data[src_off..][0..width];
        if (clear_backdrop) {
            @memcpy(dst, src);
        } else {
            for (0..width) |i| {
                if (src[i] > dst[i]) dst[i] = src[i];
            }
        }
    }
}

fn ppuDrawBackgroundMode7(ppu: *Ppu, y0: u32, sub: usize, z: PpuZbufType) void {
    const layer: usize = 0;
    if (!isScreenEnabled(ppu, sub, layer)) return;
    var win: PpuWindows = .{};
    if (isScreenWindowed(ppu, sub, layer)) ppuWindowsCalc(&win, ppu, layer) else ppuWindowsClear(&win, ppu, layer);

    const hScroll: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[6])) << 3)) >> 3;
    const vScroll: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[7])) << 3)) >> 3;
    const xCenter: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[4])) << 3)) >> 3;
    const yCenter: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[5])) << 3)) >> 3;
    var clippedH: i32 = hScroll - xCenter;
    var clippedV: i32 = vScroll - yCenter;
    clippedH = if (clippedH & 0x2000 != 0) clippedH | ~@as(i32, 1023) else clippedH & 1023;
    clippedV = if (clippedV & 0x2000 != 0) clippedV | ~@as(i32, 1023) else clippedV & 1023;
    const mosaic_enabled = isMosaicEnabled(ppu, 0);
    var y: u32 = y0;
    if (mosaic_enabled) y = ppu.mosaicModulo[y0];
    const ry: u32 = if (ppu.m7yFlip) 255 -% y else y;

    const m7a: i32 = ppu.m7matrix[0];
    const m7b: i32 = ppu.m7matrix[1];
    const m7c: i32 = ppu.m7matrix[2];
    const m7d: i32 = ppu.m7matrix[3];

    const m7startX: u32 = @bitCast((m7a *% clippedH & ~@as(i32, 63)) +% (m7b *% @as(i32, @bitCast(ry)) & ~@as(i32, 63)) +%
        (m7b *% clippedV & ~@as(i32, 63)) +% (xCenter << 8));
    const m7startY: u32 = @bitCast((m7c *% clippedH & ~@as(i32, 63)) +% (m7d *% @as(i32, @bitCast(ry)) & ~@as(i32, 63)) +%
        (m7d *% clippedV & ~@as(i32, 63)) +% (yCenter << 8));

    const dstb = ppu.bgBuffers[sub].data[0..];

    var windex: usize = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u8, 1) << @intCast(windex)) != 0) continue;
        const x: i32 = win.edges[windex];
        const x2: i32 = win.edges[windex + 1];
        var dst_off: usize = @intCast(x + @as(i32, @intCast(kPpuExtraLeftRight)));
        const dst_end: usize = @intCast(x2 + @as(i32, @intCast(kPpuExtraLeftRight)));
        const rx: u32 = if (ppu.m7xFlip) 255 -% @as(u32, @bitCast(x)) else @bitCast(x);
        var xpos: u32 = m7startX +% @as(u32, @bitCast(m7a *% @as(i32, @bitCast(rx))));
        var ypos: u32 = m7startY +% @as(u32, @bitCast(m7c *% @as(i32, @bitCast(rx))));
        const dx: u32 = if (ppu.m7xFlip) 0 -% @as(u32, @bitCast(m7a)) else @bitCast(m7a);
        const dy: u32 = if (ppu.m7xFlip) 0 -% @as(u32, @bitCast(m7c)) else @bitCast(m7c);
        const outside_value: u32 = if (ppu.m7largeField) 0x3ffff else 0xffffffff;
        const char_fill = ppu.m7charFill;

        if (mosaic_enabled) {
            var w: i32 = @as(i32, ppu.mosaicSize) - (x - @as(i32, ppu.mosaicModulo[@intCast(x)]));
            while (true) {
                w = @min(w, @as(i32, @intCast(dst_end - dst_off)));
                var skip = false;
                var tile: u32 = 0;
                if ((xpos | ypos) > outside_value) {
                    if (!char_fill) {
                        skip = true;
                    } else {
                        tile = 0;
                    }
                } else {
                    tile = ppu.vram[(ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)] & 0xff;
                }
                if (!skip) {
                    const pixel: u32 = ppu.vram[tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)] >> 8;
                    if (pixel != 0) {
                        var i: i32 = 0;
                        while (i < w) : (i += 1) dstb[dst_off + @as(usize, @intCast(i))] = @intCast(pixel + z);
                    }
                }
                xpos +%= dx *% @as(u32, @bitCast(w));
                ypos +%= dy *% @as(u32, @bitCast(w));
                dst_off += @intCast(w);
                w = ppu.mosaicSize;
                if (dst_off == dst_end) break;
            }
        } else {
            while (true) {
                var skip = false;
                var tile: u32 = 0;
                if ((xpos | ypos) > outside_value) {
                    if (!char_fill) {
                        skip = true;
                    } else {
                        tile = 0;
                    }
                } else {
                    tile = ppu.vram[(ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)] & 0xff;
                }
                if (!skip) {
                    const pixel: u32 = ppu.vram[tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)] >> 8;
                    if (pixel != 0) dstb[dst_off] = @intCast(pixel + z);
                }
                xpos +%= dx;
                ypos +%= dy;
                dst_off += 1;
                if (dst_off == dst_end) break;
            }
        }
    }
}

pub export fn PpuSetMode7PerspectiveCorrection(ppu: *Ppu, low: c_int, high: c_int) void {
    ppu.mode7PerspectiveLow = if (low != 0) 1.0 / @as(f32, @floatFromInt(low)) else 0.0;
    ppu.mode7PerspectiveHigh = 1.0 / @as(f32, @floatFromInt(high));
}

pub export fn PpuSetExtraSideSpace(ppu: *Ppu, left: c_int, right: c_int, bottom: c_int) void {
    ppu.extraLeftCur = @intCast(@min(left, @as(c_int, ppu.extraLeftRight)));
    ppu.extraRightCur = @intCast(@min(right, @as(c_int, ppu.extraLeftRight)));
    ppu.extraBottomCur = @intCast(@min(bottom, 16));
}

inline fn floatInterpolate(x: f32, xmin: f32, xmax: f32, ymin: f32, ymax: f32) f32 {
    return ymin + (ymax - ymin) * (x - xmin) * (1.0 / (xmax - xmin));
}

fn ppuDrawMode7Upsampled(ppu: *Ppu, y: u32) void {
    const xCenter: u32 = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[4])) << 3)) >> 3));
    const yCenter: u32 = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[5])) << 3)) >> 3));
    const clippedH: u32 = (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[6])) << 3)) >> 3)))) -% xCenter;
    const clippedV: u32 = (@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[7])) << 3)) >> 3)))) -% yCenter;

    var m0v: [4]i32 = undefined;
    const persp_low_bits: u32 = @bitCast(ppu.mode7PerspectiveLow);
    if (persp_low_bits == 0) {
        const v = @as(i32, ppu.m7matrix[0]) << 12;
        m0v = .{ v, v, v, v };
    } else {
        const kInterpolateOffsets = [4]f32{ -1, -1 + 0.25, -1 + 0.5, -1 + 0.75 };
        for (0..4) |i| {
            m0v[i] = @intFromFloat(4096.0 / floatInterpolate(@as(f32, @floatFromInt(y)) + kInterpolateOffsets[i], 0, 223, ppu.mode7PerspectiveLow, ppu.mode7PerspectiveHigh));
        }
    }

    const pitch: usize = ppu.renderPitch;
    const render_buffer_ptr = ppu.renderBuffer.?[(y - 1) * 4 * pitch ..];
    const dst_start_off: usize = @as(usize, ppu.extraLeftRight - ppu.extraLeftCur) * 16;
    const draw_width: usize = 256 + @as(usize, ppu.extraLeftCur) + @as(usize, ppu.extraRightCur);
    const m1: u32 = @bitCast(@as(i32, ppu.m7matrix[1]) << 12);
    const m2: u32 = @bitCast(@as(i32, ppu.m7matrix[2]) << 12);

    var dst_curline_off: usize = dst_start_off;
    for (0..4) |j| {
        const m0: u32 = @bitCast(m0v[j]);
        const m3: u32 = m0;
        var xpos: u32 = m0 *% clippedH +% m1 *% (clippedV +% y) +% (xCenter << 20);
        var ypos: u32 = m2 *% clippedH +% m3 *% (clippedV +% y) +% (yCenter << 20);

        xpos -%= (m0 +% m1) >> 1;
        ypos -%= (m2 +% m3) >> 1;
        var xcur: u32 = (xpos << 2) +% @as(u32, @intCast(j)) *% m1;
        var ycur: u32 = (ypos << 2) +% @as(u32, @intCast(j)) *% m3;

        xcur -%= @as(u32, ppu.extraLeftCur) *% 4 *% m0;
        ycur -%= @as(u32, ppu.extraLeftCur) *% 4 *% m2;

        var dst_off: usize = dst_curline_off;
        const dst_end_off: usize = dst_curline_off + draw_width * 16;

        const half = ppu.halfColor;
        while (dst_off != dst_end_off) {
            inline for (0..4) |_| {
                const tile: u32 = ppu.vram[(ycur >> 25 & 0x7f) * 128 + (xcur >> 25 & 0x7f)] & 0xff;
                var pixel: u32 = ppu.vram[tile * 64 + (ycur >> 22 & 7) * 8 + (xcur >> 22 & 7)] >> 8;
                pixel = if (xcur & 0x80000000 != 0) 0 else pixel;
                const color = if (half) (ppu.colorMapRgb[pixel] & 0xfefefe) >> 1 else ppu.colorMapRgb[pixel];
                const p: *align(1) u32 = @ptrCast(&render_buffer_ptr[dst_off]);
                p.* = color;
                xcur +%= m0;
                ycur +%= m2;
                dst_off += 4;
            }
        }

        dst_curline_off += pitch;
    }

    if (ppu.lineHasSprites) {
        var dst_off: usize = dst_start_off;
        const pix_off: usize = kPpuExtraLeftRight - ppu.extraLeftCur;
        for (0..draw_width) |i| {
            const pixel: u32 = ppu.objBuffer.data[pix_off + i] & 0xff;
            if (pixel != 0) {
                const color = ppu.colorMapRgb[pixel];
                for (0..4) |row| {
                    const base = dst_off + pitch * row;
                    for (0..4) |col| {
                        const p: *align(1) u32 = @ptrCast(&render_buffer_ptr[base + col * 4]);
                        p.* = color;
                    }
                }
            }
            dst_off += 16;
        }
    }

    if (ppu.extraLeftRight - ppu.extraLeftCur != 0) {
        const n: usize = 16 * @as(usize, ppu.extraLeftRight - ppu.extraLeftCur);
        for (0..4) |i| @memset(render_buffer_ptr[pitch * i ..][0..n], 0);
    }
    if (ppu.extraLeftRight - ppu.extraRightCur != 0) {
        const n: usize = 16 * @as(usize, ppu.extraLeftRight - ppu.extraRightCur);
        const off: usize = (256 + @as(usize, ppu.extraLeftRight) * 2 - @as(usize, ppu.extraLeftRight - ppu.extraRightCur)) * 16;
        for (0..4) |i| @memset(render_buffer_ptr[pitch * i + off ..][0..n], 0);
    }
}

fn ppuDrawBackgrounds(ppu: *Ppu, y: u32, sub: usize) void {
    if (ppu.mode == 1) {
        if (ppu.lineHasSprites) ppuDrawSprites(ppu, sub, true);

        if (isMosaicEnabled(ppu, 0)) ppuDrawBackground4bppMosaic(ppu, y, sub, 0, 0xc000, 0x8000) else ppuDrawBackground4bpp(ppu, y, sub, 0, 0xc000, 0x8000);
        if (isMosaicEnabled(ppu, 1)) ppuDrawBackground4bppMosaic(ppu, y, sub, 1, 0xb100, 0x7100) else ppuDrawBackground4bpp(ppu, y, sub, 1, 0xb100, 0x7100);
        if (isMosaicEnabled(ppu, 2)) ppuDrawBackground2bppMosaic(ppu, y, sub, 2, 0xf200, 0x1200) else ppuDrawBackground2bpp(ppu, y, sub, 2, 0xf200, 0x1200);
    } else {
        ppuDrawBackgroundMode7(ppu, y, sub, 0xc000);
        if (ppu.lineHasSprites) ppuDrawSprites(ppu, sub, false);
    }
}

fn ppuDrawWholeLine(ppu: *Ppu, y: u32) void {
    if (ppu.forcedBlank) {
        const dst_off: usize = (y - 1) * ppu.renderPitch;
        const n: usize = 4 * (256 + @as(usize, ppu.extraLeftRight) * 2);
        @memset(ppu.renderBuffer.?[dst_off..][0..n], 0);
        return;
    }

    if (ppu.mode == 7 and (ppu.renderFlags & wrapU8(@bitCast(kPpuRenderFlags_4x4Mode7))) != 0) {
        ppuDrawMode7Upsampled(ppu, y);
        return;
    }

    clearBackdrop(&ppu.bgBuffers[0]);
    ppuDrawBackgrounds(ppu, y, 0);

    const math_enabled: u32 = ppu.mathEnabled;

    var rendered_subscreen = false;
    if (ppu.preventMathMode != 3 and ppu.addSubscreen and math_enabled != 0) {
        clearBackdrop(&ppu.bgBuffers[1]);
        if (ppu.screenEnabled[1] != 0) {
            ppuDrawBackgrounds(ppu, y, 1);
            rendered_subscreen = true;
        }
    }

    var cwin: PpuWindows = .{};
    ppuWindowsCalc(&cwin, ppu, 5);
    const kCwBitsMod = [8]u8{ 0x00, 0xff, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00 };
    var cw_clip_math: u32 = (@as(u32, cwin.bits & kCwBitsMod[ppu.clipMode]) ^ kCwBitsMod[ppu.clipMode + 4]) |
        ((@as(u32, cwin.bits & kCwBitsMod[ppu.preventMathMode]) ^ kCwBitsMod[ppu.preventMathMode + 4]) << 8);

    const row_off: usize = (y - 1) * ppu.renderPitch;
    const dst_org = ppu.renderBuffer.?[row_off..];
    var dst_off: usize = @as(usize, ppu.extraLeftRight - ppu.extraLeftCur) * 4;

    var windex: u32 = 0;
    while (true) {
        const left: u32 = @as(u32, @bitCast(@as(i32, cwin.edges[windex]))) +% kPpuExtraLeftRight;
        const right: u32 = @as(u32, @bitCast(@as(i32, cwin.edges[windex + 1]))) +% kPpuExtraLeftRight;
        const clip_color_mask: u32 = if (cw_clip_math & 1 != 0) 0x1f else 0;
        const math_enabled_cur_base: u32 = if (cw_clip_math & 0x100 != 0) math_enabled else 0;
        const fixed_color: u32 = ppu.fixedColorR | (@as(u32, ppu.fixedColorG) << 5) | (@as(u32, ppu.fixedColorB) << 10);

        if (math_enabled_cur_base == 0 or (fixed_color == 0 and !ppu.halfColor and !rendered_subscreen)) {
            var i: u32 = left;
            while (true) {
                const color: u32 = ppu.cgram[ppu.bgBuffers[0].data[i] & 0xff];
                const p: *align(1) u32 = @ptrCast(&dst_org[dst_off]);
                p.* = @as(u32, ppu.brightnessMult[color & clip_color_mask]) << 16 |
                    @as(u32, ppu.brightnessMult[(color >> 5) & clip_color_mask]) << 8 |
                    @as(u32, ppu.brightnessMult[(color >> 10) & clip_color_mask]);
                dst_off += 4;
                i += 1;
                if (i >= right) break;
            }
        } else {
            const half_color_map: []const u8 = if (ppu.halfColor) &ppu.brightnessMultHalf else &ppu.brightnessMult;
            const math_enabled_cur: u32 = math_enabled_cur_base | (@as(u32, @intFromBool(ppu.addSubscreen)) << 8) | (@as(u32, @intFromBool(ppu.subtractColor)) << 9);
            var i: u32 = left;
            while (true) {
                const color: u32 = ppu.cgram[ppu.bgBuffers[0].data[i] & 0xff];
                var color2: u32 = undefined;
                const main_layer: u5 = @intCast((ppu.bgBuffers[0].data[i] >> 8) & 0xf);
                var r: u32 = color & clip_color_mask;
                var g: u32 = (color >> 5) & clip_color_mask;
                var b: u32 = (color >> 10) & clip_color_mask;
                var color_map: []const u8 = &ppu.brightnessMult;
                if (math_enabled_cur & (@as(u32, 1) << main_layer) != 0) {
                    if (math_enabled_cur & 0x100 != 0) {
                        if ((ppu.bgBuffers[1].data[i] & 0xff) != 0) {
                            color2 = ppu.cgram[ppu.bgBuffers[1].data[i] & 0xff];
                            color_map = half_color_map;
                        } else {
                            color2 = fixed_color;
                        }
                    } else {
                        color2 = fixed_color;
                        color_map = half_color_map;
                    }
                    const r2: u32 = color2 & 0x1f;
                    const g2: u32 = (color2 >> 5) & 0x1f;
                    const b2: u32 = (color2 >> 10) & 0x1f;
                    if (math_enabled_cur & 0x200 != 0) {
                        r = if (r >= r2) r - r2 else 0;
                        g = if (g >= g2) g - g2 else 0;
                        b = if (b >= b2) b - b2 else 0;
                    } else {
                        r += r2;
                        g += g2;
                        b += b2;
                    }
                }
                const p: *align(1) u32 = @ptrCast(&dst_org[dst_off]);
                p.* = @as(u32, color_map[b]) | @as(u32, color_map[g]) << 8 | @as(u32, color_map[r]) << 16;
                dst_off += 4;
                i += 1;
                if (i >= right) break;
            }
        }

        cw_clip_math >>= 1;
        windex += 1;
        if (windex >= cwin.nr) break;
    }

    if (ppu.extraLeftRight - ppu.extraLeftCur != 0)
        @memset(dst_org[0 .. 4 * @as(usize, ppu.extraLeftRight - ppu.extraLeftCur)], 0);
    if (ppu.extraLeftRight - ppu.extraRightCur != 0) {
        const off: usize = (256 + @as(usize, ppu.extraLeftRight) * 2 - @as(usize, ppu.extraLeftRight - ppu.extraRightCur)) * 4;
        @memset(dst_org[off..][0 .. 4 * @as(usize, ppu.extraLeftRight - ppu.extraRightCur)], 0);
    }
}

fn ppuHandlePixel(ppu: *Ppu, x: i32, y: c_int) void {
    var r: i32 = 0;
    var g: i32 = 0;
    var b: i32 = 0;
    var r2: i32 = 0;
    var g2: i32 = 0;
    var b2: i32 = 0;
    if (!ppu.forcedBlank) {
        var mainR: i32 = 0;
        var mainG: i32 = 0;
        var mainB: i32 = 0;
        const mainLayer = ppuGetPixel(ppu, x, y, false, &mainR, &mainG, &mainB);
        r = mainR;
        g = mainG;
        b = mainB;

        const colorWindowState = ppuGetWindowState(ppu, 5, x);
        if (ppu.clipMode == 3 or (ppu.clipMode == 2 and colorWindowState) or (ppu.clipMode == 1 and !colorWindowState)) {
            r = 0;
            g = 0;
            b = 0;
        }
        var secondLayer: i32 = 5;
        const mathEnabled = mainLayer < 6 and (ppu.mathEnabled & (@as(u8, 1) << @intCast(mainLayer)) != 0) and
            !(ppu.preventMathMode == 3 or (ppu.preventMathMode == 2 and colorWindowState) or (ppu.preventMathMode == 1 and !colorWindowState));
        if ((mathEnabled and ppu.addSubscreen) or ppu.mode == 5 or ppu.mode == 6) {
            secondLayer = ppuGetPixel(ppu, x, y, true, &r2, &g2, &b2);
        }
        if (mathEnabled) {
            if (ppu.subtractColor) {
                r -= if (ppu.addSubscreen and secondLayer != 5) r2 else ppu.fixedColorR;
                g -= if (ppu.addSubscreen and secondLayer != 5) g2 else ppu.fixedColorG;
                b -= if (ppu.addSubscreen and secondLayer != 5) b2 else ppu.fixedColorB;
            } else {
                r += if (ppu.addSubscreen and secondLayer != 5) r2 else ppu.fixedColorR;
                g += if (ppu.addSubscreen and secondLayer != 5) g2 else ppu.fixedColorG;
                b += if (ppu.addSubscreen and secondLayer != 5) b2 else ppu.fixedColorB;
            }
            if (ppu.halfColor and (secondLayer != 5 or !ppu.addSubscreen)) {
                r >>= 1;
                g >>= 1;
                b >>= 1;
            }
            if (r > 31) r = 31;
            if (g > 31) g = 31;
            if (b > 31) b = 31;
            if (r < 0) r = 0;
            if (g < 0) g = 0;
            if (b < 0) b = 0;
        }
        if (!(ppu.mode == 5 or ppu.mode == 6)) {
            r2 = r;
            g2 = g;
            b2 = b;
        }
    }
    const row: i32 = y - 1;
    const off: usize = @intCast(row * @as(i32, @intCast(ppu.renderPitch)) + (x + @as(i32, ppu.extraLeftRight)) * 4);
    const pixelBuffer = ppu.renderBuffer.?[off..];
    pixelBuffer[0] = @intCast(@divTrunc(((b << 3) | (b >> 2)) * @as(i32, ppu.brightness), 15));
    pixelBuffer[1] = @intCast(@divTrunc(((g << 3) | (g >> 2)) * @as(i32, ppu.brightness), 15));
    pixelBuffer[2] = @intCast(@divTrunc(((r << 3) | (r >> 2)) * @as(i32, ppu.brightness), 15));
    pixelBuffer[3] = 0;
}

const bitDepthsPerMode: [10][4]i32 = .{
    .{ 2, 2, 2, 2 },
    .{ 4, 4, 2, 5 },
    .{ 4, 4, 5, 5 },
    .{ 8, 4, 5, 5 },
    .{ 8, 2, 5, 5 },
    .{ 4, 2, 5, 5 },
    .{ 4, 5, 5, 5 },
    .{ 8, 5, 5, 5 },
    .{ 4, 4, 2, 5 },
    .{ 8, 7, 5, 5 },
};

const layersPerMode: [10][12]i32 = .{
    .{ 4, 0, 1, 4, 0, 1, 4, 2, 3, 4, 2, 3 },
    .{ 4, 0, 1, 4, 0, 1, 4, 2, 4, 2, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5 },
    .{ 4, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5, 5 },
    .{ 2, 4, 0, 1, 4, 0, 1, 4, 4, 2, 5, 5 },
    .{ 4, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5, 5 },
};

const prioritysPerMode: [10][12]i32 = .{
    .{ 3, 1, 1, 2, 0, 0, 1, 1, 1, 0, 0, 0 },
    .{ 3, 1, 1, 2, 0, 0, 1, 1, 0, 0, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5 },
    .{ 3, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5, 5 },
    .{ 1, 3, 1, 1, 2, 0, 0, 1, 0, 0, 5, 5 },
    .{ 3, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5, 5 },
};

const layerCountPerMode: [10]i32 = .{ 12, 10, 8, 8, 8, 8, 6, 5, 10, 7 };

fn ppuGetPixel(ppu: *Ppu, x: i32, y: c_int, sub: bool, r: *i32, g: *i32, b: *i32) i32 {
    var actMode: i32 = if (ppu.mode == 1) 8 else ppu.mode;
    actMode = if (ppu.mode == 7 and ppu.m7extBg_always_zero) 9 else actMode;
    var layer: i32 = 5;
    var pixel: i32 = 0;
    const mi: usize = @intCast(actMode);
    var i: i32 = 0;
    while (i < layerCountPerMode[mi]) : (i += 1) {
        const ii: usize = @intCast(i);
        const curLayer = layersPerMode[mi][ii];
        const curPriority = prioritysPerMode[mi][ii];
        const cl: usize = @intCast(curLayer);
        var layerActive = false;
        if (!sub) {
            layerActive = isScreenEnabled(ppu, 0, cl) and (!isScreenWindowed(ppu, 0, cl) or !ppuGetWindowState(ppu, curLayer, x));
        } else {
            layerActive = isScreenEnabled(ppu, 1, cl) and (!isScreenWindowed(ppu, 1, cl) or !ppuGetWindowState(ppu, curLayer, x));
        }
        if (layerActive) {
            if (curLayer < 4) {
                var lx = x;
                var ly: i32 = y;
                if (isMosaicEnabled(ppu, cl)) {
                    lx -= @mod(lx, @as(i32, ppu.mosaicSize));
                    ly -= @mod(ly - 1, @as(i32, ppu.mosaicSize));
                }
                if (ppu.mode == 7) {
                    pixel = ppuGetPixelForMode7(ppu, lx, curLayer, curPriority != 0);
                } else {
                    lx += ppu.bgLayer[cl].hScroll;
                    ly += ppu.bgLayer[cl].vScroll;
                    pixel = ppuGetPixelForBgLayer(ppu, lx & 0x3ff, ly & 0x3ff, curLayer, curPriority != 0);
                }
            } else {
                pixel = 0;
                const idx: usize = @intCast(x + @as(i32, @intCast(kPpuExtraLeftRight)));
                if ((ppu.objBuffer.data[idx] >> 12) == spritePrioToPrioHi(@intCast(curPriority)))
                    pixel = ppu.objBuffer.data[idx] & 0xff;
            }
        }
        if (pixel > 0) {
            layer = curLayer;
            break;
        }
    }
    const color: u16 = ppu.cgram[@as(u32, @bitCast(pixel)) & 0xff];
    r.* = color & 0x1f;
    g.* = (color >> 5) & 0x1f;
    b.* = (color >> 10) & 0x1f;
    if (layer == 4 and pixel < 0xc0) layer = 6;
    return layer;
}

fn ppuGetPixelForBgLayer(ppu: *Ppu, x: i32, y: i32, layer: i32, priority: bool) i32 {
    const li: usize = @intCast(layer);
    const layerp = &ppu.bgLayer[li];
    const wideTiles = ppu.mode == 5 or ppu.mode == 6;
    const tileBitsX: u5 = if (wideTiles) 4 else 3;
    const tileHighBitX: i32 = if (wideTiles) 0x200 else 0x100;
    const tileBitsY: u5 = 3;
    const tileHighBitY: i32 = 0x100;
    var tilemapAdr: u32 = @as(u32, layerp.tilemapAdr) +% (((@as(u32, @bitCast(y)) >> tileBitsY) & 0x1f) << 5 | ((@as(u32, @bitCast(x)) >> tileBitsX) & 0x1f));
    if ((x & tileHighBitX) != 0 and layerp.tilemapWider) tilemapAdr +%= 0x400;
    if ((y & tileHighBitY) != 0 and layerp.tilemapHigher) tilemapAdr +%= if (layerp.tilemapWider) @as(u32, 0x800) else 0x400;
    const tile: u16 = ppu.vram[tilemapAdr & 0x7fff];
    if ((tile & 0x2000 != 0) != priority) return 0;
    var paletteNum: i32 = (tile & 0x1c00) >> 10;
    const row: i32 = if (tile & 0x8000 != 0) 7 - (y & 0x7) else (y & 0x7);
    const col: u4 = if (tile & 0x4000 != 0) @intCast(x & 0x7) else @intCast(7 - (x & 0x7));
    var tileNum: i32 = tile & 0x3ff;
    if (wideTiles) {
        if (((x & 8) != 0) != ((tile & 0x4000) != 0)) tileNum += 1;
    }
    const mi: usize = @intCast(ppu.mode);
    const bitDepth = bitDepthsPerMode[mi][li];
    if (ppu.mode == 0) paletteNum += 8 * layer;
    var paletteSize: i32 = 4;
    const base: u32 = @as(u32, layerp.tileAdr) +% @as(u32, @bitCast((tileNum & 0x3ff) *% 4 *% bitDepth)) +% @as(u32, @bitCast(row));
    const plane1: u16 = ppu.vram[base & 0x7fff];
    var pixel: i32 = (plane1 >> col) & 1;
    pixel |= @as(i32, (plane1 >> (8 + col)) & 1) << 1;
    if (bitDepth > 2) {
        paletteSize = 16;
        const plane2: u16 = ppu.vram[(base +% 8) & 0x7fff];
        pixel |= @as(i32, (plane2 >> col) & 1) << 2;
        pixel |= @as(i32, (plane2 >> (8 + col)) & 1) << 3;
    }
    if (bitDepth > 4) {
        paletteSize = 256;
        const plane3: u16 = ppu.vram[(base +% 16) & 0x7fff];
        pixel |= @as(i32, (plane3 >> col) & 1) << 4;
        pixel |= @as(i32, (plane3 >> (8 + col)) & 1) << 5;
        const plane4: u16 = ppu.vram[(base +% 24) & 0x7fff];
        pixel |= @as(i32, (plane4 >> col) & 1) << 6;
        pixel |= @as(i32, (plane4 >> (8 + col)) & 1) << 7;
    }
    return if (pixel == 0) 0 else paletteSize * paletteNum + pixel;
}

fn ppuCalculateMode7Starts(ppu: *Ppu, y0: c_int) void {
    const hScroll: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[6])) << 3)) >> 3;
    const vScroll: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[7])) << 3)) >> 3;
    const xCenter: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[4])) << 3)) >> 3;
    const yCenter: i32 = @as(i16, @bitCast(@as(u16, @bitCast(ppu.m7matrix[5])) << 3)) >> 3;
    var clippedH: i32 = hScroll - xCenter;
    var clippedV: i32 = vScroll - yCenter;
    clippedH = if (clippedH & 0x2000 != 0) clippedH | ~@as(i32, 1023) else clippedH & 1023;
    clippedV = if (clippedV & 0x2000 != 0) clippedV | ~@as(i32, 1023) else clippedV & 1023;
    var y: i32 = y0;
    if (isMosaicEnabled(ppu, 0)) {
        y -= @mod(y - 1, @as(i32, ppu.mosaicSize));
    }
    const ry: u8 = if (ppu.m7yFlip) wrapU8(255 - y) else wrapU8(y);

    const m7a: i32 = ppu.m7matrix[0];
    const m7b: i32 = ppu.m7matrix[1];
    const m7c: i32 = ppu.m7matrix[2];
    const m7d: i32 = ppu.m7matrix[3];

    ppu.m7startX = (m7a *% clippedH & ~@as(i32, 63)) +% (m7b *% @as(i32, ry) & ~@as(i32, 63)) +%
        (m7b *% clippedV & ~@as(i32, 63)) +% (xCenter << 8);
    ppu.m7startY = (m7c *% clippedH & ~@as(i32, 63)) +% (m7d *% @as(i32, ry) & ~@as(i32, 63)) +%
        (m7d *% clippedV & ~@as(i32, 63)) +% (yCenter << 8);
}

fn ppuGetPixelForMode7(ppu: *Ppu, x0: i32, layer: i32, priority: bool) i32 {
    var x = x0;
    if (isMosaicEnabled(ppu, @intCast(layer))) x -= @mod(x, @as(i32, ppu.mosaicSize));
    const rx: u8 = if (ppu.m7xFlip) wrapU8(255 - x) else wrapU8(x);
    var xPos: i32 = (ppu.m7startX +% ppu.m7matrix[0] *% @as(i32, rx)) >> 8;
    var yPos: i32 = (ppu.m7startY +% ppu.m7matrix[2] *% @as(i32, rx)) >> 8;
    var outsideMap = xPos < 0 or xPos >= 1024 or yPos < 0 or yPos >= 1024;
    xPos &= 0x3ff;
    yPos &= 0x3ff;
    if (!ppu.m7largeField) outsideMap = false;
    const tile: u8 = if (outsideMap) 0 else @truncate(ppu.vram[@as(u32, @intCast(yPos >> 3)) * 128 + @as(u32, @intCast(xPos >> 3))] & 0xff);
    const pixel: u8 = if (outsideMap and !ppu.m7charFill) 0 else @truncate(ppu.vram[@as(u32, tile) * 64 + @as(u32, @intCast(yPos & 7)) * 8 + @as(u32, @intCast(xPos & 7))] >> 8);
    if (layer == 1) {
        if (((pixel & 0x80) != 0) != priority) return 0;
        return pixel & 0x7f;
    }
    return pixel;
}

fn ppuGetWindowState(ppu: *Ppu, layer: i32, x: i32) bool {
    const winflags: u32 = getWindowFlags(ppu, @intCast(layer));
    if (winflags & kWindow1Enabled == 0 and winflags & kWindow2Enabled == 0) return false;
    if (winflags & kWindow1Enabled != 0 and winflags & kWindow2Enabled == 0) {
        const t = x >= @as(i32, ppu.window1left) and x <= @as(i32, ppu.window1right);
        return if (winflags & kWindow1Inversed != 0) !t else t;
    }
    if (winflags & kWindow1Enabled == 0 and winflags & kWindow2Enabled != 0) {
        const t = x >= @as(i32, ppu.window2left) and x <= @as(i32, ppu.window2right);
        return if (winflags & kWindow2Inversed != 0) !t else t;
    }
    var test1 = x >= @as(i32, ppu.window1left) and x <= @as(i32, ppu.window1right);
    var test2 = x >= @as(i32, ppu.window2left) and x <= @as(i32, ppu.window2right);
    if (winflags & kWindow1Inversed != 0) test1 = !test1;
    if (winflags & kWindow2Inversed != 0) test2 = !test2;
    return test1 or test2;
}

fn ppuEvaluateSprites(ppu: *Ppu, line: c_int) bool {
    var index: i32 = 0;
    const index_end: i32 = index;
    var spritesLeft: i32 = 32 + 1;
    var tilesLeft: i32 = 34 + 1;
    const spriteSizes = [2]u8{ kSpriteSizes[ppu.objSize][0], kSpriteSizes[ppu.objSize][1] };
    const extra_left_right: i32 = ppu.extraLeftRight;
    if (ppu.renderFlags & wrapU8(@bitCast(kPpuRenderFlags_NoSpriteLimits)) != 0) {
        spritesLeft = 1024;
        tilesLeft = 1024;
    }
    const tilesLeftOrg = tilesLeft;

    while (true) {
        const idx: usize = @intCast(index);
        const yy: i32 = ppu.oam[idx] >> 8;
        cont: {
            if (yy == 0xf0) break :cont;
            const row0: i32 = (line - yy) & 0xff;
            const highOam: i32 = ppu.oam[0x100 + @as(usize, @intCast(index >> 4))] >> @intCast(index & 15);
            const spriteSize: i32 = spriteSizes[@as(usize, @intCast((highOam >> 1) & 1))];
            if (row0 >= spriteSize) break :cont;
            var x: i32 = (ppu.oam[idx] & 0xff) + (highOam & 1) * 256;
            x -= @as(i32, @intFromBool(x >= 256 + extra_left_right)) * 512;
            if (x <= -(spriteSize + extra_left_right)) break :cont;
            spritesLeft -= 1;
            if (spritesLeft == 0) return tilesLeft != tilesLeftOrg;

            const oam1: i32 = ppu.oam[idx + 1];
            const objAdr: u32 = if (oam1 & 0x100 != 0) ppu.objTileAdr2 else ppu.objTileAdr1;
            var row = row0;
            if (oam1 & 0x8000 != 0) row = spriteSize - 1 - row;
            const paletteBase: i32 = 0x80 + 16 * ((oam1 & 0xe00) >> 9);
            const prio: u32 = spritePrioToPrio(@intCast((oam1 & 0x3000) >> 12), (oam1 & 0x800) == 0);
            const z: PpuZbufType = @intCast(@as(u32, @intCast(paletteBase)) +% (prio << 8));

            var col: i32 = 0;
            while (col < spriteSize) : (col += 8) {
                if (col + x > -8 - extra_left_right and col + x < 256 + extra_left_right) {
                    tilesLeft -= 1;
                    if (tilesLeft == 0) return true;
                    const usedCol: i32 = if (oam1 & 0x4000 != 0) spriteSize - 1 - col else col;
                    const usedTile: u32 = (@as(u32, @bitCast((((oam1 & 0xff) >> 4) + (row >> 3)))) << 4) | (@as(u32, @bitCast((oam1 & 0xf) + (usedCol >> 3))) & 0xf);
                    const addr_base: u32 = (objAdr +% usedTile *% 16 +% @as(u32, @bitCast(row & 0x7))) & 0x7fff;
                    const plane: u32 = @as(u32, ppu.vram[addr_base]) | (@as(u32, ppu.vram[(addr_base +% 8) & 0x7fff]) << 16);
                    const px_left: i32 = @max(-(col + x + @as(i32, @intCast(kPpuExtraLeftRight))), 0);
                    const px_right: i32 = @min(256 + @as(i32, @intCast(kPpuExtraLeftRight)) - (col + x), 8);
                    const dst_base: usize = @intCast(col + x + px_left + @as(i32, @intCast(kPpuExtraLeftRight)));
                    var px: i32 = px_left;
                    while (px < px_right) : (px += 1) {
                        const shift: u5 = @intCast(if (oam1 & 0x4000 != 0) px else 7 - px);
                        const bits: u32 = plane >> shift;
                        const pixel: u32 = (bits & 1) | ((bits >> 7) & 2) | ((bits >> 14) & 4) | ((bits >> 21) & 8);
                        const doff = dst_base + @as(usize, @intCast(px - px_left));
                        if (pixel != 0 and (ppu.objBuffer.data[doff] & 0xff) == 0)
                            ppu.objBuffer.data[doff] = @intCast(z + pixel);
                    }
                }
            }
        }
        index = (index + 2) & 0xff;
        if (index == index_end) break;
    }
    return tilesLeft != tilesLeftOrg;
}

pub export fn ppu_read(ppu: *Ppu, adr: u8) u8 {
    switch (adr) {
        0x34, 0x35, 0x36 => {
            const result: i32 = @as(i32, ppu.m7matrix[0]) *% (@as(i32, ppu.m7matrix[1]) >> 8);
            const shift: u5 = @intCast(8 * (adr - 0x34));
            return @truncate(@as(u32, @bitCast(result)) >> shift);
        },
        else => return 0xff,
    }
}

pub export fn ppu_write(ppu: *Ppu, adr: u8, val: u8) void {
    switch (adr) {
        0x00 => {
            ppu.brightness = val & 0xf;
            ppu.forcedBlank = val & 0x80 != 0;
        },
        0x01 => {},
        0x02 => {
            ppu.oamAdr = (ppu.oamAdr & ~@as(u16, 0xff)) | val;
            ppu.oamSecondWrite = false;
        },
        0x03 => {
            ppu.oamAdr = (ppu.oamAdr & ~@as(u16, 0xff00)) | (@as(u16, val & 1) << 8);
            ppu.oamSecondWrite = false;
        },
        0x04 => {
            if (!ppu.oamSecondWrite) {
                ppu.oamBuffer = val;
            } else {
                if (ppu.oamAdr < 0x110) {
                    ppu.oam[ppu.oamAdr] = (@as(u16, val) << 8) | ppu.oamBuffer;
                    ppu.oamAdr += 1;
                }
            }
            ppu.oamSecondWrite = !ppu.oamSecondWrite;
        },
        0x05 => {
            ppu.mode = val & 0x7;
        },
        0x06 => {
            ppu.mosaicSize = (val >> 4) + 1;
            ppu.mosaicEnabled = if (ppu.mosaicSize > 1) val else 0;
        },
        0x07, 0x08, 0x09, 0x0a => {
            const i: usize = adr - 7;
            ppu.bgLayer[i].tilemapWider = val & 0x1 != 0;
            ppu.bgLayer[i].tilemapHigher = val & 0x2 != 0;
            ppu.bgLayer[i].tilemapAdr = @as(u16, val & 0xfc) << 8;
        },
        0x0b => {
            ppu.bgLayer[0].tileAdr = @as(u16, val & 0xf) << 12;
            ppu.bgLayer[1].tileAdr = @as(u16, val & 0xf0) << 8;
        },
        0x0c => {
            ppu.bgLayer[2].tileAdr = @as(u16, val & 0xf) << 12;
            ppu.bgLayer[3].tileAdr = @as(u16, val & 0xf0) << 8;
        },
        0x0d, 0x0f, 0x11, 0x13 => {
            if (adr == 0x0d) {
                ppu.m7matrix[6] = @bitCast(((@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
                ppu.m7prev = val;
            }
            const i: usize = @intCast((adr - 0xd) / 2);
            ppu.bgLayer[i].hScroll = ((@as(u16, val) << 8) | (@as(u16, ppu.scrollPrev) & 0xf8) | (@as(u16, ppu.scrollPrev2) & 0x7)) & 0x3ff;
            ppu.scrollPrev = val;
            ppu.scrollPrev2 = val;
        },
        0x0e, 0x10, 0x12, 0x14 => {
            if (adr == 0x0e) {
                ppu.m7matrix[7] = @bitCast(((@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
                ppu.m7prev = val;
            }
            const i: usize = @intCast((adr - 0xe) / 2);
            ppu.bgLayer[i].vScroll = ((@as(u16, val) << 8) | ppu.scrollPrev) & 0x3ff;
            ppu.scrollPrev = val;
        },
        0x15 => {
            if ((val & 3) == 0) {
                ppu.vramIncrement = 1;
            } else if ((val & 3) == 1) {
                ppu.vramIncrement = 32;
            } else {
                ppu.vramIncrement = 128;
            }
            ppu.vramIncrementOnHigh = val & 0x80 != 0;
        },
        0x16 => ppu.vramPointer = (ppu.vramPointer & 0xff00) | val,
        0x17 => ppu.vramPointer = (ppu.vramPointer & 0x00ff) | (@as(u16, val) << 8),
        0x18 => {
            const vramAdr: u16 = ppu.vramPointer;
            const i: usize = vramAdr & 0x7fff;
            ppu.vram[i] = (ppu.vram[i] & 0xff00) | val;
            if (!ppu.vramIncrementOnHigh) ppu.vramPointer +%= ppu.vramIncrement;
        },
        0x19 => {
            const vramAdr: u16 = ppu.vramPointer;
            const i: usize = vramAdr & 0x7fff;
            ppu.vram[i] = (ppu.vram[i] & 0x00ff) | (@as(u16, val) << 8);
            if (ppu.vramIncrementOnHigh) ppu.vramPointer +%= ppu.vramIncrement;
        },
        0x1a => {
            ppu.m7largeField = val & 0x80 != 0;
            ppu.m7charFill = val & 0x40 != 0;
            ppu.m7yFlip = val & 0x2 != 0;
            ppu.m7xFlip = val & 0x1 != 0;
        },
        0x1b, 0x1c, 0x1d, 0x1e => {
            ppu.m7matrix[adr - 0x1b] = @bitCast((@as(u16, val) << 8) | ppu.m7prev);
            ppu.m7prev = val;
        },
        0x1f, 0x20 => {
            ppu.m7matrix[adr - 0x1b] = @bitCast(((@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
            ppu.m7prev = val;
        },
        0x21 => {
            ppu.cgramPointer = val;
            ppu.cgramSecondWrite = false;
        },
        0x22 => {
            if (!ppu.cgramSecondWrite) {
                ppu.cgramBuffer = val;
            } else {
                ppu.cgram[ppu.cgramPointer] = (@as(u16, val) << 8) | ppu.cgramBuffer;
                ppu.cgramPointer +%= 1;
            }
            ppu.cgramSecondWrite = !ppu.cgramSecondWrite;
        },
        0x23 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff)) | val,
        0x24 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff00)) | (@as(u32, val) << 8),
        0x25 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff0000)) | (@as(u32, val) << 16),
        0x26 => ppu.window1left = val,
        0x27 => ppu.window1right = val,
        0x28 => ppu.window2left = val,
        0x29 => ppu.window2right = val,
        0x2a => {},
        0x2b => {},
        0x2c => ppu.screenEnabled[0] = val,
        0x2d => ppu.screenEnabled[1] = val,
        0x2e => ppu.screenWindowed[0] = val,
        0x2f => ppu.screenWindowed[1] = val,
        0x30 => {
            ppu.addSubscreen = val & 0x2 != 0;
            ppu.preventMathMode = (val & 0x30) >> 4;
            ppu.clipMode = (val & 0xc0) >> 6;
        },
        0x31 => {
            ppu.subtractColor = val & 0x80 != 0;
            ppu.halfColor = val & 0x40 != 0;
            ppu.mathEnabled = val & 0x3f;
        },
        0x32 => {
            if (val & 0x80 != 0) ppu.fixedColorB = val & 0x1f;
            if (val & 0x40 != 0) ppu.fixedColorG = val & 0x1f;
            if (val & 0x20 != 0) ppu.fixedColorR = val & 0x1f;
        },
        0x33 => {
            ppu.m7extBg_always_zero = val & 0x40 != 0;
        },
        else => {},
    }
}
