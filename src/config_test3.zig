// Tier-A unit tests for src/config.zig: ExtendedAspectRatio token handling.
// One ParseConfigFile scenario per binary — see config_test.zig's header.

const std = @import("std");
const c = @import("config.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

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

test "ExtendedAspectRatio with unchanged_sprites/no_visual_fixes suppresses the feature bits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const ini =
        \\[General]
        \\ExtendedAspectRatio = 18:9, unchanged_sprites, no_visual_fixes
        \\[Features]
        \\CancelBirdTravel = on
        \\[Sound]
        \\MSUPath = /tmp/msu
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.ini", .data = ini });
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/test.ini", .{tmp.sub_path});
    const path = try absZ(rel);

    c.ParseConfigFile(@ptrCast(&path));

    // 18:9 at h=224: (224*2 - 256)/2 = 96; both feature bits suppressed.
    try expectEqual(@as(u8, 96), c.g_config.extended_aspect_ratio);
    try expectEqual(@as(u32, 8192), c.g_config.features0);
    try expectEqualStrings("/tmp/msu", std.mem.span(c.g_config.msu_path.?));

    free(c.g_config.memory_buffer);
}
