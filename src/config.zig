// Port of src/config.c: zelda3.ini parsing — the [KeyMap]/[GamepadMap] hash
// tables, the [Graphics]/[Sound]/[General]/[Features] g_config fields, and
// the FindCmdForSdlKey/FindCmdForGamepadButton lookup entry points. Every
// exported symbol keeps its exact C-ABI name and signature so the remaining
// .c callers (main.c, glsl_shader.c) link unchanged.
//
// Keymap entries are the SDL keycode remapped to 9 bits (scancodes folded to
// kKeyMod_ScanCode) OR'd with kKeyMod_Shift/Alt/Ctrl; KeyMapHash_Add is an
// append-only chained table whose duplicate-rejection still consumes a slot
// — matching the original exactly, since ParseConfigFile runs once per
// process there.
//
// SDL_GetKeyFromName stays on the C side (SDL.h pulls in all of SDL) and is
// reached via an extern declared in the harnesses that link this module.

const std = @import("std");
const t = @import("types.zig");

extern fn Die(msg: [*:0]const u8) noreturn;

extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern var stderr: *anyopaque;

// util.zig owns these; plain externs so this object links standalone in the
// test harnesses as well as next to util.o in the exe.
extern fn NextDelim(s: *?[*:0]u8, sep: c_int) ?[*:0]u8;
extern fn NextLineStripComments(s: *?[*:0]u8) ?[*:0]u8;
extern fn NextPossiblyQuotedString(s: *?[*:0]u8) ?[*:0]u8;
extern fn SplitKeyValue(p: [*:0]u8) ?[*:0]u8;
extern fn StringEqualsNoCase(a: [*:0]const u8, b: [*:0]const u8) bool;
extern fn StringStartsWithNoCase(a: [*:0]const u8, b: [*:0]const u8) ?[*:0]const u8;
extern fn SkipPrefix(big: [*:0]const u8, little: [*:0]const u8) ?[*:0]const u8;
extern fn ReplaceFilenameWithNewPath(old_path: [*:0]const u8, new_path: [*:0]const u8) ?[*:0]u8;
extern fn ReadWholeFile(name: [*:0]const u8, length: ?*usize) ?[*]t.uint8;

// SDL key name -> keycode (e.g. "Up" -> SDLK_UP) for the [KeyMap] values.
pub extern fn SDL_GetKeyFromName(name: [*:0]const u8) c_int;

const SDLK_SCANCODE_MASK: c_int = 1 << 30;
const SDLK_UNKNOWN: c_int = 0;
const KMOD_ALT: c_int = 0x0300;
const KMOD_CTRL: c_int = 0x00c0;
const KMOD_SHIFT: c_int = 0x0003;

const kKeyMod_ScanCode: t.uint16 = 0x200;
const kKeyMod_Alt: t.uint16 = 0x400;
const kKeyMod_Shift: t.uint16 = 0x800;
const kKeyMod_Ctrl: t.uint16 = 0x1000;

// Command ids (config.h's kKeys_* enum).
pub const kKeys_Null: u8 = 0;
pub const kKeys_Controls: u8 = 1;
pub const kKeys_Controls_Last: u8 = kKeys_Controls + 11;
pub const kKeys_Load: u8 = kKeys_Controls_Last + 1;
pub const kKeys_Load_Last: u8 = kKeys_Load + 19;
pub const kKeys_Save: u8 = kKeys_Load_Last + 1;
pub const kKeys_Save_Last: u8 = kKeys_Save + 19;
pub const kKeys_Replay: u8 = kKeys_Save_Last + 1;
pub const kKeys_Replay_Last: u8 = kKeys_Replay + 19;
pub const kKeys_LoadRef: u8 = kKeys_Replay_Last + 1;
pub const kKeys_LoadRef_Last: u8 = kKeys_LoadRef + 19;
pub const kKeys_ReplayRef: u8 = kKeys_LoadRef_Last + 1;
pub const kKeys_ReplayRef_Last: u8 = kKeys_ReplayRef + 19;
pub const kKeys_CheatLife: u8 = kKeys_ReplayRef_Last + 1;
pub const kKeys_CheatKeys: u8 = kKeys_CheatLife + 1;
pub const kKeys_CheatEquipment: u8 = kKeys_CheatKeys + 1;
pub const kKeys_CheatWalkThroughWalls: u8 = kKeys_CheatEquipment + 1;
pub const kKeys_ClearKeyLog: u8 = kKeys_CheatWalkThroughWalls + 1;
pub const kKeys_StopReplay: u8 = kKeys_ClearKeyLog + 1;
pub const kKeys_Fullscreen: u8 = kKeys_StopReplay + 1;
pub const kKeys_Reset: u8 = kKeys_Fullscreen + 1;
pub const kKeys_Pause: u8 = kKeys_Reset + 1;
pub const kKeys_PauseDimmed: u8 = kKeys_Pause + 1;
pub const kKeys_Turbo: u8 = kKeys_PauseDimmed + 1;
pub const kKeys_ReplayTurbo: u8 = kKeys_Turbo + 1;
pub const kKeys_WindowBigger: u8 = kKeys_ReplayTurbo + 1;
pub const kKeys_WindowSmaller: u8 = kKeys_WindowBigger + 1;
pub const kKeys_DisplayPerf: u8 = kKeys_WindowSmaller + 1;
pub const kKeys_ToggleRenderer: u8 = kKeys_DisplayPerf + 1;
pub const kKeys_VolumeUp: u8 = kKeys_ToggleRenderer + 1;
pub const kKeys_VolumeDown: u8 = kKeys_VolumeUp + 1;
pub const kKeys_Total: u8 = kKeys_VolumeDown + 1;

