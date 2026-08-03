// Tier-B differential test for snes/dma.zig: links the pre-port snes/dma.c
// (symbols renamed with a c_ prefix via the preprocessor (-D), wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized op streams (register read/write,
// dma_doDma, dma_initHdma/dma_doHdma, dma_cycle, dma_startDma).
//
// The Dma/DmaChannel struct layout mirrors snes/dma.h (C keeps ownership of
// it; zelda_cpu_infra.c/zelda_rtl.c poke fields directly). snes.c (not yet
// ported) owns the real snes_read/snes_write/snes_readBBus/snes_writeBBus;
// both dma.c and dma.zig call those exact (unrenamed) symbol names, so this
// file supplies them itself as a small per-flavour fake bus, dispatched by
// comparing the passed Snes* against the known C/Z fake-snes buffer
// addresses. dma.zig is not @import'ed here: its exports come from the
// linked object, so the test only needs the extern declarations and the
// mirrored layout.

const std = @import("std");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

// Mirrors struct DmaChannel in snes/dma.h.
pub const DmaChannel = extern struct {
    bAdr: u8,
    aBank: u8,
    indBank: u8,
    repCount: u8,
    aAdr: u16,
    size: u16,
    tableAdr: u16,
    unusedByte: u8,
    dmaActive: bool,
    hdmaActive: bool,
    mode: u8,
    fixed: bool,
    decrement: bool,
    indirect: bool,
    fromB: bool,
    unusedBit: bool,
    doTransfer: bool,
    terminated: bool,
    offIndex: u8,
};

// Mirrors struct Dma in snes/dma.h; Snes is opaque (only openBus is read,
// via the fake image below).
pub const Dma = extern struct {
    snes: ?*anyopaque,
    channel: [8]DmaChannel,
    hdmaTimer: u16,
    dmaTimer: u32,
    dmaBusy: bool,
};

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

// The Zig port's exported symbols resolve against the linked dma.o (the
// ported module); the C reference via the c_* externs (preprocessor-renamed).
extern fn dma_init(snes: ?*anyopaque) ?*Dma;
extern fn dma_free(dma: ?*Dma) void;
extern fn dma_reset(dma: *Dma) void;
extern fn dma_saveload(dma: *Dma, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn dma_read(dma: *Dma, adr: u16) u8;
extern fn dma_write(dma: *Dma, adr: u16, val: u8) void;
extern fn dma_doDma(dma: *Dma) void;
extern fn dma_initHdma(dma: *Dma) void;
extern fn dma_doHdma(dma: *Dma) void;
extern fn dma_cycle(dma: *Dma) bool;
extern fn dma_startDma(dma: *Dma, val: u8, hdma: bool) void;

extern fn c_dma_init(snes: ?*anyopaque) ?*Dma;
extern fn c_dma_free(dma: ?*Dma) void;
extern fn c_dma_reset(dma: *Dma) void;
extern fn c_dma_saveload(dma: *Dma, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn c_dma_read(dma: *Dma, adr: u16) u8;
extern fn c_dma_write(dma: *Dma, adr: u16, val: u8) void;
extern fn c_dma_doDma(dma: *Dma) void;
extern fn c_dma_initHdma(dma: *Dma) void;
extern fn c_dma_doHdma(dma: *Dma) void;
extern fn c_dma_cycle(dma: *Dma) bool;
extern fn c_dma_startDma(dma: *Dma, val: u8, hdma: bool) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0xd4a5eed5);
    return prng.?.random();
}

const openbus_off = 121;
var c_snes_buf: [128]u8 = undefined;
var z_snes_buf: [128]u8 = undefined;

fn resetSnesImages(open_bus: u8) void {
    c_snes_buf = [_]u8{0} ** 128;
    z_snes_buf = [_]u8{0} ** 128;
    c_snes_buf[openbus_off] = open_bus;
    z_snes_buf[openbus_off] = open_bus;
}

// Per-flavour fake memory: a-bus (24-bit address, masked to 64K here — dma.c
// never cares about real memory contents, only that both flavours read back
// whatever the other flavour last wrote to the same masked address) and
// b-bus (8-bit PPU-register-style address space).
var c_a_bus: [0x10000]u8 = undefined;
var z_a_bus: [0x10000]u8 = undefined;
var c_b_bus: [0x100]u8 = undefined;
var z_b_bus: [0x100]u8 = undefined;

fn resetBuses() void {
    c_a_bus = [_]u8{0} ** 0x10000;
    z_a_bus = [_]u8{0} ** 0x10000;
    c_b_bus = [_]u8{0} ** 0x100;
    z_b_bus = [_]u8{0} ** 0x100;
}

fn isC(snes: ?*anyopaque) bool {
    return snes == @as(?*anyopaque, @ptrCast(&c_snes_buf));
}

