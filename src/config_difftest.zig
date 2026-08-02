// Tier-B differential test for src/config.zig: links the pre-port config.c
// (symbols renamed to c_* via objcopy, wired in build.zig's difftest step)
// alongside the ported Zig module and diffs their behavior over randomized
// .ini files.
//
// The keymap/joymap tables are process-global append-only state and the
// original's KeyMapHash_Add leaks a dead slot per rejected duplicate key, so
// repeated in-process ParseConfigFile calls corrupt the table identically on
// both sides after ~5 parses. The harness therefore re-execs itself per
// randomized ini (ZELDA3_CFG_WORKER=c|z selects the flavour, ZELDA3_CFG_INI
// is the file to parse): each child runs ParseConfigFile exactly once with
// zeroed tables — exactly how production uses it — then dumps g_config plus
// the FindCmd* probe matrix as hex/comma text on stdout. The parent diffs
// the two dumps byte-for-byte.
//
// The first-declared test performs the worker dispatch (Zig runs tests in
// declaration order), calling _exit before the runner prints anything so the
// parent's readback is pure dump. All child I/O goes through libc directly
// (fprintf/popen/fread); std.process.Child/std.io shapes changed under us in
// 0.16 and libc is the stable surface here.

const std = @import("std");
const c = @import("config.zig");

const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

extern fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern fn fflush(stream: ?*anyopaque) c_int;
extern fn _exit(status: c_int) noreturn;
extern var stdout: *anyopaque;

extern fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: *anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *anyopaque) usize;

extern fn fopen(name: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: *anyopaque) c_int;

extern fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;

extern var stderr: *anyopaque;

// Zig 0.16 removed std.fs.selfExePath; /proc/self/exe is the Linux answer
// (the difftest is Linux-only anyway, same as zig:parity-replay).
fn selfExePath(buf: []u8) ![]const u8 {
    const n = readlink("/proc/self/exe", buf.ptr, buf.len);
    if (n < 0) return error.SelfExePathFailed;
    return buf[0..@intCast(n)];
}

// Die lives in zelda_rtl.c, which is not linked into this test; the fixtures
// never hit it. Stub it so the renamed C reference object links.
export fn Die(msg: [*:0]const u8) noreturn {
    std.debug.print("Die: {s}\n", .{msg});
    @panic("Die called in difftest");
}

// The renamed C reference (config.c + util.c, c_ prefix via objcopy).
extern fn c_ParseConfigFile(filename: ?[*:0]const u8) void;
extern fn c_ParseBool(value: [*:0]const u8, result: ?*bool) bool;
extern fn c_FindCmdForSdlKey(code: c_int, mod: c_int) c_int;
extern fn c_FindCmdForGamepadButton(button: c_int, modifiers: u32) c_int;
extern var c_g_config: c.Config;

comptime {
    // Pull the Zig port's exported symbols into this binary; its plain util
    // externs resolve against the util.o linked into this test (same split
    // as the exe), the c_* externs against the renamed C objects.
    _ = c.ParseConfigFile;
    _ = c.ParseBool;
    _ = c.FindCmdForSdlKey;
    _ = c.FindCmdForGamepadButton;
}

// SDL keycodes the probe matrix covers (plus the ASCII range 32..126).
const kProbeKeys = [_]c_int{
    0x40000039, // F1 .. F12
    0x4000003A, 0x4000003B, 0x4000003C, 0x4000003D, 0x4000003E,
    0x4000003F, 0x40000040, 0x40000041, 0x40000042, 0x40000043,
    0x40000044, 0x40000045,
    0x40000052, 0x40000051, 0x40000050, 0x4000004F, // Up Down Left Right
    0x400000E0, 0x400000E4, 0x400000E1, 0x400000E5, // LCtrl RCtrl LShift RShift
    0x400000E2, 0x400000E6, // LAlt RAlt
    '\r', '\t',
};
const kProbeMods = [_]c_int{ 0, 0x0003, 0x00c0, 0x0300, 0x03c3 };