// Output methods (config.h's kOutputMethod_*).
pub const kOutputMethod_SDL: u8 = 0;
pub const kOutputMethod_SDLSoftware: u8 = 1;
pub const kOutputMethod_OpenGL: u8 = 2;
pub const kOutputMethod_OpenGL_ES: u8 = 3;

// Gamepad buttons (config.h's kGamepadBtn_*).
pub const kGamepadBtn_Invalid: i8 = -1;
pub const kGamepadBtn_A: u8 = 0;
pub const kGamepadBtn_B: u8 = 1;
pub const kGamepadBtn_X: u8 = 2;
pub const kGamepadBtn_Y: u8 = 3;
pub const kGamepadBtn_Back: u8 = 4;
pub const kGamepadBtn_Guide: u8 = 5;
pub const kGamepadBtn_Start: u8 = 6;
pub const kGamepadBtn_L3: u8 = 7;
pub const kGamepadBtn_R3: u8 = 8;
pub const kGamepadBtn_L1: u8 = 9;
pub const kGamepadBtn_R1: u8 = 10;
pub const kGamepadBtn_DpadUp: u8 = 11;
pub const kGamepadBtn_DpadDown: u8 = 12;
pub const kGamepadBtn_DpadLeft: u8 = 13;
pub const kGamepadBtn_DpadRight: u8 = 14;
pub const kGamepadBtn_L2: u8 = 15;
pub const kGamepadBtn_R2: u8 = 16;
pub const kGamepadBtn_Count: u8 = 17;

// MSU enable bits (config.h's kMsuEnabled_*).
pub const kMsuEnabled_Msu: u8 = 1;
pub const kMsuEnabled_MsuDeluxe: u8 = 2;
pub const kMsuEnabled_Opuz: u8 = 4;

// Feature bits (features.h's kFeatures0_*).
const kFeatures0_ExtendScreen64: t.uint32 = 1;
const kFeatures0_SwitchLR: t.uint32 = 2;
const kFeatures0_TurnWhileDashing: t.uint32 = 4;
const kFeatures0_MirrorToDarkworld: t.uint32 = 8;
const kFeatures0_CollectItemsWithSword: t.uint32 = 16;
const kFeatures0_BreakPotsWithSword: t.uint32 = 32;
const kFeatures0_DisableLowHealthBeep: t.uint32 = 64;
const kFeatures0_SkipIntroOnKeypress: t.uint32 = 128;
const kFeatures0_ShowMaxItemsInYellow: t.uint32 = 256;
const kFeatures0_MoreActiveBombs: t.uint32 = 512;
const kFeatures0_WidescreenVisualFixes: t.uint32 = 1024;
const kFeatures0_CarryMoreRupees: t.uint32 = 2048;
const kFeatures0_MiscBugFixes: t.uint32 = 4096;
const kFeatures0_CancelBirdTravel: t.uint32 = 8192;
const kFeatures0_GameChangingBugFixes: t.uint32 = 16384;
const kFeatures0_SwitchLRLimit: t.uint32 = 32768;
const kFeatures0_DimFlashes: t.uint32 = 65536;

pub const Config = extern struct {
    window_width: c_int = 0,
    window_height: c_int = 0,
    enhanced_mode7: bool = false,
    new_renderer: bool = false,
    ignore_aspect_ratio: bool = false,
    fullscreen: t.uint8 = 0,
    window_scale: t.uint8 = 0,
    enable_audio: bool = false,
    linear_filtering: bool = false,
    output_method: t.uint8 = 0,
    audio_freq: t.uint16 = 0,
    audio_channels: t.uint8 = 0,
    audio_samples: t.uint16 = 0,
    autosave: bool = false,
    extended_aspect_ratio: t.uint8 = 0,
    extend_y: bool = false,
    no_sprite_limits: bool = false,
    display_perf_title: bool = false,
    enable_msu: t.uint8 = 0,
    resume_msu: bool = false,
    disable_frame_delay: bool = false,
    msuvolume: t.uint8 = 0,
    features0: t.uint32 = 0,
    link_graphics: ?[*:0]const u8 = null,
    memory_buffer: ?[*]u8 = null,
    shader: ?[*:0]const u8 = null,
    msu_path: ?[*:0]const u8 = null,
    language: ?[*:0]const u8 = null,
};