export fn snes_readBBus(snes: ?*anyopaque, adr: u8) callconv(.c) u8 {
    return if (isC(snes)) c_b_bus[adr] else z_b_bus[adr];
}
export fn snes_writeBBus(snes: ?*anyopaque, adr: u8, val: u8) callconv(.c) void {
    if (isC(snes)) c_b_bus[adr] = val else z_b_bus[adr] = val;
}
export fn snes_read(snes: ?*anyopaque, adr: u32) callconv(.c) u8 {
    return if (isC(snes)) c_a_bus[adr & 0xffff] else z_a_bus[adr & 0xffff];
}
export fn snes_write(snes: ?*anyopaque, adr: u32, val: u8) callconv(.c) void {
    if (isC(snes)) c_a_bus[adr & 0xffff] = val else z_a_bus[adr & 0xffff] = val;
}

fn randomChannel() DmaChannel {
    return .{
        .bAdr = rnd().int(u8),
        .aBank = rnd().int(u8),
        .indBank = rnd().int(u8),
        .repCount = rnd().int(u8),
        .aAdr = rnd().int(u16),
        .size = rnd().int(u16),
        .tableAdr = rnd().int(u16),
        .unusedByte = rnd().int(u8),
        .dmaActive = rnd().boolean(),
        .hdmaActive = rnd().boolean(),
        .mode = rnd().intRangeAtMost(u8, 0, 7),
        .fixed = rnd().boolean(),
        .decrement = rnd().boolean(),
        .indirect = rnd().boolean(),
        .fromB = rnd().boolean(),
        .unusedBit = rnd().boolean(),
        .doTransfer = rnd().boolean(),
        .terminated = rnd().boolean(),
        .offIndex = rnd().intRangeAtMost(u8, 0, 3),
    };
}

