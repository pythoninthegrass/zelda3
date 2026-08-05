// Port of snes/spc.c: the SPC700 CPU emulator — register file, all 256
// opcodes, and the saveload serialiser. Every exported function keeps its
// exact C-ABI name and signature (callconv(.c)) so the remaining .c callers
// (apu.c/apu.zig) link unchanged. The Spc struct layout matches snes/spc.h
// field-for-field (extern struct); apu.zig treats the pointer as anyopaque
// today but the typed layout is available for future callers.
//
// spc.c cross-module calls: spc_read/spc_write delegate to apu_cpuRead/
// apu_cpuWrite (declared below as externs). Those resolve against apu.zig
// (or apu.c) at link time, same as spc.c did.

const std = @import("std");

// Forward-declare Apu as opaque since spc.zig only ever passes the pointer
// through to apu_cpuRead/apu_cpuWrite — it never dereferences Apu fields.
const Apu = opaque {};

pub const Spc = extern struct {
    apu: ?*Apu,
    // registers
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    // flags
    c: bool,
    z: bool,
    v: bool,
    n: bool,
    i: bool,
    h: bool,
    p: bool,
    b: bool,
    // stopping
    stopped: bool,
    // internal use
    cyclesUsed: u8,
};

// Same type as SaveLoadFunc in snes/saveload.h.
const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

extern fn apu_cpuRead(apu: ?*Apu, adr: u16) callconv(.c) u8;
extern fn apu_cpuWrite(apu: ?*Apu, adr: u16, val: u8) callconv(.c) void;

const cyclesPerOpcode = [256]u8{
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 4, 6,  8,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 6, 5, 2, 2, 4,  6,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 4, 5,  4,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 6, 5, 2, 2, 3,  8,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 4, 6,  6,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 4, 5, 2, 2, 4,  3,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 4, 5,  5,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 3,  6,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 2, 4,  5,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 12, 5,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 2, 4,  4,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 3,  4,
    2, 8, 4, 5, 4, 5, 4, 7, 2, 5, 6, 4, 5, 2, 4,  9,
    2, 8, 4, 5, 5, 6, 6, 7, 4, 5, 5, 5, 2, 2, 6,  3,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 4, 5, 3, 4, 3, 4,  3,
    2, 8, 4, 5, 4, 5, 5, 6, 3, 4, 5, 4, 2, 2, 4,  3,
};

pub export fn spc_init(apu: ?*Apu) callconv(.c) ?*Spc {
    const spc: *Spc = @ptrCast(@alignCast(malloc(@sizeOf(Spc)) orelse return null));
    spc.apu = apu;
    return spc;
}

pub export fn spc_free(spc: ?*Spc) callconv(.c) void {
    free(spc);
}

pub export fn spc_reset(spc: *Spc) callconv(.c) void {
    spc.a = 0;
    spc.x = 0;
    spc.y = 0;
    spc.sp = 0;
    spc.pc = read(spc, 0xfffe) | (@as(u16, read(spc, 0xffff)) << 8);
    spc.c = false;
    spc.z = false;
    spc.v = false;
    spc.n = false;
    spc.i = false;
    spc.h = false;
    spc.p = false;
    spc.b = false;
    spc.stopped = false;
    spc.cyclesUsed = 0;
}

pub export fn spc_saveload(spc: *Spc, func: ?*const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    const f = func orelse return;
    const off = @offsetOf(Spc, "a");
    const len = @offsetOf(Spc, "cyclesUsed") - off;
    f(ctx, @as(?*anyopaque, @ptrCast(&spc.a)), len);
}

pub export fn spc_runOpcode(spc: *Spc) callconv(.c) c_int {
    spc.cyclesUsed = 0;
    if (spc.stopped) return 1;
    const opcode = readOpcode(spc);
    spc.cyclesUsed = cyclesPerOpcode[opcode];
    doOpcode(spc, opcode);
    return spc.cyclesUsed;
}

// ---------- internal bus helpers ----------

fn read(spc: *Spc, adr: u16) u8 {
    return apu_cpuRead(spc.apu, adr);
}

fn write(spc: *Spc, adr: u16, val: u8) void {
    apu_cpuWrite(spc.apu, adr, val);
}

fn readOpcode(spc: *Spc) u8 {
    const v = read(spc, spc.pc);
    spc.pc +%= 1;
    return v;
}

fn readOpcodeWord(spc: *Spc) u16 {
    const lo = readOpcode(spc);
    return lo | (@as(u16, readOpcode(spc)) << 8);
}

fn getFlags(spc: *Spc) u8 {
    var val: u8 = if (spc.n) 0x80 else 0;
    val |= if (spc.v) @as(u8, 0x40) else 0;
    val |= if (spc.p) @as(u8, 0x20) else 0;
    val |= if (spc.b) @as(u8, 0x10) else 0;
    val |= if (spc.h) @as(u8, 0x08) else 0;
    val |= if (spc.i) @as(u8, 0x04) else 0;
    val |= if (spc.z) @as(u8, 0x02) else 0;
    val |= if (spc.c) @as(u8, 0x01) else 0;
    return val;
}

