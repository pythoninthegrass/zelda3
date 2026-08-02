// Tier-B differential test for src/util.zig: links the pre-port util.c
// (symbols renamed with a c_ prefix via objcopy, wired in build.zig's
// difftest step) against the ported Zig module and diffs their outputs over
// randomized inputs driven by a fixed-seed PRNG. Both implementations are
// reached via extern declarations — the original names resolve to the Zig
// port (util.zig's export fns), the c_ names to the renamed C object.
//
// Functions that mutate their input (the tokenizers write 0 terminators and
// advance a cursor) run against two separate copies of the same bytes so the
// runs stay independent. Heap pointers the C side returns are freed with libc
// free, not the Zig testing allocator.

const std = @import("std");
const t = @import("types.zig");
const u = @import("util.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expect = std.testing.expect;

const MemBlk = t.MemBlk;
const ByteArray = u.ByteArray;

extern fn free(ptr: ?*anyopaque) void;

// Die lives in zelda_rtl.c, which is not linked into this test; the C
// reference object calls it on allocation/IO failure paths that the
// differential fixtures never trigger. Stub it so the object links.
export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in difftest");
}

// Pull the Zig port's exported symbols into this binary; they are reached via
// the `u.*` module namespace below, the C reference via the c_* externs.
comptime {
    _ = u.NextDelim;
    _ = u.StringEqualsNoCase;
    _ = u.StringStartsWithNoCase;
    _ = u.ReadWholeFile;
    _ = u.NextLineStripComments;
    _ = u.NextPossiblyQuotedString;
    _ = u.ReplaceFilenameWithNewPath;
    _ = u.SplitKeyValue;
    _ = u.SkipPrefix;
    _ = u.StrSet;
    _ = u.ByteArray_Resize;
    _ = u.ByteArray_Destroy;
    _ = u.ByteArray_AppendData;
    _ = u.ByteArray_AppendByte;
    _ = u.FindIndexInMemblk;
    _ = u.ApplyBps;
}

// Pre-port C reference (util.c), symbols renamed to c_<name> by objcopy.
extern fn c_NextDelim(s: *?[*:0]u8, sep: c_int) ?[*:0]u8;
extern fn c_StringEqualsNoCase(a: [*:0]const u8, b: [*:0]const u8) bool;
extern fn c_StringStartsWithNoCase(a: [*:0]const u8, b: [*:0]const u8) ?[*:0]const u8;
extern fn c_NextLineStripComments(s: *?[*:0]u8) ?[*:0]u8;
extern fn c_NextPossiblyQuotedString(s: *?[*:0]u8) ?[*:0]u8;
extern fn c_ReplaceFilenameWithNewPath(old_path: [*:0]const u8, new_path: [*:0]const u8) ?[*:0]u8;
extern fn c_SplitKeyValue(p: [*:0]u8) ?[*:0]u8;
extern fn c_SkipPrefix(big: [*:0]const u8, little: [*:0]const u8) ?[*:0]const u8;
extern fn c_StrSet(rv: *?[*:0]u8, s: [*:0]const u8) void;
extern fn c_ByteArray_Resize(arr: *ByteArray, new_size: usize) void;
extern fn c_ByteArray_Destroy(arr: *ByteArray) void;
extern fn c_ByteArray_AppendData(arr: *ByteArray, data: [*]const u8, data_size: usize) void;
extern fn c_ByteArray_AppendByte(arr: *ByteArray, v: u8) void;
extern fn c_FindIndexInMemblk(data: MemBlk, i: usize) MemBlk;
extern fn c_ApplyBps(src: [*]const u8, src_size: usize, bps: [*]const u8, bps_size: usize, length_out: *usize) ?[*]u8;

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0x5eed);
    return prng.?.random();
}

fn spanZ(p: ?[*:0]const u8) []const u8 {
    return if (p) |q| std.mem.span(q) else "";
}

// Fill with NUL-free bytes drawn from an alphabet heavy on the separators the
// string helpers key off (blank, tab, quote, '#', '=', newline, path chars).
fn randTok(buf: []u8, alphabet: []const u8) void {
    for (buf) |*b|
        b.* = alphabet[rnd().uintLessThan(usize, alphabet.len)];
}

