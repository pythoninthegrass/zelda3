// Tier-A unit tests for snes/spc.zig: golden-value checks for spc_init,
// spc_reset, flag pack/unpack (getFlags/setFlags round-trip via spc_saveload),
// cycle counts, and representative opcode behaviour.
//
// Tests use only the exported C-ABI functions plus the Spc struct layout
// (both from spc_mod). Bus reads/writes are serviced by a flat 64 KiB RAM
// buffer wired through tiny apu_cpuRead/apu_cpuWrite stubs defined below.

const std = @import("std");
const spc_mod = @import("spc.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Spc = spc_mod.Spc;

// Flat 64 KiB bus RAM used by all tests (re-zeroed per test via freshSpc).
var bus_ram: [0x10000]u8 = undefined;

// C-ABI stubs satisfying apu_cpuRead/apu_cpuWrite — spc.zig calls these
// through its extern declarations.
export fn apu_cpuRead(apu: ?*anyopaque, adr: u16) callconv(.c) u8 {
    _ = apu;
    return bus_ram[adr];
}

export fn apu_cpuWrite(apu: ?*anyopaque, adr: u16, val: u8) callconv(.c) void {
    _ = apu;
    bus_ram[adr] = val;
}

fn freshSpc() *Spc {
    bus_ram = [_]u8{0} ** 0x10000;
    // Place a reset vector (0xfffe/0xffff) pointing to address 0x0200.
    bus_ram[0xfffe] = 0x00;
    bus_ram[0xffff] = 0x02;
    const s = spc_mod.spc_init(null) orelse unreachable;
    spc_mod.spc_reset(s);
    return s;
}

test "spc_init returns a non-null pointer" {
    const s = spc_mod.spc_init(null) orelse return error.OutOfMemory;
    defer spc_mod.spc_free(s);
    try expectEqual(@as(@TypeOf(s.apu), null), s.apu);
}

test "spc_reset zeroes registers and reads reset vector" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    try expectEqual(@as(u8, 0), s.a);
    try expectEqual(@as(u8, 0), s.x);
    try expectEqual(@as(u8, 0), s.y);
    try expectEqual(@as(u8, 0), s.sp);
    try expectEqual(@as(u16, 0x0200), s.pc);
    try expectEqual(false, s.c);
    try expectEqual(false, s.z);
    try expectEqual(false, s.v);
    try expectEqual(false, s.n);
    try expectEqual(false, s.i);
    try expectEqual(false, s.h);
    try expectEqual(false, s.p);
    try expectEqual(false, s.b);
    try expectEqual(false, s.stopped);
    try expectEqual(@as(u8, 0), s.cyclesUsed);
}

test "spc_runOpcode nop (0x00) costs 2 cycles" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0x00; // nop
    const cycles = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(c_int, 2), cycles);
    try expectEqual(@as(u16, 0x0201), s.pc);
}

test "spc_runOpcode when stopped returns 1" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.stopped = true;
    const cycles = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(c_int, 1), cycles);
    try expectEqual(@as(u16, 0x0200), s.pc);
}

test "0xff stop halts execution" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0xff;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(true, s.stopped);
}

test "0x60 clrc clears carry flag" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.c = true;
    bus_ram[0x0200] = 0x60;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(false, s.c);
}

test "0x80 setc sets carry flag" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0x80;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(true, s.c);
}

test "0xed notc toggles carry" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.c = false;
    bus_ram[0x0200] = 0xed;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(true, s.c);
    s.pc = 0x0200;
    bus_ram[0x0200] = 0xed;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(false, s.c);
}

test "0xe8 mov imm loads immediate into A and sets ZN" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0xe8; // mov A, imm
    bus_ram[0x0201] = 0x42;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0x42), s.a);
    try expectEqual(false, s.z);
    try expectEqual(false, s.n);
}

test "0xe8 mov imm with 0 sets Z flag" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.a = 0x55;
    bus_ram[0x0200] = 0xe8;
    bus_ram[0x0201] = 0x00;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0), s.a);
    try expectEqual(true, s.z);
    try expectEqual(false, s.n);
}

