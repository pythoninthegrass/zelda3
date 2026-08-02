// Tier-A unit tests for src/config.zig: a second ParseConfigFile scenario.
// See config_test.zig's header for why each scenario needs its own binary:
// the keymap/joymap tables accumulate across ParseConfigFile calls, so the
// only clean way to test two inis is two processes.

const std = @import("std");
const c = @import("config.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

extern fn free(ptr: ?*anyopaque) void;
extern fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;

export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in config test");
}

comptime {
    _ = c.ParseConfigFile;
    _ = c.FindCmdForSdlKey;
    _ = c.FindCmdForGamepadButton;
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

fn writeAndParse(tmp: *std.testing.TmpDir, ini: []const u8) ![std.fs.max_path_bytes:0]u8 {
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.ini", .data = ini });
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/test.ini", .{tmp.sub_path});
    return absZ(rel);
}

test "WindowSize variants and ExtendedAspectRatio ordering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const ini =
        \\[Graphics]
        \\WindowSize = Auto
        \\OutputMethod = SDL-Software
        \\Shader =
        \\[Sound]
        \\EnableMSU = opuz
        \\[General]
        \\ExtendedAspectRatio = extend_y, 16:10
        \\
    ;
    const path = try writeAndParse(&tmp, ini);

    c.ParseConfigFile(@ptrCast(&path));

    // WindowSize Auto resets both axes.
    try expectEqual(@as(c_int, 0), c.g_config.window_width);
    try expectEqual(@as(c_int, 0), c.g_config.window_height);
    try expectEqual(c.kOutputMethod_SDLSoftware, c.g_config.output_method);
    // Empty Shader value maps to NULL.
    try expect(c.g_config.shader == null);
    try expectEqual(c.kMsuEnabled_Opuz, c.g_config.enable_msu);
    // extend_y first switches h to 240: (240*16/10 - 256)/2 = 64.
    try expect(c.g_config.extend_y);
    try expectEqual(@as(u8, 64), c.g_config.extended_aspect_ratio);
    try expectEqual(@as(u32, 1 | 1024), c.g_config.features0);

    free(c.g_config.memory_buffer);
}
