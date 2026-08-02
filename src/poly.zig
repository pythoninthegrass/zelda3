// Port of src/poly.c: the polyhedral/triforce intro renderer — shape
// pointer/rotation-matrix setup, per-vertex 3D rotation and projection,
// backface culling via cross product, and the span rasterizer that XORs
// faces into polyhedral_buffer. Every exported symbol keeps its exact C-ABI
// name and signature so the remaining .c callers (attract.c, ending.c)
// link unchanged. All game state lives in g_ram (variables.zig accessors),
// byte-for-byte where the original 65816 code and the RAM-compare oracle
// expect it.
//
// The C leans on int16 wraparound in the rotation-matrix multiply-accumulate
// (poly_e0..poly_e3) and in Polyhedral_CalculateCrossProduct; the port uses
// explicit wrapping ops (*%, +%, -%) so ReleaseFast codegen stays identical.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

const kPolySinCos = [320]t.int8{
    0,   2,   3,   5,   6,   8,   9,   11,  12,  14,  16,  17,  19,  20,  22,  23,
    24,  26,  27,  29,  30,  32,  33,  34,  36,  37,  38,  39,  41,  42,  43,  44,
    45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  56,  57,  58,  59,
    59,  60,  60,  61,  61,  62,  62,  62,  63,  63,  63,  64,  64,  64,  64,  64,
    64,  64,  64,  64,  64,  64,  63,  63,  63,  62,  62,  62,  61,  61,  60,  60,
    59,  59,  58,  57,  56,  56,  55,  54,  53,  52,  51,  50,  49,  48,  47,  46,
    45,  44,  43,  42,  41,  39,  38,  37,  36,  34,  33,  32,  30,  29,  27,  26,
    24,  23,  22,  20,  19,  17,  16,  14,  12,  11,  9,   8,   6,   5,   3,   2,
    0,   -2,  -3,  -5,  -6,  -8,  -9,  -11, -12, -14, -16, -17, -19, -20, -22, -23,
    -24, -26, -27, -29, -30, -32, -33, -34, -36, -37, -38, -39, -41, -42, -43, -44,
    -45, -46, -47, -48, -49, -50, -51, -52, -53, -54, -55, -56, -56, -57, -58, -59,
    -59, -60, -60, -61, -61, -62, -62, -62, -63, -63, -63, -64, -64, -64, -64, -64,
    -64, -64, -64, -64, -64, -64, -63, -63, -63, -62, -62, -62, -61, -61, -60, -60,
    -59, -59, -58, -57, -56, -56, -55, -54, -53, -52, -51, -50, -49, -48, -47, -46,
    -45, -44, -43, -42, -41, -39, -38, -37, -36, -34, -33, -32, -30, -29, -27, -26,
    -24, -23, -22, -20, -19, -17, -16, -14, -12, -11, -9,  -8,  -6,  -5,  -3,  -2,
    0,   2,   3,   5,   6,   8,   9,   11,  12,  14,  16,  17,  19,  20,  22,  23,
    24,  26,  27,  29,  30,  32,  33,  34,  36,  37,  38,  39,  41,  42,  43,  44,
    45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  56,  57,  58,  59,
    59,  60,  60,  61,  61,  62,  62,  62,  63,  63,  63,  64,  64,  64,  64,  64,
};

const Vertex3 = extern struct {
    x: t.int8,
    y: t.int8,
    z: t.int8,
};

const kPoly0_Vtx = [6]Vertex3{
    .{ .x = 0, .y = 65, .z = 0 },
    .{ .x = 0, .y = -65, .z = 0 },
    .{ .x = 0, .y = 0, .z = -40 },
    .{ .x = -40, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 40 },
    .{ .x = 40, .y = 0, .z = 0 },
};

const kPoly0_Polys = [40]t.uint8{
    3, 0, 5, 2, 4,
    3, 0, 2, 3, 1,
    3, 0, 3, 4, 2,
    3, 0, 4, 5, 3,
    3, 1, 2, 5, 4,
    3, 1, 3, 2, 1,
    3, 1, 4, 3, 2,
    3, 1, 5, 4, 3,
};

const kPoly1_Vtx = [6]Vertex3{
    .{ .x = 0, .y = 40, .z = 10 },
    .{ .x = 40, .y = -40, .z = 10 },
    .{ .x = -40, .y = -40, .z = 10 },
    .{ .x = 0, .y = 40, .z = -10 },
    .{ .x = -40, .y = -40, .z = -10 },
    .{ .x = 40, .y = -40, .z = -10 },
};