fn diffState(c_dma: *Dma, z_dma: *Dma, label: []const u8) !void {
    const c_bytes = std.mem.asBytes(&c_dma.channel);
    const z_bytes = std.mem.asBytes(&z_dma.channel);
    if (!std.mem.eql(u8, c_bytes, z_bytes)) {
        for (c_bytes, 0..) |b, i| {
            if (b != z_bytes[i]) {
                std.debug.print("{s}: channel byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_bytes[i] });
                break;
            }
        }
        return error.ChannelMismatch;
    }
    try expectEqual(c_dma.hdmaTimer, z_dma.hdmaTimer);
    try expectEqual(c_dma.dmaTimer, z_dma.dmaTimer);
    try expectEqual(c_dma.dmaBusy, z_dma.dmaBusy);
    if (!std.mem.eql(u8, &c_a_bus, &z_a_bus)) {
        for (c_a_bus, 0..) |b, i| {
            if (b != z_a_bus[i]) {
                std.debug.print("{s}: a-bus byte {X:0>4}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_a_bus[i] });
                break;
            }
        }
        return error.ABusMismatch;
    }
    try expectEqualSlices(u8, &c_b_bus, &z_b_bus);
}

test "diff register read/write streams over all 8 channels" {
    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        resetSnesImages(rnd().int(u8));
        var c_dma: Dma = .{ .snes = @ptrCast(&c_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        var z_dma: Dma = .{ .snes = @ptrCast(&z_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        c_dma_reset(&c_dma);
        dma_reset(&z_dma);

        var ops_buf: [64][2]u8 = undefined;
        const n = rnd().intRangeAtMost(usize, 1, ops_buf.len);
        for (ops_buf[0..n]) |*op| op.* = .{ rnd().int(u8), rnd().int(u8) };
        for (ops_buf[0..n], 0..) |op, i| {
            const adr: u16 = op[0];
            if (op[1] & 1 == 0) {
                const c_ret = c_dma_read(&c_dma, adr);
                const z_ret = dma_read(&z_dma, adr);
                if (c_ret != z_ret) {
                    std.debug.print("op {d}: read adr {X:0>2}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, adr, c_ret, z_ret });
                    return error.ReadMismatch;
                }
            } else {
                c_dma_write(&c_dma, adr, op[1]);
                dma_write(&z_dma, adr, op[1]);
            }
        }
        try diffState(&c_dma, &z_dma, "read/write stream");
    }
}

test "diff dma_doDma over randomized channel state until inactive" {
    var iter: usize = 0;
    while (iter < 1000) : (iter += 1) {
        resetSnesImages(rnd().int(u8));
        resetBuses();
        rnd().bytes(&c_a_bus);
        @memcpy(&z_a_bus, &c_a_bus);

        var c_dma: Dma = .{ .snes = @ptrCast(&c_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = true };
        var z_dma: Dma = .{ .snes = @ptrCast(&z_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = true };
        for (0..8) |i| {
            const ch = randomChannel();
            c_dma.channel[i] = ch;
            z_dma.channel[i] = ch;
        }

        var steps: usize = 0;
        while (steps < 32) : (steps += 1) {
            c_dma_doDma(&c_dma);
            dma_doDma(&z_dma);
            try diffState(&c_dma, &z_dma, "doDma step");
        }
    }
}

test "diff dma_initHdma/dma_doHdma over randomized channel state" {
    var iter: usize = 0;
    while (iter < 1000) : (iter += 1) {
        resetSnesImages(rnd().int(u8));
        resetBuses();
        rnd().bytes(&c_a_bus);
        @memcpy(&z_a_bus, &c_a_bus);

        var c_dma: Dma = .{ .snes = @ptrCast(&c_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        var z_dma: Dma = .{ .snes = @ptrCast(&z_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        for (0..8) |i| {
            const ch = randomChannel();
            c_dma.channel[i] = ch;
            z_dma.channel[i] = ch;
        }

        c_dma_initHdma(&c_dma);
        dma_initHdma(&z_dma);
        try diffState(&c_dma, &z_dma, "initHdma");

        var lines: usize = 0;
        while (lines < 16) : (lines += 1) {
            c_dma_doHdma(&c_dma);
            dma_doHdma(&z_dma);
            try diffState(&c_dma, &z_dma, "doHdma line");
        }
    }
}

test "diff dma_cycle over randomized hdmaTimer/dmaBusy state" {
    var iter: usize = 0;
    while (iter < 1000) : (iter += 1) {
        resetSnesImages(rnd().int(u8));
        resetBuses();
        rnd().bytes(&c_a_bus);
        @memcpy(&z_a_bus, &c_a_bus);

        var c_dma: Dma = .{ .snes = @ptrCast(&c_snes_buf), .channel = undefined, .hdmaTimer = rnd().intRangeAtMost(u16, 0, 40), .dmaTimer = 0, .dmaBusy = rnd().boolean() };
        var z_dma: Dma = .{ .snes = @ptrCast(&z_snes_buf), .channel = undefined, .hdmaTimer = c_dma.hdmaTimer, .dmaTimer = 0, .dmaBusy = c_dma.dmaBusy };
        for (0..8) |i| {
            const ch = randomChannel();
            c_dma.channel[i] = ch;
            z_dma.channel[i] = ch;
        }

        var steps: usize = 0;
        while (steps < 24) : (steps += 1) {
            const c_ret = c_dma_cycle(&c_dma);
            const z_ret = dma_cycle(&z_dma);
            if (c_ret != z_ret) {
                std.debug.print("cycle step {d}: c={} z={}\n", .{ steps, c_ret, z_ret });
                return error.ReturnMismatch;
            }
            try diffState(&c_dma, &z_dma, "cycle step");
        }
    }
}

test "diff dma_startDma over randomized bitmask/hdma flag streams" {
    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        resetSnesImages(0);
        var c_dma: Dma = .{ .snes = @ptrCast(&c_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        var z_dma: Dma = .{ .snes = @ptrCast(&z_snes_buf), .channel = undefined, .hdmaTimer = 0, .dmaTimer = 0, .dmaBusy = false };
        c_dma_reset(&c_dma);
        dma_reset(&z_dma);

        var steps: usize = 0;
        while (steps < 16) : (steps += 1) {
            const val = rnd().int(u8);
            const hdma = rnd().boolean();
            c_dma_startDma(&c_dma, val, hdma);
            dma_startDma(&z_dma, val, hdma);
            try diffState(&c_dma, &z_dma, "startDma step");
        }
    }
}

// Captured callback results for the saveload diff (file scope: Zig
// containers can't capture locals).
var seen_c: Seen = .{};
var seen_z: Seen = .{};
const Seen = struct { data: ?*anyopaque = null, size: usize = 0 };

fn saveloadCbC(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    seen_c = .{ .data = data, .size = data_size };
}

fn saveloadCbZ(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    seen_z = .{ .data = data, .size = data_size };
}

test "diff init/reset/saveload lifecycle" {
    seen_c = .{};
    seen_z = .{};
    resetSnesImages(0x5A);

    const c_dma = c_dma_init(@ptrCast(&c_snes_buf)) orelse return error.OutOfMemory;
    defer c_dma_free(c_dma);
    const z_dma = dma_init(@ptrCast(&z_snes_buf)) orelse return error.OutOfMemory;
    defer dma_free(z_dma);

    try expectEqual(@as(?*anyopaque, @ptrCast(&c_snes_buf)), c_dma.snes);
    try expectEqual(@as(?*anyopaque, @ptrCast(&z_snes_buf)), z_dma.snes);

    c_dma_reset(c_dma);
    dma_reset(z_dma);
    try diffState(c_dma, z_dma, "post-reset");

    c_dma_saveload(c_dma, saveloadCbC, null);
    dma_saveload(z_dma, saveloadCbZ, null);
    try expectEqual(seen_c.size, seen_z.size);
    try expectEqual(@as(?*anyopaque, @ptrCast(&c_dma.channel)), seen_c.data);
    try expectEqual(@as(?*anyopaque, @ptrCast(&z_dma.channel)), seen_z.data);
}
