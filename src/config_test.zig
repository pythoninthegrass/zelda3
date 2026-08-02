// Tier-A unit tests for src/config.zig: the exported ParseBool truth table
// (including the NULL-result form glsl_shader.c relies on), plus real
// ParseConfigFile passes over fixture .ini files checked through g_config
// and the FindCmd* lookups. The keymap/joymap tables are process-global and
// append-only, and the RAM-compare oracle pins the original's one-shot
// ParseConfigFile semantics (in particular RegisterDefaultKeys only fills in
// what the ini didn't mention), so each ParseConfigFile scenario gets its own
// test binary entry in build.zig — one parse per process.

const std = @import("std");
const c = @import("config.zig");

extern fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

extern fn free(ptr: ?*anyopaque) void;

// Die lives in zelda_rtl.c, which is not linked into this test; stub it so
// the object links (the fixtures never hit it).
export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in config test");
}

comptime {
    _ = c.ParseConfigFile;
    _ = c.FindCmdForSdlKey;
    _ = c.FindCmdForGamepadButton;
}

fn cstr(s: []const u8) [*:0]const u8 {
    return @ptrCast(s.ptr);
}

test "ParseBool accepts the documented spellings" {
    var rv: bool = undefined;
    const truths = [_][]const u8{ "1", "yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON" };
    for (truths) |s| {
        try expect(c.ParseBool(cstr(s), &rv));
        try expect(rv);
    }
    const falses = [_][]const u8{ "0", "false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF" };
    for (falses) |s| {
        try expect(c.ParseBool(cstr(s), &rv));
        try expect(!rv);
    }
}

test "ParseBool rejects garbage and partial spellings" {
    // Single letters are rejected too: the tail check needs "es"/"rue"/"o".
    var rv: bool = undefined;
    const bad = [_][]const u8{ "", "2", "01", "10", "y", "t", "f", "n", "yess", "nope", "truth", "ofn", "o", "of", "falsetto", "onnx", " yes", "-1" };
    for (bad) |s|
        try expect(!c.ParseBool(cstr(s), &rv));
}

test "ParseBool with NULL result returns the value directly" {
    // glsl_shader.c calls ParseBool(value, NULL) as a plain predicate.
    try expect(c.ParseBool(cstr("yes"), null));
    try expect(c.ParseBool(cstr("on"), null));
    try expect(!c.ParseBool(cstr("no"), null));
    try expect(!c.ParseBool(cstr("garbage"), null));
}

// tmpDir in 0.16 lands in .zig-cache/tmp/<rand>; libc realpath gives the
// absolute NUL-terminated path ParseConfigFile needs.
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

// The keymap/joymap tables are process-global and append-only, and the
// RAM-compare oracle pins the exact one-shot semantics of the original, so
// ParseConfigFile can only be exercised once per process — each of these
// runs in a fresh binary.

test "ParseConfigFile parses the [Graphics]/[Sound]/[General]/[Features] sections" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const ini =
        \\[Graphics]
        \\WindowSize = 512x448
        \\EnhancedMode7 = true
        \\Fullscreen = 2
        \\WindowScale = 3
        \\OutputMethod = OpenGL
        \\LinearFiltering = yes
        \\NoSpriteLimits = 1
        \\DimFlashes = true
        \\[Sound]
        \\EnableAudio = off
        \\AudioFreq = 44100
        \\AudioChannels = 2
        \\AudioSamples = 512
        \\EnableMSU = deluxe-opuz
        \\ResumeMSU = true
        \\MSUVolume = 42
        \\[General]
        \\Autosave = 1
        \\ExtendedAspectRatio = 16:9
        \\DisplayPerfInTitle = yes
        \\Language = de
        \\[Features]
        \\ItemSwitchLR = 1
        \\TurnWhileDashing = true
        \\MiscBugFixes = yes
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "test.ini", .data = ini });
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/test.ini", .{tmp.sub_path});
    const path = try absZ(rel);

    c.ParseConfigFile(@ptrCast(&path));

    // Graphics
    try expectEqual(@as(c_int, 512), c.g_config.window_width);
    try expectEqual(@as(c_int, 448), c.g_config.window_height);
    try expect(c.g_config.enhanced_mode7);
    try expectEqual(@as(u8, 2), c.g_config.fullscreen);
    try expectEqual(@as(u8, 3), c.g_config.window_scale);
    try expectEqual(c.kOutputMethod_OpenGL, c.g_config.output_method);
    try expect(c.g_config.linear_filtering);
    try expect(c.g_config.no_sprite_limits);
    // Sound
    try expect(!c.g_config.enable_audio);
    try expectEqual(@as(u16, 44100), c.g_config.audio_freq);
    try expectEqual(@as(u8, 2), c.g_config.audio_channels);
    try expectEqual(@as(u16, 512), c.g_config.audio_samples);
    try expectEqual(c.kMsuEnabled_MsuDeluxe | c.kMsuEnabled_Opuz, c.g_config.enable_msu);
    try expect(c.g_config.resume_msu);
    try expectEqual(@as(u8, 42), c.g_config.msuvolume);
    // General
    try expect(c.g_config.autosave);
    try expectEqual(@as(u8, 71), c.g_config.extended_aspect_ratio);
    try expect(c.g_config.display_perf_title);
    try expectEqualStrings("de", std.mem.span(c.g_config.language.?));
    // Features: DimFlashes | ExtendScreen64 | WidescreenVisualFixes |
    // ItemSwitchLR | TurnWhileDashing | MiscBugFixes
    try expectEqual(@as(u32, 65536 | 1 | 1024 | 2 | 4 | 4096), c.g_config.features0);
    // ParseConfigFile defaults msuvolume to 100 before parsing; the ini's
    // MSUVolume = 42 overrides it. The ini bytes stay alive in memory_buffer.
    try expect(c.g_config.memory_buffer != null);

    // Default key bindings registered: A button on 'x', RShift = Controls+4.
    try expectEqual(c.kKeys_Controls + 6, c.FindCmdForSdlKey('x', 0));
    try expectEqual(c.kKeys_Controls + 4, c.FindCmdForSdlKey(0x400000E5, 0x0003));
    // Unmapped key returns 0.
    try expectEqual(0, c.FindCmdForSdlKey('q', 0));
    // Default gamepad: button 0 -> Controls+8, button 1 -> Controls+7.
    try expectEqual(c.kKeys_Controls + 7, c.FindCmdForGamepadButton(0, 0));
    try expectEqual(c.kKeys_Controls + 6, c.FindCmdForGamepadButton(1, 0));

    // The memory buffer belongs to ReadWholeFile (libc malloc).
    free(c.g_config.memory_buffer);
}