comptime {
    // Config is consumed field-by-field from C; pin the layout.
    std.debug.assert(@sizeOf(Config) == 80);
    std.debug.assert(@offsetOf(Config, "features0") == 32);
    std.debug.assert(@offsetOf(Config, "link_graphics") == 40);
    std.debug.assert(@offsetOf(Config, "language") == 72);
}

pub export var g_config: Config = .{};

// SDL keycodes for the default bindings (SDL_keycode.h). Lowercase letters
// are ASCII; the rest are SDLK_* values for the named keys used below.
const SDLK_RETURN: c_int = '\r';
const SDLK_TAB: c_int = '\t';
const SDLK_F1: c_int = 0x4000003A;
const SDLK_F2: c_int = 0x4000003B;
const SDLK_F3: c_int = 0x4000003C;
const SDLK_F4: c_int = 0x4000003D;
const SDLK_F5: c_int = 0x4000003E;
const SDLK_F6: c_int = 0x4000003F;
const SDLK_F7: c_int = 0x40000040;
const SDLK_F8: c_int = 0x40000041;
const SDLK_F9: c_int = 0x40000042;
const SDLK_F10: c_int = 0x40000043;
const SDLK_UP: c_int = 0x40000052;
const SDLK_DOWN: c_int = 0x40000051;
const SDLK_LEFT: c_int = 0x40000050;
const SDLK_RIGHT: c_int = 0x4000004F;
const SDLK_RSHIFT: c_int = 0x400000E5;
const SDLK_LSHIFT: c_int = 0x400000E1;
const SDLK_LCTRL: c_int = 0x400000E0;
const SDLK_RCTRL: c_int = 0x400000E4;
const SDLK_LALT: c_int = 0x400000E2;
const SDLK_RALT: c_int = 0x400000E6;

inline fn remapSdlKeycode(key: c_int) t.uint16 {
    return (@as(t.uint16, if (key & SDLK_SCANCODE_MASK != 0) kKeyMod_ScanCode else 0)) |
        (@as(t.uint16, @truncate(@as(u32, @bitCast(key)))) & (kKeyMod_ScanCode - 1));
}

const N: t.uint16 = 0;
const kDefaultKbdControls = blk: {
    var arr: [kKeys_Total]t.uint16 = @splat(0);
    var i: usize = 1;
    const plain = .{ SDLK_UP, SDLK_DOWN, SDLK_LEFT, SDLK_RIGHT, SDLK_RSHIFT, SDLK_RETURN, 'x', 'z', 's', 'a', 'c', 'v' };
    for (plain) |k| {
        arr[i] = remapSdlKeycode(k);
        i += 1;
    }
    const fkeys = .{ SDLK_F1, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6, SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10 };
    // LoadState: F1..F10
    for (fkeys) |k| {
        arr[i] = remapSdlKeycode(k);
        i += 1;
    }
    i += 10;
    // SaveState: Shift+F1..F10
    for (fkeys) |k| {
        arr[i] = remapSdlKeycode(k) | kKeyMod_Shift;
        i += 1;
    }
    i += 10;
    // Replay State: Ctrl+F1..F10
    for (fkeys) |k| {
        arr[i] = remapSdlKeycode(k) | kKeyMod_Ctrl;
        i += 1;
    }
    i += 10;
    i += 40; // LoadRef, ReplayRef
    // CheatLife, CheatKeys, CheatEquipment, CheatWalkThroughWalls
    arr[i] = remapSdlKeycode('w');
    arr[i + 1] = remapSdlKeycode('o');
    arr[i + 2] = remapSdlKeycode('w') | kKeyMod_Shift;
    arr[i + 3] = remapSdlKeycode('e') | kKeyMod_Ctrl;
    i += 4;
    // ClearKeyLog, StopReplay, Fullscreen, Reset, Pause, PauseDimmed, Turbo,
    // ReplayTurbo, WindowBigger, WindowSmaller, DisplayPerf, ToggleRenderer
    const tail = .{ 'k', 'l', SDLK_RETURN, 'r', 'p', 'p', SDLK_TAB, 't', 0, 0, 'f', 'r' };
    const tail_mods = .{ 0, 0, kKeyMod_Alt, kKeyMod_Ctrl, kKeyMod_Shift, 0, 0, 0, 0, 0, 0, 0 };
    for (tail, tail_mods) |k, m| {
        arr[i] = if (k == 0) N else remapSdlKeycode(k) | m;
        i += 1;
    }
    i += 2; // VolumeUp, VolumeDown
    std.debug.assert(i == kKeys_Total);
    break :blk arr;
};

const KeyNameId = struct {
    name: [*:0]const u8,
    id: t.uint16,
    size: t.uint16,
};