const kPoly1_Polys = [28]t.uint8{
    3, 0, 1, 2, 7,
    3, 3, 4, 5, 6,
    4, 0, 3, 5, 1, 5,
    4, 1, 5, 4, 2, 4,
    4, 3, 0, 2, 4, 3,
};

const PolyConfig = extern struct {
    num_vtx: t.uint8,
    num_poly: t.uint8,
    vtx_val: t.uint16,
    polys_val: t.uint16,
    vertex: [*]const Vertex3,
    poly: [*]const t.uint8,
};

const kPolyConfigs = [2]PolyConfig{
    .{ .num_vtx = 6, .num_poly = 8, .vtx_val = 0xff98, .polys_val = 0xffaa, .vertex = &kPoly0_Vtx, .poly = &kPoly0_Polys },
    .{ .num_vtx = 6, .num_poly = 5, .vtx_val = 0xffd2, .polys_val = 0xffe4, .vertex = &kPoly1_Vtx, .poly = &kPoly1_Polys },
};

const kPoly_RasterColors = [16]t.uint32{
    0x00,       0xff,       0xff00,     0xffff,
    0xff0000,   0xff00ff,   0xffff00,   0xffffff,
    0xff000000, 0xff0000ff, 0xff00ff00, 0xff00ffff,
    0xffff0000, 0xffff00ff, 0xffffff00, 0xffffffff,
};

const kPoly_LeftSideMask = [8]t.uint16{ 0xffff, 0x7f7f, 0x3f3f, 0x1f1f, 0xf0f, 0x707, 0x303, 0x101 };
const kPoly_RightSideMask = [8]t.uint16{ 0x8080, 0xc0c0, 0xe0e0, 0xf0f0, 0xf8f8, 0xfcfc, 0xfefe, 0xffff };

pub export fn Poly_Divide(a: t.uint16, b: t.uint16) t.uint16 {
    v.poly_tmp1().* = if (t.sign16(a) != 0) 0 -% a else a;
    v.poly_tmp0().* = b;
    while (v.poly_tmp0().* >= 256) {
        v.poly_tmp0().* >>= 1;
        v.poly_tmp1().* >>= 1;
    }
    const q: t.uint16 = @intCast(@divTrunc(v.poly_tmp1().*, v.poly_tmp0().*));
    return if (t.sign16(a) != 0) 0 -% q else q;
}

pub export fn Poly_RunFrame() void {
    Polyhedral_EmptyBitMapBuffer();
    Polyhedral_SetShapePointer();
    Polyhedral_SetRotationMatrix();
    Polyhedral_OperateRotation();
    Polyhedral_DrawPolyhedron();
}

pub export fn Polyhedral_SetShapePointer() void { // 89f83d
    v.poly_var1().* = @as(t.uint16, v.poly_config1().*) * 2 + 0x80;
    v.poly_tmp0().* = @as(t.uint16, v.poly_which_model().*) * 2;

    const poly_config = &kPolyConfigs[v.poly_which_model().*];
    v.poly_config_num_vertex().* = poly_config.num_vtx;
    v.poly_config_num_polys().* = poly_config.num_poly;
    v.poly_fromlut_ptr2().* = poly_config.vtx_val;
    v.poly_fromlut_ptr4().* = poly_config.polys_val;
}

pub export fn Polyhedral_SetRotationMatrix() void { // 89f864
    v.poly_sin_a().* = @as(t.uint16, @bitCast(@as(t.int16, kPolySinCos[v.poly_a().*])));
    v.poly_cos_a().* = @as(t.uint16, @bitCast(@as(t.int16, kPolySinCos[@as(usize, v.poly_a().*) + 64])));
    v.poly_sin_b().* = @as(t.uint16, @bitCast(@as(t.int16, kPolySinCos[v.poly_b().*])));
    v.poly_cos_b().* = @as(t.uint16, @bitCast(@as(t.int16, kPolySinCos[@as(usize, v.poly_b().*) + 64])));
    v.poly_e0().* = @bitCast(@as(t.int16, @truncate((as16(v.poly_sin_b().*) * asInt8(v.poly_sin_a().*)) >> 8 << 2)));
    v.poly_e1().* = @bitCast(@as(t.int16, @truncate((as16(v.poly_cos_b().*) * asInt8(v.poly_cos_a().*)) >> 8 << 2)));
    v.poly_e2().* = @bitCast(@as(t.int16, @truncate((as16(v.poly_cos_b().*) * asInt8(v.poly_sin_a().*)) >> 8 << 2)));
    v.poly_e3().* = @bitCast(@as(t.int16, @truncate((as16(v.poly_sin_b().*) * asInt8(v.poly_cos_a().*)) >> 8 << 2)));
}

