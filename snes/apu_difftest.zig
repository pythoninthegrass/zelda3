// Tier-B differential test for snes/apu.zig: links the pre-port snes/apu.c
// (symbols renamed with a c_ prefix via the preprocessor (-D), wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized read/write/cycle streams.
//
// apu.c's cross-module calls (spc_*/dsp_*) are NOT renamed: spc.c/dsp.c
// aren't ported yet, so both flavours are linked against the same real
// snes/spc.c and snes/dsp.c objects (unrenamed, shared) — this drives real
// SPC700/DSP execution through apu_cycle rather than a stub, so the test
// exercises the same code path production does.
//
// The Apu layout mirrors snes/apu.h (C keeps ownership of it; spc_player.c
// and tracing.c poke fields directly). apu.zig is not @import'ed here: its
// exports come from the linked object, so the test only needs the extern
// declarations and the mirrored layout.

const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

pub const Timer = extern struct {
    cycles: u8,
    divider: u8,
    target: u8,
    counter: u8,
    enabled: bool,
};

pub const DspRegWriteHistory = extern struct {
    count: u32,
    addr: [256]u8,
    val: [256]u8,
};

pub const HistUnion = extern union {
    value: DspRegWriteHistory,
    padpad: ?*anyopaque,
};

pub const Apu = extern struct {
    spc: ?*anyopaque,
    dsp: ?*anyopaque,
    ram: [0x10000]u8,
    romReadable: bool,
    dspAdr: u8,
    cycles: u32,
    inPorts: [6]u8,
    outPorts: [4]u8,
    timer: [3]Timer,
    cpuCyclesLeft: u8,
    hist: HistUnion,
};

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn apu_init() ?*Apu;
extern fn apu_free(apu: ?*Apu) void;
extern fn apu_reset(apu: *Apu) void;
extern fn apu_cycle(apu: *Apu) void;
extern fn apu_cpuRead(apu: *Apu, adr: u16) u8;
extern fn apu_cpuWrite(apu: *Apu, adr: u16, val: u8) void;
extern fn apu_saveload(apu: *Apu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;

extern fn c_apu_init() ?*Apu;
extern fn c_apu_free(apu: ?*Apu) void;
extern fn c_apu_reset(apu: *Apu) void;
extern fn c_apu_cycle(apu: *Apu) void;
extern fn c_apu_cpuRead(apu: *Apu, adr: u16) u8;
extern fn c_apu_cpuWrite(apu: *Apu, adr: u16, val: u8) void;
extern fn c_apu_saveload(apu: *Apu, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x50c700ee);
    return prng.?.random();
}

fn expectApusEqual(c: *Apu, z: *Apu) !void {
    try expectEqualSlices(u8, &c.ram, &z.ram);
    try expectEqual(c.romReadable, z.romReadable);
    try expectEqual(c.dspAdr, z.dspAdr);
    try expectEqual(c.cycles, z.cycles);
    try expectEqualSlices(u8, &c.inPorts, &z.inPorts);
    try expectEqualSlices(u8, &c.outPorts, &z.outPorts);
    for (0..3) |i| {
        try expectEqual(c.timer[i].cycles, z.timer[i].cycles);
        try expectEqual(c.timer[i].divider, z.timer[i].divider);
        try expectEqual(c.timer[i].target, z.timer[i].target);
        try expectEqual(c.timer[i].counter, z.timer[i].counter);
        try expectEqual(c.timer[i].enabled, z.timer[i].enabled);
    }
    try expectEqual(c.cpuCyclesLeft, z.cpuCyclesLeft);
    try expectEqual(c.hist.value.count, z.hist.value.count);
    const n = @min(c.hist.value.count, 256);
    try expectEqualSlices(u8, c.hist.value.addr[0..n], z.hist.value.addr[0..n]);
    try expectEqualSlices(u8, c.hist.value.val[0..n], z.hist.value.val[0..n]);
}