test "0x88 adc imm adds with carry" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.a = 0x10;
    s.c = true;
    bus_ram[0x0200] = 0x88; // adc A, imm
    bus_ram[0x0201] = 0x20;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0x31), s.a);
    try expectEqual(false, s.c);
}

test "0x88 adc imm produces carry out" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.a = 0xff;
    s.c = false;
    bus_ram[0x0200] = 0x88;
    bus_ram[0x0201] = 0x01;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0x00), s.a);
    try expectEqual(true, s.c);
    try expectEqual(true, s.z);
}

test "0xcd movx imm loads X" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0xcd;
    bus_ram[0x0201] = 0xab;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0xab), s.x);
    try expectEqual(false, s.z);
    try expectEqual(true, s.n);
}

test "0x8d movy imm loads Y" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0x8d;
    bus_ram[0x0201] = 0x00;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0), s.y);
    try expectEqual(true, s.z);
}

test "0x5f jmp abs jumps to absolute address" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    bus_ram[0x0200] = 0x5f;
    bus_ram[0x0201] = 0x34;
    bus_ram[0x0202] = 0x12;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u16, 0x1234), s.pc);
}

test "0x3f call abs pushes PC and jumps" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.sp = 0xef;
    bus_ram[0x0200] = 0x3f;
    bus_ram[0x0201] = 0x00;
    bus_ram[0x0202] = 0x03;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u16, 0x0300), s.pc);
    // Return address 0x0203 should be on the stack (pushed high then low).
    try expectEqual(@as(u8, 0x02), bus_ram[0x01ef]); // high byte
    try expectEqual(@as(u8, 0x03), bus_ram[0x01ee]); // low byte
    try expectEqual(@as(u8, 0xed), s.sp);
}

test "0x6f ret pops PC" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.sp = 0xed;
    bus_ram[0x01ee] = 0x78;
    bus_ram[0x01ef] = 0x56;
    bus_ram[0x0200] = 0x6f;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u16, 0x5678), s.pc);
    try expectEqual(@as(u8, 0xef), s.sp);
}

test "0x10 bpl taken branch adds 2 extra cycles" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.n = false;
    bus_ram[0x0200] = 0x10;
    bus_ram[0x0201] = 0x05; // +5
    const cycles = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u16, 0x0207), s.pc); // 0x0202 + 5
    try expectEqual(@as(c_int, 4), cycles); // 2 base + 2 taken
}

test "0x10 bpl not-taken branch does not add extra cycles" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.n = true;
    bus_ram[0x0200] = 0x10;
    bus_ram[0x0201] = 0x05;
    const cycles = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u16, 0x0202), s.pc);
    try expectEqual(@as(c_int, 2), cycles);
}

test "0x20 clrp / 0x40 setp toggle page flag" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.p = true;
    bus_ram[0x0200] = 0x20; // clrp
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(false, s.p);

    bus_ram[0x0201] = 0x40; // setp
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(true, s.p);
}

test "0xcf mul A*Y -> YA" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.a = 0x10;
    s.y = 0x20;
    bus_ram[0x0200] = 0xcf;
    _ = spc_mod.spc_runOpcode(s);
    try expectEqual(@as(u8, 0x00), s.a);
    try expectEqual(@as(u8, 0x02), s.y);
}

test "spc_saveload covers bytes a..cyclesUsed-1 (exclusive)" {
    const s = freshSpc();
    defer spc_mod.spc_free(s);
    s.a = 0xaa;
    var seen: struct { ptr: ?*anyopaque = null, size: usize = 0 } = .{};
    const cb = struct {
        fn run(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
            const p: *@TypeOf(seen) = @ptrCast(@alignCast(ctx));
            p.ptr = data;
            p.size = data_size;
        }
    }.run;
    spc_mod.spc_saveload(s, cb, &seen);
    try expectEqual(@as(?*anyopaque, @ptrCast(&s.a)), seen.ptr);
    const expected_size = @offsetOf(Spc, "cyclesUsed") - @offsetOf(Spc, "a");
    try expectEqual(expected_size, seen.size);
}
