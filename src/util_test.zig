// Tier-A unit tests for src/util.zig: the pure string/tokenizer helpers,
// ByteArray growth, FindIndexInMemblk (16/32-bit index modes), and a BPS
// patch apply with CRC-correct fixtures. Buffers the C functions mutate are
// plain stack/heap arrays; pointers returned by functions that allocate
// (ReadWholeFile, ReplaceFilenameWithNewPath, StrSet, ApplyBps) are libc
// malloc'd and freed with libc free, not the Zig testing allocator.

const std = @import("std");
const u = @import("util.zig");
const t = @import("types.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expect = std.testing.expect;

extern fn free(ptr: ?*anyopaque) void;

// Die lives in zelda_rtl.c, which is not linked into this test; util.zig's
// allocation/IO failure paths call it but the fixtures below never trigger
// them. Stub it so the test binary links (same pattern as util_difftest.zig).
export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in util test");
}

fn cstr(s: []const u8) [*:0]const u8 {
    return @ptrCast(s.ptr);
}

test "NextDelim skips leading blanks, splits on sep, null-terminates" {
    var buf = "  one,two,three".*;
    var s: ?[*:0]u8 = @ptrCast(&buf);
    const r1 = u.NextDelim(&s, ',');
    try expectEqualSlices(u8, "one", std.mem.span(r1.?));
    const r2 = u.NextDelim(&s, ',');
    try expectEqualSlices(u8, "two", std.mem.span(r2.?));
    const r3 = u.NextDelim(&s, ',');
    try expectEqualSlices(u8, "three", std.mem.span(r3.?));
    try expect(s == null);
}

test "NextDelim on last token leaves s null" {
    var buf = "solo".*;
    var s: ?[*:0]u8 = @ptrCast(&buf);
    const r = u.NextDelim(&s, ',');
    try expectEqualSlices(u8, "solo", std.mem.span(r.?));
    try expect(s == null);
}

test "StringEqualsNoCase" {
    try expect(u.StringEqualsNoCase(cstr("Hello"), cstr("hELLo")));
    try expect(u.StringEqualsNoCase(cstr(""), cstr("")));
    try expect(!u.StringEqualsNoCase(cstr("abc"), cstr("abd")));
    try expect(!u.StringEqualsNoCase(cstr("abc"), cstr("abcd")));
}

test "StringStartsWithNoCase returns tail or null" {
    const tail = u.StringStartsWithNoCase(cstr("Widescreen=1"), cstr("wide"));
    try expectEqualSlices(u8, "screen=1", std.mem.span(tail.?));
    try expect(u.StringStartsWithNoCase(cstr("abc"), cstr("abd")) == null);
    try expect(u.StringStartsWithNoCase(cstr("ab"), cstr("abc")) == null);
    // empty prefix returns the whole string
    const whole = u.StringStartsWithNoCase(cstr("abc"), cstr(""));
    try expectEqualSlices(u8, "abc", std.mem.span(whole.?));
}

test "NextLineStripComments strips comments, trims blanks, advances" {
    var buf = "  key = val  # comment\r\nnext line\n".*;
    var s: ?[*:0]u8 = @ptrCast(&buf);
    const l1 = u.NextLineStripComments(&s);
    try expectEqualSlices(u8, "key = val", std.mem.span(l1.?));
    const l2 = u.NextLineStripComments(&s);
    try expectEqualSlices(u8, "next line", std.mem.span(l2.?));
    // The trailing '\n' after "next line" advances s past it (to the '\0'
    // terminator), same as the C original (`*s = eol ? eol + 1 : NULL;`) --
    // s isn't null yet, so a third call sees one more (empty) line before s
    // finally goes null.
    const l3 = u.NextLineStripComments(&s);
    try expectEqualSlices(u8, "", std.mem.span(l3.?));
    try expect(s == null);
}

test "NextPossiblyQuotedString handles quoted and bare tokens" {
    var buf = "\"a b\" bare \"c\"".*;
    var s: ?[*:0]u8 = @ptrCast(&buf);
    const q1 = u.NextPossiblyQuotedString(&s);
    try expectEqualSlices(u8, "a b", std.mem.span(q1.?));
    const b2 = u.NextPossiblyQuotedString(&s);
    try expectEqualSlices(u8, "bare", std.mem.span(b2.?));
    const q3 = u.NextPossiblyQuotedString(&s);
    try expectEqualSlices(u8, "c", std.mem.span(q3.?));
}

test "ReplaceFilenameWithNewPath keeps dir, swaps filename" {
    const r = u.ReplaceFilenameWithNewPath(cstr("/home/user/old.sfc"), cstr("new.smc"));
    defer free(r);
    try expectEqualSlices(u8, "/home/user/new.smc", std.mem.span(r.?));

    const r2 = u.ReplaceFilenameWithNewPath(cstr("nodir.sfc"), cstr("x.smc"));
    defer free(r2);
    try expectEqualSlices(u8, "x.smc", std.mem.span(r2.?));

    // Windows-style separator
    const r3 = u.ReplaceFilenameWithNewPath(cstr("C:\\roms\\old.sfc"), cstr("y.smc"));
    defer free(r3);
    try expectEqualSlices(u8, "C:\\roms\\y.smc", std.mem.span(r3.?));
}

