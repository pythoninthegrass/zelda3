// Tier-A unit tests for src/poly.zig: golden-value checks for the polyhedral
// renderer's leaf logic, using reference outputs captured from the pre-port
// poly.c. g_ram and g_zenv are defined test-locally so the variables.zig
// accessors resolve; the raster buffer window lives at g_ram[0xE800..].

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");
const p = @import("poly.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

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

comptime {
    _ = p.Poly_Divide;
    _ = p.Poly_RunFrame;
    _ = p.Polyhedral_SetShapePointer;
    _ = p.Polyhedral_SetRotationMatrix;
    _ = p.Polyhedral_OperateRotation;
    _ = p.Polyhedral_RotatePoint;
    _ = p.Polyhedral_ProjectPoint;
    _ = p.Polyhedral_DrawPolyhedron;
    _ = p.Polyhedral_SetForegroundColor;
    _ = p.Polyhedral_CalculateCrossProduct;
    _ = p.Polyhedral_SetColorMask;
    _ = p.Polyhedral_EmptyBitMapBuffer;
    _ = p.Polyhedral_DrawFace;
    _ = p.Polyhedral_FillLine;
    _ = p.Polyhedral_SetLeft;
    _ = p.Polyhedral_SetRight;
}

test "Poly_Divide matches reference quotients" {
    const cases = [_]struct { a: t.uint16, b: t.uint16, q: t.uint16 }{
        .{ .a = 100, .b = 7, .q = 14 },
        .{ .a = 32773, .b = 3, .q = 54615 }, // sign16(a) set: -(-32763)/3 truncated
        .{ .a = 64, .b = 256, .q = 0 },      // divisor reduced to 1, dividend to 0
        .{ .a = 0, .b = 1, .q = 0 },
        .{ .a = 65535, .b = 65535, .q = 0 }, // both reduced to 1..0 range
    };
    for (cases) |c| {
        try expectEqual(c.q, p.Poly_Divide(c.a, c.b));
    }
}

test "Polyhedral_SetRotationMatrix produces the golden matrix for a=0xA0 b=0x60" {
    v.poly_a().* = 0xA0;
    v.poly_b().* = 0x60;
    p.Polyhedral_SetRotationMatrix();
    // captured from pre-port poly.c at -O2
    try expectEqual(@as(t.int16, -32), @as(t.int16, @bitCast(v.poly_e0().*)));
    try expectEqual(@as(t.int16, 28), @as(t.int16, @bitCast(v.poly_e1().*)));
    try expectEqual(@as(t.int16, 28), @as(t.int16, @bitCast(v.poly_e2().*)));
    try expectEqual(@as(t.int16, -32), @as(t.int16, @bitCast(v.poly_e3().*)));
    try expectEqual(@as(t.int16, -45), @as(t.int16, @bitCast(v.poly_sin_a().*)));
    try expectEqual(@as(t.int16, -45), @as(t.int16, @bitCast(v.poly_cos_a().*)));
    try expectEqual(@as(t.int16, 45), @as(t.int16, @bitCast(v.poly_sin_b().*)));
    try expectEqual(@as(t.int16, -45), @as(t.int16, @bitCast(v.poly_cos_b().*)));
}

test "Polyhedral_RotatePoint projects a golden vertex" {
    v.poly_a().* = 0xA0;
    v.poly_b().* = 0x60;
    v.poly_var1().* = 0x80;
    p.Polyhedral_SetRotationMatrix();
    v.poly_fromlut_x().* = 40;
    v.poly_fromlut_y().* = 65;
    v.poly_fromlut_z().* = @bitCast(@as(t.int8, -40));
    p.Polyhedral_RotatePoint();
    try expectEqual(@as(t.int16, 0), @as(t.int16, @bitCast(v.poly_f0().*)));
    try expectEqual(@as(t.int16, -525), @as(t.int16, @bitCast(v.poly_f1().*)));
    try expectEqual(@as(t.int16, 149), @as(t.int16, @bitCast(v.poly_f2().*)));
}

test "Polyhedral_FillLine single-byte span XORs both bitplanes" {
    v.poly_raster_dst_ptr().* = 0xe800;
    v.poly_raster_color0().* = 0x1234;
    v.poly_raster_color1().* = 0x5678;
    v.poly_x0_frac().* = (3 << 8) | 0x80;
    v.poly_x1_frac().* = (5 << 8) | 0x80;
    const words: [*]align(1) t.uint16 = @ptrCast(&g_ram[0xe800]);
    var i: usize = 0;
    while (i < 16) : (i += 1)
        words[i] = 0xAAAA;
    p.Polyhedral_FillLine();
    // captured from pre-port poly.c at -O2
    try expectEqual(@as(t.uint16, 0xb2b6), words[0]);
    try expectEqual(@as(t.uint16, 0xb6ba), words[8]);
    try expectEqual(@as(t.uint16, 0x1c1c), v.poly_tmp1().*);
}

test "Polyhedral_FillLine rejects a right-to-left span untouched" {
    v.poly_raster_dst_ptr().* = 0xe800;
    v.poly_raster_color0().* = 0x1234;
    v.poly_raster_color1().* = 0x5678;
    v.poly_x0_frac().* = (20 << 8) | 0x80;
    v.poly_x1_frac().* = (4 << 8) | 0x80;
    const words: [*]align(1) t.uint16 = @ptrCast(&g_ram[0xe800]);
    words[0] = 0xAAAA;
    p.Polyhedral_FillLine();
    try expectEqual(@as(t.uint16, 0xAAAA), words[0]);
}

test "Polyhedral_FillLine multi-byte span fills whole planes" {
    v.poly_raster_dst_ptr().* = 0xe800;
    v.poly_raster_color0().* = 0x1234;
    v.poly_raster_color1().* = 0x5678;
    v.poly_x0_frac().* = (2 << 8) | 0x80;
    v.poly_x1_frac().* = (30 << 8) | 0x80;
    const words: [*]align(1) t.uint16 = @ptrCast(&g_ram[0xe800]);
    var i: usize = 0;
    while (i < 64) : (i += 1)
        words[i] = 0x1111;
    p.Polyhedral_FillLine();
    // captured from pre-port poly.c at -O2
    const golden = [_]t.uint16{ 0x1234, 0x1638, 0x1234, 0x5678, 0x1234 };
    const golden_hi = [_]t.uint16{ 0x1638, 0x1234, 0x5678, 0x1234, 0x5678 };
    var k: usize = 0;
    while (k < 5) : (k += 1) {
        try expectEqual(golden[k], words[k * 8]);
        try expectEqual(golden_hi[k], words[k * 8 + 8]);
    }
}

test "Polyhedral_SetColorMask splits the 32-bit color across two words" {
    p.Polyhedral_SetColorMask(0);
    try expectEqual(@as(t.uint16, 0x00), v.poly_raster_color0().*);
    try expectEqual(@as(t.uint16, 0x00), v.poly_raster_color1().*);
    p.Polyhedral_SetColorMask(15);
    try expectEqual(@as(t.uint16, 0xffff), v.poly_raster_color0().*);
    try expectEqual(@as(t.uint16, 0xffff), v.poly_raster_color1().*);
    p.Polyhedral_SetColorMask(8);
    try expectEqual(@as(t.uint16, 0x0000), v.poly_raster_color0().*);
    try expectEqual(@as(t.uint16, 0xff00), v.poly_raster_color1().*);
}

test "Polyhedral_EmptyBitMapBuffer zeroes 0x800 bytes" {
    var i: usize = 0;
    while (i < 0x800) : (i += 1)
        g_ram[0xE800 + i] = 0x5A;
    p.Polyhedral_EmptyBitMapBuffer();
    try expectEqualSlices(u8, &([_]u8{0} ** 0x800), g_ram[0xE800..0xF000]);
}

test "Polyhedral_CalculateCrossProduct front/back face signs" {
    // a CCW quad (front face): (10,10) (50,10) (50,50) (10,50)
    v.poly_xy_coords()[0] = 8;
    v.poly_xy_coords()[1] = 10;
    v.poly_xy_coords()[2] = 10;
    v.poly_xy_coords()[3] = 50;
    v.poly_xy_coords()[4] = 10;
    v.poly_xy_coords()[5] = 50;
    v.poly_xy_coords()[6] = 50;
    v.poly_xy_coords()[7] = 50;
    const front = p.Polyhedral_CalculateCrossProduct();
    try expectEqual(@as(t.int16, @bitCast(v.poly_tmp0().*)), front);
    // same vertices reversed (back face) flips the sign
    v.poly_xy_coords()[1] = 50;
    v.poly_xy_coords()[2] = 10;
    v.poly_xy_coords()[3] = 10;
    v.poly_xy_coords()[4] = 10;
    v.poly_xy_coords()[5] = 50;
    v.poly_xy_coords()[6] = 50;
    v.poly_xy_coords()[7] = 50;
    const back = p.Polyhedral_CalculateCrossProduct();
    try expectEqual(front, -back);
    try expect(front > 0);
}

test "Polyhedral_OperateRotation writes projected x/y arrays for model 0" {
    v.poly_which_model().* = 0;
    v.poly_config1().* = 255;
    v.poly_a().* = 0xA0;
    v.poly_b().* = 0x60;
    v.poly_base_x().* = 32;
    v.poly_base_y().* = 32;
    p.Polyhedral_SetShapePointer();
    p.Polyhedral_SetRotationMatrix();
    p.Polyhedral_OperateRotation();
    // the octahedron's six vertices project to distinct screen points
    var seen: [6]u8 = undefined;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        seen[i] = v.poly_arr_x()[i] ^ v.poly_arr_y()[i];
    }
    // all pairs differ from their neighbours
    try expect(v.poly_arr_x()[0] != v.poly_arr_x()[1] or v.poly_arr_y()[0] != v.poly_arr_y()[1]);
}
