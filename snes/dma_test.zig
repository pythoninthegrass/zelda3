// Tier-A unit tests for snes/dma.zig: golden-value checks for the channel
// register read/write decode, one-step DMA transfer, the two-phase HDMA
// (init/do) sequencing, dma_cycle, and dma_startDma, using reference
// behavior from the pre-port snes/dma.c. snes.c (not yet ported) still owns
// snes_read/snes_write/snes_readBBus/snes_writeBBus, so this file stubs
// those C-ABI entry points itself (a small byte-addressable fake bus) rather
// than linking the real memory map — that real-behavior coverage lives in
// dma_difftest.zig instead. The Dma/DmaChannel layout mirrors snes/dma.h;
// the tests drive it through the exported C-ABI functions only.

const std = @import("std");
const dma_mod = @import("dma.zig");

const expectEqual = std.testing.expectEqual;

const Dma = dma_mod.Dma;
const Snes = dma_mod.Snes;
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

var a_bus: [0x10000]u8 = undefined;
var b_bus: [0x100]u8 = undefined;

fn resetBus() void {
    a_bus = [_]u8{0} ** 0x10000;
    b_bus = [_]u8{0} ** 0x100;
}

export fn snes_readBBus(snes: ?*Snes, adr: u8) callconv(.c) u8 {
    _ = snes;
    return b_bus[adr];
}
export fn snes_writeBBus(snes: ?*Snes, adr: u8, val: u8) callconv(.c) void {
    _ = snes;
    b_bus[adr] = val;
}
export fn snes_read(snes: ?*Snes, adr: u32) callconv(.c) u8 {
    _ = snes;
    return a_bus[adr & 0xffff];
}
export fn snes_write(snes: ?*Snes, adr: u32, val: u8) callconv(.c) void {
    _ = snes;
    a_bus[adr & 0xffff] = val;
}

const openbus_off = 121;
var fake_snes_buf: [128]u8 = undefined;

fn fakeSnes(open_bus: u8) *Snes {
    fake_snes_buf = [_]u8{0} ** 128;
    fake_snes_buf[openbus_off] = open_bus;
    return @ptrCast(@alignCast(&fake_snes_buf));
}

fn zeroDma(snes: *Snes) Dma {
    var dma: Dma = undefined;
    dma.snes = snes;
    dma_mod.dma_reset(&dma);
    return dma;
}

test "dma_init seeds snes pointer" {
    const snes = fakeSnes(0);
    const d = dma_mod.dma_init(snes) orelse return error.OutOfMemory;
    defer dma_mod.dma_free(d);
    try expectEqual(@as(?*Snes, snes), d.snes);
}

test "dma_reset seeds every channel to power-on defaults" {
    const d = zeroDma(fakeSnes(0));
    for (d.channel) |ch| {
        try expectEqual(@as(u8, 0xff), ch.bAdr);
        try expectEqual(@as(u16, 0xffff), ch.aAdr);
        try expectEqual(@as(u8, 0xff), ch.aBank);
        try expectEqual(@as(u16, 0xffff), ch.size);
        try expectEqual(@as(u8, 0xff), ch.indBank);
        try expectEqual(@as(u16, 0xffff), ch.tableAdr);
        try expectEqual(@as(u8, 0xff), ch.repCount);
        try expectEqual(@as(u8, 0xff), ch.unusedByte);
        try expectEqual(false, ch.dmaActive);
        try expectEqual(false, ch.hdmaActive);
        try expectEqual(@as(u8, 7), ch.mode);
        try expectEqual(true, ch.fixed);
        try expectEqual(true, ch.decrement);
        try expectEqual(true, ch.indirect);
        try expectEqual(true, ch.fromB);
        try expectEqual(true, ch.unusedBit);
        try expectEqual(false, ch.doTransfer);
        try expectEqual(false, ch.terminated);
        try expectEqual(@as(u8, 0), ch.offIndex);
    }
    try expectEqual(@as(u16, 0), d.hdmaTimer);
    try expectEqual(@as(u32, 0), d.dmaTimer);
    try expectEqual(false, d.dmaBusy);
}

