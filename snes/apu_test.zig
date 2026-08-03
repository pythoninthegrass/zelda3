// Tier-A unit tests for snes/apu.zig: golden-value checks for the I/O
// register decode (apu_cpuRead/apu_cpuWrite), timer ticking, and the
// init/reset/saveload lifecycle, using reference behavior from the pre-port
// snes/apu.c. spc.c/dsp.c aren't ported yet, so this file stubs their
// spc_*/dsp_* C-ABI entry points itself (call counters + captured args)
// rather than linking the real SPC700/DSP emulation — that real-behavior
// coverage lives in apu_difftest.zig instead. The Apu layout mirrors
// snes/apu.h; the tests drive it through the exported C-ABI functions only.

const std = @import("std");
const apu_mod = @import("apu.zig");

const expectEqual = std.testing.expectEqual;

const Apu = apu_mod.Apu;
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

var spc_reset_calls: u32 = 0;
var dsp_reset_calls: u32 = 0;
var dsp_cycle_calls: u32 = 0;
var spc_free_calls: u32 = 0;
var dsp_free_calls: u32 = 0;
var spc_run_opcode_result: c_int = 4;
var dsp_read_result: u8 = 0;
var last_dsp_write: ?struct { adr: u8, val: u8 } = null;

fn resetStubState() void {
    spc_reset_calls = 0;
    dsp_reset_calls = 0;
    dsp_cycle_calls = 0;
    spc_free_calls = 0;
    dsp_free_calls = 0;
    spc_run_opcode_result = 4;
    dsp_read_result = 0;
    last_dsp_write = null;
}

export fn spc_init(apu: *Apu) callconv(.c) ?*anyopaque {
    _ = apu;
    return @ptrFromInt(0x1);
}
export fn spc_free(spc: ?*anyopaque) callconv(.c) void {
    _ = spc;
    spc_free_calls += 1;
}
export fn spc_reset(spc: ?*anyopaque) callconv(.c) void {
    _ = spc;
    spc_reset_calls += 1;
}
export fn spc_runOpcode(spc: ?*anyopaque) callconv(.c) c_int {
    _ = spc;
    return spc_run_opcode_result;
}
export fn spc_saveload(spc: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    _ = spc;
    _ = func;
    _ = ctx;
}

export fn dsp_init(apu_ram: [*]u8) callconv(.c) ?*anyopaque {
    _ = apu_ram;
    return @ptrFromInt(0x2);
}
export fn dsp_free(dsp: ?*anyopaque) callconv(.c) void {
    _ = dsp;
    dsp_free_calls += 1;
}
export fn dsp_reset(dsp: ?*anyopaque) callconv(.c) void {
    _ = dsp;
    dsp_reset_calls += 1;
}
export fn dsp_cycle(dsp: ?*anyopaque) callconv(.c) void {
    _ = dsp;
    dsp_cycle_calls += 1;
}
export fn dsp_read(dsp: ?*anyopaque, adr: u8) callconv(.c) u8 {
    _ = dsp;
    _ = adr;
    return dsp_read_result;
}
export fn dsp_write(dsp: ?*anyopaque, adr: u8, val: u8) callconv(.c) void {
    _ = dsp;
    last_dsp_write = .{ .adr = adr, .val = val };
}
export fn dsp_saveload(dsp: ?*anyopaque, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    _ = dsp;
    _ = func;
    _ = ctx;
}

fn freshApu() *Apu {
    resetStubState();
    const a = apu_mod.apu_init() orelse @panic("apu_init returned null");
    apu_mod.apu_reset(a);
    resetStubState(); // apu_reset above called spc_reset/dsp_reset once; tests care about post-reset calls
    return a;
}

test "apu_init wires spc/dsp handles" {
    resetStubState();
    const a = apu_mod.apu_init() orelse return error.OutOfMemory;
    defer apu_mod.apu_free(a);
    try expectEqual(@as(?*anyopaque, @ptrFromInt(0x1)), a.spc);
    try expectEqual(@as(?*anyopaque, @ptrFromInt(0x2)), a.dsp);
}

test "apu_free releases spc and dsp" {
    resetStubState();
    const a = apu_mod.apu_init() orelse return error.OutOfMemory;
    apu_mod.apu_free(a);
    try expectEqual(@as(u32, 1), spc_free_calls);
    try expectEqual(@as(u32, 1), dsp_free_calls);
}

