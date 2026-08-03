// Tier-B differential test for snes/dsp.zig: links the pre-port snes/dsp.c
// (symbols renamed with a c_ prefix via the preprocessor, wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized op streams (register read/write, keyon/
// keyoff, dsp_cycle, dsp_getSamples).
//
// The Dsp/DspChannel struct layout mirrors snes/dsp.h (C keeps ownership of
// it; dsp_saveload serializes its tail byte-for-byte into saves/ref/
// Chapter*.sav reference saves). Unlike dma.zig, dsp only ever touches
// memory through the apu_ram pointer passed to dsp_init — no cross-module
// bus externs — so each flavour just gets its own apu_ram buffer, seeded
// with identical random bytes, diffed after each op alongside the Dsp
// struct state. dsp.zig is not @import'ed here: its exports come from the
// linked object, so the test only needs the extern declarations and the
// mirrored layout.

const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub const DspChannel = extern struct {
    pitch: u16,
    pitchCounter: u16,
    pitchModulation: bool,
    decodeBuffer: [19]i16,
    srcn: u8,
    decodeOffset: u16,
    previousFlags: u8,
    old: i16,
    older: i16,
    useNoise: bool,
    adsrRates: [4]u16,
    rateCounter: u16,
    adsrState: u8,
    sustainLevel: u16,
    useGain: bool,
    gainMode: u8,
    directGain: bool,
    gainValue: u16,
    gain: u16,
    keyOn: bool,
    keyOff: bool,
    sampleOut: i16,
    volumeL: i8,
    volumeR: i8,
    echoEnable: bool,
};

pub const Dsp = extern struct {
    apu_ram: [*]u8,
    ram: [0x80]u8,
    channel: [8]DspChannel,
    dirPage: u16,
    evenCycle: bool,
    mute: bool,
    reset: bool,
    masterVolumeL: i8,
    masterVolumeR: i8,
    noiseSample: i16,
    noiseRate: u16,
    noiseCounter: u16,
    echoWrites: bool,
    echoVolumeL: i8,
    echoVolumeR: i8,
    feedbackVolume: i8,
    echoBufferAdr: u16,
    echoDelay: u16,
    echoRemain: u16,
    echoBufferIndex: u16,
    firBufferIndex: u8,
    firValues: [8]i8,
    firBufferL: [8]i16,
    firBufferR: [8]i16,
    sampleBuffer: [534 * 2]i16,
    sampleOffset: u16,
};

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn dsp_init(apu_ram: [*]u8) ?*Dsp;
extern fn dsp_free(dsp: ?*Dsp) void;
extern fn dsp_reset(dsp: *Dsp) void;
extern fn dsp_saveload(dsp: *Dsp, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn dsp_cycle(dsp: *Dsp) void;
extern fn dsp_read(dsp: *Dsp, adr: u8) u8;
extern fn dsp_write(dsp: *Dsp, adr: u8, val: u8) void;
extern fn dsp_getSamples(dsp: *Dsp, sampleData: [*]i16, samplesPerFrame: c_int, numChannels: c_int) void;

extern fn c_dsp_init(apu_ram: [*]u8) ?*Dsp;
extern fn c_dsp_free(dsp: ?*Dsp) void;
extern fn c_dsp_reset(dsp: *Dsp) void;
extern fn c_dsp_saveload(dsp: *Dsp, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn c_dsp_cycle(dsp: *Dsp) void;
extern fn c_dsp_read(dsp: *Dsp, adr: u8) u8;
extern fn c_dsp_write(dsp: *Dsp, adr: u8, val: u8) void;
extern fn c_dsp_getSamples(dsp: *Dsp, sampleData: [*]i16, samplesPerFrame: c_int, numChannels: c_int) void;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x5d5eeda4);
    return prng.?.random();
}

var c_apu_ram: [0x10000]u8 = undefined;
var z_apu_ram: [0x10000]u8 = undefined;

fn resetRam() void {
    rnd().bytes(&c_apu_ram);
    @memcpy(&z_apu_ram, &c_apu_ram);
}