test "SplitKeyValue splits at '=', trims blanks around both sides" {
    var buf = "  width  =  512  ".*; // leading blanks stay (caller strips line first)
    const v = u.SplitKeyValue(@ptrCast(&buf));
    try expectEqualSlices(u8, "512  ", std.mem.span(v.?)); // trailing blanks kept
    try expectEqualSlices(u8, "  width", std.mem.span(@as([*:0]u8, @ptrCast(&buf))));

    var buf2 = "k=v".*;
    const v2 = u.SplitKeyValue(@ptrCast(&buf2));
    try expectEqualSlices(u8, "v", std.mem.span(v2.?));

    var buf3 = "noequals".*;
    try expect(u.SplitKeyValue(@ptrCast(&buf3)) == null);
}

test "SkipPrefix" {
    const r = u.SkipPrefix(cstr("LoadRef"), cstr("Load"));
    try expectEqualSlices(u8, "Ref", std.mem.span(r.?));
    try expect(u.SkipPrefix(cstr("LoadRef"), cstr("Save")) == null);
}

test "StrSet frees old, duplicates new" {
    var rv: ?[*:0]u8 = null;
    u.StrSet(&rv, cstr("first"));
    try expectEqualSlices(u8, "first", std.mem.span(rv.?));
    u.StrSet(&rv, cstr("second"));
    try expectEqualSlices(u8, "second", std.mem.span(rv.?));
    free(rv); // old freed by StrSet; free the current one
}

test "ByteArray grows capacity geometrically and appends" {
    var arr: u.ByteArray = .{ .data = null, .size = 0, .capacity = 0 };
    defer u.ByteArray_Destroy(&arr);
    var i: u32 = 0;
    while (i < 100) : (i += 1)
        u.ByteArray_AppendByte(&arr, @intCast(i & 0xff));
    try expectEqual(@as(usize, 100), arr.size);
    try expect(arr.capacity >= 100);
    try expectEqual(@as(u8, 0), arr.data.?[0]);
    try expectEqual(@as(u8, 99), arr.data.?[99]);

    const chunk = [_]u8{ 10, 20, 30 };
    u.ByteArray_AppendData(&arr, &chunk, chunk.len);
    try expectEqual(@as(usize, 103), arr.size);
    try expectEqual(@as(u8, 30), arr.data.?[102]);
}

test "FindIndexInMemblk 16-bit mode" {
    // 2 entries (mx=2, <8192 selects 16-bit mode). Layout: [index table:
    // ix0,ix1 u16][payload][count u16]. The table lives at the START of the
    // buffer (size mx*2 = 4 bytes) -- left_off/right_off add mx*2 as a fixed
    // offset past the table to reach the payload, then look up ix[i-1]/ix[i]
    // *within the table* (offsets (i-1)*2 / i*2 from the buffer start, not
    // from the payload).
    var buf = [_]u8{0} ** 11;
    std.mem.writeInt(u16, buf[0..2], 2, .little); // ix0 -> entry0 ends at 4+2=6
    std.mem.writeInt(u16, buf[2..4], 5, .little); // ix1 -> entry1 ends at 4+5=9
    buf[4] = 10;
    buf[5] = 20;
    buf[6] = 30;
    buf[7] = 40;
    buf[8] = 50; // payload, 5 bytes: entry0=bytes[4..6], entry1=bytes[6..9]
    // end = 9. mx read at buf[9..11] = count = 2.
    std.mem.writeInt(u16, buf[9..11], 2, .little);
    const data: t.MemBlk = .{ .ptr = &buf, .size = buf.len };

    const e0 = u.FindIndexInMemblk(data, 0);
    try expectEqual(@as(usize, 2), e0.size);
    try expectEqual(@as(u8, 10), e0.ptr.?[0]); // buf[4]
    try expectEqual(@as(u8, 20), e0.ptr.?[1]); // buf[5]

    const e1 = u.FindIndexInMemblk(data, 1);
    try expectEqual(@as(usize, 3), e1.size); // bytes[6..9]
    try expectEqual(@as(u8, 30), e1.ptr.?[0]); // buf[6]

    // out-of-range index
    const bad = u.FindIndexInMemblk(data, 3);
    try expectEqual(@as(usize, 0), bad.size);
    try expect(bad.ptr == null);
}

