// Tier-A unit tests for snes/ppu.zig: ppu_init/free, ppu_reset defaults,
// register read/write decode across the address groups (brightness/forced
// blank, BG tilemap/tile addresses, BG scroll incl. mode7 side-effects,
// VRAM/CGRAM/OAM port access, mode7 matrix, window, screen enable/windowed,
// color math, fixed color), and ppu_saveload's byte sequence — driven
// through the exported C-ABI functions only.

const std = @import("std");
const ppu_mod = @import("ppu.zig");

const expectEqual = std.testing.expectEqual;

const Ppu = ppu_mod.Ppu;

fn freshPpu() *Ppu {
    const p = ppu_mod.ppu_init() orelse unreachable;
    ppu_mod.ppu_reset(p);
    return p;
}

test "ppu_init/free round trip" {
    const p = ppu_mod.ppu_init() orelse return error.OutOfMemory;
    ppu_mod.ppu_free(p);
}

test "ppu_reset sets documented defaults" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    try expectEqual(@as(u16, 0x4000), p.objTileAdr1);
    try expectEqual(@as(u16, 0x5000), p.objTileAdr2);
    try expectEqual(@as(u8, 1), p.mosaicSize);
    try expectEqual(true, p.m7largeField);
    try expectEqual(true, p.forcedBlank);
    try expectEqual(@as(u16, 1), p.vramIncrement);
    try expectEqual(false, p.vramIncrementOnHigh);
    try expectEqual(@as(u8, 0xff), p.lastBrightnessMult);
    try expectEqual(@as(u8, 0xff), p.lastMosaicModulo);
    for (p.vram) |v| try expectEqual(@as(u16, 0), v);
}

test "ppu_write 0x00 sets brightness and forced blank" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x00, 0x8f);
    try expectEqual(@as(u8, 0xf), p.brightness);
    try expectEqual(true, p.forcedBlank);
    ppu_mod.ppu_write(p, 0x00, 0x03);
    try expectEqual(@as(u8, 3), p.brightness);
    try expectEqual(false, p.forcedBlank);
}

test "ppu_write 0x05 sets mode" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x05, 0x07);
    try expectEqual(@as(u8, 7), p.mode);
}

test "ppu_write 0x06 mosaic size and enabled mask" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x06, (3 << 4) | 0x5);
    try expectEqual(@as(u8, 4), p.mosaicSize);
    try expectEqual(@as(u8, (3 << 4) | 0x5), p.mosaicEnabled);

    ppu_mod.ppu_write(p, 0x06, 0x0);
    try expectEqual(@as(u8, 1), p.mosaicSize);
    try expectEqual(@as(u8, 0), p.mosaicEnabled);
}

test "ppu_write 0x07-0x0a set BG tilemap addr/wider/higher" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x07, 0xfc | 0x3); // BG1SC
    try expectEqual(true, p.bgLayer[0].tilemapWider);
    try expectEqual(true, p.bgLayer[0].tilemapHigher);
    try expectEqual(@as(u16, 0xfc00), p.bgLayer[0].tilemapAdr);

    ppu_mod.ppu_write(p, 0x0a, 0x04); // BG4SC, wider=0 higher=0
    try expectEqual(false, p.bgLayer[3].tilemapWider);
    try expectEqual(false, p.bgLayer[3].tilemapHigher);
    try expectEqual(@as(u16, 0x0400), p.bgLayer[3].tilemapAdr);
}

test "ppu_write 0x0b/0x0c set BG tile addresses" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x0b, 0x21); // BG1 nibble=1, BG2 nibble=2
    try expectEqual(@as(u16, 0x1000), p.bgLayer[0].tileAdr);
    try expectEqual(@as(u16, 0x2000), p.bgLayer[1].tileAdr);

    ppu_mod.ppu_write(p, 0x0c, 0x43); // BG3 nibble=3, BG4 nibble=4
    try expectEqual(@as(u16, 0x3000), p.bgLayer[2].tileAdr);
    try expectEqual(@as(u16, 0x4000), p.bgLayer[3].tileAdr);
}

