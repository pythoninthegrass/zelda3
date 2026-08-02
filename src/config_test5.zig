// Tier-A unit tests for src/config.zig: [KeyMap]/[GamepadMap] overrides.
// One ParseConfigFile scenario per binary — see config_test.zig's header.

const std = @import("std");
const c = @import("config.zig");

const expectEqual = std.testing.expectEqual;

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

test "ParseConfigFile parses [KeyMap]/[GamepadMap] overrides" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const ini =
        \\[KeyMap]
        \\Turbo = Shift+F12
        \\[GamepadMap]
        \\Controls = DpadUp, DpadDown, DpadLeft, DpadRight, Back, Start, B, A, Y, X, L1, R1
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.ini", .data = ini });
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/test.ini", .{tmp.sub_path});
    const path = try absZ(rel);

    c.ParseConfigFile(@ptrCast(&path));

    // KeyMap override: Turbo (id 26) moved to Shift+F12. The [GamepadMap]
    // entries replace the default gamepad set (has_joypad_controls), so the
    // listed buttons keep their defaults here but unlisted ones don't.
    try expectEqual(c.kKeys_Turbo, c.FindCmdForSdlKey(0x40000045, 0x0003));
    // Modifier-free lookup of a plain key must not match a shifted entry.
    try expectEqual(0, c.FindCmdForSdlKey(0x40000045, 0));
    // Unmapped key returns 0.
    try expectEqual(0, c.FindCmdForSdlKey('q', 0));

    // GamepadMap: button 0 -> Controls+8, button 1 -> Controls+7.
    try expectEqual(c.kKeys_Controls + 7, c.FindCmdForGamepadButton(0, 0));
    try expectEqual(c.kKeys_Controls + 6, c.FindCmdForGamepadButton(1, 0));

    free(c.g_config.memory_buffer);
}