const kKeyNameId = [_]KeyNameId{
    .{ .name = "Null", .id = kKeys_Null, .size = 65535 },
    .{ .name = "Controls", .id = kKeys_Controls, .size = kKeys_Controls_Last - kKeys_Controls + 1 },
    .{ .name = "Load", .id = kKeys_Load, .size = kKeys_Load_Last - kKeys_Load + 1 },
    .{ .name = "Save", .id = kKeys_Save, .size = kKeys_Save_Last - kKeys_Save + 1 },
    .{ .name = "Replay", .id = kKeys_Replay, .size = kKeys_Replay_Last - kKeys_Replay + 1 },
    .{ .name = "LoadRef", .id = kKeys_LoadRef, .size = kKeys_LoadRef_Last - kKeys_LoadRef + 1 },
    .{ .name = "ReplayRef", .id = kKeys_ReplayRef, .size = kKeys_ReplayRef_Last - kKeys_ReplayRef + 1 },
    .{ .name = "CheatLife", .id = kKeys_CheatLife, .size = 1 },
    .{ .name = "CheatKeys", .id = kKeys_CheatKeys, .size = 1 },
    .{ .name = "CheatEquipment", .id = kKeys_CheatEquipment, .size = 1 },
    .{ .name = "CheatWalkThroughWalls", .id = kKeys_CheatWalkThroughWalls, .size = 1 },
    .{ .name = "ClearKeyLog", .id = kKeys_ClearKeyLog, .size = 1 },
    .{ .name = "StopReplay", .id = kKeys_StopReplay, .size = 1 },
    .{ .name = "Fullscreen", .id = kKeys_Fullscreen, .size = 1 },
    .{ .name = "Reset", .id = kKeys_Reset, .size = 1 },
    .{ .name = "Pause", .id = kKeys_Pause, .size = 1 },
    .{ .name = "PauseDimmed", .id = kKeys_PauseDimmed, .size = 1 },
    .{ .name = "Turbo", .id = kKeys_Turbo, .size = 1 },
    .{ .name = "ReplayTurbo", .id = kKeys_ReplayTurbo, .size = 1 },
    .{ .name = "WindowBigger", .id = kKeys_WindowBigger, .size = 1 },
    .{ .name = "WindowSmaller", .id = kKeys_WindowSmaller, .size = 1 },
    .{ .name = "VolumeUp", .id = kKeys_VolumeUp, .size = 1 },
    .{ .name = "VolumeDown", .id = kKeys_VolumeDown, .size = 1 },
    .{ .name = "DisplayPerf", .id = kKeys_DisplayPerf, .size = 1 },
    .{ .name = "ToggleRenderer", .id = kKeys_ToggleRenderer, .size = 1 },
};

const KeyMapHashEnt = extern struct {
    key: t.uint16,
    cmd: t.uint16,
    next: t.uint16,
};

var keymap_hash_first: [255]t.uint16 = @splat(0);
var keymap_hash: ?[*]KeyMapHashEnt = null;
var keymap_hash_size: c_int = 0;
var has_keynameid: [kKeyNameId.len]bool = @splat(false);

fn KeyMapHash_Add(key: t.uint16, cmd: t.uint16) bool {
    if ((keymap_hash_size & 0xff) == 0) {
        if (keymap_hash_size > 10000)
            Die("Too many keys");
        keymap_hash = @ptrCast(@alignCast(realloc(keymap_hash, @sizeOf(KeyMapHashEnt) * (@as(usize, @intCast(keymap_hash_size)) + 256))));
    }
    const i = keymap_hash_size;
    keymap_hash_size += 1;
    const ent = &keymap_hash.?[@intCast(i)];
    ent.key = key;
    ent.cmd = cmd;
    ent.next = 0;
    const j = @as(usize, key) % 255;

    var cur: *t.uint16 = &keymap_hash_first[j];
    while (cur.* != 0) {
        const e = &keymap_hash.?[cur.* - 1];
        if (e.key == key)
            return false;
        cur = &e.next;
    }
    cur.* = @intCast(i + 1);
    return true;
}

fn KeyMapHash_Find(key: t.uint16) c_int {
    var i = keymap_hash_first[@as(usize, key) % 255];
    while (i != 0) {
        const ent = &keymap_hash.?[i - 1];
        if (ent.key == key)
            return ent.cmd;
        i = ent.next;
    }
    return 0;
}

pub export fn FindCmdForSdlKey(code: c_int, mod: c_int) c_int {
    if (code & ~(SDLK_SCANCODE_MASK | 0x1ff) != 0)
        return 0;
    var key: t.uint16 = 0;
    if (code != SDLK_LALT and code != SDLK_RALT)
        key |= if (mod & KMOD_ALT != 0) kKeyMod_Alt else 0;
    if (code != SDLK_LCTRL and code != SDLK_RCTRL)
        key |= if (mod & KMOD_CTRL != 0) kKeyMod_Ctrl else 0;
    if (code != SDLK_LSHIFT and code != SDLK_RSHIFT)
        key |= if (mod & KMOD_SHIFT != 0) kKeyMod_Shift else 0;
    key |= remapSdlKeycode(code);
    return KeyMapHash_Find(key);
}

