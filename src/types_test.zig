// Tier-A unit tests for src/types.zig. The punning helpers are exercised
// against an odd-offset byte buffer (mirroring unaligned g_ram accesses like
// WORD(sram[0x3e5]) and BYTE(dungeon_room_index)) plus struct fields and
// wider lvalues, verifying byte-identical reinterpretation both directions
// (read through the alias, write through the alias).

const std = @import("std");
const t = @import("types.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

fn expectBytes(expected: []const u8, actual: []const u8) !void {
    try expectEqualSlices(u8, expected, actual);
}

test "typedefs match the C widths" {
    try expectEqual(1, @sizeOf(t.uint8));
    try expectEqual(1, @sizeOf(t.int8));
    try expectEqual(2, @sizeOf(t.uint16));
    try expectEqual(2, @sizeOf(t.int16));
    try expectEqual(4, @sizeOf(t.uint32));
    try expectEqual(4, @sizeOf(t.int32));
    try expectEqual(8, @sizeOf(t.uint64));
    try expectEqual(8, @sizeOf(t.int64));
    try expectEqual(@sizeOf(c_uint), @sizeOf(t.uint));
}

test "build-time config constants" {
    try expectEqual(96, t.kPpuExtraLeftRight);
    try expectEqual(false, t.kDebugFlag);
}

test "byte/hibyte/word/dword reinterpret unaligned storage little-endian" {
    // .{ 78 56 34 12 ef cd ab 90 } — bytes 1..2, 4..7 sit at odd addresses.
    var ram: [8]u8 = .{ 0x78, 0x56, 0x34, 0x12, 0xef, 0xcd, 0xab, 0x90 };
    try expectEqual(@as(t.uint8, 0x78), t.byte(&ram[0]).*);
    try expectEqual(@as(t.uint8, 0x56), t.hibyte(&ram[0]).*);
    try expectEqual(@as(t.uint16, 0x3456), t.word(&ram[1]).*);
    try expectEqual(@as(t.uint32, 0x90abcdef), t.dword(&ram[4]).*);
    try expectEqual(@as(t.uint32, 0xabcdef), t.load24(&ram[4]));
}

test "writes through the aliases land in the underlying bytes" {
    var ram: [8]u8 = @splat(0);
    t.byte(&ram[3]).* = 0xa5;
    t.hibyte(&ram[3]).* = 0x5a;
    try expectBytes(&.{ 0, 0, 0, 0xa5, 0x5a, 0, 0, 0 }, &ram);
    t.word(&ram[1]).* = 0xbeef;
    try expectBytes(&.{ 0, 0xef, 0xbe, 0xa5, 0x5a, 0, 0, 0 }, &ram);
    t.dword(&ram[3]).* = 0x11223344;
    try expectBytes(&.{ 0, 0xef, 0xbe, 0x44, 0x33, 0x22, 0x11, 0 }, &ram);
}

test "punning over wider lvalues matches the C macros" {
    var v16: t.uint16 = 0x1234;
    try expectEqual(@as(t.uint8, 0x34), t.byte(&v16).*);
    try expectEqual(@as(t.uint8, 0x12), t.hibyte(&v16).*);
    t.hibyte(&v16).* = 0xff;
    try expectEqual(@as(t.uint16, 0xff34), v16);

    var v32: t.uint32 = 0xdeadbeef;
    try expectEqual(@as(t.uint16, 0xbeef), t.word(&v32).*);
    t.byte(&v32).* = 0;
    try expectEqual(@as(t.uint32, 0xdeadbe00), v32);

    // HIBYTE over a byte array aliases element 1, as in HIBYTE(dst[i]).
    var dst: [2]t.uint16 = .{ 0, 0 };
    t.hibyte(&dst[0]).* = 0xcc;
    try expectEqual(@as(t.uint16, 0xcc00), dst[0]);
}

test "sign/abs/min/max/swap16 match the C inline semantics" {
    try expectEqual(@as(t.uint8, 0x80), t.sign8(0xff));
    try expectEqual(@as(t.uint8, 0), t.sign8(0x7f));
    try expectEqual(@as(t.uint16, 0x8000), t.sign16(0xffff));
    try expectEqual(@as(t.uint16, 0), t.sign16(0x7fff));

    try expectEqual(@as(t.uint8, 1), t.abs8(0xff)); // -1 wraps to 1, like C
    try expectEqual(@as(t.uint8, 0x80), t.abs8(0x80)); // -128 stays 0x80
    try expectEqual(@as(t.uint8, 42), t.abs8(42));
    try expectEqual(@as(t.uint16, 1), t.abs16(0xffff));
    try expectEqual(@as(t.uint16, 0x8000), t.abs16(0x8000));
    try expectEqual(@as(t.uint16, 42), t.abs16(42));

    try expectEqual(@as(c_int, -3), t.IntMin(-3, 7));
    try expectEqual(@as(c_int, 7), t.IntMax(-3, 7));
    try expectEqual(@as(t.uint, 3), t.UintMin(3, 7));
    try expectEqual(@as(t.uint, 7), t.UintMax(3, 7));

    try expectEqual(@as(t.uint16, 0x3412), t.swap16(0x1234));
}

test "arraysize/countof/xy" {
    const arr: [17]t.uint8 = undefined;
    try expectEqual(17, t.arraysize(arr));
    try expectEqual(17, t.countof(arr));
    try expectEqual(64 * 5 + 3, t.xy(3, 5));
}

test "struct layouts match the C ABI" {
    // Sizes and member offsets are pinned at comptime inside types.zig;
    // here the structs are round-tripped through raw bytes the way the C
    // side lays them out (no padding, declaration order).
    try expectEqual(4, @sizeOf(t.Point16U));
    try expectEqual(2, @sizeOf(t.PointU8));
    try expectEqual(4, @sizeOf(t.Pair16U));
    try expectEqual(2, @sizeOf(t.PairU8));
    try expectEqual(4, @sizeOf(t.ProjectSpeedRet));
    try expectEqual(4, @sizeOf(t.OamEnt));
    try expectEqual(@sizeOf(?[*]const t.uint8) + @sizeOf(usize), @sizeOf(t.MemBlk));

    var ent: t.OamEnt = .{ .x = 1, .y = 2, .charnum = 3, .flags = 4 };
    try expectBytes(&.{ 1, 2, 3, 4 }, @ptrCast(&ent));

    var pair: t.Pair16U = .{ .a = 0x1122, .b = 0x3344 };
    try expectBytes(&.{ 0x22, 0x11, 0x44, 0x33 }, @ptrCast(&pair));
}