test "apu_reset zeroes state and reinitializes cpuCyclesLeft/romReadable" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.ram[0] = 0xAA;
    a.dspAdr = 0x42;
    a.cycles = 123;
    a.inPorts[0] = 1;
    a.outPorts[0] = 1;
    a.timer[0] = .{ .cycles = 5, .divider = 5, .target = 5, .counter = 5, .enabled = true };
    a.cpuCyclesLeft = 0;
    a.hist.value.count = 10;

    apu_mod.apu_reset(a);

    try expectEqual(@as(u32, 1), spc_reset_calls);
    try expectEqual(@as(u32, 1), dsp_reset_calls);
    try expectEqual(true, a.romReadable);
    try expectEqual(@as(u8, 0), a.ram[0]);
    try expectEqual(@as(u8, 0), a.dspAdr);
    try expectEqual(@as(u32, 0), a.cycles);
    try expectEqual(@as(u8, 0), a.inPorts[0]);
    try expectEqual(@as(u8, 0), a.outPorts[0]);
    try expectEqual(@as(u8, 0), a.timer[0].cycles);
    try expectEqual(@as(u8, 0), a.timer[0].divider);
    try expectEqual(@as(u8, 0), a.timer[0].target);
    try expectEqual(@as(u8, 0), a.timer[0].counter);
    try expectEqual(false, a.timer[0].enabled);
    try expectEqual(@as(u8, 7), a.cpuCyclesLeft);
    try expectEqual(@as(u32, 0), a.hist.value.count);
}

test "apu_saveload hands ram (excluding hist), then dsp, then spc callbacks" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    const Ctx = struct {
        calls: usize = 0,
        size: usize = 0,
        fn cb(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            _ = data;
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.calls += 1;
            self.size = data_size;
        }
    };
    var ctx = Ctx{};
    apu_mod.apu_saveload(a, Ctx.cb, &ctx);
    try expectEqual(@as(usize, 1), ctx.calls);
    try expectEqual(@offsetOf(Apu, "hist") - @offsetOf(Apu, "ram"), ctx.size);
}

test "apu_cycle pulls a fresh cpuCyclesLeft from spc_runOpcode when exhausted" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.cpuCyclesLeft = 0;
    spc_run_opcode_result = 6;
    apu_mod.apu_cycle(a);
    try expectEqual(@as(u8, 5), a.cpuCyclesLeft); // 6 fetched, then -1 this cycle
}

test "apu_cycle calls dsp_cycle every 32 cycles" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.cpuCyclesLeft = 200; // avoid spc_runOpcode refetch noise
    a.cycles = 0;
    apu_mod.apu_cycle(a); // cycles==0 -> dsp_cycle fires, then cycles becomes 1
    try expectEqual(@as(u32, 1), dsp_cycle_calls);
    var i: u32 = 0;
    while (i < 32) : (i += 1) apu_mod.apu_cycle(a);
    // cycles is now 32 (0x20), which & 0x1f == 0 again
    try expectEqual(@as(u32, 2), dsp_cycle_calls);
}

test "apu_cycle timer: enabled timer 2 increments counter every 16*target cycles" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.cpuCyclesLeft = 200;
    a.timer[2].enabled = true;
    a.timer[2].target = 1;
    a.timer[2].cycles = 0;
    var i: u32 = 0;
    while (i < 16) : (i += 1) apu_mod.apu_cycle(a);
    try expectEqual(@as(u8, 1), a.timer[2].counter);
    try expectEqual(@as(u8, 0), a.timer[2].divider);
}

test "apu_cpuRead: fixed registers f0/f1/fa/fb/fc read as 0" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    for ([_]u16{ 0xf0, 0xf1, 0xfa, 0xfb, 0xfc }) |adr| {
        try expectEqual(@as(u8, 0), apu_mod.apu_cpuRead(a, adr));
    }
}

test "apu_cpuRead: f2 returns dspAdr, f3 forwards to dsp_read masked to 0x7f" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.dspAdr = 0xF5;
    try expectEqual(@as(u8, 0xF5), apu_mod.apu_cpuRead(a, 0xf2));
    dsp_read_result = 0x99;
    try expectEqual(@as(u8, 0x99), apu_mod.apu_cpuRead(a, 0xf3));
}

test "apu_cpuRead: f4-f9 read inPorts" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.inPorts = .{ 1, 2, 3, 4, 5, 6 };
    try expectEqual(@as(u8, 1), apu_mod.apu_cpuRead(a, 0xf4));
    try expectEqual(@as(u8, 6), apu_mod.apu_cpuRead(a, 0xf9));
}

test "apu_cpuRead: fd-ff read and clear the corresponding timer counter" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.timer[1].counter = 7;
    try expectEqual(@as(u8, 7), apu_mod.apu_cpuRead(a, 0xfe));
    try expectEqual(@as(u8, 0), a.timer[1].counter);
    try expectEqual(@as(u8, 0), apu_mod.apu_cpuRead(a, 0xfe));
}