fn ParseKeyArray(value: [*:0]u8, cmd_in: c_int, size: c_int) void {
    var v: ?[*:0]u8 = value;
    var cmd = cmd_in;
    var i: c_int = 0;
    while (i < size) : ({
        i += 1;
        cmd += @intFromBool(cmd != 0);
    }) {
        const s = NextDelim(&v, ',') orelse break;
        if (s[0] == 0)
            continue;
        var key_with_mod: t.uint16 = 0;
        var p: [*:0]const u8 = s;
        while (true) {
            if (StringStartsWithNoCase(p, "Shift+")) |_| {
                key_with_mod |= kKeyMod_Shift;
                p += 6;
            } else if (StringStartsWithNoCase(p, "Ctrl+")) |_| {
                key_with_mod |= kKeyMod_Ctrl;
                p += 5;
            } else if (StringStartsWithNoCase(p, "Alt+")) |_| {
                key_with_mod |= kKeyMod_Alt;
                p += 4;
            } else {
                break;
            }
        }
        const key = SDL_GetKeyFromName(p);
        if (key == SDLK_UNKNOWN) {
            _ = fprintf(stderr, "Unknown key: '%s'\n", p);
            continue;
        }
        if (!KeyMapHash_Add(key_with_mod | remapSdlKeycode(key), @intCast(cmd)))
            _ = fprintf(stderr, "Duplicate key: '%s'\n", p);
    }
}

const GamepadMapEnt = extern struct {
    modifiers: t.uint32,
    cmd: t.uint16,
    next: t.uint16,
};

var joymap_first: [kGamepadBtn_Count]t.uint16 = @splat(0);
var joymap_ents: ?[*]GamepadMapEnt = null;
var joymap_size: c_int = 0;
var has_joypad_controls: bool = false;

fn CountBits32(n_in: t.uint32) c_int {
    var n = n_in;
    var count: c_int = 0;
    while (n != 0) : (count += 1)
        n &= (n - 1);
    return count;
}

fn GamepadMap_Add(button: usize, modifiers: t.uint32, cmd: t.uint16) void {
    if ((joymap_size & 0xff) == 0) {
        if (joymap_size > 1000)
            Die("Too many joypad keys");
        joymap_ents = @ptrCast(@alignCast(realloc(joymap_ents, @sizeOf(GamepadMapEnt) * (@as(usize, @intCast(joymap_size)) + 64))));
        if (joymap_ents == null) Die("realloc failure");
    }
    var p: *t.uint16 = &joymap_first[button];
    // Insert it as early as possible but before after any entry with more modifiers.
    const cb = CountBits32(modifiers);
    while (p.* != 0 and cb < CountBits32(joymap_ents.?[p.* - 1].modifiers))
        p = &joymap_ents.?[p.* - 1].next;
    const i = joymap_size;
    joymap_size += 1;
    const ent = &joymap_ents.?[@intCast(i)];
    ent.modifiers = modifiers;
    ent.cmd = cmd;
    ent.next = p.*;
    p.* = @intCast(i + 1);
}

pub export fn FindCmdForGamepadButton(button: c_int, modifiers: t.uint32) c_int {
    var e = joymap_first[@intCast(button)];
    while (e != 0) : (e = joymap_ents.?[e - 1].next) {
        const ent = &joymap_ents.?[e - 1];
        if ((modifiers & ent.modifiers) == ent.modifiers)
            return ent.cmd;
    }
    return 0;
}

fn ParseGamepadButtonName(value: *[*:0]const u8) c_int {
    const s = value.*;
    // Longest substring first
    const kGamepadKeyNames = [_][*:0]const u8{
        "Back",  "Guide", "Start",    "L3",       "R3",
        "L1",    "R1",    "DpadUp",   "DpadDown", "DpadLeft", "DpadRight", "L2", "R2",
        "Lb",    "Rb",    "A",        "B",        "X",        "Y",
    };
    const kGamepadKeyIds = [_]t.uint8{
        kGamepadBtn_Back, kGamepadBtn_Guide, kGamepadBtn_Start, kGamepadBtn_L3, kGamepadBtn_R3,
        kGamepadBtn_L1,   kGamepadBtn_R1,    kGamepadBtn_DpadUp, kGamepadBtn_DpadDown, kGamepadBtn_DpadLeft, kGamepadBtn_DpadRight, kGamepadBtn_L2, kGamepadBtn_R2,
        kGamepadBtn_L1,   kGamepadBtn_R1,    kGamepadBtn_A,     kGamepadBtn_B,        kGamepadBtn_X,        kGamepadBtn_Y,
    };
    for (kGamepadKeyNames, kGamepadKeyIds) |name, id| {
        if (StringStartsWithNoCase(s, name)) |r| {
            value.* = r;
            return id;
        }
    }
    return kGamepadBtn_Invalid;
}

