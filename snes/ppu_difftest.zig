// Tier-B differential test for snes/ppu.zig: links the pre-port snes/ppu.c
// (symbols renamed with a c_ prefix via the preprocessor, wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized register op streams and full-line
// rendering (legacy per-pixel path, new renderer, and the 4x4-upsampled
// mode7 fast path).
//
// The Ppu/BgLayer/PpuPixelPrioBufs struct layout mirrors snes/ppu.h exactly
// (C keeps ownership of the real layout; zelda_cpu_infra.c's RAM-compare
// oracle snapshots ppu->vram directly). ppu.c has no cross-module externs
// (it only ever touches its own Ppu struct, passed by pointer), so each
// flavour just gets its own malloc'd Ppu, zeroed identically before use to
// avoid comparing uninitialized-malloc garbage as if it were a real diff.
// ppu.zig is not @import'ed here: its exports come from the linked object,
// so the test only needs the extern declarations and the mirrored layout.

const std = @import("std");

const expectEqual = std.testing.expectEqual;

const kPpuExtraLeftRight: u32 = 96;
const kPpuXPixels: u32 = 256 + kPpuExtraLeftRight * 2;
const PpuZbufType = u16;

const BgLayer = extern struct {
    hScroll: u16,
    vScroll: u16,
    tilemapWider: bool,
    tilemapHigher: bool,
    tilemapAdr: u16,
    tileAdr: u16,
};

const PpuPixelPrioBufs = extern struct {
    data: [kPpuXPixels]PpuZbufType,
};