fn diffState(c_dsp: *Dsp, z_dsp: *Dsp, label: []const u8) !void {
    const c_bytes = std.mem.asBytes(c_dsp)[@offsetOf(Dsp, "ram")..];
    const z_bytes = std.mem.asBytes(z_dsp)[@offsetOf(Dsp, "ram")..];
    if (!std.mem.eql(u8, c_bytes, z_bytes)) {
        for (c_bytes, 0..) |b, i| {
            if (b != z_bytes[i]) {
                std.debug.print("{s}: dsp byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_bytes[i] });
                break;
            }
        }
        return error.DspStateMismatch;
    }
    if (!std.mem.eql(u8, &c_apu_ram, &z_apu_ram)) {
        for (c_apu_ram, 0..) |b, i| {
            if (b != z_apu_ram[i]) {
                std.debug.print("{s}: apu_ram byte {X:0>4}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ label, i, b, z_apu_ram[i] });
                break;
            }
        }
        return error.RamMismatch;
    }
}

test "diff register read/write streams over all registers" {
    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        resetRam();
        const c_dsp = c_dsp_init(&c_apu_ram) orelse return error.OutOfMemory;
        defer c_dsp_free(c_dsp);
        const z_dsp = dsp_init(&z_apu_ram) orelse return error.OutOfMemory;
        defer dsp_free(z_dsp);
        c_dsp_reset(c_dsp);
        dsp_reset(z_dsp);
        try diffState(c_dsp, z_dsp, "post-reset");

        var ops_buf: [64][2]u8 = undefined;
        const n = rnd().intRangeAtMost(usize, 1, ops_buf.len);
        for (ops_buf[0..n]) |*op| op.* = .{ rnd().int(u8) & 0x7f, rnd().int(u8) };
        for (ops_buf[0..n], 0..) |op, i| {
            const adr = op[0];
            if (op[1] & 1 == 0) {
                const c_ret = c_dsp_read(c_dsp, adr);
                const z_ret = dsp_read(z_dsp, adr);
                if (c_ret != z_ret) {
                    std.debug.print("op {d}: read adr {X:0>2}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, adr, c_ret, z_ret });
                    return error.ReadMismatch;
                }
            } else {
                c_dsp_write(c_dsp, adr, op[1]);
                dsp_write(z_dsp, adr, op[1]);
            }
        }
        try diffState(c_dsp, z_dsp, "read/write stream");
    }
}

test "diff dsp_cycle over randomized channel/register state" {
    var iter: usize = 0;
    while (iter < 500) : (iter += 1) {
        resetRam();
        const c_dsp = c_dsp_init(&c_apu_ram) orelse return error.OutOfMemory;
        defer c_dsp_free(c_dsp);
        const z_dsp = dsp_init(&z_apu_ram) orelse return error.OutOfMemory;
        defer dsp_free(z_dsp);
        c_dsp_reset(c_dsp);
        dsp_reset(z_dsp);
        c_dsp.reset = false;
        z_dsp.reset = false;
        c_dsp.mute = false;
        z_dsp.mute = false;

        // Randomized register setup, identical for both flavours.
        var reg_ops: [96][2]u8 = undefined;
        for (&reg_ops) |*op| op.* = .{ rnd().int(u8) & 0x7f, rnd().int(u8) };
        for (reg_ops) |op| {
            c_dsp_write(c_dsp, op[0], op[1]);
            dsp_write(z_dsp, op[0], op[1]);
        }
        // key on a random subset of channels.
        const kon = rnd().int(u8);
        c_dsp_write(c_dsp, 0x4c, kon);
        dsp_write(z_dsp, 0x4c, kon);
        try diffState(c_dsp, z_dsp, "post-setup");

        var steps: usize = 0;
        while (steps < 40) : (steps += 1) {
            c_dsp_cycle(c_dsp);
            dsp_cycle(z_dsp);
            try diffState(c_dsp, z_dsp, "cycle step");
        }
    }
}

test "diff dsp_getSamples resampling for mono and stereo" {
    var iter: usize = 0;
    while (iter < 200) : (iter += 1) {
        resetRam();
        const c_dsp = c_dsp_init(&c_apu_ram) orelse return error.OutOfMemory;
        defer c_dsp_free(c_dsp);
        const z_dsp = dsp_init(&z_apu_ram) orelse return error.OutOfMemory;
        defer dsp_free(z_dsp);
        c_dsp_reset(c_dsp);
        dsp_reset(z_dsp);

        var sample_bytes: [534 * 2 * 2]u8 = undefined;
        rnd().bytes(&sample_bytes);
        @memcpy(std.mem.sliceAsBytes(&c_dsp.sampleBuffer), &sample_bytes);
        @memcpy(std.mem.sliceAsBytes(&z_dsp.sampleBuffer), &sample_bytes);
        c_dsp.sampleOffset = 534;
        z_dsp.sampleOffset = 534;

        const channels: c_int = if (iter % 2 == 0) 1 else 2;
        const samplesPerFrame: c_int = 800;
        var c_out: [800 * 2]i16 = undefined;
        var z_out: [800 * 2]i16 = undefined;
        c_dsp_getSamples(c_dsp, &c_out, samplesPerFrame, channels);
        dsp_getSamples(z_dsp, &z_out, samplesPerFrame, channels);
        const written: usize = @intCast(samplesPerFrame * channels);
        try std.testing.expectEqualSlices(i16, c_out[0..written], z_out[0..written]);
        try expectEqual(c_dsp.sampleOffset, z_dsp.sampleOffset);
    }
}

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
    resetRam();

    const c_dsp = c_dsp_init(&c_apu_ram) orelse return error.OutOfMemory;
    defer c_dsp_free(c_dsp);
    const z_dsp = dsp_init(&z_apu_ram) orelse return error.OutOfMemory;
    defer dsp_free(z_dsp);

    try expectEqual(@as([*]u8, &c_apu_ram), c_dsp.apu_ram);
    try expectEqual(@as([*]u8, &z_apu_ram), z_dsp.apu_ram);

    c_dsp_reset(c_dsp);
    dsp_reset(z_dsp);
    try diffState(c_dsp, z_dsp, "post-reset");

    c_dsp_saveload(c_dsp, saveloadCbC, null);
    dsp_saveload(z_dsp, saveloadCbZ, null);
    try expectEqual(seen_c.size, seen_z.size);
    try expectEqual(@as(?*anyopaque, @ptrCast(&c_dsp.ram)), seen_c.data);
    try expectEqual(@as(?*anyopaque, @ptrCast(&z_dsp.ram)), seen_z.data);
}