const kDefaultGamepadCmds = [_]t.uint8{
    kGamepadBtn_DpadUp, kGamepadBtn_DpadDown, kGamepadBtn_DpadLeft, kGamepadBtn_DpadRight, kGamepadBtn_Back, kGamepadBtn_Start,
    kGamepadBtn_B,      kGamepadBtn_A,        kGamepadBtn_Y,        kGamepadBtn_X,         kGamepadBtn_L1,   kGamepadBtn_R1,
};

fn ParseGamepadArray(value: [*:0]u8, cmd_in: c_int, size: c_int) void {
    var v: ?[*:0]u8 = value;
    var cmd = cmd_in;
    var i: c_int = 0;
    while (i < size) : ({
        i += 1;
        cmd += @intFromBool(cmd != 0);
    }) {
        const s = NextDelim(&v, ',') orelse break;
        if (s[0] == 0)
            continue;
        var modifiers: t.uint32 = 0;
        var ss: [*:0]const u8 = s;
        while (true) {
            const button = ParseGamepadButtonName(&ss);
            if (button == kGamepadBtn_Invalid) {
                _ = fprintf(stderr, "Unknown gamepad button: '%s'\n", s);
                break;
            }
            while (ss[0] == ' ' or ss[0] == '\t') ss += 1;
            if (ss[0] == '+') {
                ss += 1;
                modifiers |= @as(t.uint32, 1) << @intCast(button);
            } else if (ss[0] == 0) {
                GamepadMap_Add(@intCast(button), modifiers, @intCast(cmd));
                break;
            } else {
                _ = fprintf(stderr, "Unknown gamepad button: '%s'\n", s);
                break;
            }
        }
    }
}

fn RegisterDefaultKeys() void {
    for (1..kKeyNameId.len) |i| {
        if (!has_keynameid[i]) {
            const size = kKeyNameId[i].size;
            var k = kKeyNameId[i].id;
            var j: t.uint16 = 0;
            while (j < size) : ({
                j += 1;
                k += 1;
            })
                _ = KeyMapHash_Add(kDefaultKbdControls[k], k);
        }
    }
    if (!has_joypad_controls) {
        for (kDefaultGamepadCmds, 0..) |btn, i|
            GamepadMap_Add(btn, 0, kKeys_Controls + @as(t.uint16, @intCast(i)));
    }
}

fn GetIniSection(s: [*:0]const u8) c_int {
    if (StringEqualsNoCase(s, "[KeyMap]"))
        return 0;
    if (StringEqualsNoCase(s, "[Graphics]"))
        return 1;
    if (StringEqualsNoCase(s, "[Sound]"))
        return 2;
    if (StringEqualsNoCase(s, "[General]"))
        return 3;
    if (StringEqualsNoCase(s, "[Features]"))
        return 4;
    if (StringEqualsNoCase(s, "[GamepadMap]"))
        return 5;
    return -1;
}

pub export fn ParseBool(value: [*:0]const u8, result: ?*bool) bool {
    var rv = false;
    var p = value;
    switch (p[0] | 32) {
        '0' => {
            p += 1;
            if (p[0] != 0) return false;
        },
        'f' => {
            p += 1;
            if (!StringEqualsNoCase(p, "alse")) return false;
        },
        'n' => {
            p += 1;
            if (!StringEqualsNoCase(p, "o")) return false;
        },
        'o' => {
            p += 1;
            rv = (p[0] | 32) == 'n';
            if (!StringEqualsNoCase(p, if (rv) "n" else "ff")) return false;
        },
        '1' => {
            p += 1;
            rv = true;
            if (p[0] != 0) return false;
        },
        'y' => {
            p += 1;
            rv = true;
            if (!StringEqualsNoCase(p, "es")) return false;
        },
        't' => {
            p += 1;
            rv = true;
            if (!StringEqualsNoCase(p, "rue")) return false;
        },
        else => return false,
    }
    if (result) |res| {
        res.* = rv;
        return true;
    }
    return rv;
}

fn ParseBoolBit(value: [*:0]const u8, data: *t.uint32, mask: t.uint32) bool {
    var tmp: bool = undefined;
    if (!ParseBool(value, &tmp))
        return false;
    data.* = data.* & ~mask | (if (tmp) mask else 0);
    return true;
}

// C strtol base 10: optional blanks, sign, digits; 0 when no digits.
fn parseLong10(s: [*:0]const u8) c_long {
    var p = s;
    while (p[0] == ' ' or (p[0] >= 0x09 and p[0] <= 0x0d)) p += 1;
    var neg = false;
    if (p[0] == '+' or p[0] == '-') {
        neg = p[0] == '-';
        p += 1;
    }
    var v: c_long = 0;
    while (p[0] >= '0' and p[0] <= '9') : (p += 1)
        v = v * 10 + (p[0] - '0');
    return if (neg) -v else v;
}