fn crc32(data: [*]const u8, length: usize) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data[0..length]) |b| {
        crc ^= b;
        for (0..8) |_|
            crc = (crc >> 1) ^ ((crc & 1) *% 0xEDB88320);
    }
    return crc ^ 0xFFFFFFFF;
}

test "diff NextDelim over random token streams" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        var bz: [64]u8 = undefined;
        var bc: [64]u8 = undefined;
        const n = rnd().uintLessThan(usize, 60) + 1;
        randTok(bz[0..n], "abcXYZ ,|=\t");
        @memcpy(bc[0..n], bz[0..n]);
        bz[n] = 0;
        bc[n] = 0;
        var sz: ?[*:0]u8 = @ptrCast(&bz);
        var sc: ?[*:0]u8 = @ptrCast(&bc);
        const sep: c_int = @as(c_int, ",|="[rnd().uintLessThan(usize, 3)]);
        while (true) {
            const rz = u.NextDelim(&sz, sep);
            const rc = c_NextDelim(&sc, sep);
            try expectEqual(rz == null, rc == null);
            if (rz == null) break;
            try expectEqualSlices(u8, spanZ(rc), spanZ(rz));
            try expectEqual(sz == null, sc == null);
            if (sz == null) break;
        }
    }
}

test "diff StringEqualsNoCase / StringStartsWithNoCase" {
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        var a: [24]u8 = undefined;
        var b: [24]u8 = undefined;
        const na = rnd().uintLessThan(usize, 20);
        randTok(a[0..na], "abcXYZdef");
        const nb = if (rnd().boolean()) na else rnd().uintLessThan(usize, 20);
        for (0..nb) |j| {
            var ch = a[if (j < na) j else 0];
            if (rnd().boolean()) {
                if (ch >= 'a' and ch <= 'z') ch -= 32 else if (ch >= 'A' and ch <= 'Z') ch += 32;
            }
            b[j] = ch;
        }
        a[na] = 0;
        b[nb] = 0;
        const az: [*:0]const u8 = @ptrCast(&a);
        const bz: [*:0]const u8 = @ptrCast(&b);
        try expectEqual(c_StringEqualsNoCase(az, bz), u.StringEqualsNoCase(az, bz));
        const tz = u.StringStartsWithNoCase(az, bz);
        const tc = c_StringStartsWithNoCase(az, bz);
        try expectEqual(tz == null, tc == null);
        if (tz != null)
            try expectEqualSlices(u8, spanZ(tc), spanZ(tz));
    }
}

test "diff NextLineStripComments over random line streams" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        var bz: [96]u8 = undefined;
        var bc: [96]u8 = undefined;
        const n = rnd().uintLessThan(usize, 90) + 1;
        randTok(bz[0..n], "abc =#kv \t\r\n");
        @memcpy(bc[0..n], bz[0..n]);
        bz[n] = 0;
        bc[n] = 0;
        var sz: ?[*:0]u8 = @ptrCast(&bz);
        var sc: ?[*:0]u8 = @ptrCast(&bc);
        while (true) {
            const rz = u.NextLineStripComments(&sz);
            const rc = c_NextLineStripComments(&sc);
            try expectEqual(rz == null, rc == null);
            if (rz == null) break;
            try expectEqualSlices(u8, spanZ(rc), spanZ(rz));
            try expectEqual(sz == null, sc == null);
            if (sz == null) break;
        }
    }
}

test "diff NextPossiblyQuotedString over random token streams" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        var bz: [80]u8 = undefined;
        var bc: [80]u8 = undefined;
        const n = rnd().uintLessThan(usize, 74) + 1;
        randTok(bz[0..n], "abc \"\txy");
        @memcpy(bc[0..n], bz[0..n]);
        bz[n] = 0;
        bc[n] = 0;
        var sz: ?[*:0]u8 = @ptrCast(&bz);
        var sc: ?[*:0]u8 = @ptrCast(&bc);
        var steps: usize = 0;
        while (steps < 8) : (steps += 1) {
            if (sz == null and sc == null) break;
            const rz = u.NextPossiblyQuotedString(&sz);
            const rc = c_NextPossiblyQuotedString(&sc);
            try expectEqual(rz == null, rc == null);
            if (rz == null) break;
            try expectEqualSlices(u8, spanZ(rc), spanZ(rz));
            if (sz == null or sc == null) break;
        }
    }
}