test "ppu_write BG1 hofs/vofs two-write latch, and mode7 side-effect on 0x0d/0x0e" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x0d, 0x34); // BG1HOFS low
    ppu_mod.ppu_write(p, 0x0d, 0x12); // BG1HOFS high
    // hScroll = ((high<<8)|(prev&0xf8)|(prev2&7)) & 0x3ff, prev==prev2==0x34 here
    try expectEqual(@as(u16, ((0x12 << 8) | (0x34 & 0xf8) | (0x34 & 7)) & 0x3ff), p.bgLayer[0].hScroll);
    // m7matrix[6] (h) also latched from the same writes
    try expectEqual(@as(i16, @bitCast(@as(u16, ((0x12 << 8) | 0x34) & 0x1fff))), p.m7matrix[6]);

    ppu_mod.ppu_write(p, 0x0e, 0x56);
    ppu_mod.ppu_write(p, 0x0e, 0x78);
    try expectEqual(@as(u16, ((0x78 << 8) | 0x56) & 0x3ff), p.bgLayer[0].vScroll);
    try expectEqual(@as(i16, @bitCast(@as(u16, ((0x78 << 8) | 0x56) & 0x1fff))), p.m7matrix[7]);
}

test "ppu_write BG2 hofs/vofs (no mode7 side-effect)" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x0f, 0x11);
    ppu_mod.ppu_write(p, 0x0f, 0x02);
    try expectEqual(@as(u16, ((0x02 << 8) | (0x11 & 0xf8) | (0x11 & 7)) & 0x3ff), p.bgLayer[1].hScroll);
    try expectEqual(@as(i16, 0), p.m7matrix[6]);
}

test "ppu_write 0x15/16/17/18/19 VRAM port access with increment-on-high" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x15, 0x80); // increment=1, incrementOnHigh
    ppu_mod.ppu_write(p, 0x16, 0x34);
    ppu_mod.ppu_write(p, 0x17, 0x12);
    try expectEqual(@as(u16, 0x1234), p.vramPointer);
    ppu_mod.ppu_write(p, 0x18, 0xab);
    try expectEqual(@as(u16, 0x1234), p.vramPointer); // no increment yet (low byte)
    try expectEqual(@as(u16, 0xab), p.vram[0x1234] & 0xff);
    ppu_mod.ppu_write(p, 0x19, 0xcd);
    try expectEqual(@as(u16, 0xcdab), p.vram[0x1234]);
    try expectEqual(@as(u16, 0x1235), p.vramPointer);
}

test "ppu_write 0x21/0x22 CGRAM two-write latch" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x21, 0x05);
    ppu_mod.ppu_write(p, 0x22, 0xef);
    ppu_mod.ppu_write(p, 0x22, 0x7b);
    try expectEqual(@as(u16, 0x7bef), p.cgram[5]);
    try expectEqual(@as(u8, 6), p.cgramPointer);
}

test "ppu_write 0x02/0x03/0x04 OAM two-write latch" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x02, 0x10);
    ppu_mod.ppu_write(p, 0x03, 0x01);
    try expectEqual(@as(u16, 0x110), p.oamAdr);
    ppu_mod.ppu_write(p, 0x04, 0xaa); // out of range (>= 0x110), dropped
    ppu_mod.ppu_write(p, 0x04, 0xbb);
    try expectEqual(@as(u16, 0x110), p.oamAdr);
}

test "ppu_write 0x1a mode7 settings flags" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x1a, 0x80 | 0x40 | 0x2 | 0x1);
    try expectEqual(true, p.m7largeField);
    try expectEqual(true, p.m7charFill);
    try expectEqual(true, p.m7yFlip);
    try expectEqual(true, p.m7xFlip);
}

test "ppu_write 0x1b-0x1e mode7 matrix a-d (16-bit unmasked)" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x1b, 0x34);
    ppu_mod.ppu_write(p, 0x1b, 0x12);
    try expectEqual(@as(i16, 0x1234), p.m7matrix[0]);
}

test "ppu_write 0x1f-0x20 mode7 x/y center (13-bit masked)" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x1f, 0xff);
    ppu_mod.ppu_write(p, 0x1f, 0xff);
    try expectEqual(@as(i16, 0x1fff), p.m7matrix[4]);
}

test "ppu_read 0x34-0x36 returns m7matrix[0]*(m7matrix[1]>>8) bytes" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    p.m7matrix[0] = 100;
    p.m7matrix[1] = @bitCast(@as(u16, 2 << 8));
    const result: i32 = 100 * 2;
    try expectEqual(@as(u8, @truncate(@as(u32, @bitCast(result)))), ppu_mod.ppu_read(p, 0x34));
    try expectEqual(@as(u8, @truncate(@as(u32, @bitCast(result)) >> 8)), ppu_mod.ppu_read(p, 0x35));
}

test "ppu_read unmapped register returns 0xff" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    try expectEqual(@as(u8, 0xff), ppu_mod.ppu_read(p, 0x00));
}