const Ppu = extern struct {
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

extern fn ppu_init() ?*Ppu;
extern fn ppu_free(ppu: ?*Ppu) void;
extern fn ppu_reset(ppu: *Ppu) void;
extern fn ppu_runLine(ppu: *Ppu, line: c_int) void;
extern fn ppu_read(ppu: *Ppu, adr: u8) u8;
extern fn ppu_write(ppu: *Ppu, adr: u8, val: u8) void;
extern fn ppu_saveload(ppu: *Ppu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn PpuBeginDrawing(ppu: *Ppu, buffer: ?[*]u8, pitch: usize, render_flags: u32) void;
extern fn PpuGetCurrentRenderScale(ppu: *Ppu, render_flags: u32) c_int;
extern fn PpuSetMode7PerspectiveCorrection(ppu: *Ppu, low: c_int, high: c_int) void;
extern fn PpuSetExtraSideSpace(ppu: *Ppu, left: c_int, right: c_int, bottom: c_int) void;

extern fn c_ppu_init() ?*Ppu;
extern fn c_ppu_free(ppu: ?*Ppu) void;
extern fn c_ppu_reset(ppu: *Ppu) void;
extern fn c_ppu_runLine(ppu: *Ppu, line: c_int) void;
extern fn c_ppu_read(ppu: *Ppu, adr: u8) u8;
extern fn c_ppu_write(ppu: *Ppu, adr: u8, val: u8) void;
extern fn c_ppu_saveload(ppu: *Ppu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn c_PpuBeginDrawing(ppu: *Ppu, buffer: ?[*]u8, pitch: usize, render_flags: u32) void;
extern fn c_PpuGetCurrentRenderScale(ppu: *Ppu, render_flags: u32) c_int;
extern fn c_PpuSetMode7PerspectiveCorrection(ppu: *Ppu, low: c_int, high: c_int) void;
extern fn c_PpuSetExtraSideSpace(ppu: *Ppu, left: c_int, right: c_int, bottom: c_int) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x9a1e0ffb);
    return prng.?.random();
}

const PpuPair = struct { c: *Ppu, z: *Ppu };

fn freshPair() PpuPair {
    const c_ppu = c_ppu_init() orelse unreachable;
    const z_ppu = ppu_init() orelse unreachable;
    // Zero malloc'd memory identically so uninitialized garbage never shows
    // up as a spurious diff; ppu_reset doesn't touch every field (renderFlags,
    // colorMapRgb, brightnessMult, etc. are runtime-populated by
    // PpuBeginDrawing/ppu_write, never by reset).
    @memset(std.mem.asBytes(c_ppu), 0);
    @memset(std.mem.asBytes(z_ppu), 0);
    c_ppu.extraLeftRight = @intCast(kPpuExtraLeftRight);
    z_ppu.extraLeftRight = @intCast(kPpuExtraLeftRight);
    c_ppu_reset(c_ppu);
    ppu_reset(z_ppu);
    return .{ .c = c_ppu, .z = z_ppu };
}

fn diffState(pair: PpuPair, label: []const u8) !void {
    const c_bytes = std.mem.asBytes(pair.c);
    const z_bytes = std.mem.asBytes(pair.z);
    if (!std.mem.eql(u8, c_bytes, z_bytes)) {
        for (c_bytes, 0..) |b, i| {
            if (b != z_bytes[i]) {
                std.debug.print("{s}: Ppu byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_bytes[i] });
                break;
            }
        }
        return error.PpuStateMismatch;
    }
}

// Same as diffState but ignores the renderBuffer pointer field (each flavour
// legitimately points at its own separate output buffer).
fn diffStateIgnoringRenderBuffer(pair: PpuPair, label: []const u8) !void {
    const off = @offsetOf(Ppu, "renderBuffer");
    const field_size = @sizeOf(?[*]u8);
    const c_bytes = std.mem.asBytes(pair.c);
    const z_bytes = std.mem.asBytes(pair.z);
    if (!std.mem.eql(u8, c_bytes[0..off], z_bytes[0..off]) or
        !std.mem.eql(u8, c_bytes[off + field_size ..], z_bytes[off + field_size ..]))
    {
        for (c_bytes, 0..) |b, i| {
            if (i >= off and i < off + field_size) continue;
            if (b != z_bytes[i]) {
                std.debug.print("{s}: Ppu byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_bytes[i] });
                break;
            }
        }
        return error.PpuStateMismatch;
    }
}

test "diff register read/write streams over all registers" {
    var iter: usize = 0;
    while (iter < 1000) : (iter += 1) {
        const pair = freshPair();
        defer c_ppu_free(pair.c);
        defer ppu_free(pair.z);
        try diffState(pair, "post-reset");

        var ops_buf: [64][2]u8 = undefined;
        const n = rnd().intRangeAtMost(usize, 1, ops_buf.len);
        for (ops_buf[0..n]) |*op| op.* = .{ rnd().int(u8) & 0x7f, rnd().int(u8) };
        for (ops_buf[0..n], 0..) |op, i| {
            const adr = op[0];
            if (op[1] & 1 == 0 and adr >= 0x34 and adr <= 0x36) {
                const c_ret = c_ppu_read(pair.c, adr);
                const z_ret = ppu_read(pair.z, adr);
                if (c_ret != z_ret) {
                    std.debug.print("op {d}: read adr {X:0>2}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, adr, c_ret, z_ret });
                    return error.ReadMismatch;
                }
            } else {
                c_ppu_write(pair.c, adr, op[1]);
                ppu_write(pair.z, adr, op[1]);
            }
        }
        try diffState(pair, "read/write stream");
    }
}

test "diff init/reset/saveload lifecycle" {
    const pair = freshPair();
    defer c_ppu_free(pair.c);
    defer ppu_free(pair.z);
    try diffState(pair, "post-reset");

    const Seen = struct { data: ?*anyopaque = null, size: usize = 0 };
    var seen_c: Seen = .{};
    var seen_z: Seen = .{};
    const cbC = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const s: *Seen = @ptrCast(@alignCast(ctx));
            s.* = .{ .data = data, .size = data_size };
        }
    }.run;
    c_ppu_saveload(pair.c, cbC, &seen_c);
    ppu_saveload(pair.z, cbC, &seen_z);
    try expectEqual(seen_c.size, seen_z.size);
}

fn randomizeVramOamCgram(pair: PpuPair) void {
    var vram_bytes: [0x10000]u8 = undefined;
    rnd().bytes(&vram_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.c.vram), &vram_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.z.vram), &vram_bytes);

    var oam_bytes: [0x110 * 2]u8 = undefined;
    rnd().bytes(&oam_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.c.oam), &oam_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.z.oam), &oam_bytes);

    var cgram_bytes: [0x100 * 2]u8 = undefined;
    rnd().bytes(&cgram_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.c.cgram), &cgram_bytes);
    @memcpy(std.mem.sliceAsBytes(&pair.z.cgram), &cgram_bytes);
}