test "diff ReplaceFilenameWithNewPath" {
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        var op: [40]u8 = undefined;
        var np: [24]u8 = undefined;
        const no = rnd().uintLessThan(usize, 34) + 1;
        const nn = rnd().uintLessThan(usize, 20) + 1;
        randTok(op[0..no], "abc/\\._xy");
        randTok(np[0..nn], "roms.fc");
        op[no] = 0;
        np[nn] = 0;
        const oz: [*:0]const u8 = @ptrCast(&op);
        const nz: [*:0]const u8 = @ptrCast(&np);
        const rz = u.ReplaceFilenameWithNewPath(oz, nz);
        const rc = c_ReplaceFilenameWithNewPath(oz, nz);
        defer free(rz);
        defer free(rc);
        try expectEqual(rz == null, rc == null);
        if (rz != null)
            try expectEqualSlices(u8, spanZ(rc), spanZ(rz));
    }
}

test "diff SplitKeyValue / SkipPrefix / StrSet" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        var bz: [48]u8 = undefined;
        var bc: [48]u8 = undefined;
        const n = rnd().uintLessThan(usize, 42) + 1;
        randTok(bz[0..n], "key =val\t");
        @memcpy(bc[0..n], bz[0..n]);
        bz[n] = 0;
        bc[n] = 0;
        const rz = u.SplitKeyValue(@ptrCast(&bz));
        const rc = c_SplitKeyValue(@ptrCast(&bc));
        try expectEqual(rz == null, rc == null);
        if (rz != null) {
            try expectEqualSlices(u8, spanZ(rc), spanZ(rz));
            // the mutated key side (left of the '=' split) must match too
            try expectEqualSlices(u8, spanZ(@as(?[*:0]u8, @ptrCast(&bc))), spanZ(@as(?[*:0]u8, @ptrCast(&bz))));
        }

        var s: [24]u8 = undefined;
        const ns = rnd().uintLessThan(usize, 20) + 1;
        randTok(s[0..ns], "LoadRefSav");
        s[ns] = 0;
        const plen = rnd().uintLessThan(usize, ns + 1);
        var pfx: [24]u8 = undefined;
        @memcpy(pfx[0..plen], s[0..plen]);
        pfx[plen] = 0;
        const sz: [*:0]const u8 = @ptrCast(&s);
        const pz: [*:0]const u8 = @ptrCast(&pfx);
        const tz = u.SkipPrefix(sz, pz);
        const tc = c_SkipPrefix(sz, pz);
        try expectEqual(tz == null, tc == null);
        if (tz != null)
            try expectEqualSlices(u8, spanZ(tc), spanZ(tz));

        var vz: ?[*:0]u8 = null;
        var vc: ?[*:0]u8 = null;
        u.StrSet(&vz, sz);
        c_StrSet(&vc, sz);
        try expectEqualSlices(u8, spanZ(vc), spanZ(vz));
        free(vz);
        free(vc);
    }
}

test "diff ByteArray op sequences" {
    var i: usize = 0;
    while (i < 800) : (i += 1) {
        var az: ByteArray = .{ .data = null, .size = 0, .capacity = 0 };
        var ac: ByteArray = .{ .data = null, .size = 0, .capacity = 0 };
        const ops = rnd().uintLessThan(usize, 60) + 1;
        var j: usize = 0;
        while (j < ops) : (j += 1) {
            if (rnd().boolean()) {
                const v: u8 = @intCast(rnd().uintLessThan(usize, 256));
                u.ByteArray_AppendByte(&az, v);
                c_ByteArray_AppendByte(&ac, v);
            } else {
                var chunk: [8]u8 = undefined;
                const cn = rnd().uintLessThan(usize, 8) + 1;
                rnd().bytes(chunk[0..cn]);
                u.ByteArray_AppendData(&az, &chunk, cn);
                c_ByteArray_AppendData(&ac, &chunk, cn);
            }
        }
        try expectEqual(ac.size, az.size);
        try expectEqual(ac.capacity, az.capacity);
        try expectEqualSlices(u8, ac.data.?[0..ac.size], az.data.?[0..az.size]);
        u.ByteArray_Destroy(&az);
        c_ByteArray_Destroy(&ac);
    }
}