test "ppu_write 0x23-0x29 window select and edges" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x23, 0xab);
    ppu_mod.ppu_write(p, 0x24, 0xcd);
    ppu_mod.ppu_write(p, 0x25, 0xef);
    try expectEqual(@as(u32, 0xefcdab), p.windowsel);
    ppu_mod.ppu_write(p, 0x26, 10);
    ppu_mod.ppu_write(p, 0x27, 200);
    ppu_mod.ppu_write(p, 0x28, 20);
    ppu_mod.ppu_write(p, 0x29, 220);
    try expectEqual(@as(u8, 10), p.window1left);
    try expectEqual(@as(u8, 200), p.window1right);
    try expectEqual(@as(u8, 20), p.window2left);
    try expectEqual(@as(u8, 220), p.window2right);
}

test "ppu_write 0x2c-0x2f screen enable/windowed masks" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x2c, 0x1f);
    ppu_mod.ppu_write(p, 0x2d, 0x0f);
    ppu_mod.ppu_write(p, 0x2e, 0x03);
    ppu_mod.ppu_write(p, 0x2f, 0x01);
    try expectEqual(@as(u8, 0x1f), p.screenEnabled[0]);
    try expectEqual(@as(u8, 0x0f), p.screenEnabled[1]);
    try expectEqual(@as(u8, 0x03), p.screenWindowed[0]);
    try expectEqual(@as(u8, 0x01), p.screenWindowed[1]);
}

test "ppu_write 0x30/0x31 color math config" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x30, 0x2 | (0x1 << 4) | (0x2 << 6));
    try expectEqual(true, p.addSubscreen);
    try expectEqual(@as(u8, 1), p.preventMathMode);
    try expectEqual(@as(u8, 2), p.clipMode);

    ppu_mod.ppu_write(p, 0x31, 0x80 | 0x40 | 0x15);
    try expectEqual(true, p.subtractColor);
    try expectEqual(true, p.halfColor);
    try expectEqual(@as(u8, 0x15), p.mathEnabled);
}

test "ppu_write 0x32 fixed color, per-channel gated" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x32, 0x20 | 15); // R only
    try expectEqual(@as(u8, 15), p.fixedColorR);
    try expectEqual(@as(u8, 0), p.fixedColorG);
    try expectEqual(@as(u8, 0), p.fixedColorB);
    ppu_mod.ppu_write(p, 0x32, 0x40 | 7); // G only
    try expectEqual(@as(u8, 7), p.fixedColorG);
    try expectEqual(@as(u8, 15), p.fixedColorR); // unchanged
}

test "ppu_write 0x33 m7extBg flag" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.ppu_write(p, 0x33, 0x40);
    try expectEqual(true, p.m7extBg_always_zero);
}

test "PpuGetCurrentRenderScale" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    p.mode = 7;
    p.forcedBlank = false;
    try expectEqual(@as(c_int, 4), ppu_mod.PpuGetCurrentRenderScale(p, ppu_mod.kPpuRenderFlags_4x4Mode7 | ppu_mod.kPpuRenderFlags_NewRenderer));
    try expectEqual(@as(c_int, 1), ppu_mod.PpuGetCurrentRenderScale(p, 0));
    p.mode = 1;
    try expectEqual(@as(c_int, 1), ppu_mod.PpuGetCurrentRenderScale(p, ppu_mod.kPpuRenderFlags_4x4Mode7 | ppu_mod.kPpuRenderFlags_NewRenderer));
}

test "PpuSetExtraSideSpace clamps to extraLeftRight/16" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    ppu_mod.PpuSetExtraSideSpace(p, 1000, 1000, 1000);
    try expectEqual(p.extraLeftRight, p.extraLeftCur);
    try expectEqual(p.extraLeftRight, p.extraRightCur);
    try expectEqual(@as(u8, 16), p.extraBottomCur);
}

test "ppu_saveload sends vram, cgram, and per-bglayer snapshot region" {
    const p = freshPpu();
    defer ppu_mod.ppu_free(p);
    p.vram[10] = 0xabcd;
    p.cgram[3] = 0x1234;
    p.bgLayer[0].tilemapWider = true;
    p.bgLayer[0].tilemapAdr = 0x0200;

    var calls: std.ArrayList(usize) = .empty;
    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            _ = data;
            const c: *std.ArrayList(usize) = @ptrCast(@alignCast(ctx));
            c.append(std.heap.page_allocator, data_size) catch {};
        }
    }.run;
    ppu_mod.ppu_saveload(p, cb, &calls);
    // vram(0x10000) + tmp(10) + cgram(512) + tmp(556) + tmp(520) + 4*(4+4+4) + tmp(123)
    var total: usize = 0;
    for (calls.items) |sz| total += sz;
    try expectEqual(@as(usize, 0x8000 * 2 + 10 + 512 + 556 + 520 + 4 * 12 + 123), total);
    calls.deinit(std.heap.page_allocator);
}