pub export fn Polyhedral_OperateRotation() void { // 89f8fb
    const poly_config = &kPolyConfigs[v.poly_which_model().*];
    const src: [*]const t.int8 = @ptrCast(poly_config.vertex);
    var i = v.poly_config_num_vertex().*;
    var base: usize = @as(usize, i) * 3;
    while (true) {
        base -= 3;
        i -= 1;
        v.poly_fromlut_x().* = @bitCast(src[base + 2]);
        v.poly_fromlut_y().* = @bitCast(src[base + 1]);
        v.poly_fromlut_z().* = @bitCast(src[base + 0]);
        Polyhedral_RotatePoint();
        Polyhedral_ProjectPoint();
        v.poly_arr_x()[i] = v.poly_base_x().* +% t.byte(v.poly_f0()).*;
        v.poly_arr_y()[i] = v.poly_base_y().* -% t.byte(v.poly_f1()).*;
        if (i == 0) break;
    }
}

pub export fn Polyhedral_RotatePoint() void { // 89f931
    const x: i32 = @as(t.int8, @bitCast(v.poly_fromlut_x().*));
    const y: i32 = @as(t.int8, @bitCast(v.poly_fromlut_y().*));
    const z: i32 = @as(t.int8, @bitCast(v.poly_fromlut_z().*));

    v.poly_f0().* = @bitCast(@as(t.int16, @truncate(as16(v.poly_cos_b().*) * z - as16(v.poly_sin_b().*) * x)));
    v.poly_f1().* = @bitCast(@as(t.int16, @truncate(as16(v.poly_e0().*) * z + as16(v.poly_cos_a().*) * y + as16(v.poly_e2().*) * x)));
    v.poly_f2().* = @bitCast(@as(t.int16, @truncate(((as16(v.poly_e3().*) * z) >> 8) - ((as16(v.poly_sin_a().*) * y) >> 8) + ((as16(v.poly_e1().*) * x) >> 8) + @as(i32, v.poly_var1().*))));
}

pub export fn Polyhedral_ProjectPoint() void { // 89f9d6
    v.poly_f0().* = Poly_Divide(v.poly_f0().*, v.poly_f2().*);
    v.poly_f1().* = Poly_Divide(v.poly_f1().*, v.poly_f2().*);
}

pub export fn Polyhedral_DrawPolyhedron() void { // 89fa4f
    const poly_config = &kPolyConfigs[v.poly_which_model().*];
    var src: [*]const t.uint8 = poly_config.poly;
    while (true) {
        v.poly_num_vertex_in_poly().* = src[0];
        src += 1;
        t.byte(v.poly_tmp0()).* = v.poly_num_vertex_in_poly().*;
        v.poly_xy_coords()[0] = v.poly_num_vertex_in_poly().* * 2;

        var i: usize = 1;
        while (true) {
            const j = src[0];
            src += 1;
            v.poly_xy_coords()[i + 0] = v.poly_arr_x()[j];
            v.poly_xy_coords()[i + 1] = v.poly_arr_y()[j];
            i += 2;
            t.byte(v.poly_tmp0()).* -%= 1;
            if (t.byte(v.poly_tmp0()).* == 0) break;
        }

        v.poly_raster_color_config().* = src[0];
        src += 1;
        const order = Polyhedral_CalculateCrossProduct();
        if (order > 0) {
            Polyhedral_SetForegroundColor();
            Polyhedral_DrawFace();
        }
        v.poly_config_num_polys().* -%= 1;
        if (v.poly_config_num_polys().* == 0) break;
    }
}

pub export fn Polyhedral_SetForegroundColor() void { // 89faca
    const tt: u4 = if (v.poly_which_model().* != 0) @intCast(v.poly_config1().* >> 5) else 0;
    const a: t.uint8 = @truncate(v.poly_tmp0().* << (tt + 1) >> 8);
    Polyhedral_SetColorMask(if (a <= 1) 1 else if (a >= 7) 7 else a);
}