fn randomizeRegisters(pair: PpuPair, mode: u8) void {
    const brightness_val = rnd().int(u8) & 0x8f;
    c_ppu_write(pair.c, 0x00, brightness_val);
    ppu_write(pair.z, 0x00, brightness_val);
    c_ppu_write(pair.c, 0x05, mode);
    ppu_write(pair.z, 0x05, mode);
    var adr: u8 = 0x06;
    while (adr <= 0x33) : (adr += 1) {
        const val = rnd().int(u8);
        c_ppu_write(pair.c, adr, val);
        ppu_write(pair.z, adr, val);
    }
    // re-force the mode after the randomized sweep, in case 0x05 got hit again.
    c_ppu_write(pair.c, 0x05, mode);
    ppu_write(pair.z, 0x05, mode);
}

test "diff rendering: legacy vs new renderer across modes 0-6" {
    const pitch: usize = kPpuXPixels * 4;
    const buf_size: usize = pitch * 224;
    var iter: usize = 0;
    var mode: u8 = 0;
    while (iter < 42) : (iter += 1) {
        const flags: u32 = if (iter % 2 == 0) 0 else 1; // kPpuRenderFlags_NewRenderer
        const pair = freshPair();
        defer c_ppu_free(pair.c);
        defer ppu_free(pair.z);

        randomizeVramOamCgram(pair);
        randomizeRegisters(pair, mode % 7);
        PpuSetExtraSideSpace(pair.z, 0, 0, 0);
        c_PpuSetExtraSideSpace(pair.c, 0, 0, 0);

        var c_render_buf: [buf_size]u8 = undefined;
        var z_render_buf: [buf_size]u8 = undefined;
        @memset(&c_render_buf, 0xaa);
        @memset(&z_render_buf, 0xaa);
        c_PpuBeginDrawing(pair.c, &c_render_buf, pitch, flags);
        PpuBeginDrawing(pair.z, &z_render_buf, pitch, flags);

        var line: c_int = 1;
        while (line <= 224) : (line += 1) {
            c_ppu_runLine(pair.c, line);
            ppu_runLine(pair.z, line);
        }
        if (!std.mem.eql(u8, &c_render_buf, &z_render_buf)) {
            for (c_render_buf, 0..) |b, i| {
                if (b != z_render_buf[i]) {
                    std.debug.print("mode {d} flags {d}: renderBuffer byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ mode % 7, flags, i, b, z_render_buf[i] });
                    break;
                }
            }
            return error.RenderMismatch;
        }
        try diffStateIgnoringRenderBuffer(pair, "post-render");
        mode += 1;
    }
}

test "diff rendering: mode7 4x4 upsampled fast path" {
    const scaled_pitch: usize = kPpuXPixels * 4 * 4;
    const buf_size: usize = scaled_pitch * 4 * 224;
    var iter: usize = 0;
    while (iter < 8) : (iter += 1) {
        const pair = freshPair();
        defer c_ppu_free(pair.c);
        defer ppu_free(pair.z);

        randomizeVramOamCgram(pair);
        randomizeRegisters(pair, 7);
        PpuSetExtraSideSpace(pair.z, 0, 0, 0);
        c_PpuSetExtraSideSpace(pair.c, 0, 0, 0);
        c_PpuSetMode7PerspectiveCorrection(pair.c, 0, 1);
        PpuSetMode7PerspectiveCorrection(pair.z, 0, 1);

        const flags: u32 = 1 | 2; // kPpuRenderFlags_NewRenderer | kPpuRenderFlags_4x4Mode7

        const c_render_buf = try std.testing.allocator.alloc(u8, buf_size);
        defer std.testing.allocator.free(c_render_buf);
        const z_render_buf = try std.testing.allocator.alloc(u8, buf_size);
        defer std.testing.allocator.free(z_render_buf);
        @memset(c_render_buf, 0xaa);
        @memset(z_render_buf, 0xaa);
        c_PpuBeginDrawing(pair.c, c_render_buf.ptr, scaled_pitch, flags);
        PpuBeginDrawing(pair.z, z_render_buf.ptr, scaled_pitch, flags);

        var line: c_int = 1;
        while (line <= 224) : (line += 1) {
            c_ppu_runLine(pair.c, line);
            ppu_runLine(pair.z, line);
        }
        if (!std.mem.eql(u8, c_render_buf, z_render_buf)) {
            for (c_render_buf, 0..) |b, i| {
                if (b != z_render_buf[i]) {
                    std.debug.print("mode7 upsampled: renderBuffer byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, b, z_render_buf[i] });
                    break;
                }
            }
            return error.RenderMismatch;
        }
        try diffStateIgnoringRenderBuffer(pair, "post-render mode7 upsampled");
    }
}