fn dumpState(comptime flavor: []const u8) void {
    const cfg = if (comptime std.mem.eql(u8, flavor, "c")) &c_g_config else &c.g_config;
    const bytes: [*]const u8 = @ptrCast(cfg);
    // Zero the pointer fields before dumping: they hold addresses into the
    // process's own ini buffer and differ across processes by nature. The
    // strings they point at are dumped separately below.
    var raw: [@sizeOf(c.Config)]u8 = undefined;
    @memcpy(&raw, bytes[0..@sizeOf(c.Config)]);
    @memset(raw[@offsetOf(c.Config, "link_graphics")..@offsetOf(c.Config, "link_graphics") + 40], 0);
    // stderr, not stdout: the test runner prints its per-test prefix to
    // stdout before this test body runs, which would poison the parent's
    // byte diff. stderr is captured separately by runWorker's popen (2>&1
    // is appended in the shell command).
    const out = stderr;
    _ = fprintf(out, "%s cfg=", flavor.ptr);
    for (raw) |b|
        _ = fprintf(out, "%02x", @as(c_uint, b));
    _ = fprintf(out, "\n");

    const ptrs = .{
        .{ "lg", cfg.link_graphics },
        .{ "sh", cfg.shader },
        .{ "mp", cfg.msu_path },
        .{ "la", cfg.language },
    };
    inline for (ptrs) |p| {
        _ = fprintf(out, "%s %s=", flavor.ptr, p[0].ptr);
        if (p[1]) |s| {
            var i: usize = 0;
            while (s[i] != 0) : (i += 1)
                _ = fprintf(out, "%02x", @as(c_uint, s[i]));
        }
        _ = fprintf(out, "\n");
    }

    const findKey = if (comptime std.mem.eql(u8, flavor, "c")) c_FindCmdForSdlKey else c.FindCmdForSdlKey;
    const findPad = if (comptime std.mem.eql(u8, flavor, "c")) c_FindCmdForGamepadButton else c.FindCmdForGamepadButton;
    _ = fprintf(out, "%s kbd=", flavor.ptr);
    for (kProbeKeys) |key| {
        for (kProbeMods) |mod|
            _ = fprintf(out, "%d,", findKey(key, mod));
    }
    var ch: c_int = 32;
    while (ch < 127) : (ch += 1) {
        for (kProbeMods) |mod|
            _ = fprintf(out, "%d,", findKey(ch, mod));
    }
    _ = fprintf(out, "\n");
    _ = fprintf(out, "%s pad=", flavor.ptr);
    var btn: c_int = 0;
    while (btn < c.kGamepadBtn_Count) : (btn += 1) {
        var m: u6 = 0;
        while (m < 32) : (m += 1)
            _ = fprintf(out, "%d,", findPad(btn, @as(u32, 1) << @intCast(m)));
        // plus a few multi-modifier combos
        _ = fprintf(out, "%d,%d,%d,", findPad(btn, 0), findPad(btn, 0x3), findPad(btn, 0xffff));
    }
    _ = fprintf(out, "\n");
}

test "worker dispatch (must stay first)" {
    const flavor = getenv("ZELDA3_CFG_WORKER") orelse return;
    const ini = getenv("ZELDA3_CFG_INI") orelse _exit(2);
    if (std.mem.orderZ(u8, flavor, "c") == .eq) {
        c_ParseConfigFile(ini);
        dumpState("c");
    } else {
        c.ParseConfigFile(ini);
        dumpState("z");
    }
    _ = fflush(stderr);
    _exit(0);
}

var prng: ?std.Random.DefaultPrng = null;
fn rnd() std.Random {
    if (prng == null)
        prng = std.Random.DefaultPrng.init(0xc0ff19);
    return prng.?.random();
}

const kSections = [_][]const u8{ "[KeyMap]", "[Graphics]", "[Sound]", "[General]", "[Features]", "[GamepadMap]" };
const kGraphicsKeys = [_][]const u8{ "WindowSize", "EnhancedMode7", "NewRenderer", "IgnoreAspectRatio", "Fullscreen", "WindowScale", "OutputMethod", "LinearFiltering", "NoSpriteLimits", "DimFlashes" };
const kSoundKeys = [_][]const u8{ "EnableAudio", "AudioFreq", "AudioChannels", "AudioSamples", "EnableMSU", "MSUVolume", "ResumeMSU" };
const kGeneralKeys = [_][]const u8{ "Autosave", "ExtendedAspectRatio", "DisplayPerfInTitle", "DisableFrameDelay", "Language" };
const kFeatureKeys = [_][]const u8{ "ItemSwitchLR", "ItemSwitchLRLimit", "TurnWhileDashing", "MirrorToDarkworld", "CollectItemsWithSword", "BreakPotsWithSword", "DisableLowHealthBeep", "SkipIntroOnKeypress", "ShowMaxItemsInYellow", "MoreActiveBombs", "CarryMoreRupees", "MiscBugFixes", "GameChangingBugFixes", "CancelBirdTravel" };
const kMapKeys = [_][]const u8{ "Controls", "Load", "Save", "Replay", "LoadRef", "ReplayRef", "CheatLife", "CheatKeys", "CheatEquipment", "CheatWalkThroughWalls", "ClearKeyLog", "StopReplay", "Fullscreen", "Reset", "Pause", "PauseDimmed", "Turbo", "ReplayTurbo", "WindowBigger", "WindowSmaller", "VolumeUp", "VolumeDown", "DisplayPerf", "ToggleRenderer" };
const kKeyNames = [_][]const u8{ "a", "b", "x", "y", "z", "s", "c", "v", "w", "o", "e", "p", "t", "k", "l", "r", "f", "q", "Return", "Tab", "Up", "Down", "Left", "Right", "F1", "F2", "F3", "F4", "F5", "F10", "RShift", "LShift" };
const kPadNames = [_][]const u8{ "A", "B", "X", "Y", "Back", "Start", "L1", "R1", "L2", "R2", "DpadUp", "DpadDown", "DpadLeft", "DpadRight" };
const kBoolVals = [_][]const u8{ "0", "1", "yes", "no", "true", "false", "on", "off", "garbage", "2" };