pub export fn Polyhedral_CalculateCrossProduct() t.int16 { // 89fb24
    var a: i32 = @as(i32, v.poly_xy_coords()[3]) - v.poly_xy_coords()[1];
    v.poly_tmp0().* = @bitCast(@as(t.int16, @truncate(a * @as(t.int8, @bitCast(v.poly_xy_coords()[6] -% v.poly_xy_coords()[4])))));
    a = @as(i32, v.poly_xy_coords()[5]) - v.poly_xy_coords()[3];
    v.poly_tmp0().* -%= @bitCast(@as(t.int16, @truncate(a * @as(t.int8, @bitCast(v.poly_xy_coords()[4] -% v.poly_xy_coords()[2])))));
    return @bitCast(v.poly_tmp0().*);
}

pub export fn Polyhedral_SetColorMask(c: c_int) void { // 89fcae
    const val = kPoly_RasterColors[@intCast(c)];
    v.poly_raster_color0().* = @truncate(val);
    v.poly_raster_color1().* = @truncate(val >> 16);
}

pub export fn Polyhedral_EmptyBitMapBuffer() void { // 89fd04
    @memset(v.polyhedral_buffer()[0..0x800], 0);
}

pub export fn Polyhedral_DrawFace() void { // 89fd1e
    var n = v.poly_xy_coords()[0];
    var min_y = v.poly_xy_coords()[n];
    var min_idx = n;
    while (true) {
        n -%= 2;
        if (n == 0) break;
        if (v.poly_xy_coords()[n] < min_y) {
            min_y = v.poly_xy_coords()[n];
            min_idx = n;
        }
    }
    const low: t.uint16 = if (min_y & 0x20 != 0) 0x24 else 0;
    v.poly_raster_dst_ptr().* = 0xe800 + ((@as(t.uint16, (min_y & 0x38)) ^ low) << 6) + @as(t.uint16, min_y & 7) * 2;
    v.poly_cur_vertex_idx0().* = min_idx;
    v.poly_cur_vertex_idx1().* = min_idx;
    v.poly_total_num_steps().* = v.poly_xy_coords()[0] >> 1;
    v.poly_y0_cur().* = v.poly_xy_coords()[min_idx];
    v.poly_y1_cur().* = v.poly_y0_cur().*;
    v.poly_x0_cur().* = v.poly_xy_coords()[min_idx - 1];
    v.poly_x1_cur().* = v.poly_x0_cur().*;
    if (Polyhedral_SetLeft() or Polyhedral_SetRight())
        return;
    while (true) {
        Polyhedral_FillLine();
        if (t.byte(v.poly_raster_dst_ptr()).* != 0xe) {
            v.poly_raster_dst_ptr().* +%= 2;
        } else {
            const a: t.uint8 = t.hibyte(v.poly_raster_dst_ptr()).* +% 2;
            const x: t.uint8 = if (a & 8 != 0) 0 else 0x19;
            v.poly_raster_dst_ptr().* = @as(t.uint16, a ^ x) << 8;
        }
        if (v.poly_y0_cur().* == v.poly_y0_trig().*) {
            v.poly_x0_cur().* = v.poly_x0_target().*;
            if (Polyhedral_SetLeft())
                return;
        }
        v.poly_y0_cur().* +%= 1;
        if (v.poly_y1_cur().* == v.poly_y1_trig().*) {
            v.poly_x1_cur().* = v.poly_x1_target().*;
            if (Polyhedral_SetRight())
                return;
        }
        v.poly_y1_cur().* +%= 1;
        v.poly_x0_frac().* +%= v.poly_x0_step().*;
        v.poly_x1_frac().* +%= v.poly_x1_step().*;
    }
}

