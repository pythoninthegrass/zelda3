// Tier-A unit tests for snes/input.zig: golden-value checks for the
// controller serial-shift model (init/reset/latch/read), using reference
// outputs captured from the pre-port snes/input.c. The Input layout mirrors
// snes/input.h; the tests drive it through the exported C-ABI functions only.

const std = @import("std");
const input = @import("input.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Input = input.Input;

test "input_init stores snes pointer and seeds type/currentState" {
    var fake_snes: u8 = 0;
    const inp = input.input_init(@ptrCast(&fake_snes)) orelse return error.OutOfMemory;
    defer input.input_free(inp);
    try expectEqual(@as(u8, 1), inp.type);
    try expectEqual(@as(u16, 0), inp.currentState);
    try expectEqual(@as(?*anyopaque, @ptrCast(&fake_snes)), @as(?*anyopaque, @ptrCast(inp.snes)));
}

test "input_reset clears latchLine and latchedState" {
    var inp: Input = .{
        .snes = null,
        .type = 1,
        .latchLine = true,
        .currentState = 0xBEEF,
        .latchedState = 0xCAFE,
    };
    input.input_reset(&inp);
    try expectEqual(false, inp.latchLine);
    try expectEqual(@as(u16, 0), inp.latchedState);
    // reset leaves type/currentState alone
    try expectEqual(@as(u8, 1), inp.type);
    try expectEqual(@as(u16, 0xBEEF), inp.currentState);
}

test "input_cycle latches currentState only while latchLine is high" {
    var inp: Input = .{
        .snes = null,
        .type = 1,
        .latchLine = false,
        .currentState = 0x1234,
        .latchedState = 0xAAAA,
    };
    input.input_cycle(&inp);
    try expectEqual(@as(u16, 0xAAAA), inp.latchedState);

    inp.latchLine = true;
    input.input_cycle(&inp);
    try expectEqual(@as(u16, 0x1234), inp.latchedState);

    // still high: keeps re-latching the live state every cycle
    inp.currentState = 0x5678;
    input.input_cycle(&inp);
    try expectEqual(@as(u16, 0x5678), inp.latchedState);
}

test "input_read shifts LSB-first and shifts 1s in at the top" {
    var inp: Input = .{
        .snes = null,
        .type = 1,
        .latchLine = false,
        .currentState = 0,
        .latchedState = 0xB38D,
    };
    // 0xB38D = 0b1011001110001101; reads come out LSB first, then the
    // register fills with 1s (disconnected-pad behaviour after bit 15).
    const expected = [16]u8{ 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1 };
    for (expected) |bit| {
        try expectEqual(bit, input.input_read(&inp));
    }
    try expectEqual(@as(u16, 0xFFFF), inp.latchedState);
    // every further read returns 1
    try expectEqual(@as(u8, 1), input.input_read(&inp));
    try expectEqual(@as(u16, 0xFFFF), inp.latchedState);
}

test "input_read returns only the low bit even with bit 1 set" {
    var inp: Input = .{
        .snes = null,
        .type = 1,
        .latchLine = false,
        .currentState = 0,
        .latchedState = 0x0006,
    };
    try expectEqual(@as(u8, 0), input.input_read(&inp));
    try expectEqual(@as(u16, 0x8003), inp.latchedState);
    try expectEqual(@as(u8, 1), input.input_read(&inp));
    try expectEqual(@as(u8, 1), input.input_read(&inp));
}

test "full latch-then-read frame: 16-bit pad report over $4016" {
    var inp: Input = .{
        .snes = null,
        .type = 1,
        .latchLine = true,
        .currentState = 0x801F, // B, Y, Select, Start, Up bits all present
        .latchedState = 0,
    };
    input.input_cycle(&inp);
    inp.latchLine = false;
    var report: u16 = 0;
    var i: u5 = 0;
    while (i < 16) : (i += 1) {
        report |= @as(u16, input.input_read(&inp)) << @intCast(i);
    }
    try expectEqual(@as(u16, 0x801F), report);
}