fn pick(comptime T: type, vals: []const T) T {
    return vals[rnd().uintLessThan(usize, vals.len)];
}

fn wstr(f: *anyopaque, s: []const u8) void {
    _ = fprintf(f, "%.*s", @as(c_int, @intCast(s.len)), s.ptr);
}

fn wint(f: *anyopaque, v: u32) void {
    _ = fprintf(f, "%u", @as(c_uint, v));
}

// Emit one "key = value" line whose key belongs to the current section.
fn writeRandomEntry(f: *anyopaque, section: []const u8) void {
    const is_keymap = std.mem.eql(u8, section, "[KeyMap]");
    const is_padmap = std.mem.eql(u8, section, "[GamepadMap]");
    const is_graphics = std.mem.eql(u8, section, "[Graphics]");
    const is_sound = std.mem.eql(u8, section, "[Sound]");
    const is_general = std.mem.eql(u8, section, "[General]");
    const is_features = std.mem.eql(u8, section, "[Features]");

    if (is_keymap) {
        wstr(f, pick([]const u8, &kMapKeys));
        wstr(f, " = ");
        const n = rnd().uintLessThan(usize, 3) + 1;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (i != 0) wstr(f, ", ");
            if (rnd().boolean())
                wstr(f, pick([]const u8, &.{ "Shift+", "Ctrl+", "Alt+", "Ctrl+Alt+" }));
            wstr(f, pick([]const u8, &kKeyNames));
        }
    } else if (is_padmap) {
        wstr(f, pick([]const u8, &kMapKeys));
        wstr(f, " = ");
        const n = rnd().uintLessThan(usize, 3) + 1;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (i != 0) wstr(f, ", ");
            if (rnd().uintLessThan(usize, 3) == 0) {
                wstr(f, pick([]const u8, &kPadNames));
                wstr(f, "+");
            }
            wstr(f, pick([]const u8, &kPadNames));
        }
    } else if (is_graphics) {
        wstr(f, pick([]const u8, &kGraphicsKeys));
        wstr(f, " = ");
        switch (rnd().uintLessThan(usize, 4)) {
            0 => wstr(f, pick([]const u8, &kBoolVals)),
            1 => wint(f, rnd().uintLessThan(u32, 65536)),
            2 => wstr(f, pick([]const u8, &.{ "Auto", "512x448", "OpenGL", "SDL-Software", "OpenGL ES" })),
            else => wstr(f, pick([]const u8, &kBoolVals)),
        }
    } else if (is_sound) {
        wstr(f, pick([]const u8, &kSoundKeys));
        wstr(f, " = ");
        switch (rnd().uintLessThan(usize, 4)) {
            0 => wstr(f, pick([]const u8, &kBoolVals)),
            1 => wint(f, rnd().uintLessThan(u32, 65536)),
            2 => wstr(f, pick([]const u8, &.{ "opuz", "deluxe", "deluxe-opuz" })),
            else => wstr(f, pick([]const u8, &kBoolVals)),
        }
    } else if (is_general) {
        wstr(f, pick([]const u8, &kGeneralKeys));
        wstr(f, " = ");
        switch (rnd().uintLessThan(usize, 3)) {
            0 => wstr(f, pick([]const u8, &kBoolVals)),
            1 => wint(f, rnd().uintLessThan(u32, 4)),
            else => wstr(f, pick([]const u8, &.{ "16:9", "16:10", "18:9", "4:3", "16:9, extend_y", "extend_y, 16:10", "16:9, unchanged_sprites", "16:9, no_visual_fixes", "en", "de" })),
        }
    } else if (is_features) {
        wstr(f, pick([]const u8, &kFeatureKeys));
        wstr(f, " = ");
        wstr(f, pick([]const u8, &kBoolVals));
    } else {
        wstr(f, pick([]const u8, &kMapKeys));
        wstr(f, " = ");
        wstr(f, pick([]const u8, &kBoolVals));
    }
    wstr(f, "\n");
}