fn setFlags(spc: *Spc, val: u8) void {
    spc.n = (val & 0x80) != 0;
    spc.v = (val & 0x40) != 0;
    spc.p = (val & 0x20) != 0;
    spc.b = (val & 0x10) != 0;
    spc.h = (val & 0x08) != 0;
    spc.i = (val & 0x04) != 0;
    spc.z = (val & 0x02) != 0;
    spc.c = (val & 0x01) != 0;
}

fn setZN(spc: *Spc, value: u8) void {
    spc.z = value == 0;
    spc.n = (value & 0x80) != 0;
}

fn doBranch(spc: *Spc, value: u8, check: bool) void {
    if (check) {
        spc.cyclesUsed +%= 2;
        spc.pc = spc.pc +% @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(value)))));
    }
}

fn pullByte(spc: *Spc) u8 {
    spc.sp +%= 1;
    return read(spc, 0x100 | @as(u16, spc.sp));
}

fn pushByte(spc: *Spc, value: u8) void {
    write(spc, 0x100 | @as(u16, spc.sp), value);
    spc.sp -%= 1;
}

fn pullWord(spc: *Spc) u16 {
    const lo = pullByte(spc);
    return lo | (@as(u16, pullByte(spc)) << 8);
}

fn pushWord(spc: *Spc, value: u16) void {
    pushByte(spc, @truncate(value >> 8));
    pushByte(spc, @truncate(value));
}

fn readWord(spc: *Spc, adrl: u16, adrh: u16) u16 {
    const lo = read(spc, adrl);
    return lo | (@as(u16, read(spc, adrh)) << 8);
}

fn writeWord(spc: *Spc, adrl: u16, adrh: u16, value: u16) void {
    write(spc, adrl, @truncate(value));
    write(spc, adrh, @truncate(value >> 8));
}

// ---------- addressing modes ----------

fn adrDp(spc: *Spc) u16 {
    return readOpcode(spc) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrAbs(spc: *Spc) u16 {
    return readOpcodeWord(spc);
}

fn adrInd(spc: *Spc) u16 {
    return spc.x | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrIdx(spc: *Spc) u16 {
    const pointer = readOpcode(spc);
    const base: u16 = @as(u16, @intFromBool(spc.p)) << 8;
    return readWord(spc, ((pointer +% spc.x) & 0xff) | base, ((pointer +% spc.x +% 1) & 0xff) | base);
}

fn adrImm(spc: *Spc) u16 {
    const pc = spc.pc;
    spc.pc +%= 1;
    return pc;
}

fn adrDpx(spc: *Spc) u16 {
    return ((readOpcode(spc) +% spc.x) & 0xff) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrDpy(spc: *Spc) u16 {
    return ((readOpcode(spc) +% spc.y) & 0xff) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrAbx(spc: *Spc) u16 {
    return (readOpcodeWord(spc) +% spc.x) & 0xffff;
}

fn adrAby(spc: *Spc) u16 {
    return (readOpcodeWord(spc) +% spc.y) & 0xffff;
}

fn adrIdy(spc: *Spc) u16 {
    const pointer = readOpcode(spc);
    const base: u16 = @as(u16, @intFromBool(spc.p)) << 8;
    const adr = readWord(spc, pointer | base, ((pointer +% 1) & 0xff) | base);
    return (adr +% spc.y) & 0xffff;
}

fn adrDpDp(spc: *Spc, src: *u16) u16 {
    src.* = readOpcode(spc) | (@as(u16, @intFromBool(spc.p)) << 8);
    return readOpcode(spc) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrDpImm(spc: *Spc, src: *u16) u16 {
    src.* = spc.pc;
    spc.pc +%= 1;
    return readOpcode(spc) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrIndInd(spc: *Spc, src: *u16) u16 {
    src.* = spc.y | (@as(u16, @intFromBool(spc.p)) << 8);
    return spc.x | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrAbsBit(spc: *Spc, adr: *u16) u8 {
    const adrBit = readOpcodeWord(spc);
    adr.* = adrBit & 0x1fff;
    return @truncate(adrBit >> 13);
}

fn adrDpWord(spc: *Spc, low: *u16) u16 {
    const a = readOpcode(spc);
    low.* = a | (@as(u16, @intFromBool(spc.p)) << 8);
    return ((a +% 1) & 0xff) | (@as(u16, @intFromBool(spc.p)) << 8);
}

fn adrIndP(spc: *Spc) u16 {
    const adr: u16 = spc.x | (@as(u16, @intFromBool(spc.p)) << 8);
    spc.x +%= 1;
    return adr;
}

// ---------- ALU helpers ----------

fn spcAnd(spc: *Spc, adr: u16) void {
    spc.a &= read(spc, adr);
    setZN(spc, spc.a);
}

fn spcAndm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src);
    const result = read(spc, dst) & value;
    write(spc, dst, result);
    setZN(spc, result);
}

fn spcOr(spc: *Spc, adr: u16) void {
    spc.a |= read(spc, adr);
    setZN(spc, spc.a);
}

fn spcOrm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src);
    const result = read(spc, dst) | value;
    write(spc, dst, result);
    setZN(spc, result);
}

fn spcEor(spc: *Spc, adr: u16) void {
    spc.a ^= read(spc, adr);
    setZN(spc, spc.a);
}

fn spcEorm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src);
    const result = read(spc, dst) ^ value;
    write(spc, dst, result);
    setZN(spc, result);
}

fn spcAdc(spc: *Spc, adr: u16) void {
    const value = read(spc, adr);
    const result: c_int = @as(c_int, spc.a) + @as(c_int, value) + @intFromBool(spc.c);
    spc.v = ((spc.a & 0x80) == (value & 0x80)) and ((value & 0x80) != (@as(u8, @truncate(@as(c_uint, @bitCast(result)))) & 0x80));
    spc.h = ((spc.a & 0xf) + (value & 0xf) + @as(u8, @intFromBool(spc.c))) > 0xf;
    spc.c = result > 0xff;
    spc.a = @truncate(@as(c_uint, @bitCast(result)));
    setZN(spc, spc.a);
}

fn spcAdcm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src);
    const applyOn = read(spc, dst);
    const result: c_int = @as(c_int, applyOn) + @as(c_int, value) + @intFromBool(spc.c);
    spc.v = ((applyOn & 0x80) == (value & 0x80)) and ((value & 0x80) != (@as(u8, @truncate(@as(c_uint, @bitCast(result)))) & 0x80));
    spc.h = ((applyOn & 0xf) + (value & 0xf) + @as(u8, @intFromBool(spc.c))) > 0xf;
    spc.c = result > 0xff;
    write(spc, dst, @truncate(@as(c_uint, @bitCast(result))));
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcSbc(spc: *Spc, adr: u16) void {
    const value = read(spc, adr) ^ 0xff;
    const result: c_int = @as(c_int, spc.a) + @as(c_int, value) + @intFromBool(spc.c);
    spc.v = ((spc.a & 0x80) == (value & 0x80)) and ((value & 0x80) != (@as(u8, @truncate(@as(c_uint, @bitCast(result)))) & 0x80));
    spc.h = ((spc.a & 0xf) + (value & 0xf) + @as(u8, @intFromBool(spc.c))) > 0xf;
    spc.c = result > 0xff;
    spc.a = @truncate(@as(c_uint, @bitCast(result)));
    setZN(spc, spc.a);
}

