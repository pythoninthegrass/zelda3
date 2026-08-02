// Tier-B differential test for snes/input.zig: links the pre-port snes/input.c
// (symbols renamed with a c_ prefix via objcopy, wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// state over fixed-seed randomized input streams.
//
// The Input struct layout mirrors snes/input.h (C keeps ownership of it;
// snes.c pokes fields directly). The harness runs randomized sequences of
// reset / latch-toggle / cycle / read against both flavours on identical
// seeds and byte-compares the post-state plus every read's return value.
// input.zig is not @import'ed here: its exports come from the linked object,
// so the test only needs the extern declarations and the mirrored layout.

const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// Mirrors struct Input in snes/input.h; Snes is opaque (input.c only stores
// the back-pointer).
pub const Input = extern struct {
    snes: ?*anyopaque,
    type: u8,
    latchLine: bool,
    currentState: u16,
    latchedState: u16,
};

// The Zig port's exported symbols resolve against the linked input.o (the
// ported module); the C reference via the c_* externs (objcopy-renamed).
extern fn input_init(snes: ?*anyopaque) ?*Input;
extern fn input_free(input: ?*Input) void;
extern fn input_reset(input: *Input) void;
extern fn input_cycle(input: *Input) void;
extern fn input_read(input: *Input) u8;

extern fn c_input_init(snes: ?*anyopaque) ?*Input;
extern fn c_input_free(input: ?*Input) void;
extern fn c_input_reset(input: *Input) void;
extern fn c_input_cycle(input: *Input) void;
extern fn c_input_read(input: *Input) u8;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x1a2b3c4d);
    return prng.?.random();
}

// Run one randomized op stream against both flavours and diff the post-state.
fn runStreamAndDiff(ops: []const u8, initial: Input) !void {
    var c_inp = initial;
    var z_inp = initial;
    for (ops, 0..) |op, i| {
        const c_ret: u8 = switch (op % 4) {
            0 => blk: {
                c_input_reset(&c_inp);
                break :blk 0;
            },
            1 => blk: {
                c_inp.latchLine = (op & 2) != 0;
                c_input_cycle(&c_inp);
                break :blk 0;
            },
            2 => blk: {
                c_inp.currentState = (@as(u16, op) << 8) | @as(u16, op *% 3);
                c_input_cycle(&c_inp);
                break :blk 0;
            },
            else => c_input_read(&c_inp),
        };
        const z_ret: u8 = switch (op % 4) {
            0 => blk: {
                input_reset(&z_inp);
                break :blk 0;
            },
            1 => blk: {
                z_inp.latchLine = (op & 2) != 0;
                input_cycle(&z_inp);
                break :blk 0;
            },
            2 => blk: {
                z_inp.currentState = (@as(u16, op) << 8) | @as(u16, op *% 3);
                input_cycle(&z_inp);
                break :blk 0;
            },
            else => input_read(&z_inp),
        };
        if (c_ret != z_ret) {
            std.debug.print("op {d} (kind {d}): c read {d}, z read {d}\n", .{ i, op % 4, c_ret, z_ret });
            return error.ReadMismatch;
        }
    }
    const c_bytes = std.mem.asBytes(&c_inp);
    const z_bytes = std.mem.asBytes(&z_inp);
    if (!std.mem.eql(u8, c_bytes, z_bytes)) {
        for (c_bytes, 0..) |b, i| {
            if (b != z_bytes[i]) {
                std.debug.print("post-state byte {d}: c=0x{X:0>2} z=0x{X:0>2}\n", .{ i, b, z_bytes[i] });
                break;
            }
        }
        return error.StateMismatch;
    }
}

test "diff input lifecycle over randomized op streams" {
    var iter: usize = 0;
    while (iter < 4000) : (iter += 1) {
        var initial: Input = .{
            .snes = null,
            .type = rnd().int(u8),
            .latchLine = rnd().boolean(),
            .currentState = rnd().int(u16),
            .latchedState = rnd().int(u16),
        };
        var ops_buf: [64]u8 = undefined;
        const n = rnd().intRangeAtMost(usize, 1, ops_buf.len);
        for (ops_buf[0..n]) |*op| op.* = rnd().int(u8);
        try runStreamAndDiff(ops_buf[0..n], initial);
        // keep the compiler from proving the loop body dead
        initial.latchedState ^= 1;
    }
}

test "diff init/free allocation behaviour" {
    var fake_snes: u8 = 0;
    const z_inp = input_init(@ptrCast(&fake_snes)) orelse return error.OutOfMemory;
    defer input_free(z_inp);
    const c_inp = c_input_init(@ptrCast(&fake_snes)) orelse return error.OutOfMemory;
    defer c_input_free(c_inp);
    try expectEqual(c_inp.type, z_inp.type);
    try expectEqual(c_inp.currentState, z_inp.currentState);
    try expectEqual(@as(?*anyopaque, @ptrCast(c_inp.snes)), @as(?*anyopaque, @ptrCast(z_inp.snes)));
}