test "dma_write/dma_read round-trip every channel register" {
    var d = zeroDma(fakeSnes(0));
    // channel 3 (adr 0x30-0x3f): 0xD2 = fromB(1) indirect(1) unusedBit(0)
    // decrement(1) fixed(0) mode(010=2)
    dma_mod.dma_write(&d, 0x30, 0xD2);
    try expectEqual(@as(u8, 2), d.channel[3].mode);
    try expectEqual(false, d.channel[3].fixed);
    try expectEqual(true, d.channel[3].decrement);
    try expectEqual(false, d.channel[3].unusedBit);
    try expectEqual(true, d.channel[3].indirect);
    try expectEqual(true, d.channel[3].fromB);
    try expectEqual(dma_mod.dma_read(&d, 0x30), @as(u8, 0xD2));

    dma_mod.dma_write(&d, 0x31, 0x42);
    try expectEqual(@as(u8, 0x42), dma_mod.dma_read(&d, 0x31));

    dma_mod.dma_write(&d, 0x32, 0xcd);
    dma_mod.dma_write(&d, 0x33, 0xab);
    try expectEqual(@as(u16, 0xabcd), d.channel[3].aAdr);
    try expectEqual(@as(u8, 0xcd), dma_mod.dma_read(&d, 0x32));
    try expectEqual(@as(u8, 0xab), dma_mod.dma_read(&d, 0x33));

    dma_mod.dma_write(&d, 0x34, 0x7f);
    try expectEqual(@as(u8, 0x7f), d.channel[3].aBank);

    dma_mod.dma_write(&d, 0x35, 0x34);
    dma_mod.dma_write(&d, 0x36, 0x12);
    try expectEqual(@as(u16, 0x1234), d.channel[3].size);

    dma_mod.dma_write(&d, 0x37, 0x55);
    try expectEqual(@as(u8, 0x55), d.channel[3].indBank);

    dma_mod.dma_write(&d, 0x38, 0x78);
    dma_mod.dma_write(&d, 0x39, 0x56);
    try expectEqual(@as(u16, 0x5678), d.channel[3].tableAdr);

    dma_mod.dma_write(&d, 0x3a, 0x99);
    try expectEqual(@as(u8, 0x99), d.channel[3].repCount);

    dma_mod.dma_write(&d, 0x3b, 0x11);
    try expectEqual(@as(u8, 0x11), d.channel[3].unusedByte);
    try expectEqual(@as(u8, 0x11), dma_mod.dma_read(&d, 0x3f));
    dma_mod.dma_write(&d, 0x3f, 0x22);
    try expectEqual(@as(u8, 0x22), d.channel[3].unusedByte);
}

test "dma_read returns openBus for the unmapped 0xc-0xe range" {
    var d = zeroDma(fakeSnes(0xAB));
    try expectEqual(@as(u8, 0xAB), dma_mod.dma_read(&d, 0x0c));
    try expectEqual(@as(u8, 0xAB), dma_mod.dma_read(&d, 0x0d));
    try expectEqual(@as(u8, 0xAB), dma_mod.dma_read(&d, 0x0e));
}

test "dma_saveload hands the channel array and its exact size to the callback" {
    var d = zeroDma(fakeSnes(0));
    var seen: struct { data: ?*anyopaque = null, size: usize = 0 } = .{};
    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const s: *@TypeOf(seen) = @ptrCast(@alignCast(ctx));
            s.data = data;
            s.size = data_size;
        }
    }.run;
    dma_mod.dma_saveload(&d, cb, &seen);
    try expectEqual(@as(?*anyopaque, @ptrCast(&d.channel)), seen.data);
    try expectEqual(@sizeOf(Dma) - @offsetOf(Dma, "channel"), seen.size);
}

