// Tier-A unit tests for src/config.zig: the !include directive.
// One ParseConfigFile scenario per binary — see config_test.zig's header.

const std = @import("std");
const c = @import("config.zig");

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

extern fn free(ptr: ?*anyopaque) void;
extern fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;

export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in config test");
}

comptime {
    _ = c.ParseConfigFile;
}

fn absZ(rel: []const u8) ![std.fs.max_path_bytes:0]u8 {
    var rel_z: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(rel_z[0..rel.len], rel);
    rel_z[rel.len] = 0;
    var out: [std.fs.max_path_bytes:0]u8 = undefined;
    if (realpath(&rel_z, &out) == null)
        return error.FileNotFound;
    out[std.mem.len(@as([*:0]u8, @ptrCast(&out)))] = 0;
    return out;
}

test "!include pulls in a sibling ini relative to the includer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const child =
        \\[Sound]
        \\AudioSamples = 256
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "child.ini", .data = child });
    const ini =
        \\[Graphics]
        \\LinearFiltering = 1
        \\!include child.ini
        \\[Sound]
        \\AudioFreq = 48000
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.ini", .data = ini });
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/test.ini", .{tmp.sub_path});
    const path = try absZ(rel);

    c.ParseConfigFile(@ptrCast(&path));

    try expect(c.g_config.linear_filtering);
    try expectEqual(@as(u16, 48000), c.g_config.audio_freq);
    try expectEqual(@as(u16, 256), c.g_config.audio_samples);

    free(c.g_config.memory_buffer);
}