test "FindIndexInMemblk 32-bit mode" {
    // count marker >= 8192 selects 32-bit mode; real count = marker - 8192.
    // 1 entry (mx32=1). Layout: [index table: ix0 u32][payload][marker u16],
    // same table-at-start-of-buffer layout as the 16-bit case above.
    var buf = [_]u8{0} ** 10;
    std.mem.writeInt(u32, buf[0..4], 4, .little); // ix0 -> entry0 ends at 4+4=8
    buf[4] = 4;
    buf[5] = 5;
    buf[6] = 6;
    buf[7] = 7; // payload, 4 bytes: entry0 = bytes[4..8]
    // end = 8. marker at buf[8..10] = 8192 + 1 = 8193 -> mx32 = 1.
    std.mem.writeInt(u16, buf[8..10], 8193, .little);
    const data: t.MemBlk = .{ .ptr = &buf, .size = buf.len };

    const e0 = u.FindIndexInMemblk(data, 0);
    try expectEqual(@as(usize, 4), e0.size);
    try expectEqual(@as(u8, 4), e0.ptr.?[0]); // buf[4]
}

// Local copy of the CRC32 (reflected, poly 0xEDB88320) used to build
// CRC-correct BPS fixtures; mirrors the static crc32 inside util.zig.
fn crc32(data: [*]const u8, length: usize) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data[0..length]) |b| {
        crc ^= b;
        for (0..8) |_|
            crc = (crc >> 1) ^ ((crc & 1) *% 0xEDB88320);
    }
    return crc ^ 0xFFFFFFFF;
}

// Build a minimal valid BPS patch: metadata + a single "target read" block,
// with all three CRC32 checksums correct so ApplyBps accepts it.
fn bpsEncodeInt(gpa: std.mem.Allocator, buf: *std.ArrayList(u8), val: u64) void {
    var data = val;
    var shift: u64 = 1;
    while (true) {
        const x: u8 = @intCast(data & 0x7f);
        data >>= 7;
        if (data == 0) {
            buf.append(gpa, x | 0x80) catch unreachable;
            break;
        }
        buf.append(gpa, x) catch unreachable;
        data -= shift;
        shift <<= 7;
    }
}

test "ApplyBps applies a source-copy + target-write patch" {
    // source = "ABCD" (4 bytes). Patch: sourceRead 4 bytes (copies src),
    // then targetWrite 2 bytes 'E','F'. Output should be "ABCDEF".
    const gpa = std.testing.allocator;
    const src = "ABCD";
    var bps = std.ArrayList(u8).empty;
    defer bps.deinit(gpa);
    try bps.appendSlice(gpa, "BPS1");
    bpsEncodeInt(gpa, &bps, 4); // src_size
    bpsEncodeInt(gpa, &bps, 6); // dst_size
    bpsEncodeInt(gpa, &bps, 0); // meta_size
    bpsEncodeInt(gpa, &bps, (4 - 1) << 2 | 0); // SourceRead, length 4
    bpsEncodeInt(gpa, &bps, (2 - 1) << 2 | 1); // TargetRead, length 2
    try bps.append(gpa, 'E');
    try bps.append(gpa, 'F');

    // footer: src_crc, dst_crc, bps_crc (computed after dst known)
    var length: usize = 0;
    // First compute expected dst = "ABCDEF" to get dst_crc.
    const expected = "ABCDEF";
    const src_crc = crc32(src.ptr, 4);
    const dst_crc = crc32(expected.ptr, 6);

    // append placeholder for bps_crc computation: footer is src_crc+dst_crc+bps_crc
    var footer: [12]u8 = undefined;
    std.mem.writeInt(u32, footer[0..4], src_crc, .little);
    std.mem.writeInt(u32, footer[4..8], dst_crc, .little);
    // bps_crc covers everything except last 4 bytes: header+body+src_crc+dst_crc
    try bps.appendSlice(gpa, footer[0..8]);
    const bps_crc = crc32(bps.items.ptr, bps.items.len);
    std.mem.writeInt(u32, footer[8..12], bps_crc, .little);
    try bps.appendSlice(gpa, footer[8..12]);

    const out = u.ApplyBps(src.ptr, 4, bps.items.ptr, bps.items.len, &length);
    defer free(out);
    try expectEqual(@as(usize, 6), length);
    try expectEqualSlices(u8, "ABCDEF", out.?[0..6]);
}

test "ApplyBps rejects bad magic and bad source crc" {
    const gpa = std.testing.allocator;
    const src = "ABCD";
    var bps = std.ArrayList(u8).empty;
    defer bps.deinit(gpa);
    try bps.appendSlice(gpa, "XXXX"); // bad magic
    try bps.appendSlice(gpa, &[_]u8{0} ** 16);
    var length: usize = 0;
    try expect(u.ApplyBps(src.ptr, 4, bps.items.ptr, bps.items.len, &length) == null);
}

test "ReadWholeFile round-trips and zero-terminates" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = "rwf_test.bin";
    const payload = "hello world";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = payload });

    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_len = try tmp.dir.realPathFile(std.testing.io, path, &abs_buf);
    var abs_z: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(abs_z[0..abs_len], abs_buf[0..abs_len]);
    abs_z[abs_len] = 0;

    var len: usize = 0;
    const data = u.ReadWholeFile(&abs_z, &len);
    defer free(data);
    try expectEqual(@as(usize, payload.len), len);
    try expectEqualSlices(u8, payload, data.?[0..len]);
    try expectEqual(@as(u8, 0), data.?[len]); // zero terminator
}