fn genIni(path: [*:0]const u8) !void {
    const f = fopen(path, "w") orelse return error.OpenFailed;
    defer _ = fclose(f);
    const nsec = rnd().uintLessThan(usize, 4) + 1;
    var s: usize = 0;
    while (s < nsec) : (s += 1) {
        const section = pick([]const u8, &kSections);
        wstr(f, section);
        wstr(f, "\n");
        const nkeys = rnd().uintLessThan(usize, 6) + 1;
        var k: usize = 0;
        while (k < nkeys) : (k += 1)
            writeRandomEntry(f, section);
        wstr(f, "\n");
    }
}

// The child test runner's per-test progress line ("1/3 ...worker dispatch
// (must stay first)...") shares stderr with the dump. Keep only the tagged
// dump lines ("c cfg=", "z kbd=", ...) and strip the flavour tag, so the
// byte diff compares pure state.
fn filterDump(s: []const u8, tag: u8, out: *std.ArrayList(u8)) !void {
    var rest = s;
    while (rest.len != 0) {
        const nl = std.mem.indexOfScalar(u8, rest, '\n');
        const line = if (nl) |i| rest[0..i] else rest;
        rest = if (nl) |i| rest[i + 1 ..] else rest[rest.len..];
        if (line.len > 2 and line[0] == tag and line[1] == ' ') {
            try out.appendSlice(std.testing.allocator, line[2..]);
            try out.append(std.testing.allocator, '\n');
        }
    }
}

// Run one worker flavour and append its stdout to `out`.
fn runWorker(flavor: []const u8, exe: []const u8, ini: []const u8, out: *std.ArrayList(u8)) !void {
    var cmd_buf: [4096]u8 = undefined;
    const cmd = try std.fmt.bufPrintZ(&cmd_buf, "ZELDA3_CFG_WORKER={s} ZELDA3_CFG_INI={s} {s} 2>&1", .{ flavor, ini, exe });
    const pipe = popen(cmd.ptr, "r") orelse return error.PopenFailed;
    defer _ = pclose(pipe);
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = fread(&chunk, 1, chunk.len, pipe);
        if (n == 0) break;
        try out.appendSlice(std.testing.allocator, chunk[0..n]);
    }
}

test "diff ParseConfigFile over randomized ini files (fresh process per side)" {
    var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe = try selfExePath(&exe_buf);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const ini_rel = try std.fmt.bufPrint(&rel_buf, ".zig-cache/tmp/{s}/rand.ini", .{tmp.sub_path});
    var ini_z: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(ini_z[0..ini_rel.len], ini_rel);
    ini_z[ini_rel.len] = 0;

    var out_c = std.ArrayList(u8).empty;
    defer out_c.deinit(std.testing.allocator);
    var out_z = std.ArrayList(u8).empty;
    defer out_z.deinit(std.testing.allocator);

    var iter: usize = 0;
    while (iter < 60) : (iter += 1) {
        try genIni(&ini_z);
        out_c.clearRetainingCapacity();
        out_z.clearRetainingCapacity();
        try runWorker("c", exe, ini_rel, &out_c);
        try runWorker("z", exe, ini_rel, &out_z);
        var dump_c = std.ArrayList(u8).empty;
        defer dump_c.deinit(std.testing.allocator);
        var dump_z = std.ArrayList(u8).empty;
        defer dump_z.deinit(std.testing.allocator);
        try filterDump(out_c.items, 'c', &dump_c);
        try filterDump(out_z.items, 'z', &dump_z);
        try expectEqualStrings(dump_c.items, dump_z.items);
    }
}

test "diff ParseBool over fixed spellings" {
    const spellings = [_][]const u8{
        "0",  "1",    "yes",  "no",   "true", "false", "on",  "off",
        "Yes", "TRUE", "Off",  "NO",   "2",    "garbage", "",   "of",
        "y",  "t",     "f",    "n",    "o",    "ofn",   "ofx",
    };
    for (spellings) |s| {
        var rv_z: bool = undefined;
        var rv_c: bool = undefined;
        const sz: [*:0]const u8 = @ptrCast(s.ptr);
        const ok_z = c.ParseBool(sz, &rv_z);
        const ok_c = c_ParseBool(sz, &rv_c);
        try expect(ok_z == ok_c);
        if (ok_z)
            try expect(rv_z == rv_c);
    }
}
