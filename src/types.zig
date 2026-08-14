// Port of src/types.h: base integer typedefs plus the BYTE/WORD/DWORD/
// HIBYTE/load24 type-punning helpers. The C macros reinterpret an lvalue's
// address as a wider or narrower integer type (`*(uint16*)&(x)`); in Zig
// each becomes an inline generic fn returning a *align(1) pointer, since
// g_ram offsets are frequently odd and Zig forbids implicit unaligned
// access. Dereference the result to read, assign through it to write:
//   byte(&v)   <-> BYTE(v)      word(&v)  <-> WORD(v)
//   hibyte(&v) <-> HIBYTE(v)    dword(&v) <-> DWORD(v)

const std = @import("std");
const builtin = @import("builtin");

pub const uint8 = u8;
pub const int8 = i8;
pub const uint16 = u16;
pub const int16 = i16;
pub const uint32 = u32;
pub const int32 = i32;
pub const uint64 = u64;
pub const int64 = i64;
pub const uint = c_uint;

// Build time config options
pub const kEnableLargeScreen = 1;
// How much extra spacing to add on the sides
pub const kPpuExtraLeftRight = if (kEnableLargeScreen != 0) 96 else 0;

pub const kDebugFlag = builtin.mode == .Debug;

pub inline fn arraysize(x: anytype) usize {
    return x.len;
}

pub inline fn countof(x: anytype) usize {
    return x.len;
}

pub inline fn sign8(x: uint8) uint8 {
    return x & 0x80;
}

pub inline fn sign16(x: uint16) uint16 {
    return x & 0x8000;
}

pub inline fn load24(x: anytype) uint32 {
    return dword(x).* & 0xffffff;
}

pub inline fn abs16(t: uint16) uint16 {
    return if (sign16(t) != 0) 0 -% t else t;
}

pub inline fn abs8(t: uint8) uint8 {
    return if (sign8(t) != 0) 0 -% t else t;
}

pub inline fn IntMin(a: c_int, b: c_int) c_int {
    return @min(a, b);
}

pub inline fn IntMax(a: c_int, b: c_int) c_int {
    return @max(a, b);
}

pub inline fn UintMin(a: uint, b: uint) uint {
    return @min(a, b);
}

pub inline fn UintMax(a: uint, b: uint) uint {
    return @max(a, b);
}

// The punning helpers accept any single-item pointer (comptime-enforced)
// and reinterpret its address, matching how the C macros apply to array
// elements, struct fields, and g_ram-backed lvalues alike. The result
// preserves the input's const-ness (a `*const u8` in yields a
// `*align(1) const T` out) so read-only C locals (`const uint8 *src`)
// can still be punned for reading without needing a `@constCast`.
fn Pun(comptime In: type, comptime Out: type) type {
    return if (@typeInfo(In).pointer.is_const) *align(1) const Out else *align(1) Out;
}

pub inline fn byte(x: anytype) Pun(@TypeOf(x), uint8) {
    return @ptrCast(x);
}

pub inline fn hibyte(x: anytype) Pun(@TypeOf(x), uint8) {
    const Many = if (@typeInfo(@TypeOf(x)).pointer.is_const) [*]align(1) const uint8 else [*]align(1) uint8;
    const p: Many = @ptrCast(x);
    return &p[1];
}

pub inline fn word(x: anytype) Pun(@TypeOf(x), uint16) {
    return @ptrCast(x);
}

pub inline fn dword(x: anytype) Pun(@TypeOf(x), uint32) {
    return @ptrCast(x);
}

pub inline fn xy(x: usize, y: usize) usize {
    return y * 64 + x;
}

pub inline fn swap16(v: uint16) uint16 {
    return @byteSwap(v);
}

pub const Point16U = extern struct {
    x: uint16,
    y: uint16,
};

pub const PointU8 = extern struct {
    x: uint8,
    y: uint8,
};

pub const Pair16U = extern struct {
    a: uint16,
    b: uint16,
};

pub const PairU8 = extern struct {
    a: uint8,
    b: uint8,
};

pub const ProjectSpeedRet = extern struct {
    x: uint8,
    y: uint8,
    xdiff: uint8,
    ydiff: uint8,
};

pub const OamEnt = extern struct {
    x: uint8,
    y: uint8,
    charnum: uint8,
    flags: uint8,
};

pub const MemBlk = extern struct {
    ptr: ?[*]const uint8,
    size: usize,
};

comptime {
    const C = struct {
        const Point16U = extern struct { x: u16, y: u16 };
        const PointU8 = extern struct { x: u8, y: u8 };
        const Pair16U = extern struct { a: u16, b: u16 };
        const PairU8 = extern struct { a: u8, b: u8 };
        const ProjectSpeedRet = extern struct { x: u8, y: u8, xdiff: u8, ydiff: u8 };
        const OamEnt = extern struct { x: u8, y: u8, charnum: u8, flags: u8 };
        const MemBlk = extern struct { ptr: ?[*]const u8, size: usize };
    };
    // The C structs are plain (non-packed) aggregates of uint8/uint16, so
    // they carry the natural C layout; pin each Zig twin to it.
    std.debug.assert(@sizeOf(Point16U) == @sizeOf(C.Point16U));
    std.debug.assert(@bitOffsetOf(Point16U, "y") == @bitOffsetOf(C.Point16U, "y"));
    std.debug.assert(@sizeOf(PointU8) == @sizeOf(C.PointU8));
    std.debug.assert(@sizeOf(Pair16U) == @sizeOf(C.Pair16U));
    std.debug.assert(@bitOffsetOf(Pair16U, "b") == @bitOffsetOf(C.Pair16U, "b"));
    std.debug.assert(@sizeOf(PairU8) == @sizeOf(C.PairU8));
    std.debug.assert(@sizeOf(ProjectSpeedRet) == @sizeOf(C.ProjectSpeedRet));
    std.debug.assert(@sizeOf(OamEnt) == @sizeOf(C.OamEnt));
    std.debug.assert(@sizeOf(MemBlk) == @sizeOf(C.MemBlk));
}