pub export fn Polyhedral_FillLine() void { // 89fdcf
    const left = kPoly_LeftSideMask[(v.poly_x0_frac().* >> 8) & 7];
    const right = kPoly_RightSideMask[(v.poly_x1_frac().* >> 8) & 7];
    v.poly_tmp2().* = @truncate((v.poly_x0_frac().* >> 8) & 0x38);
    const d0_init: i32 = (v.poly_x1_frac().* >> 8) & 0x38;
    var ptr: [*]align(1) t.uint16 = @ptrCast(&v.g_ram[v.poly_raster_dst_ptr().* + @as(usize, @intCast(d0_init)) * 4]);
    const d0 = d0_init - v.poly_tmp2().*;
    if (d0 == 0) {
        v.poly_tmp1().* = left & right;
        ptr[0] ^= (ptr[0] ^ v.poly_raster_color0().*) & v.poly_tmp1().*;
        ptr[8] ^= (ptr[8] ^ v.poly_raster_color1().*) & v.poly_tmp1().*;
        return;
    }
    if (d0 < 0)
        return;
    const n = d0 >> 3;
    ptr[0] ^= (ptr[0] ^ v.poly_raster_color0().*) & right;
    ptr[8] ^= (ptr[8] ^ v.poly_raster_color1().*) & right;
    ptr -= 0x10;
    var k = n;
    while (k -% 1 != 0) : (k -= 1) {
        ptr[0] = v.poly_raster_color0().*;
        ptr[8] = v.poly_raster_color1().*;
        ptr -= 0x10;
    }
    ptr[0] ^= (ptr[0] ^ v.poly_raster_color0().*) & left;
    ptr[8] ^= (ptr[8] ^ v.poly_raster_color1().*) & left;
    v.poly_tmp1().* = left;
    v.poly_raster_numfull().* = 0;
}

pub export fn Polyhedral_SetLeft() bool { // 89feb4
    var i: i32 = undefined;
    while (true) {
        v.poly_total_num_steps().* -%= 1;
        if (t.sign8(v.poly_total_num_steps().*) != 0)
            return true;
        i = @as(i32, v.poly_cur_vertex_idx0().*) - 2;
        if (i == 0)
            i = v.poly_xy_coords()[0];
        if (v.poly_xy_coords()[@intCast(i)] < v.poly_y0_cur().*)
            return true;
        if (v.poly_xy_coords()[@intCast(i)] != v.poly_y0_cur().*)
            break;
        v.poly_x0_cur().* = v.poly_xy_coords()[@intCast(i - 1)];
        v.poly_cur_vertex_idx0().* = @intCast(i);
    }
    v.poly_y0_trig().* = v.poly_xy_coords()[@intCast(i)];
    v.poly_x0_target().* = v.poly_xy_coords()[@intCast(i - 1)];
    v.poly_cur_vertex_idx0().* = @intCast(i);
    const u: i32 = @as(i32, v.poly_x0_target().*) - v.poly_x0_cur().*;
    var tt = u;
    if (tt < 0)
        tt = -tt;
    tt = @divTrunc((tt & 0xff) << 8, @as(i32, v.poly_y0_trig().* -% v.poly_y0_cur().*));
    v.poly_x0_frac().* = (@as(t.uint16, v.poly_x0_cur().*) << 8) | 0x80;
    v.poly_x0_step().* = @bitCast(@as(t.int16, @truncate(if (u < 0) -tt else tt)));
    return false;
}

pub export fn Polyhedral_SetRight() bool { // 89ff1e
    var i: i32 = undefined;
    while (true) {
        v.poly_total_num_steps().* -%= 1;
        if (t.sign8(v.poly_total_num_steps().*) != 0)
            return true;
        i = v.poly_cur_vertex_idx1().*;
        if (i == v.poly_xy_coords()[0])
            i = 0;
        i += 2;
        if (v.poly_xy_coords()[@intCast(i)] < v.poly_y1_cur().*)
            return true;
        if (v.poly_xy_coords()[@intCast(i)] != v.poly_y1_cur().*)
            break;
        v.poly_x1_cur().* = v.poly_xy_coords()[@intCast(i - 1)];
        v.poly_cur_vertex_idx1().* = @intCast(i);
    }
    v.poly_y1_trig().* = v.poly_xy_coords()[@intCast(i)];
    v.poly_x1_target().* = v.poly_xy_coords()[@intCast(i - 1)];
    v.poly_cur_vertex_idx1().* = @intCast(i);
    const u: i32 = @as(i32, v.poly_x1_target().*) - v.poly_x1_cur().*;
    var tt = u;
    if (tt < 0)
        tt = -tt;
    tt = @divTrunc((tt & 0xff) << 8, @as(i32, v.poly_y1_trig().* -% v.poly_y1_cur().*));
    v.poly_x1_frac().* = (@as(t.uint16, v.poly_x1_cur().*) << 8) | 0x80;
    v.poly_x1_step().* = @bitCast(@as(t.int16, @truncate(if (u < 0) -tt else tt)));
    return false;
}

inline fn as16(x: t.uint16) i32 {
    return @as(t.int16, @bitCast(x));
}

inline fn asInt8(x: t.uint16) i32 {
    return @as(t.int8, @truncate(@as(t.int16, @bitCast(x))));
}
