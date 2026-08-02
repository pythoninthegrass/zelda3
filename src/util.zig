// Port of src/util.c: string/tokenizing helpers, ByteArray, the BPS patch
// applier, and the memblk index walker. Every function keeps its exact C-ABI
// name and signature (callconv(.c), C-pointer types) so the remaining .c
// callers link unchanged. StrFmt is the one exception: it is C-variadic and
// stays in C (src/util_strfmt.c) — Zig cannot forward a va_list without
// ABI-fragile interop, and the function has no in-tree callers.

const std = @import("std");
const t = @import("types.zig");

extern fn Die(msg: [*:0]const u8) noreturn;

extern fn fopen(name: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fseek(stream: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(stream: *anyopaque) c_long;
extern fn rewind(stream: *anyopaque) void;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn fclose(stream: *anyopaque) c_int;

extern fn malloc(size: usize) ?*anyopaque;
extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;

const SEEK_END: c_int = 2;

// Zig 0.16's std.start semantically analyzes root.main whenever it emits an
// executable, even with the entry point disabled (the C main in src/main.c
// is the real entry; this stub is dead code that the linker discards because
// it is never exported).
pub fn main() callconv(.c) c_int {
    return 0;
}

pub const ByteArray = extern struct {
    data: ?[*]t.uint8,
    size: usize,
    capacity: usize,
};

pub export fn NextDelim(s: *?[*:0]u8, sep: c_int) ?[*:0]u8 {
    const r0 = s.* orelse return null;
    var r = r0;
    while (r[0] == ' ' or r[0] == '\t')
        r += 1;
    const c: t.uint8 = @intCast(sep);
    if (std.mem.indexOfScalar(t.uint8, std.mem.span(r), c)) |i| {
        r[i] = 0;
        s.* = @ptrCast(r + i + 1);
    } else {
        s.* = null;
    }
    return r;
}

inline fn toLower(a: t.uint8) t.uint8 {
    return a + @as(t.uint8, if (a >= 'A' and a <= 'Z') 32 else 0);
}

pub export fn StringEqualsNoCase(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    while (true) : (i += 1) {
        const aa = toLower(a[i]);
        const bb = toLower(b[i]);
        if (aa != bb)
            return false;
        if (aa == 0)
            return true;
    }
}

pub export fn StringStartsWithNoCase(a: [*:0]const u8, b: [*:0]const u8) ?[*:0]const u8 {
    var i: usize = 0;
    while (true) : (i += 1) {
        const aa = toLower(a[i]);
        const bb = toLower(b[i]);
        if (bb == 0)
            return @ptrCast(a + i);
        if (aa != bb)
            return null;
    }
}

pub export fn ReadWholeFile(name: [*:0]const u8, length: ?*usize) ?[*]t.uint8 {
    const f = fopen(name, "rb") orelse return null;
    _ = fseek(f, 0, SEEK_END);
    const size: usize = @intCast(ftell(f));
    rewind(f);
    const buffer: [*]t.uint8 = @ptrCast(malloc(size + 1) orelse Die("malloc failed"));
    // Always zero terminate so this function can be used also for strings.
    buffer[size] = 0;
    if (fread(buffer, 1, size, f) != size)
        Die("fread failed");
    _ = fclose(f);
    if (length) |len| len.* = size;
    return buffer;
}

pub export fn NextLineStripComments(s: *?[*:0]u8) ?[*:0]u8 {
    const p = s.* orelse return null;
    const line = std.mem.span(p);
    // find end of line
    var eol: usize = line.len;
    if (std.mem.indexOfScalar(t.uint8, line, '\n')) |i| {
        eol = i;
        s.* = @ptrCast(p + i + 1);
    } else {
        s.* = null;
    }
    // strip comments
    if (std.mem.indexOfScalar(t.uint8, line[0..eol], '#')) |i|
        eol = i;
    // strip trailing whitespace
    while (eol > 0 and (line[eol - 1] == '\r' or line[eol - 1] == ' ' or line[eol - 1] == '\t'))
        eol -= 1;
    line[eol] = 0;
    // strip leading whitespace
    var lead: usize = 0;
    while (lead < eol and (line[lead] == ' ' or line[lead] == '\t'))
        lead += 1;
    return @ptrCast(p + lead);
}

// Return the next possibly quoted string, space separated, or the empty string
pub export fn NextPossiblyQuotedString(s: *?[*:0]u8) ?[*:0]u8 {
    var r = s.* orelse return null;
    while (r[0] == ' ' or r[0] == '\t')
        r += 1;
    var i: usize = 0;
    if (r[0] == '"') {
        r += 1;
        while (r[i] != 0 and r[i] != '"')
            i += 1;
    } else {
        while (r[i] != 0 and r[i] != ' ' and r[i] != '\t')
            i += 1;
    }
    if (r[i] != 0) {
        r[i] = 0;
        i += 1;
    }
    while (r[i] == ' ' or r[i] == '\t')
        i += 1;
    s.* = @ptrCast(r + i);
    return r;
}

pub export fn ReplaceFilenameWithNewPath(old_path: [*:0]const u8, new_path: [*:0]const u8) ?[*:0]u8 {
    const old = std.mem.span(old_path);
    const new = std.mem.span(new_path);
    var olen = old.len;
    while (olen > 0 and old[olen - 1] != '/' and old[olen - 1] != '\\')
        olen -= 1;
    const result: [*]u8 = @ptrCast(malloc(olen + new.len + 1) orelse return null);
    @memcpy(result[0..olen], old[0..olen]);
    @memcpy(result[olen .. olen + new.len + 1], new[0 .. new.len + 1]);
    return @ptrCast(result);
}

pub export fn SplitKeyValue(p: [*:0]u8) ?[*:0]u8 {
    const str = std.mem.span(p);
    const eq = std.mem.indexOfScalar(t.uint8, str, '=') orelse return null;
    var kr = eq;
    while (kr > 0 and (str[kr - 1] == ' ' or str[kr - 1] == '\t'))
        kr -= 1;
    str[kr] = 0;
    var v = eq + 1;
    while (str[v] == ' ' or str[v] == '\t')
        v += 1;
    return @ptrCast(p + v);
}

pub export fn SkipPrefix(big: [*:0]const u8, little: [*:0]const u8) ?[*:0]const u8 {
    var i: usize = 0;
    while (little[i] != 0) : (i += 1) {
        if (little[i] != big[i])
            return null;
    }
    return @ptrCast(big + i);
}

pub export fn StrSet(rv: *?[*:0]u8, s: [*:0]const u8) void {
    const news = strdup(s);
    const old = rv.*;
    rv.* = news;
    free(old);
}

pub export fn ByteArray_Resize(arr: *ByteArray, new_size: usize) void {
    arr.size = new_size;
    if (new_size > arr.capacity) {
        const minsize = arr.capacity + (arr.capacity >> 1) + 8;
        arr.capacity = if (new_size < minsize) minsize else new_size;
        const data = realloc(arr.data, arr.capacity) orelse Die("memory allocation failed");
        arr.data = @ptrCast(data);
    }
}

pub export fn ByteArray_Destroy(arr: *ByteArray) void {
    const data = arr.data;
    arr.data = null;
    free(data);
}

pub export fn ByteArray_AppendData(arr: *ByteArray, data: [*]const t.uint8, data_size: usize) void {
    ByteArray_Resize(arr, arr.size + data_size);
    @memcpy(arr.data.?[arr.size - data_size .. arr.size], data[0..data_size]);
}

pub export fn ByteArray_AppendByte(arr: *ByteArray, v: t.uint8) void {
    ByteArray_Resize(arr, arr.size + 1);
    arr.data.?[arr.size - 1] = v;
}

// Automatically selects between 16 or 32 bit indexes. Can hold up to 8192 elements in 16-bit mode.
pub export fn FindIndexInMemblk(data: t.MemBlk, i: usize) t.MemBlk {
    const empty: t.MemBlk = .{ .ptr = null, .size = 0 };
    const ptr = data.ptr orelse return empty;
    if (data.size < 2)
        return empty;
    const end = data.size - 2;
    var left_off: usize = undefined;
    var right_off: usize = undefined;
    const mx = std.mem.readInt(t.uint16, ptr[end..][0..2], .little);
    if (mx < 8192) {
        if (i > mx or @as(usize, mx) * 2 > end)
            return empty;
        left_off = if (i == 0) @as(usize, mx) * 2 else @as(usize, mx) * 2 + std.mem.readInt(t.uint16, ptr[i * 2 - 2 ..][0..2], .little);
        right_off = if (i == mx) end else @as(usize, mx) * 2 + std.mem.readInt(t.uint16, ptr[i * 2 ..][0..2], .little);
    } else {
        const mx32 = @as(usize, mx) - 8192;
        if (i > mx32 or mx32 * 4 > end)
            return empty;
        left_off = if (i == 0) mx32 * 4 else mx32 * 4 + std.mem.readInt(t.uint32, ptr[i * 4 - 4 ..][0..4], .little);
        right_off = if (i == mx32) end else mx32 * 4 + std.mem.readInt(t.uint32, ptr[i * 4 ..][0..4], .little);
    }
    if (left_off > right_off or right_off > end)
        return empty;
    return .{ .ptr = ptr + left_off, .size = right_off - left_off };
}

fn bpsDecodeInt(src: *[*]const t.uint8) t.uint64 {
    var data: t.uint64 = 0;
    var shift: t.uint64 = 1;
    while (true) {
        const x = src.*[0];
        src.* += 1;
        data +%= @as(t.uint64, x & 0x7f) *% shift;
        if (x & 0x80 != 0) break;
        shift *%= 128;
        data +%= shift;
    }
    return data;
}

const kCrc32Polynomial: t.uint32 = 0xEDB88320;

fn crc32(data: [*]const t.uint8, length: usize) t.uint32 {
    var crc: t.uint32 = 0xFFFFFFFF;
    for (data[0..length]) |b| {
        crc ^= b;
        for (0..8) |_|
            crc = (crc >> 1) ^ ((crc & 1) *% kCrc32Polynomial);
    }
    return crc ^ 0xFFFFFFFF;
}

pub export fn ApplyBps(src: [*]const t.uint8, src_size_in: usize, bps_in: [*]const t.uint8, bps_size: usize, length_out: *usize) ?[*]t.uint8 {
    const bps_end = bps_in + bps_size - 12;

    if (!std.mem.eql(t.uint8, bps_in[0..4], "BPS1"))
        return null;
    if (crc32(src, src_size_in) != std.mem.readInt(t.uint32, bps_end[0..4], .little))
        return null;
    if (crc32(bps_in, bps_size - 4) != std.mem.readInt(t.uint32, (bps_end + 8)[0..4], .little))
        return null;

    var bps = bps_in + 4;
    const src_size = bpsDecodeInt(&bps);
    const dst_size = bpsDecodeInt(&bps);
    const meta_size = bpsDecodeInt(&bps);
    _ = meta_size;
    var outputOffset: t.uint32 = 0;
    var sourceRelativeOffset: t.uint32 = 0;
    var targetRelativeOffset: t.uint32 = 0;
    if (src_size != src_size_in)
        return null;
    length_out.* = @intCast(dst_size);
    const dst: [*]t.uint8 = @ptrCast(malloc(@intCast(dst_size)) orelse return null);
    while (@intFromPtr(bps) < @intFromPtr(bps_end)) {
        var cmd = bpsDecodeInt(&bps);
        var length: t.uint32 = @intCast((cmd >> 2) + 1);
        switch (cmd & 3) {
            0 => {
                while (length != 0) : (length -= 1) {
                    dst[outputOffset] = src[outputOffset];
                    outputOffset += 1;
                }
            },
            1 => {
                while (length != 0) : (length -= 1) {
                    dst[outputOffset] = bps[0];
                    outputOffset += 1;
                    bps += 1;
                }
            },
            2 => {
                cmd = bpsDecodeInt(&bps);
                // (cmd & 1 ? -1 : +1) * (cmd >> 1), in wrapping u32 arithmetic
                const delta: t.uint32 = @intCast(cmd >> 1);
                sourceRelativeOffset +%= if (cmd & 1 != 0) 0 -% delta else delta;
                while (length != 0) : (length -= 1) {
                    dst[outputOffset] = src[sourceRelativeOffset];
                    outputOffset += 1;
                    sourceRelativeOffset +%= 1;
                }
            },
            else => {
                cmd = bpsDecodeInt(&bps);
                const delta: t.uint32 = @intCast(cmd >> 1);
                targetRelativeOffset +%= if (cmd & 1 != 0) 0 -% delta else delta;
                while (length != 0) : (length -= 1) {
                    dst[outputOffset] = dst[targetRelativeOffset];
                    outputOffset += 1;
                    targetRelativeOffset +%= 1;
                }
            },
        }
    }
    if (dst_size != outputOffset)
        return null;
    if (crc32(dst, @intCast(dst_size)) != std.mem.readInt(t.uint32, (bps_end + 4)[0..4], .little))
        return null;
    return dst;
}
