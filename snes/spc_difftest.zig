// Tier-B differential test for snes/spc.zig: links the pre-port snes/spc.c
// (symbols renamed with a c_ prefix via the preprocessor, wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized opcode streams.
//
// spc.c's cross-module calls to apu_cpuRead/apu_cpuWrite are NOT renamed:
// both flavours share a common apu_cpuRead/apu_cpuWrite backed by a single
// flat 64 KiB RAM buffer owned by this test.  Each flavour gets its own Spc
// allocation and its own pc cursor into the shared RAM so they execute
// identical instruction streams and produce identical state.
//
// spc.zig is not @import'ed here: its exports come from the linked object, so
// the test only needs the extern declarations and the mirrored Spc layout.

const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub const Spc = extern struct {
    apu: ?*anyopaque,
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    c: bool,
    z: bool,
    v: bool,
    n: bool,
    i: bool,
    h: bool,
    p: bool,
    b: bool,
    stopped: bool,
    cyclesUsed: u8,
};

const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

// Plain (Zig port) symbols.
extern fn spc_init(apu: ?*anyopaque) callconv(.c) ?*Spc;
extern fn spc_free(spc: ?*Spc) callconv(.c) void;
extern fn spc_reset(spc: *Spc) callconv(.c) void;
extern fn spc_runOpcode(spc: *Spc) callconv(.c) c_int;
extern fn spc_saveload(spc: *Spc, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;

// C reference symbols (renamed c_*).
extern fn c_spc_init(apu: ?*anyopaque) callconv(.c) ?*Spc;
extern fn c_spc_free(spc: ?*Spc) callconv(.c) void;
extern fn c_spc_reset(spc: *Spc) callconv(.c) void;
extern fn c_spc_runOpcode(spc: *Spc) callconv(.c) c_int;
extern fn c_spc_saveload(spc: *Spc, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void;

// Shared bus RAM — both flavours see the same memory.
var bus_ram: [0x10000]u8 = undefined;

export fn apu_cpuRead(apu: ?*anyopaque, adr: u16) callconv(.c) u8 {
    _ = apu;
    return bus_ram[adr];
}

export fn apu_cpuWrite(apu: ?*anyopaque, adr: u16, val: u8) callconv(.c) void {
    _ = apu;
    bus_ram[adr] = val;
}

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x5f7c00);
    return prng.?.random();
}

fn expectSpcsEqual(z: *Spc, c: *Spc) !void {
    try expectEqual(c.a, z.a);
    try expectEqual(c.x, z.x);
    try expectEqual(c.y, z.y);
    try expectEqual(c.sp, z.sp);
    try expectEqual(c.pc, z.pc);
    try expectEqual(c.c, z.c);
    try expectEqual(c.z, z.z);
    try expectEqual(c.v, z.v);
    try expectEqual(c.n, z.n);
    try expectEqual(c.i, z.i);
    try expectEqual(c.h, z.h);
    try expectEqual(c.p, z.p);
    try expectEqual(c.b, z.b);
    try expectEqual(c.stopped, z.stopped);
}

// Seed the shared RAM with random bytes and place a reset vector.
fn seedRam() void {
    const r = rnd();
    for (&bus_ram) |*b| b.* = r.int(u8);
    bus_ram[0xfffe] = 0x00;
    bus_ram[0xffff] = 0x02;
}

// Write a stream of simple safe opcodes (nop=0x00) to address 0x0200 so
// runOpcode can execute without branching into undefined territory.
fn fillNops(count: usize) void {
    for (0..count) |i| bus_ram[0x0200 + i] = 0x00;
}

fn bothReset(z: *Spc, c: *Spc) void {
    spc_reset(z);
    c_spc_reset(c);
}

test "spc_reset produces identical initial state" {
    seedRam();
    const z = spc_init(null) orelse return error.OutOfMemory;
    defer spc_free(z);
    const c = c_spc_init(null) orelse return error.OutOfMemory;
    defer c_spc_free(c);
    bothReset(z, c);
    try expectSpcsEqual(z, c);
}