test "dma_startDma sets/clears channel activity bits and dmaBusy/dmaTimer" {
    var d = zeroDma(fakeSnes(0));
    dma_mod.dma_startDma(&d, 0b0000_0101, false); // channels 0 and 2
    try expectEqual(true, d.channel[0].dmaActive);
    try expectEqual(false, d.channel[1].dmaActive);
    try expectEqual(true, d.channel[2].dmaActive);
    try expectEqual(true, d.dmaBusy);
    try expectEqual(@as(u32, 16), d.dmaTimer);

    dma_mod.dma_startDma(&d, 0, false);
    try expectEqual(false, d.channel[0].dmaActive);
    try expectEqual(false, d.dmaBusy);

    dma_mod.dma_startDma(&d, 0b1000_0000, true); // channel 7 hdma
    try expectEqual(true, d.channel[7].hdmaActive);
    try expectEqual(false, d.channel[0].hdmaActive);
}

test "dma_doDma transfers one byte per call, decrements size, deactivates at zero" {
    resetBus();
    var d = zeroDma(fakeSnes(0));
    a_bus[0x001234] = 0x5a;
    d.channel[0] = .{
        .bAdr = 0x18,
        .aBank = 0x00,
        .indBank = 0,
        .repCount = 0,
        .aAdr = 0x1234,
        .size = 2,
        .tableAdr = 0,
        .unusedByte = 0,
        .dmaActive = true,
        .hdmaActive = false,
        .mode = 0,
        .fixed = false,
        .decrement = false,
        .indirect = false,
        .fromB = false,
        .unusedBit = false,
        .doTransfer = false,
        .terminated = false,
        .offIndex = 0,
    };
    dma_mod.dma_doDma(&d);
    try expectEqual(@as(u8, 0x5a), b_bus[0x18]);
    try expectEqual(@as(u16, 0x1235), d.channel[0].aAdr);
    try expectEqual(@as(u16, 1), d.channel[0].size);
    try expectEqual(true, d.channel[0].dmaActive);
    try expectEqual(@as(u32, 6), d.dmaTimer);

    a_bus[0x001235] = 0x77;
    dma_mod.dma_doDma(&d);
    try expectEqual(@as(u8, 0x77), b_bus[0x18]);
    try expectEqual(@as(u16, 0), d.channel[0].size);
    try expectEqual(false, d.channel[0].dmaActive);
    try expectEqual(@as(u32, 6 + 6 + 8), d.dmaTimer);
}

test "dma_doDma with fixed=true leaves aAdr unchanged" {
    resetBus();
    var d = zeroDma(fakeSnes(0));
    a_bus[0x998877 & 0xffff] = 0x11;
    d.channel[1] = .{
        .bAdr = 0x00,
        .aBank = 0x99,
        .indBank = 0,
        .repCount = 0,
        .aAdr = 0x8877,
        .size = 5,
        .tableAdr = 0,
        .unusedByte = 0,
        .dmaActive = true,
        .hdmaActive = false,
        .mode = 0,
        .fixed = true,
        .decrement = true,
        .indirect = false,
        .fromB = false,
        .unusedBit = false,
        .doTransfer = false,
        .terminated = false,
        .offIndex = 0,
    };
    dma_mod.dma_doDma(&d);
    try expectEqual(@as(u16, 0x8877), d.channel[1].aAdr);
    try expectEqual(@as(u16, 4), d.channel[1].size);
}

test "dma_doDma with no active channels clears dmaBusy" {
    var d = zeroDma(fakeSnes(0));
    d.dmaBusy = true;
    dma_mod.dma_doDma(&d);
    try expectEqual(false, d.dmaBusy);
}