test "diff init/reset lifecycle" {
    const c = c_apu_init() orelse return error.OutOfMemory;
    defer c_apu_free(c);
    const z = apu_init() orelse return error.OutOfMemory;
    defer apu_free(z);

    c_apu_reset(c);
    apu_reset(z);
    try expectApusEqual(c, z);
}

test "diff randomized cpuRead/cpuWrite/cycle streams" {
    const c = c_apu_init() orelse return error.OutOfMemory;
    defer c_apu_free(c);
    const z = apu_init() orelse return error.OutOfMemory;
    defer apu_free(z);
    c_apu_reset(c);
    apu_reset(z);

    var iter: usize = 0;
    while (iter < 20000) : (iter += 1) {
        const kind = rnd().intRangeAtMost(u8, 0, 9);
        if (kind == 0) {
            const c_ret = c_apu_cycle;
            const z_ret = apu_cycle;
            c_ret(c);
            z_ret(z);
        } else if (kind < 6) {
            // bias reads/writes toward the I/O register window (0xf0-0xff)
            // most of the time so timers/dsp/ports get exercised, with an
            // occasional full-range address to cover plain ram passthrough.
            const adr: u16 = if (rnd().boolean())
                0xff00 | @as(u16, rnd().int(u8))
            else
                rnd().int(u16);
            const c_val = c_apu_cpuRead(c, adr);
            const z_val = apu_cpuRead(z, adr);
            if (c_val != z_val) {
                std.debug.print("iter {d}: read {X:0>4}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ iter, adr, c_val, z_val });
                return error.ReadMismatch;
            }
        } else {
            const adr: u16 = if (rnd().boolean())
                0xff00 | @as(u16, rnd().int(u8))
            else
                rnd().int(u16);
            const val = rnd().int(u8);
            c_apu_cpuWrite(c, adr, val);
            apu_cpuWrite(z, adr, val);
        }

        if (iter % 200 == 0) try expectApusEqual(c, z);
    }
    try expectApusEqual(c, z);
}

// apu_saveload invokes func once per contiguous save region: apu->ram first,
// then dsp_saveload and spc_saveload each hand their own region (in dsp, then
// spc order). Record the whole sequence so the test can verify the C and Zig
// flavours serialize the same regions, in the same order, with the same sizes.
// Only the first region (apu->ram) has an address we can check against a known
// field; dsp/spc regions live in separately-allocated objects whose addresses
// legitimately differ per instance, so those are compared by size, not pointer.
const MaxRegions = 8;
const Recorder = struct {
    sizes: [MaxRegions]usize = undefined,
    first: ?*anyopaque = null,
    n: usize = 0,

    fn record(self: *Recorder, data: ?*anyopaque, size: usize) void {
        if (self.n == 0) self.first = data;
        if (self.n < MaxRegions) self.sizes[self.n] = size;
        self.n += 1;
    }
};

var rec_c: Recorder = .{};
var rec_z: Recorder = .{};

fn saveloadCbC(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    rec_c.record(data, data_size);
}

fn saveloadCbZ(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    _ = ctx;
    rec_z.record(data, data_size);
}

test "diff saveload hands the same regions in the same order" {
    rec_c = .{};
    rec_z = .{};
    const c = c_apu_init() orelse return error.OutOfMemory;
    defer c_apu_free(c);
    const z = apu_init() orelse return error.OutOfMemory;
    defer apu_free(z);
    c_apu_reset(c);
    apu_reset(z);

    c_apu_saveload(c, saveloadCbC, null);
    apu_saveload(z, saveloadCbZ, null);

    // The first region handed to the callback is apu->ram (before dsp/spc).
    try expectEqual(@as(?*anyopaque, @ptrCast(&c.ram)), rec_c.first);
    try expectEqual(@as(?*anyopaque, @ptrCast(&z.ram)), rec_z.first);
    // Both flavours must serialize the same number of regions...
    try expect(rec_c.n <= MaxRegions);
    try expectEqual(rec_c.n, rec_z.n);
    // ...with identical region sizes in identical order.
    try expectEqualSlices(usize, rec_c.sizes[0..rec_c.n], rec_z.sizes[0..rec_z.n]);
}