fn HandleIniConfig(section: c_int, key: [*:0]const u8, value: [*:0]u8) bool {
    if (section == 0) {
        for (kKeyNameId, 0..) |kni, i| {
            if (StringEqualsNoCase(key, kni.name)) {
                has_keynameid[i] = true;
                ParseKeyArray(value, kni.id, kni.size);
                return true;
            }
        }
    } else if (section == 5) {
        for (kKeyNameId, 0..) |kni, i| {
            if (StringEqualsNoCase(key, kni.name)) {
                if (i == 1)
                    has_joypad_controls = true;
                ParseGamepadArray(value, kni.id, kni.size);
                return true;
            }
        }
    } else if (section == 1) {
        if (StringEqualsNoCase(key, "WindowSize")) {
            if (StringEqualsNoCase(value, "Auto")) {
                g_config.window_width = 0;
                g_config.window_height = 0;
                return true;
            }
            var v: ?[*:0]u8 = value;
            while (NextDelim(&v, 'x')) |s| {
                if (g_config.window_width == 0) {
                    g_config.window_width = @intCast(parseLong10(s));
                } else {
                    g_config.window_height = @intCast(parseLong10(s));
                    return true;
                }
            }
        } else if (StringEqualsNoCase(key, "EnhancedMode7")) {
            return ParseBool(value, &g_config.enhanced_mode7);
        } else if (StringEqualsNoCase(key, "NewRenderer")) {
            return ParseBool(value, &g_config.new_renderer);
        } else if (StringEqualsNoCase(key, "IgnoreAspectRatio")) {
            return ParseBool(value, &g_config.ignore_aspect_ratio);
        } else if (StringEqualsNoCase(key, "Fullscreen")) {
            g_config.fullscreen = @intCast(@as(t.uint8, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "WindowScale")) {
            g_config.window_scale = @intCast(@as(t.uint8, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "OutputMethod")) {
            g_config.output_method = if (StringEqualsNoCase(value, "SDL-Software")) kOutputMethod_SDLSoftware else if (StringEqualsNoCase(value, "OpenGL")) kOutputMethod_OpenGL else if (StringEqualsNoCase(value, "OpenGL ES")) kOutputMethod_OpenGL_ES else kOutputMethod_SDL;
            return true;
        } else if (StringEqualsNoCase(key, "LinearFiltering")) {
            return ParseBool(value, &g_config.linear_filtering);
        } else if (StringEqualsNoCase(key, "NoSpriteLimits")) {
            return ParseBool(value, &g_config.no_sprite_limits);
        } else if (StringEqualsNoCase(key, "LinkGraphics")) {
            g_config.link_graphics = value;
            return true;
        } else if (StringEqualsNoCase(key, "Shader")) {
            g_config.shader = if (value[0] != 0) value else null;
            return true;
        } else if (StringEqualsNoCase(key, "DimFlashes")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_DimFlashes);
        }
    } else if (section == 2) {
        if (StringEqualsNoCase(key, "EnableAudio")) {
            return ParseBool(value, &g_config.enable_audio);
        } else if (StringEqualsNoCase(key, "AudioFreq")) {
            g_config.audio_freq = @intCast(@as(t.uint16, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "AudioChannels")) {
            g_config.audio_channels = @intCast(@as(t.uint8, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "AudioSamples")) {
            g_config.audio_samples = @intCast(@as(t.uint16, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "EnableMSU")) {
            if (StringEqualsNoCase(value, "opuz")) {
                g_config.enable_msu = kMsuEnabled_Opuz;
            } else if (StringEqualsNoCase(value, "deluxe")) {
                g_config.enable_msu = kMsuEnabled_MsuDeluxe;
            } else if (StringEqualsNoCase(value, "deluxe-opuz")) {
                g_config.enable_msu = kMsuEnabled_MsuDeluxe | kMsuEnabled_Opuz;
            } else {
                return ParseBool(value, @ptrCast(&g_config.enable_msu));
            }
            return true;
        } else if (StringEqualsNoCase(key, "MSUPath")) {
            g_config.msu_path = value;
            return true;
        } else if (StringEqualsNoCase(key, "MSUVolume")) {
            g_config.msuvolume = @intCast(@as(t.uint8, @truncate(@as(c_ulong, @bitCast(parseLong10(value))))));
            return true;
        } else if (StringEqualsNoCase(key, "ResumeMSU")) {
            return ParseBool(value, &g_config.resume_msu);
        }
    } else if (section == 3) {
        if (StringEqualsNoCase(key, "Autosave")) {
            g_config.autosave = parseLong10(value) != 0;
            return true;
        } else if (StringEqualsNoCase(key, "ExtendedAspectRatio")) {
            var h: c_int = 224;
            var nospr = false;
            var novis = false;
            // todo: make it not depend on the order
            var v: ?[*:0]u8 = value;
            while (NextDelim(&v, ',')) |s| {
                if (std.mem.eql(u8, std.mem.span(s), "extend_y")) {
                    h = 240;
                    g_config.extend_y = true;
                } else if (std.mem.eql(u8, std.mem.span(s), "16:9")) {
                    g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 16, 9) - 256, 2));
                } else if (std.mem.eql(u8, std.mem.span(s), "16:10")) {
                    g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 16, 10) - 256, 2));
                } else if (std.mem.eql(u8, std.mem.span(s), "18:9")) {
                    g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 18, 9) - 256, 2));
                } else if (std.mem.eql(u8, std.mem.span(s), "4:3")) {
                    g_config.extended_aspect_ratio = 0;
                } else if (std.mem.eql(u8, std.mem.span(s), "unchanged_sprites")) {
                    nospr = true;
                } else if (std.mem.eql(u8, std.mem.span(s), "no_visual_fixes")) {
                    novis = true;
                } else {
                    return false;
                }
            }
            if (g_config.extended_aspect_ratio != 0 and !nospr)
                g_config.features0 |= kFeatures0_ExtendScreen64;
            if (g_config.extended_aspect_ratio != 0 and !novis)
                g_config.features0 |= kFeatures0_WidescreenVisualFixes;
            return true;
        } else if (StringEqualsNoCase(key, "DisplayPerfInTitle")) {
            return ParseBool(value, &g_config.display_perf_title);
        } else if (StringEqualsNoCase(key, "DisableFrameDelay")) {
            return ParseBool(value, &g_config.disable_frame_delay);
        } else if (StringEqualsNoCase(key, "Language")) {
            g_config.language = value;
            return true;
        }
    } else if (section == 4) {
        if (StringEqualsNoCase(key, "ItemSwitchLR")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_SwitchLR);
        } else if (StringEqualsNoCase(key, "ItemSwitchLRLimit")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_SwitchLRLimit);
        } else if (StringEqualsNoCase(key, "TurnWhileDashing")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_TurnWhileDashing);
        } else if (StringEqualsNoCase(key, "MirrorToDarkworld")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_MirrorToDarkworld);
        } else if (StringEqualsNoCase(key, "CollectItemsWithSword")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_CollectItemsWithSword);
        } else if (StringEqualsNoCase(key, "BreakPotsWithSword")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_BreakPotsWithSword);
        } else if (StringEqualsNoCase(key, "DisableLowHealthBeep")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_DisableLowHealthBeep);
        } else if (StringEqualsNoCase(key, "SkipIntroOnKeypress")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_SkipIntroOnKeypress);
        } else if (StringEqualsNoCase(key, "ShowMaxItemsInYellow")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_ShowMaxItemsInYellow);
        } else if (StringEqualsNoCase(key, "MoreActiveBombs")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_MoreActiveBombs);
        } else if (StringEqualsNoCase(key, "CarryMoreRupees")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_CarryMoreRupees);
        } else if (StringEqualsNoCase(key, "MiscBugFixes")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_MiscBugFixes);
        } else if (StringEqualsNoCase(key, "GameChangingBugFixes")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_GameChangingBugFixes);
        } else if (StringEqualsNoCase(key, "CancelBirdTravel")) {
            return ParseBoolBit(value, &g_config.features0, kFeatures0_CancelBirdTravel);
        }
    }
    return false;
}

