// Tier-B differential test for src/poly.zig: links the pre-port poly.c
// (symbols renamed with a c_ prefix via the preprocessor (-D), wired in build.zig's
// difftest step) against the ported Zig module and diffs their observable
// g_ram state over fixed-seed randomized inputs.
//
// Every Poly_* function is a pure g_ram state machine: inputs are the
// poly_a/poly_b/poly_which_model/poly_config1 scalars and the poly_f0..f2 /
// poly_xy_coords / poly_x{0,1}_* scratch cells; outputs are writes back into
// g_ram (projection arrays, raster colors, and the 0x800-byte polyhedral
// buffer). The harness seeds identical inputs, snapshots, runs the C
// reference, captures the post-state, restores, runs the Zig port, and
// byte-compares the two post-states. g_ram and g_zenv are defined here so
// both flavours share one buffer.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

// Test-local definitions of the externs poly.zig and the renamed C object
// reference. Same shape as the C side: extern uint8 g_ram[131072].
export var g_ram: [0x20000]u8 = undefined;
export var g_zenv: v.ZeldaEnv = .{
    .ram = null,
    .sram = null,
    .vram = null,
    .ppu = null,
    .player = null,
    .dma = null,
    .dialogue_blk = .{ .ptr = null, .size = 0 },
    .dialogue_font_blk = .{ .ptr = null, .size = 0 },
    .dialogue_flags = 0,
};

// The Zig port's exported symbols resolve against the linked poly.o (the
// ported module), the C reference via the c_* externs (preprocessor-renamed).
extern fn Poly_Divide(a: t.uint16, b: t.uint16) t.uint16;
extern fn Poly_RunFrame() void;
extern fn Polyhedral_SetShapePointer() void;
extern fn Polyhedral_SetRotationMatrix() void;
extern fn Polyhedral_OperateRotation() void;
extern fn Polyhedral_RotatePoint() void;
extern fn Polyhedral_ProjectPoint() void;
extern fn Polyhedral_DrawPolyhedron() void;
extern fn Polyhedral_SetForegroundColor() void;
extern fn Polyhedral_CalculateCrossProduct() t.int16;
extern fn Polyhedral_SetColorMask(c: c_int) void;
extern fn Polyhedral_EmptyBitMapBuffer() void;
extern fn Polyhedral_DrawFace() void;
extern fn Polyhedral_FillLine() void;
extern fn Polyhedral_SetLeft() bool;
extern fn Polyhedral_SetRight() bool;

// Pre-port C reference (poly.c), symbols renamed to c_<name> by the preprocessor.
extern fn c_Poly_Divide(a: t.uint16, b: t.uint16) t.uint16;
extern fn c_Poly_RunFrame() void;
extern fn c_Polyhedral_SetShapePointer() void;
extern fn c_Polyhedral_SetRotationMatrix() void;
extern fn c_Polyhedral_OperateRotation() void;
extern fn c_Polyhedral_RotatePoint() void;
extern fn c_Polyhedral_ProjectPoint() void;
extern fn c_Polyhedral_DrawPolyhedron() void;
extern fn c_Polyhedral_SetForegroundColor() void;
extern fn c_Polyhedral_CalculateCrossProduct() t.int16;
extern fn c_Polyhedral_SetColorMask(c: c_int) void;
extern fn c_Polyhedral_EmptyBitMapBuffer() void;
extern fn c_Polyhedral_DrawFace() void;
extern fn c_Polyhedral_FillLine() void;
extern fn c_Polyhedral_SetLeft() bool;
extern fn c_Polyhedral_SetRight() bool;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x90d1f3);
    return prng.?.random();
}

var seed: [0x20000]u8 = undefined;
var c_post: [0x20000]u8 = undefined;

fn seedRam() void {
    @memcpy(&g_ram, &seed);
}

fn captureSeed() void {
    @memcpy(&seed, &g_ram);
}

// Run `cFn` then `zFn` against identical seeded g_ram, then byte-compare the
// whole buffer so any write outside the expected windows is caught.
fn runAndDiff(context: []const u8, cFn: anytype, zFn: anytype) !void {
    captureSeed();
    seedRam();
    cFn();
    @memcpy(&c_post, &g_ram);
    seedRam();
    zFn();
    if (!std.mem.eql(u8, &c_post, &g_ram)) {
        var i: usize = 0;
        while (i < 0x20000) : (i += 1) {
            if (c_post[i] != g_ram[i]) {
                std.debug.print("{s}: g_ram[0x{X:0>5}] c=0x{X:0>2} z=0x{X:0>2}\n", .{ context, i, c_post[i], g_ram[i] });
                break;
            }
        }
        return error.RamMismatch;
    }
}

test "diff Poly_Divide over randomized dividend/divisor pairs" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        const a = rnd().int(t.uint16);
        // keep divisors in the rasterizer's working range; zero would fault
        // identically on both sides and tells us nothing
        const b = rnd().intRangeAtMost(t.uint16, 1, 2048);
        captureSeed();
        seedRam();
        const rc = c_Poly_Divide(a, b);
        const c_tmp0 = v.poly_tmp0().*;
        const c_tmp1 = v.poly_tmp1().*;
        seedRam();
        const rz = Poly_Divide(a, b);
        try expectEqual(rc, rz);
        try expectEqual(c_tmp0, v.poly_tmp0().*);
        try expectEqual(c_tmp1, v.poly_tmp1().*);
    }
}