test "nop stream produces identical state" {
    seedRam();
    fillNops(200);
    const z = spc_init(null) orelse return error.OutOfMemory;
    defer spc_free(z);
    const c = c_spc_init(null) orelse return error.OutOfMemory;
    defer c_spc_free(c);
    bothReset(z, c);
    for (0..100) |_| {
        const zc = spc_runOpcode(z);
        const cc = c_spc_runOpcode(c);
        try expectEqual(cc, zc);
        try expectSpcsEqual(z, c);
    }
}

test "flag-manipulation opcodes produce identical state" {
    seedRam();
    // Sequence: setc, clrc, setp, clrp, ei, di, setc, notc, clrv
    const ops = [_]u8{ 0x80, 0x60, 0x40, 0x20, 0xa0, 0xc0, 0x80, 0xed, 0xe0 };
    for (ops, 0..) |op, i| bus_ram[0x0200 + i] = op;
    // Pad with nops
    for (ops.len..200) |i| bus_ram[0x0200 + i] = 0x00;

    const z = spc_init(null) orelse return error.OutOfMemory;
    defer spc_free(z);
    const c = c_spc_init(null) orelse return error.OutOfMemory;
    defer c_spc_free(c);
    bothReset(z, c);

    for (0..ops.len) |_| {
        _ = spc_runOpcode(z);
        _ = c_spc_runOpcode(c);
        try expectSpcsEqual(z, c);
    }
}

test "adc/sbc/cmp imm stream produces identical state" {
    seedRam();
    // Build a stream: mov A,#0x50, adc A,#0xc0 (carry), sbc A,#0x10, cmp A,#0x40
    // followed by nops to fill the rest
    const ops = [_]u8{
        0xe8, 0x50, // mov A, #0x50
        0x88, 0xc0, // adc A, #0xc0
        0xa8, 0x10, // sbc A, #0x10
        0x68, 0x40, // cmp A, #0x40
        0xe8, 0x80, // mov A, #0x80 (sets N)
    };
    for (ops, 0..) |b, i| bus_ram[0x0200 + i] = b;
    for (ops.len..200) |i| bus_ram[0x0200 + i] = 0x00;

    const z = spc_init(null) orelse return error.OutOfMemory;
    defer spc_free(z);
    const c = c_spc_init(null) orelse return error.OutOfMemory;
    defer c_spc_free(c);
    bothReset(z, c);

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = spc_runOpcode(z);
        _ = c_spc_runOpcode(c);
        try expectSpcsEqual(z, c);
    }
}

test "spc_saveload serialises identical byte ranges" {
    seedRam();
    fillNops(50);
    const z = spc_init(null) orelse return error.OutOfMemory;
    defer spc_free(z);
    const c = c_spc_init(null) orelse return error.OutOfMemory;
    defer c_spc_free(c);
    bothReset(z, c);
    for (0..20) |_| {
        _ = spc_runOpcode(z);
        _ = c_spc_runOpcode(c);
    }

    var z_buf: [64]u8 = undefined;
    var c_buf: [64]u8 = undefined;
    var z_size: usize = 0;
    var c_size: usize = 0;

    const ZCtx = struct { buf: *[64]u8, size: *usize };
    var zctx = ZCtx{ .buf = &z_buf, .size = &z_size };
    var cctx = ZCtx{ .buf = &c_buf, .size = &c_size };

    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const p: *ZCtx = @ptrCast(@alignCast(ctx));
            p.size.* = data_size;
            @memcpy(p.buf.*[0..data_size], @as([*]u8, @ptrCast(data.?))[0..data_size]);
        }
    }.run;

    spc_saveload(z, cb, &zctx);
    c_spc_saveload(c, cb, &cctx);

    try expectEqual(c_size, z_size);
    try std.testing.expectEqualSlices(u8, c_buf[0..c_size], z_buf[0..z_size]);
}