fn ParseOneConfigFile(filename: [*:0]const u8, depth: c_int) bool {
    const fd = ReadWholeFile(filename, null) orelse return false;
    var filedata: ?[*:0]u8 = @ptrCast(fd);

    var section: c_int = -2;
    g_config.memory_buffer = fd;

    var lineno: c_int = 1;
    while (NextLineStripComments(&filedata)) |p| : (lineno += 1) {
        if (p[0] == 0)
            continue; // empty line
        if (p[0] == '[') {
            section = GetIniSection(p);
            if (section < 0)
                _ = fprintf(stderr, "%s:%d: Invalid .ini section %s\n", filename, lineno, p);
        } else if (p[0] == '!' and SkipPrefix(p + 1, "include ") != null) {
            var tt: ?[*:0]u8 = p + 8;
            const new_filename = ReplaceFilenameWithNewPath(filename, NextPossiblyQuotedString(&tt).?);
            if (depth > 10 or !ParseOneConfigFile(new_filename.?, depth + 1))
                _ = fprintf(stderr, "Warning: Unable to read %s\n", new_filename.?);
            free(new_filename);
        } else if (section == -2) {
            _ = fprintf(stderr, "%s:%d: Expecting [section]\n", filename, lineno);
        } else {
            const v = SplitKeyValue(p) orelse {
                _ = fprintf(stderr, "%s:%d: Expecting 'key=value'\n", filename, lineno);
                continue;
            };
            if (section >= 0 and !HandleIniConfig(section, p, v))
                _ = fprintf(stderr, "%s:%d: Can't parse '%s'\n", filename, lineno, p);
        }
    }
    return true;
}

pub export fn ParseConfigFile(filename: ?[*:0]const u8) void {
    g_config.msuvolume = 100; // default msu volume, 100%

    if (filename != null or !ParseOneConfigFile("zelda3.user.ini", 0)) {
        const fname = filename orelse "zelda3.ini";
        if (!ParseOneConfigFile(fname, 0))
            _ = fprintf(stderr, "Warning: Unable to read config file %s\n", fname);
    }
    RegisterDefaultKeys();
}