test "diff Polyhedral_SetRotationMatrix over random angle pairs" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        v.poly_a().* = rnd().int(t.uint8);
        v.poly_b().* = rnd().int(t.uint8);
        try runAndDiff("SetRotationMatrix", c_Polyhedral_SetRotationMatrix, Polyhedral_SetRotationMatrix);
    }
}

test "diff Polyhedral_RotatePoint over randomized points and matrices" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        v.poly_a().* = rnd().int(t.uint8);
        v.poly_b().* = rnd().int(t.uint8);
        v.poly_var1().* = rnd().int(t.uint16);
        v.poly_fromlut_x().* = rnd().int(t.uint8);
        v.poly_fromlut_y().* = rnd().int(t.uint8);
        v.poly_fromlut_z().* = rnd().int(t.uint8);
        try runAndDiff("RotatePoint", struct {
            fn f() void {
                c_Polyhedral_SetRotationMatrix();
                c_Polyhedral_RotatePoint();
            }
        }.f, struct {
            fn f() void {
                Polyhedral_SetRotationMatrix();
                Polyhedral_RotatePoint();
            }
        }.f);
    }
}

test "diff Polyhedral_OperateRotation for both models over random angles" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        v.poly_which_model().* = rnd().intRangeAtMost(t.uint8, 0, 1);
        v.poly_config1().* = rnd().int(t.uint8);
        v.poly_a().* = rnd().int(t.uint8);
        v.poly_b().* = rnd().int(t.uint8);
        v.poly_base_x().* = rnd().int(t.uint8);
        v.poly_base_y().* = rnd().int(t.uint8);
        try runAndDiff("OperateRotation", struct {
            fn f() void {
                c_Polyhedral_SetShapePointer();
                c_Polyhedral_SetRotationMatrix();
                c_Polyhedral_OperateRotation();
            }
        }.f, struct {
            fn f() void {
                Polyhedral_SetShapePointer();
                Polyhedral_SetRotationMatrix();
                Polyhedral_OperateRotation();
            }
        }.f);
    }
}

test "diff Poly_RunFrame (cull + rasterize) over both models and random angles" {
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        v.poly_which_model().* = rnd().intRangeAtMost(t.uint8, 0, 1);
        v.poly_config1().* = rnd().int(t.uint8);
        v.poly_a().* = rnd().int(t.uint8);
        v.poly_b().* = rnd().int(t.uint8);
        v.poly_base_x().* = rnd().intRangeAtMost(t.uint8, 16, 64);
        v.poly_base_y().* = rnd().intRangeAtMost(t.uint8, 16, 64);
        @memset(g_ram[0xE800..0xF000], 0);
        try runAndDiff("RunFrame", c_Poly_RunFrame, Poly_RunFrame);
    }
}

test "diff Polyhedral_SetColorMask over all 16 color indices" {
    var c_idx: c_int = 0;
    while (c_idx < 16) : (c_idx += 1) {
        const ci = c_idx;
        captureSeed();
        seedRam();
        c_Polyhedral_SetColorMask(ci);
        const c0 = v.poly_raster_color0().*;
        const c1 = v.poly_raster_color1().*;
        seedRam();
        Polyhedral_SetColorMask(ci);
        try expectEqual(c0, v.poly_raster_color0().*);
        try expectEqual(c1, v.poly_raster_color1().*);
    }
}

test "diff Polyhedral_SetForegroundColor over both models and random tmp0/config1" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        v.poly_which_model().* = rnd().intRangeAtMost(t.uint8, 0, 1);
        v.poly_config1().* = rnd().int(t.uint8);
        v.poly_tmp0().* = rnd().int(t.uint16);
        try runAndDiff("SetForegroundColor", c_Polyhedral_SetForegroundColor, Polyhedral_SetForegroundColor);
    }
}

test "diff Polyhedral_CalculateCrossProduct over random xy coords" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        var j: usize = 0;
        while (j < 8) : (j += 1)
            v.poly_xy_coords()[j] = rnd().int(t.uint8);
        captureSeed();
        seedRam();
        const rc = c_Polyhedral_CalculateCrossProduct();
        const c_tmp0 = v.poly_tmp0().*;
        seedRam();
        const rz = Polyhedral_CalculateCrossProduct();
        try expectEqual(rc, rz);
        try expectEqual(c_tmp0, v.poly_tmp0().*);
    }
}

test "diff Polyhedral_FillLine over random spans" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        v.poly_raster_dst_ptr().* = 0xe800 + rnd().intRangeAtMost(t.uint16, 0, 0x700);
        v.poly_raster_color0().* = rnd().int(t.uint16);
        v.poly_raster_color1().* = rnd().int(t.uint16);
        // x positions within one raster line (0..31 bytes)
        const x0 = rnd().intRangeAtMost(t.uint16, 0, 31);
        const x1 = rnd().intRangeAtMost(t.uint16, 0, 31);
        v.poly_x0_frac().* = (x0 << 8) | 0x80;
        v.poly_x1_frac().* = (x1 << 8) | 0x80;
        var j: usize = 0;
        while (j < 0x400) : (j += 1)
            g_ram[0xe800 + j] = rnd().int(t.uint8);
        try runAndDiff("FillLine", c_Polyhedral_FillLine, Polyhedral_FillLine);
    }
}

test "diff Polyhedral_EmptyBitMapBuffer zeroes the raster buffer" {
    var j: usize = 0;
    while (j < 0x800) : (j += 1)
        g_ram[0xE800 + j] = 0xAB;
    Polyhedral_EmptyBitMapBuffer();
    try expectEqualSlices(u8, &([_]u8{0} ** 0x800), g_ram[0xE800..0xF000]);
}