// Build a self-consistent memblk blob: index ix[k] holds entry k's end offset
// relative to the end of the table; left_off(0)=table_bytes, right_off(mx)=
// end (size-2). 16-bit mode when count < 8192, else 32-bit (marker 8192+n).
fn buildMemblk(buf: []u8, mode32: bool) usize {
    const count = rnd().uintLessThan(usize, 5) + 1;
    const elem: usize = if (mode32) 4 else 2;
    var pos: usize = 0;
    var end_off: usize = 0;
    var ends: [5]usize = undefined;
    for (0..count) |k| {
        end_off += rnd().uintLessThan(usize, 6) + 1;
        ends[k] = end_off;
        if (mode32) {
            std.mem.writeInt(u32, buf[pos..][0..4], @intCast(end_off), .little);
        } else {
            std.mem.writeInt(u16, buf[pos..][0..2], @intCast(end_off), .little);
        }
        pos += elem;
    }
    rnd().bytes(buf[pos .. pos + end_off]);
    pos += end_off;
    const marker: u16 = if (mode32) @intCast(8192 + count) else @intCast(count);
    std.mem.writeInt(u16, buf[pos..][0..2], marker, .little);
    pos += 2;
    return pos;
}

test "diff FindIndexInMemblk 16-bit and 32-bit modes" {
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        var buf: [128]u8 = undefined;
        const mode32 = rnd().boolean();
        const size = buildMemblk(&buf, mode32);
        const blk: MemBlk = .{ .ptr = @ptrCast(&buf), .size = size };
        var k: usize = 0;
        while (k < 7) : (k += 1) { // probe in-range and out-of-range
            const rz = u.FindIndexInMemblk(blk, k);
            const rc = c_FindIndexInMemblk(blk, k);
            try expectEqual(rc.size, rz.size);
            try expectEqual(rz.ptr == null, rc.ptr == null);
            if (rz.ptr != null and rz.size > 0) {
                const base = @intFromPtr(@as([*]const u8, &buf));
                try expectEqual(@intFromPtr(rc.ptr.?) - base, @intFromPtr(rz.ptr.?) - base);
            }
        }
    }
}

fn bpsEncodeInt(list: *std.ArrayList(u8), val: u64) void {
    var data = val;
    var shift: u64 = 1;
    while (true) {
        const x: u8 = @intCast(data & 0x7f);
        data >>= 7;
        if (data == 0) {
            list.append(std.testing.allocator, x | 0x80) catch unreachable;
            break;
        }
        list.append(std.testing.allocator, x) catch unreachable;
        data -= shift;
        shift <<= 7;
    }
}