fn spcSbcm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src) ^ 0xff;
    const applyOn = read(spc, dst);
    const result: c_int = @as(c_int, applyOn) + @as(c_int, value) + @intFromBool(spc.c);
    spc.v = ((applyOn & 0x80) == (value & 0x80)) and ((value & 0x80) != (@as(u8, @truncate(@as(c_uint, @bitCast(result)))) & 0x80));
    spc.h = ((applyOn & 0xf) + (value & 0xf) + @as(u8, @intFromBool(spc.c))) > 0xf;
    spc.c = result > 0xff;
    write(spc, dst, @truncate(@as(c_uint, @bitCast(result))));
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcCmp(spc: *Spc, adr: u16) void {
    const value = read(spc, adr) ^ 0xff;
    const result: c_int = @as(c_int, spc.a) + @as(c_int, value) + 1;
    spc.c = result > 0xff;
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcCmpx(spc: *Spc, adr: u16) void {
    const value = read(spc, adr) ^ 0xff;
    const result: c_int = @as(c_int, spc.x) + @as(c_int, value) + 1;
    spc.c = result > 0xff;
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcCmpy(spc: *Spc, adr: u16) void {
    const value = read(spc, adr) ^ 0xff;
    const result: c_int = @as(c_int, spc.y) + @as(c_int, value) + 1;
    spc.c = result > 0xff;
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcCmpm(spc: *Spc, dst: u16, src: u16) void {
    const value = read(spc, src) ^ 0xff;
    const result: c_int = @as(c_int, read(spc, dst)) + @as(c_int, value) + 1;
    spc.c = result > 0xff;
    setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
}

fn spcMov(spc: *Spc, adr: u16) void {
    spc.a = read(spc, adr);
    setZN(spc, spc.a);
}

fn spcMovx(spc: *Spc, adr: u16) void {
    spc.x = read(spc, adr);
    setZN(spc, spc.x);
}

fn spcMovy(spc: *Spc, adr: u16) void {
    spc.y = read(spc, adr);
    setZN(spc, spc.y);
}

fn spcMovs(spc: *Spc, adr: u16) void {
    _ = read(spc, adr);
    write(spc, adr, spc.a);
}

fn spcMovsx(spc: *Spc, adr: u16) void {
    _ = read(spc, adr);
    write(spc, adr, spc.x);
}

fn spcMovsy(spc: *Spc, adr: u16) void {
    _ = read(spc, adr);
    write(spc, adr, spc.y);
}

fn spcAsl(spc: *Spc, adr: u16) void {
    var val = read(spc, adr);
    spc.c = (val & 0x80) != 0;
    val <<= 1;
    write(spc, adr, val);
    setZN(spc, val);
}

fn spcLsr(spc: *Spc, adr: u16) void {
    var val = read(spc, adr);
    spc.c = (val & 1) != 0;
    val >>= 1;
    write(spc, adr, val);
    setZN(spc, val);
}

fn spcRol(spc: *Spc, adr: u16) void {
    var val = read(spc, adr);
    const newC = (val & 0x80) != 0;
    val = (val << 1) | @intFromBool(spc.c);
    spc.c = newC;
    write(spc, adr, val);
    setZN(spc, val);
}

fn spcRor(spc: *Spc, adr: u16) void {
    var val = read(spc, adr);
    const newC = (val & 1) != 0;
    val = (val >> 1) | (@as(u8, @intFromBool(spc.c)) << 7);
    spc.c = newC;
    write(spc, adr, val);
    setZN(spc, val);
}

fn spcInc(spc: *Spc, adr: u16) void {
    const val = read(spc, adr) +% 1;
    write(spc, adr, val);
    setZN(spc, val);
}

fn spcDec(spc: *Spc, adr: u16) void {
    const val = read(spc, adr) -% 1;
    write(spc, adr, val);
    setZN(spc, val);
}

// ---------- opcode dispatch ----------

fn doOpcode(spc: *Spc, opcode: u8) void {
    switch (opcode) {
        0x00 => { // nop
        },
        0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91, 0xa1, 0xb1, 0xc1, 0xd1, 0xe1, 0xf1 => { // tcall
            pushWord(spc, spc.pc);
            const adr: u16 = 0xffde - (2 * @as(u16, opcode >> 4));
            spc.pc = readWord(spc, adr, adr + 1);
        },
        0x02, 0x22, 0x42, 0x62, 0x82, 0xa2, 0xc2, 0xe2 => { // set1 dp
            const adr = adrDp(spc);
            write(spc, adr, read(spc, adr) | (@as(u8, 1) << @as(u3, @truncate(opcode >> 5))));
        },
        0x12, 0x32, 0x52, 0x72, 0x92, 0xb2, 0xd2, 0xf2 => { // clr1 dp
            const adr = adrDp(spc);
            write(spc, adr, read(spc, adr) & ~(@as(u8, 1) << @as(u3, @truncate(opcode >> 5))));
        },
        0x03, 0x23, 0x43, 0x63, 0x83, 0xa3, 0xc3, 0xe3 => { // bbs dp, rel
            const val = read(spc, adrDp(spc));
            doBranch(spc, readOpcode(spc), (val & (@as(u8, 1) << @as(u3, @truncate(opcode >> 5)))) != 0);
        },
        0x13, 0x33, 0x53, 0x73, 0x93, 0xb3, 0xd3, 0xf3 => { // bbc dp, rel
            const val = read(spc, adrDp(spc));
            doBranch(spc, readOpcode(spc), (val & (@as(u8, 1) << @as(u3, @truncate(opcode >> 5)))) == 0);
        },
        0x04 => spcOr(spc, adrDp(spc)),
        0x05 => spcOr(spc, adrAbs(spc)),
        0x06 => spcOr(spc, adrInd(spc)),
        0x07 => spcOr(spc, adrIdx(spc)),
        0x08 => spcOr(spc, adrImm(spc)),
        0x09 => { // orm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcOrm(spc, dst, src);
        },
        0x0a => { // or1 abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = spc.c or ((read(spc, adr) >> @as(u3, @truncate(bit))) & 1) != 0;
        },
        0x0b => spcAsl(spc, adrDp(spc)),
        0x0c => spcAsl(spc, adrAbs(spc)),
        0x0d => pushByte(spc, getFlags(spc)), // pushp
        0x0e => { // tset1 abs
            const adr = adrAbs(spc);
            const val = read(spc, adr);
            const result: c_int = @as(c_int, spc.a) + @as(c_int, val ^ 0xff) + 1;
            setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
            write(spc, adr, val | spc.a);
        },
        0x0f => { // brk
            pushWord(spc, spc.pc);
            pushByte(spc, getFlags(spc));
            spc.i = false;
            spc.b = true;
            spc.pc = readWord(spc, 0xffde, 0xffdf);
        },
        0x10 => doBranch(spc, readOpcode(spc), !spc.n), // bpl
        0x14 => spcOr(spc, adrDpx(spc)),
        0x15 => spcOr(spc, adrAbx(spc)),
        0x16 => spcOr(spc, adrAby(spc)),
        0x17 => spcOr(spc, adrIdy(spc)),
        0x18 => { // orm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcOrm(spc, dst, src);
        },
        0x19 => { // orm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcOrm(spc, dst, src);
        },
        0x1a => { // decw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const value = readWord(spc, low, high) -% 1;
            spc.z = value == 0;
            spc.n = (value & 0x8000) != 0;
            writeWord(spc, low, high, value);
        },
        0x1b => spcAsl(spc, adrDpx(spc)),
        0x1c => { // asla
            spc.c = (spc.a & 0x80) != 0;
            spc.a <<= 1;
            setZN(spc, spc.a);
        },
        0x1d => { // decx
            spc.x -%= 1;
            setZN(spc, spc.x);
        },
        0x1e => spcCmpx(spc, adrAbs(spc)),
        0x1f => { // jmp iax
            const pointer = readOpcodeWord(spc);
            spc.pc = readWord(spc, (pointer +% spc.x) & 0xffff, (pointer +% spc.x +% 1) & 0xffff);
        },
        0x20 => spc.p = false, // clrp
        0x24 => spcAnd(spc, adrDp(spc)),
        0x25 => spcAnd(spc, adrAbs(spc)),
        0x26 => spcAnd(spc, adrInd(spc)),
        0x27 => spcAnd(spc, adrIdx(spc)),
        0x28 => spcAnd(spc, adrImm(spc)),
        0x29 => { // andm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcAndm(spc, dst, src);
        },
        0x2a => { // or1n abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = spc.c or (~(read(spc, adr) >> @as(u3, @truncate(bit))) & 1) != 0;
        },
        0x2b => spcRol(spc, adrDp(spc)),
        0x2c => spcRol(spc, adrAbs(spc)),
        0x2d => pushByte(spc, spc.a), // pusha
        0x2e => { // cbne dp, rel
            const val = read(spc, adrDp(spc)) ^ 0xff;
            const result: c_int = @as(c_int, spc.a) + @as(c_int, val) + 1;
            doBranch(spc, readOpcode(spc), result != 0);
        },
        0x2f => { // bra
            spc.pc = spc.pc +% @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(readOpcode(spc))))));
        },
        0x30 => doBranch(spc, readOpcode(spc), spc.n), // bmi
        0x34 => spcAnd(spc, adrDpx(spc)),
        0x35 => spcAnd(spc, adrAbx(spc)),
        0x36 => spcAnd(spc, adrAby(spc)),
        0x37 => spcAnd(spc, adrIdy(spc)),
        0x38 => { // andm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcAndm(spc, dst, src);
        },
        0x39 => { // andm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcAndm(spc, dst, src);
        },
        0x3a => { // incw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const value = readWord(spc, low, high) +% 1;
            spc.z = value == 0;
            spc.n = (value & 0x8000) != 0;
            writeWord(spc, low, high, value);
        },
        0x3b => spcRol(spc, adrDpx(spc)),
        0x3c => { // rola
            const newC = (spc.a & 0x80) != 0;
            spc.a = (spc.a << 1) | @intFromBool(spc.c);
            spc.c = newC;
            setZN(spc, spc.a);
        },
        0x3d => { // incx
            spc.x +%= 1;
            setZN(spc, spc.x);
        },
        0x3e => spcCmpx(spc, adrDp(spc)),
        0x3f => { // call abs
            const dst = readOpcodeWord(spc);
            pushWord(spc, spc.pc);
            spc.pc = dst;
        },
        0x40 => spc.p = true, // setp
        0x44 => spcEor(spc, adrDp(spc)),
        0x45 => spcEor(spc, adrAbs(spc)),
        0x46 => spcEor(spc, adrInd(spc)),
        0x47 => spcEor(spc, adrIdx(spc)),
        0x48 => spcEor(spc, adrImm(spc)),
        0x49 => { // eorm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcEorm(spc, dst, src);
        },
        0x4a => { // and1 abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = spc.c and ((read(spc, adr) >> @as(u3, @truncate(bit))) & 1) != 0;
        },
        0x4b => spcLsr(spc, adrDp(spc)),
        0x4c => spcLsr(spc, adrAbs(spc)),
        0x4d => pushByte(spc, spc.x), // pushx
        0x4e => { // tclr1 abs
            const adr = adrAbs(spc);
            const val = read(spc, adr);
            const result: c_int = @as(c_int, spc.a) + @as(c_int, val ^ 0xff) + 1;
            setZN(spc, @truncate(@as(c_uint, @bitCast(result))));
            write(spc, adr, val & ~spc.a);
        },
        0x4f => { // pcall dp
            const dst = readOpcode(spc);
            pushWord(spc, spc.pc);
            spc.pc = 0xff00 | @as(u16, dst);
        },
        0x50 => doBranch(spc, readOpcode(spc), !spc.v), // bvc
        0x54 => spcEor(spc, adrDpx(spc)),
        0x55 => spcEor(spc, adrAbx(spc)),
        0x56 => spcEor(spc, adrAby(spc)),
        0x57 => spcEor(spc, adrIdy(spc)),
        0x58 => { // eorm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcEorm(spc, dst, src);
        },
        0x59 => { // eorm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcEorm(spc, dst, src);
        },
        0x5a => { // cmpw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const value = readWord(spc, low, high) ^ 0xffff;
            const ya: u16 = spc.a | (@as(u16, spc.y) << 8);
            const result: c_int = ya + value + 1;
            spc.c = result > 0xffff;
            spc.z = (@as(c_uint, @bitCast(result)) & 0xffff) == 0;
            spc.n = (@as(c_uint, @bitCast(result)) & 0x8000) != 0;
        },
        0x5b => spcLsr(spc, adrDpx(spc)),
        0x5c => { // lsra
            spc.c = (spc.a & 1) != 0;
            spc.a >>= 1;
            setZN(spc, spc.a);
        },
        0x5d => { // movxa
            spc.x = spc.a;
            setZN(spc, spc.x);
        },
        0x5e => spcCmpy(spc, adrAbs(spc)),
        0x5f => spc.pc = readOpcodeWord(spc), // jmp abs
        0x60 => spc.c = false, // clrc
        0x64 => spcCmp(spc, adrDp(spc)),
        0x65 => spcCmp(spc, adrAbs(spc)),
        0x66 => spcCmp(spc, adrInd(spc)),
        0x67 => spcCmp(spc, adrIdx(spc)),
        0x68 => spcCmp(spc, adrImm(spc)),
        0x69 => { // cmpm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcCmpm(spc, dst, src);
        },
        0x6a => { // and1n abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = spc.c and (~(read(spc, adr) >> @as(u3, @truncate(bit))) & 1) != 0;
        },
        0x6b => spcRor(spc, adrDp(spc)),
        0x6c => spcRor(spc, adrAbs(spc)),
        0x6d => pushByte(spc, spc.y), // pushy
        0x6e => { // dbnz dp, rel
            const adr = adrDp(spc);
            const result = read(spc, adr) -% 1;
            write(spc, adr, result);
            doBranch(spc, readOpcode(spc), result != 0);
        },
        0x6f => spc.pc = pullWord(spc), // ret
        0x70 => doBranch(spc, readOpcode(spc), spc.v), // bvs
        0x74 => spcCmp(spc, adrDpx(spc)),
        0x75 => spcCmp(spc, adrAbx(spc)),
        0x76 => spcCmp(spc, adrAby(spc)),
        0x77 => spcCmp(spc, adrIdy(spc)),
        0x78 => { // cmpm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcCmpm(spc, dst, src);
        },
        0x79 => { // cmpm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcCmpm(spc, dst, src);
        },
        0x7a => { // addw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const value = readWord(spc, low, high);
            const ya: u16 = spc.a | (@as(u16, spc.y) << 8);
            const result: c_int = ya + value;
            spc.v = ((ya & 0x8000) == (value & 0x8000)) and ((value & 0x8000) != (@as(u16, @truncate(@as(c_uint, @bitCast(result)))) & 0x8000));
            spc.h = ((ya & 0xfff) + (value & 0xfff) + 1) > 0xfff;
            spc.c = result > 0xffff;
            spc.z = (@as(c_uint, @bitCast(result)) & 0xffff) == 0;
            spc.n = (@as(c_uint, @bitCast(result)) & 0x8000) != 0;
            spc.a = @truncate(@as(c_uint, @bitCast(result)));
            spc.y = @truncate(@as(c_uint, @bitCast(result)) >> 8);
        },
        0x7b => spcRor(spc, adrDpx(spc)),
        0x7c => { // rora
            const newC = (spc.a & 1) != 0;
            spc.a = (spc.a >> 1) | (@as(u8, @intFromBool(spc.c)) << 7);
            spc.c = newC;
            setZN(spc, spc.a);
        },
        0x7d => { // movax
            spc.a = spc.x;
            setZN(spc, spc.a);
        },
        0x7e => spcCmpy(spc, adrDp(spc)),
        0x7f => { // reti
            setFlags(spc, pullByte(spc));
            spc.pc = pullWord(spc);
        },
        0x80 => spc.c = true, // setc
        0x84 => spcAdc(spc, adrDp(spc)),
        0x85 => spcAdc(spc, adrAbs(spc)),
        0x86 => spcAdc(spc, adrInd(spc)),
        0x87 => spcAdc(spc, adrIdx(spc)),
        0x88 => spcAdc(spc, adrImm(spc)),
        0x89 => { // adcm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcAdcm(spc, dst, src);
        },
        0x8a => { // eor1 abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = spc.c != (((read(spc, adr) >> @as(u3, @truncate(bit))) & 1) != 0);
        },
        0x8b => spcDec(spc, adrDp(spc)),
        0x8c => spcDec(spc, adrAbs(spc)),
        0x8d => spcMovy(spc, adrImm(spc)), // movy imm
        0x8e => setFlags(spc, pullByte(spc)), // popp
        0x8f => { // movm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            const val = read(spc, src);
            _ = read(spc, dst);
            write(spc, dst, val);
        },
        0x90 => doBranch(spc, readOpcode(spc), !spc.c), // bcc
        0x94 => spcAdc(spc, adrDpx(spc)),
        0x95 => spcAdc(spc, adrAbx(spc)),
        0x96 => spcAdc(spc, adrAby(spc)),
        0x97 => spcAdc(spc, adrIdy(spc)),
        0x98 => { // adcm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcAdcm(spc, dst, src);
        },
        0x99 => { // adcm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcAdcm(spc, dst, src);
        },
        0x9a => { // subw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const value = readWord(spc, low, high) ^ 0xffff;
            const ya: u16 = spc.a | (@as(u16, spc.y) << 8);
            const result: c_int = ya + value + 1;
            spc.v = ((ya & 0x8000) == (value & 0x8000)) and ((value & 0x8000) != (@as(u16, @truncate(@as(c_uint, @bitCast(result)))) & 0x8000));
            spc.h = ((ya & 0xfff) + (value & 0xfff) + 1) > 0xfff;
            spc.c = result > 0xffff;
            spc.z = (@as(c_uint, @bitCast(result)) & 0xffff) == 0;
            spc.n = (@as(c_uint, @bitCast(result)) & 0x8000) != 0;
            spc.a = @truncate(@as(c_uint, @bitCast(result)));
            spc.y = @truncate(@as(c_uint, @bitCast(result)) >> 8);
        },
        0x9b => spcDec(spc, adrDpx(spc)),
        0x9c => { // deca
            spc.a -%= 1;
            setZN(spc, spc.a);
        },
        0x9d => { // movxp
            spc.x = spc.sp;
            setZN(spc, spc.x);
        },
        0x9e => { // div
            const value: u16 = spc.a | (@as(u16, spc.y) << 8);
            var result: c_int = 0xffff;
            var mod: c_int = spc.a;
            if (spc.x != 0) {
                result = @divTrunc(@as(c_int, value), spc.x);
                mod = @rem(@as(c_int, value), spc.x);
            }
            spc.v = result > 0xff;
            spc.h = (spc.x & 0xf) <= (spc.y & 0xf);
            spc.a = @truncate(@as(c_uint, @bitCast(result)));
            spc.y = @truncate(@as(c_uint, @bitCast(mod)));
            setZN(spc, spc.a);
        },
        0x9f => { // xcn
            spc.a = (spc.a >> 4) | (spc.a << 4);
            setZN(spc, spc.a);
        },
        0xa0 => spc.i = true, // ei
        0xa4 => spcSbc(spc, adrDp(spc)),
        0xa5 => spcSbc(spc, adrAbs(spc)),
        0xa6 => spcSbc(spc, adrInd(spc)),
        0xa7 => spcSbc(spc, adrIdx(spc)),
        0xa8 => spcSbc(spc, adrImm(spc)),
        0xa9 => { // sbcm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            spcSbcm(spc, dst, src);
        },
        0xaa => { // mov1 abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            spc.c = (read(spc, adr) >> @as(u3, @truncate(bit))) & 1 != 0;
        },
        0xab => spcInc(spc, adrDp(spc)),
        0xac => spcInc(spc, adrAbs(spc)),
        0xad => spcCmpy(spc, adrImm(spc)),
        0xae => spc.a = pullByte(spc), // popa
        0xaf => { // movs ind+
            const adr = adrIndP(spc);
            write(spc, adr, spc.a);
        },
        0xb0 => doBranch(spc, readOpcode(spc), spc.c), // bcs
        0xb4 => spcSbc(spc, adrDpx(spc)),
        0xb5 => spcSbc(spc, adrAbx(spc)),
        0xb6 => spcSbc(spc, adrAby(spc)),
        0xb7 => spcSbc(spc, adrIdy(spc)),
        0xb8 => { // sbcm dp, imm
            var src: u16 = 0;
            const dst = adrDpImm(spc, &src);
            spcSbcm(spc, dst, src);
        },
        0xb9 => { // sbcm ind, ind
            var src: u16 = 0;
            const dst = adrIndInd(spc, &src);
            spcSbcm(spc, dst, src);
        },
        0xba => { // movw dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            const val = readWord(spc, low, high);
            spc.a = @truncate(val);
            spc.y = @truncate(val >> 8);
            spc.z = val == 0;
            spc.n = (val & 0x8000) != 0;
        },
        0xbb => spcInc(spc, adrDpx(spc)),
        0xbc => { // inca
            spc.a +%= 1;
            setZN(spc, spc.a);
        },
        0xbd => spc.sp = spc.x, // movpx
        0xbe => { // das
            if (spc.a > 0x99 or !spc.c) {
                spc.a -%= 0x60;
                spc.c = false;
            }
            if ((spc.a & 0xf) > 9 or !spc.h) {
                spc.a -%= 6;
            }
            setZN(spc, spc.a);
        },
        0xbf => { // mov ind+
            const adr = adrIndP(spc);
            spc.a = read(spc, adr);
            setZN(spc, spc.a);
        },
        0xc0 => spc.i = false, // di
        0xc4 => spcMovs(spc, adrDp(spc)),
        0xc5 => spcMovs(spc, adrAbs(spc)),
        0xc6 => spcMovs(spc, adrInd(spc)),
        0xc7 => spcMovs(spc, adrIdx(spc)),
        0xc8 => spcCmpx(spc, adrImm(spc)),
        0xc9 => spcMovsx(spc, adrAbs(spc)),
        0xca => { // mov1s abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            const result = (read(spc, adr) & ~(@as(u8, 1) << @as(u3, @truncate(bit)))) | (@as(u8, @intFromBool(spc.c)) << @as(u3, @truncate(bit)));
            write(spc, adr, result);
        },
        0xcb => spcMovsy(spc, adrDp(spc)),
        0xcc => spcMovsy(spc, adrAbs(spc)),
        0xcd => spcMovx(spc, adrImm(spc)), // movx imm
        0xce => spc.x = pullByte(spc), // popx
        0xcf => { // mul
            const result: u16 = @as(u16, spc.a) * spc.y;
            spc.a = @truncate(result);
            spc.y = @truncate(result >> 8);
            setZN(spc, spc.y);
        },
        0xd0 => doBranch(spc, readOpcode(spc), !spc.z), // bne
        0xd4 => spcMovs(spc, adrDpx(spc)),
        0xd5 => spcMovs(spc, adrAbx(spc)),
        0xd6 => spcMovs(spc, adrAby(spc)),
        0xd7 => spcMovs(spc, adrIdy(spc)),
        0xd8 => spcMovsx(spc, adrDp(spc)),
        0xd9 => spcMovsx(spc, adrDpy(spc)),
        0xda => { // movws dp
            var low: u16 = 0;
            const high = adrDpWord(spc, &low);
            _ = read(spc, low);
            write(spc, low, spc.a);
            write(spc, high, spc.y);
        },
        0xdb => spcMovsy(spc, adrDpx(spc)),
        0xdc => { // decy
            spc.y -%= 1;
            setZN(spc, spc.y);
        },
        0xdd => { // movay
            spc.a = spc.y;
            setZN(spc, spc.a);
        },
        0xde => { // cbne dpx, rel
            const val = read(spc, adrDpx(spc)) ^ 0xff;
            const result: c_int = @as(c_int, spc.a) + @as(c_int, val) + 1;
            doBranch(spc, readOpcode(spc), result != 0);
        },
        0xdf => { // daa
            if (spc.a > 0x99 or spc.c) {
                spc.a +%= 0x60;
                spc.c = true;
            }
            if ((spc.a & 0xf) > 9 or spc.h) {
                spc.a +%= 6;
            }
            setZN(spc, spc.a);
        },
        0xe0 => { // clrv
            spc.v = false;
            spc.h = false;
        },
        0xe4 => spcMov(spc, adrDp(spc)),
        0xe5 => spcMov(spc, adrAbs(spc)),
        0xe6 => spcMov(spc, adrInd(spc)),
        0xe7 => spcMov(spc, adrIdx(spc)),
        0xe8 => spcMov(spc, adrImm(spc)),
        0xe9 => spcMovx(spc, adrAbs(spc)),
        0xea => { // not1 abs.bit
            var adr: u16 = 0;
            const bit = adrAbsBit(spc, &adr);
            const result = read(spc, adr) ^ (@as(u8, 1) << @as(u3, @truncate(bit)));
            write(spc, adr, result);
        },
        0xeb => spcMovy(spc, adrDp(spc)),
        0xec => spcMovy(spc, adrAbs(spc)),
        0xed => spc.c = !spc.c, // notc
        0xee => spc.y = pullByte(spc), // popy
        0xef => spc.stopped = true, // sleep
        0xf0 => doBranch(spc, readOpcode(spc), spc.z), // beq
        0xf4 => spcMov(spc, adrDpx(spc)),
        0xf5 => spcMov(spc, adrAbx(spc)),
        0xf6 => spcMov(spc, adrAby(spc)),
        0xf7 => spcMov(spc, adrIdy(spc)),
        0xf8 => spcMovx(spc, adrDp(spc)),
        0xf9 => spcMovx(spc, adrDpy(spc)),
        0xfa => { // movm dp, dp
            var src: u16 = 0;
            const dst = adrDpDp(spc, &src);
            const val = read(spc, src);
            write(spc, dst, val);
        },
        0xfb => spcMovy(spc, adrDpx(spc)),
        0xfc => { // incy
            spc.y +%= 1;
            setZN(spc, spc.y);
        },
        0xfd => { // movya
            spc.y = spc.a;
            setZN(spc, spc.y);
        },
        0xfe => { // dbnzy rel
            spc.y -%= 1;
            doBranch(spc, readOpcode(spc), spc.y != 0);
        },
        0xff => spc.stopped = true, // stop
    }
}