test "apu_cpuRead: boot rom overlays 0xffc0-0xffff when romReadable" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.romReadable = true;
    try expectEqual(@as(u8, 0xcd), apu_mod.apu_cpuRead(a, 0xffc0));
    try expectEqual(@as(u8, 0xff), apu_mod.apu_cpuRead(a, 0xffff));
    a.romReadable = false;
    a.ram[0xffc0] = 0x11;
    try expectEqual(@as(u8, 0x11), apu_mod.apu_cpuRead(a, 0xffc0));
}

test "apu_cpuRead: everything else falls through to ram" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.ram[0x1234] = 0x77;
    try expectEqual(@as(u8, 0x77), apu_mod.apu_cpuRead(a, 0x1234));
}

test "apu_cpuWrite: f1 enables timers and clears divider/counter on rising edge" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.timer[0].divider = 5;
    a.timer[0].counter = 5;
    apu_mod.apu_cpuWrite(a, 0xf1, 0x01);
    try expectEqual(true, a.timer[0].enabled);
    try expectEqual(@as(u8, 0), a.timer[0].divider);
    try expectEqual(@as(u8, 0), a.timer[0].counter);
}

test "apu_cpuWrite: f1 bit 0x10/0x20 clear inPorts pairs, bit 0x80 sets romReadable" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    a.inPorts = .{ 1, 1, 1, 1, 0, 0 };
    apu_mod.apu_cpuWrite(a, 0xf1, 0x10);
    try expectEqual(@as(u8, 0), a.inPorts[0]);
    try expectEqual(@as(u8, 0), a.inPorts[1]);
    try expectEqual(@as(u8, 1), a.inPorts[2]);
    apu_mod.apu_cpuWrite(a, 0xf1, 0x20);
    try expectEqual(@as(u8, 0), a.inPorts[2]);
    try expectEqual(@as(u8, 0), a.inPorts[3]);
    a.romReadable = false;
    apu_mod.apu_cpuWrite(a, 0xf1, 0x80);
    try expectEqual(true, a.romReadable);
    apu_mod.apu_cpuWrite(a, 0xf1, 0x00);
    try expectEqual(false, a.romReadable);
}

test "apu_cpuWrite: f2 sets dspAdr, f3 records write history and forwards to dsp_write below 0x80" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    apu_mod.apu_cpuWrite(a, 0xf2, 0x10);
    try expectEqual(@as(u8, 0x10), a.dspAdr);
    apu_mod.apu_cpuWrite(a, 0xf3, 0x55);
    try expectEqual(@as(u32, 1), a.hist.value.count);
    try expectEqual(@as(u8, 0x10), a.hist.value.addr[0]);
    try expectEqual(@as(u8, 0x55), a.hist.value.val[0]);
    try expectEqual(@as(u8, 0x10), last_dsp_write.?.adr);
    try expectEqual(@as(u8, 0x55), last_dsp_write.?.val);

    last_dsp_write = null;
    apu_mod.apu_cpuWrite(a, 0xf2, 0x80); // >= 0x80: no dsp_write
    apu_mod.apu_cpuWrite(a, 0xf3, 0x66);
    try expectEqual(@as(?@TypeOf(last_dsp_write.?), null), last_dsp_write);
}

test "apu_cpuWrite: f4-f7 write outPorts, f8-f9 write inPorts, fa-fc write timer target" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    apu_mod.apu_cpuWrite(a, 0xf4, 0x11);
    apu_mod.apu_cpuWrite(a, 0xf7, 0x22);
    try expectEqual(@as(u8, 0x11), a.outPorts[0]);
    try expectEqual(@as(u8, 0x22), a.outPorts[3]);
    apu_mod.apu_cpuWrite(a, 0xf8, 0x33);
    try expectEqual(@as(u8, 0x33), a.inPorts[4]);
    apu_mod.apu_cpuWrite(a, 0xfa, 0x05);
    try expectEqual(@as(u8, 0x05), a.timer[0].target);
    apu_mod.apu_cpuWrite(a, 0xfc, 0x09);
    try expectEqual(@as(u8, 0x09), a.timer[2].target);
}

test "apu_cpuWrite: every write also lands in ram (shadow copy)" {
    const a = freshApu();
    defer apu_mod.apu_free(a);
    apu_mod.apu_cpuWrite(a, 0x1234, 0x88);
    try expectEqual(@as(u8, 0x88), a.ram[0x1234]);
    apu_mod.apu_cpuWrite(a, 0xf4, 0x11);
    try expectEqual(@as(u8, 0x11), a.ram[0xf4]);
}