// Build a random valid BPS patch over `src` plus the golden output a correct
// applier must produce (computed with a simple reference model). Returns null
// when a random op couldn't be modelled exactly (e.g. ran off a boundary).
fn buildBps(alloc: std.mem.Allocator, src: []const u8) !?struct { patch: []u8, golden: []u8 } {
    var body = std.ArrayList(u8).empty;
    defer body.deinit(alloc);
    var golden = std.ArrayList(u8).empty;
    defer golden.deinit(alloc);

    var src_rel: i64 = 0;
    var tgt_rel: i64 = 0;
    const ops = rnd().uintLessThan(usize, 12) + 1;
    var k: usize = 0;
    while (k < ops) : (k += 1) {
        const op = rnd().uintLessThan(usize, 4);
        const len = rnd().uintLessThan(u32, 8) + 1;
        switch (op) {
            0 => { // SourceRead: copy src[out..out+len]
                if (golden.items.len + len > src.len) continue;
                bpsEncodeInt(&body, (@as(u64, len) - 1) << 2 | 0);
                try golden.appendSlice(alloc, src[golden.items.len .. golden.items.len + len]);
            },
            1 => { // TargetRead: literal bytes follow
                bpsEncodeInt(&body, (@as(u64, len) - 1) << 2 | 1);
                var lit: [8]u8 = undefined;
                rnd().bytes(lit[0..len]);
                try body.appendSlice(alloc, lit[0..len]);
                try golden.appendSlice(alloc, lit[0..len]);
            },
            2 => { // SourceCopy: relative seek into src
                if (src.len == 0) continue;
                const target: i64 = @intCast(rnd().uintLessThan(usize, src.len));
                const delta = target - src_rel;
                src_rel = target;
                bpsEncodeInt(&body, (@as(u64, len) - 1) << 2 | 2);
                const enc: u64 = if (delta < 0) (@as(u64, @intCast(-delta)) << 1) | 1 else (@as(u64, @intCast(delta)) << 1);
                bpsEncodeInt(&body, enc);
                var m: usize = 0;
                while (m < len) : (m += 1) {
                    if (src_rel < 0 or src_rel >= @as(i64, @intCast(src.len))) break;
                    try golden.append(alloc, src[@intCast(src_rel)]);
                    src_rel += 1;
                }
                if (m != len) return null;
            },
            else => { // TargetCopy: copy from already-written output
                if (golden.items.len == 0) continue;
                const target: i64 = @intCast(rnd().uintLessThan(usize, golden.items.len));
                const delta = target - tgt_rel;
                tgt_rel = target;
                bpsEncodeInt(&body, (@as(u64, len) - 1) << 2 | 3);
                const enc: u64 = if (delta < 0) (@as(u64, @intCast(-delta)) << 1) | 1 else (@as(u64, @intCast(delta)) << 1);
                bpsEncodeInt(&body, enc);
                var m: usize = 0;
                while (m < len) : (m += 1) {
                    if (tgt_rel < 0 or tgt_rel >= @as(i64, @intCast(golden.items.len))) break;
                    try golden.append(alloc, golden.items[@intCast(tgt_rel)]);
                    tgt_rel += 1;
                }
                if (m != len) return null;
            },
        }
    }
    if (golden.items.len == 0) return null;

    var patch = std.ArrayList(u8).empty;
    errdefer patch.deinit(alloc);
    try patch.appendSlice(alloc, "BPS1");
    bpsEncodeInt(&patch, src.len);
    bpsEncodeInt(&patch, golden.items.len);
    bpsEncodeInt(&patch, 0);
    try patch.appendSlice(alloc, body.items);

    var footer: [12]u8 = undefined;
    std.mem.writeInt(u32, footer[0..4], crc32(src.ptr, src.len), .little);
    std.mem.writeInt(u32, footer[4..8], crc32(golden.items.ptr, golden.items.len), .little);
    try patch.appendSlice(alloc, footer[0..8]);
    std.mem.writeInt(u32, footer[8..12], crc32(patch.items.ptr, patch.items.len), .little);
    try patch.appendSlice(alloc, footer[8..12]);

    return .{
        .patch = try patch.toOwnedSlice(alloc),
        .golden = try golden.toOwnedSlice(alloc),
    };
}

test "diff ApplyBps over random valid patches" {
    const alloc = std.testing.allocator;
    var produced: usize = 0;
    var attempts: usize = 0;
    while (produced < 600 and attempts < 6000) : (attempts += 1) {
        var src_buf: [64]u8 = undefined;
        const slen = rnd().uintLessThan(usize, 48) + 8;
        rnd().bytes(src_buf[0..slen]);
        const built = (try buildBps(alloc, src_buf[0..slen])) orelse continue;
        defer alloc.free(built.patch);
        defer alloc.free(built.golden);
        produced += 1;

        var lz: usize = 0;
        var lc: usize = 0;
        const rz = u.ApplyBps(&src_buf, slen, built.patch.ptr, built.patch.len, &lz);
        const rc = c_ApplyBps(&src_buf, slen, built.patch.ptr, built.patch.len, &lc);
        try expectEqual(rz == null, rc == null);
        try expectEqual(lc, lz);
        if (rz != null) {
            defer free(rz);
            defer free(rc);
            try expectEqualSlices(u8, rc.?[0..lc], rz.?[0..lz]);
            try expectEqualSlices(u8, built.golden, rz.?[0..lz]);
        }
    }
    try expect(produced > 0);
}

test "diff ApplyBps rejects corrupt patches identically" {
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var src_buf: [32]u8 = undefined;
        rnd().bytes(src_buf[0..]);
        var patch: [40]u8 = undefined;
        rnd().bytes(patch[0..]); // garbage: bad magic / bad crc almost always
        var lz: usize = 0;
        var lc: usize = 0;
        const rz = u.ApplyBps(&src_buf, 32, &patch, patch.len, &lz);
        const rc = c_ApplyBps(&src_buf, 32, &patch, patch.len, &lc);
        try expectEqual(rz == null, rc == null);
        if (rz != null) {
            defer free(rz);
            defer free(rc);
            try expectEqualSlices(u8, rc.?[0..lc], rz.?[0..lz]);
        }
    }
}