test "dma_cycle drains hdmaTimer before running dma" {
    var d = zeroDma(fakeSnes(0));
    d.hdmaTimer = 4;
    try expectEqual(true, dma_mod.dma_cycle(&d));
    try expectEqual(@as(u16, 2), d.hdmaTimer);
    try expectEqual(true, dma_mod.dma_cycle(&d));
    try expectEqual(@as(u16, 0), d.hdmaTimer);
    try expectEqual(false, dma_mod.dma_cycle(&d));
}

test "dma_initHdma loads tableAdr/repCount (and indirect size) from the a-bus" {
    resetBus();
    var d = zeroDma(fakeSnes(0));
    a_bus[0x2200] = 0x03; // repCount
    a_bus[0x2201] = 0x40; // size low
    a_bus[0x2202] = 0x00; // size high
    d.channel[6].hdmaActive = true;
    d.channel[6].aBank = 0x00;
    d.channel[6].aAdr = 0x2200;
    d.channel[6].indirect = true;
    d.channel[7].hdmaActive = false;

    dma_mod.dma_initHdma(&d);

    try expectEqual(@as(u16, 0x2203), d.channel[6].tableAdr);
    try expectEqual(@as(u8, 0x03), d.channel[6].repCount);
    try expectEqual(@as(u16, 0x0040), d.channel[6].size);
    try expectEqual(true, d.channel[6].doTransfer);
    try expectEqual(false, d.channel[6].terminated);
    try expectEqual(false, d.channel[7].doTransfer);
    try expectEqual(@as(u16, 8 + 16 + 16), d.hdmaTimer);
}

test "dma_doHdma transfers transferLength[mode] bytes per active channel per line" {
    resetBus();
    var d = zeroDma(fakeSnes(0));
    a_bus[0x3000] = 0x11;
    a_bus[0x3001] = 0x22;
    d.channel[2] = .{
        .bAdr = 0x18,
        .aBank = 0x00,
        .indBank = 0,
        .repCount = 5,
        .aAdr = 0,
        .size = 0,
        .tableAdr = 0x3000,
        .unusedByte = 0,
        .dmaActive = false,
        .hdmaActive = true,
        .mode = 1, // transferLength 2, bAdrOffsets {0,1,0,1}
        .fixed = false,
        .decrement = false,
        .indirect = false,
        .fromB = false,
        .unusedBit = false,
        .doTransfer = true,
        .terminated = false,
        .offIndex = 0,
    };
    dma_mod.dma_doHdma(&d);
    try expectEqual(@as(u8, 0x11), b_bus[0x18]);
    try expectEqual(@as(u8, 0x22), b_bus[0x19]);
    try expectEqual(@as(u16, 0x3002), d.channel[2].tableAdr);
    try expectEqual(@as(u8, 4), d.channel[2].repCount);
    // repCount 4 (0b0000_0100): high bit clear -> doTransfer false; low 7
    // bits nonzero -> no reload this line.
    try expectEqual(false, d.channel[2].doTransfer);
}

test "dma_doHdma terminates the channel when repCount hits 0 after reload" {
    resetBus();
    var d = zeroDma(fakeSnes(0));
    a_bus[0x4000] = 0x00; // next repCount reload: 0 terminates
    d.channel[4] = .{
        .bAdr = 0x18,
        .aBank = 0x00,
        .indBank = 0,
        .repCount = 1,
        .aAdr = 0,
        .size = 0,
        .tableAdr = 0x4000,
        .unusedByte = 0,
        .dmaActive = false,
        .hdmaActive = true,
        .mode = 0,
        .fixed = false,
        .decrement = false,
        .indirect = false,
        .fromB = false,
        .unusedBit = false,
        .doTransfer = false,
        .terminated = false,
        .offIndex = 0,
    };
    dma_mod.dma_doHdma(&d);
    try expectEqual(@as(u8, 0), d.channel[4].repCount);
    try expectEqual(true, d.channel[4].terminated);
    try expectEqual(true, d.channel[4].doTransfer);
}
