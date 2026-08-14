// Port of src/load_gfx.c: graphics decompression/loading (tiles, sprites,
// palettes) from zelda3_assets.dat into the RAM-mirrored VRAM/CGRAM staging
// buffers. Every exported symbol keeps its exact C-ABI name and signature so
// the remaining .c callers link unchanged. All game state lives in g_ram
// (variables.zig accessors), byte-for-byte where the original 65816 code and
// the RAM-compare oracle expect it.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

// Allow this to be overwritten
export var kGlovesColor: [2]t.uint16 = .{ 0x52f6, 0x376 };

// assets.h: FindInAssetArray + the g_asset_ptrs-indexed macros this file uses.
extern fn FindInAssetArray(asset: c_int, idx: c_int) t.MemBlk;
extern var g_asset_ptrs: [165]?[*]const t.uint8;

inline fn kSprGfx(idx: c_int) t.MemBlk {
    return FindInAssetArray(64, idx);
}
inline fn kBgGfx(idx: c_int) t.MemBlk {
    return FindInAssetArray(65, idx);
}
inline fn kDialogueFont(idx: c_int) t.MemBlk {
    return FindInAssetArray(95, idx);
}
inline fn kPalette_DungBgMain() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[79].?);
}
inline fn kPalette_MainSpr() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[80].?);
}
inline fn kPalette_ArmorAndGloves() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[81].?);
}
inline fn kPalette_Sword() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[82].?);
}
inline fn kPalette_Shield() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[83].?);
}
inline fn kPalette_SpriteAux3() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[84].?);
}
inline fn kPalette_MiscSprite_Indoors() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[85].?);
}
inline fn kPalette_MiscSprite() [*]align(1) const t.uint16 {
    return kPalette_MiscSprite_Indoors();
}
inline fn kPalette_SpriteAux1() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[86].?);
}
inline fn kPalette_OverworldBgMain() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[87].?);
}
inline fn kPalette_OverworldBgAux12() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[88].?);
}
inline fn kPalette_OverworldBgAux3() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[89].?);
}
inline fn kPalette_PalaceMapBg() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[90].?);
}
inline fn kPalette_PalaceMapSpr() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[91].?);
}
inline fn kHudPalData() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[92].?);
}
inline fn kOverworldMapPaletteData() [*]align(1) const t.uint16 {
    return @ptrCast(g_asset_ptrs[93].?);
}

// features.h: enhanced_features0 is a C-only macro (not in variables.zig),
// reimplemented inline; the two bit constants this file tests.
inline fn enhanced_features0() *align(1) t.uint32 {
    return @ptrCast(&v.g_ram[0x64c]);
}
const kFeatures0_MiscBugFixes: t.uint32 = 4096;
const kFeatures0_DimFlashes: t.uint32 = 65536;

// Cross-module tables, still defined in their original C files.
extern const kUpperBitmasks: [16]t.uint16;
extern const kLitTorchesColorPlus: [4]t.uint8;
extern const kVariousPacks: [16]t.uint8;

// Cross-module functions, still defined in their original C files.
extern fn HdmaSetup(addr6: t.uint32, addr7: t.uint32, transfer_unit: t.uint8, reg6: t.uint8, reg7: t.uint8, indirect_bank: t.uint8) void;
extern fn SetTargetOverworldWarpToPyramid() void;
extern fn PreOverworld_LoadOverlays() void;
extern fn Overworld_DrawScreenAtCurrentMirrorPosition() void;
extern fn MirrorWarp_LoadSpritesAndColors() void;
extern fn HandleFollowersAfterMirroring() void;
extern fn Sprite_ResetAll() void;
extern fn FindIndexInMemblk(data: t.MemBlk, i: usize) t.MemBlk;

// snes/snes_regs.h register addresses used directly (not via a *_copy shadow).
const HDMAEN: c_int = 0x420c;
const WH0: c_uint = 0x2126;

// zelda_rtl.h: zelda_snes_dummy_write is a static inline no-op (debug-only
// hook point in the original), so this is a plain no-op translation too.
inline fn zelda_snes_dummy_write(adr: c_int, val: t.uint8) void {
    _ = adr;
    _ = val;
}

const kPaletteFilteringBits = [64]t.uint16{
    0xffff, 0xffff, 0xfffe, 0xffff, 0x7fff, 0x7fff, 0x7fdf, 0xfbff, 0x7f7f, 0x7f7f, 0x7df7, 0xefbf, 0x7bdf, 0x7bdf, 0x77bb, 0xddef,
    0x7777, 0x7777, 0x6edd, 0xbb77, 0x6db7, 0x6db7, 0x5b6d, 0xb6db, 0x5b5b, 0x5b5b, 0x56b6, 0xad6b, 0x5555, 0xad6b, 0x5555, 0xaaab,
    0x5555, 0x5555, 0x2a55, 0x5555, 0x2a55, 0x2a55, 0x294a, 0x5295, 0x2525, 0x2525, 0x2492, 0x4925, 0x1249, 0x1249, 0x1122, 0x4489,
    0x1111, 0x1111, 0x844, 0x2211, 0x421, 0x421, 0x208, 0x1041, 0x101, 0x101, 0x20, 0x401, 1, 1, 0, 1,
};
const kPaletteFilter_Agahnim_Tab = [3]t.uint16{ 0x160, 0x180, 0x1a0 };
const kMainTilesets = [37][8]t.uint8{
    .{ 0, 1, 16, 6, 14, 31, 24, 15 },
    .{ 0, 1, 16, 8, 14, 34, 27, 15 },
    .{ 0, 1, 16, 6, 14, 31, 24, 15 },
    .{ 0, 1, 19, 7, 14, 35, 28, 15 },
    .{ 0, 1, 16, 7, 14, 33, 24, 15 },
    .{ 0, 1, 16, 9, 14, 32, 25, 15 },
    .{ 2, 3, 18, 11, 14, 33, 26, 15 },
    .{ 0, 1, 17, 12, 14, 36, 27, 15 },
    .{ 0, 1, 17, 8, 14, 34, 27, 15 },
    .{ 0, 1, 17, 12, 14, 37, 26, 15 },
    .{ 0, 1, 17, 12, 14, 38, 27, 15 },
    .{ 0, 1, 20, 10, 14, 39, 29, 15 },
    .{ 0, 1, 17, 10, 14, 40, 30, 15 },
    .{ 2, 3, 18, 11, 14, 41, 22, 15 },
    .{ 0, 1, 21, 13, 14, 42, 24, 15 },
    .{ 0, 1, 16, 7, 14, 35, 28, 15 },
    .{ 0, 1, 19, 7, 14, 4, 5, 15 },
    .{ 0, 1, 19, 7, 14, 4, 5, 15 },
    .{ 0, 1, 16, 9, 14, 32, 27, 15 },
    .{ 0, 1, 16, 9, 14, 42, 23, 15 },
    .{ 2, 3, 18, 11, 14, 33, 28, 15 },
    .{ 0, 8, 17, 27, 34, 46, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 58, 59, 60, 61, 83, 77, 62, 91 },
    .{ 66, 67, 68, 69, 32, 43, 63, 93 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 0, 8, 16, 24, 32, 43, 93, 91 },
    .{ 113, 114, 113, 114, 32, 43, 93, 91 },
    .{ 58, 59, 60, 61, 83, 77, 62, 91 },
    .{ 66, 67, 68, 69, 32, 43, 63, 89 },
    .{ 0, 114, 113, 114, 32, 43, 93, 15 },
    .{ 22, 57, 29, 23, 64, 65, 57, 30 },
    .{ 0, 70, 57, 114, 64, 65, 57, 15 },
};
const kSpriteTilesets = [144][4]t.uint8{
    .{ 0, 73, 0, 0 },       .{ 70, 73, 12, 29 },    .{ 72, 73, 19, 29 },   .{ 70, 73, 19, 14 },
    .{ 72, 73, 12, 17 },    .{ 72, 73, 12, 16 },    .{ 79, 73, 74, 80 },   .{ 14, 73, 74, 17 },
    .{ 70, 73, 18, 0 },     .{ 0, 73, 0, 80 },      .{ 0, 73, 0, 17 },     .{ 72, 73, 12, 0 },
    .{ 0, 0, 55, 54 },      .{ 72, 73, 76, 17 },    .{ 93, 44, 12, 68 },   .{ 0, 0, 78, 0 },
    .{ 15, 0, 18, 16 },     .{ 0, 0, 0, 76 },       .{ 0, 13, 23, 0 },     .{ 22, 13, 23, 27 },
    .{ 22, 13, 23, 20 },    .{ 21, 13, 23, 21 },    .{ 22, 13, 24, 25 },   .{ 22, 13, 23, 25 },
    .{ 22, 13, 0, 0 },      .{ 22, 13, 24, 27 },    .{ 15, 73, 74, 17 },   .{ 75, 42, 92, 21 },
    .{ 22, 73, 23, 29 },    .{ 0, 0, 0, 21 },       .{ 22, 13, 23, 16 },   .{ 22, 73, 18, 0 },
    .{ 22, 73, 12, 17 },    .{ 0, 0, 18, 16 },      .{ 22, 13, 0, 17 },    .{ 22, 73, 12, 0 },
    .{ 22, 13, 76, 17 },    .{ 14, 13, 74, 17 },    .{ 22, 26, 23, 27 },   .{ 79, 52, 74, 80 },
    .{ 53, 77, 101, 54 },   .{ 74, 52, 78, 0 },     .{ 14, 52, 74, 17 },   .{ 81, 52, 93, 89 },
    .{ 75, 73, 76, 17 },    .{ 45, 0, 0, 0 },       .{ 93, 0, 18, 89 },    .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 71, 73, 43, 45 },
    .{ 70, 73, 28, 82 },    .{ 0, 73, 28, 82 },     .{ 93, 73, 0, 82 },    .{ 70, 73, 19, 82 },
    .{ 75, 77, 74, 90 },    .{ 71, 73, 28, 82 },    .{ 75, 77, 57, 54 },   .{ 31, 44, 46, 82 },
    .{ 31, 44, 46, 29 },    .{ 47, 44, 46, 82 },    .{ 47, 44, 46, 49 },   .{ 31, 30, 48, 82 },
    .{ 81, 73, 19, 0 },     .{ 79, 73, 19, 80 },    .{ 79, 77, 74, 80 },   .{ 75, 73, 76, 43 },
    .{ 31, 32, 34, 83 },    .{ 85, 61, 66, 67 },    .{ 31, 30, 35, 82 },   .{ 31, 30, 57, 58 },
    .{ 31, 30, 58, 62 },    .{ 31, 30, 60, 61 },    .{ 64, 30, 39, 63 },   .{ 85, 26, 66, 67 },
    .{ 31, 30, 42, 82 },    .{ 31, 30, 56, 82 },    .{ 31, 32, 40, 82 },   .{ 31, 32, 38, 82 },
    .{ 31, 44, 37, 82 },    .{ 31, 32, 39, 82 },    .{ 31, 30, 41, 82 },   .{ 31, 44, 59, 82 },
    .{ 70, 73, 36, 82 },    .{ 33, 65, 69, 51 },    .{ 31, 44, 40, 49 },   .{ 31, 13, 41, 82 },
    .{ 31, 30, 39, 82 },    .{ 31, 32, 39, 83 },    .{ 72, 73, 19, 82 },   .{ 14, 30, 74, 80 },
    .{ 31, 32, 38, 83 },    .{ 21, 0, 0, 0 },       .{ 31, 0, 42, 82 },    .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 50, 0, 0, 8 },
    .{ 93, 73, 0, 82 },     .{ 85, 73, 66, 67 },    .{ 97, 98, 99, 80 },   .{ 97, 98, 99, 80 },
    .{ 97, 98, 99, 80 },    .{ 97, 98, 99, 80 },    .{ 97, 98, 99, 80 },   .{ 97, 98, 99, 80 },
    .{ 97, 86, 87, 80 },    .{ 97, 98, 99, 80 },    .{ 97, 98, 99, 80 },   .{ 97, 86, 87, 80 },
    .{ 97, 86, 99, 80 },    .{ 97, 86, 87, 80 },    .{ 97, 86, 51, 80 },   .{ 97, 86, 87, 80 },
    .{ 97, 98, 99, 80 },    .{ 97, 98, 99, 80 },
};
const kAuxTilesets = [82][4]t.uint8{
    .{ 6, 0, 31, 24 },      .{ 8, 0, 34, 27 },      .{ 6, 0, 31, 24 },     .{ 7, 0, 35, 28 },
    .{ 7, 0, 33, 24 },      .{ 9, 0, 32, 25 },      .{ 11, 0, 33, 26 },    .{ 12, 0, 36, 25 },
    .{ 8, 0, 34, 27 },      .{ 12, 0, 37, 27 },     .{ 12, 0, 38, 27 },    .{ 10, 0, 39, 29 },
    .{ 10, 0, 40, 30 },     .{ 11, 0, 41, 22 },     .{ 13, 0, 42, 24 },    .{ 7, 0, 35, 28 },
    .{ 7, 0, 4, 5 },        .{ 7, 0, 4, 5 },        .{ 9, 0, 32, 27 },     .{ 9, 0, 42, 23 },
    .{ 11, 0, 33, 28 },     .{ 9, 0, 32, 25 },      .{ 11, 0, 33, 26 },    .{ 9, 0, 36, 27 },
    .{ 8, 0, 34, 27 },      .{ 9, 0, 37, 27 },      .{ 9, 0, 38, 27 },     .{ 10, 0, 39, 29 },
    .{ 9, 0, 40, 30 },      .{ 12, 0, 41, 22 },     .{ 13, 0, 42, 23 },    .{ 114, 0, 43, 93 },
    .{ 0, 0, 0, 0 },        .{ 0, 87, 76, 0 },      .{ 0, 86, 79, 0 },     .{ 0, 83, 77, 0 },
    .{ 0, 82, 73, 0 },      .{ 0, 85, 74, 0 },      .{ 0, 83, 84, 0 },     .{ 0, 81, 78, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 80, 75, 0 },      .{ 0, 83, 77, 0 },     .{ 0, 85, 84, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 71, 72, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 87, 76, 0 },      .{ 0, 86, 79, 0 },     .{ 0, 83, 77, 0 },
    .{ 0, 82, 73, 0 },      .{ 0, 85, 74, 0 },      .{ 0, 83, 84, 0 },     .{ 0, 81, 78, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 80, 75, 0 },      .{ 0, 83, 0, 0 },      .{ 0, 53, 54, 0 },
    .{ 0, 96, 52, 0 },      .{ 0, 43, 44, 0 },      .{ 0, 45, 46, 0 },     .{ 0, 47, 48, 0 },
    .{ 0, 55, 56, 0 },      .{ 0, 51, 52, 0 },      .{ 0, 49, 50, 0 },     .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },        .{ 0, 0, 0, 0 },       .{ 0, 0, 0, 0 },
    .{ 114, 113, 114, 113 }, .{ 23, 64, 65, 57 },
};
const kTagalongWhich = [14]t.uint16{ 0, 0x600, 0x300, 0x300, 0x300, 0, 0, 0x900, 0x600, 0x600, 0x900, 0x900, 0x600, 0x900 };
const kDecodeAnimatedSpriteTile_Tab = [57]t.uint16{
    0x9c0, 0x30,  0x60,  0x90,  0xc0,  0x300, 0x318, 0x330, 0x348, 0x360, 0x378, 0x390, 0x930, 0x3f0, 0x420, 0x450,
    0x468, 0x600, 0x630, 0x660, 0x690, 0x6c0, 0x6f0, 0x720, 0x750, 0x768, 0x900, 0x930, 0x960, 0x990, 0x9f0, 0,
    0xf0,  0xa20, 0xa50, 0x660, 0x600, 0x618, 0x630, 0x648, 0x678, 0x6d8, 0x6a8, 0x708, 0x738, 0x768, 0x960, 0x900,
    0x3c0, 0x990, 0x9a8, 0x9c0, 0x9d8, 0xa08, 0xa38, 0x600, 0x630,
};
const kSwordTypeToGfxOffs = [5]t.uint16{ 0, 0, 0x120, 0x120, 0x120 };
const kShieldTypeToGfxOffs = [4]t.uint16{ 0x660, 0x660, 0x6f0, 0x900 };
const kOwBgPalInfo = [93]t.int8{
    0,  -1, 7, 0,  1,  7, 0,  2,  7, 0,  3,  7, 0,  4,  7, 0,  5,  7, 0,  6,  7, 7,  6,  5,
    0,  8,  7, 0,  9,  7, 0,  10, 7, 0,  11, 7, 0,  -1, 7, 0,  -1, 7, 3,  4,  7, 4,  4,  3,
    16, -1, 6, 16, 1,  6, 16, 17, 6, 16, 3,  6, 16, 4,  6, 16, 5,  6, 16, 6,  6, 18, 19, 4,
    18, 5,  4, 16, 9,  6, 16, 11, 6, 16, 12, 6, 16, 13, 6, 16, 14, 6, 16, 15, 6,
};
const kOwSprPalInfo = [40]t.int8{
    -1, -1, 3,  10, 3,  6,  3,  1,  0,  2,  3,  14, 3, 2, 19, 1, 11, 12, 17, 1,
    7,  5,  17, 0,  9,  11, 15, 5,  3,  5,  3,  7,  15, 2, 10, 2, 5,  1,  12, 14,
};
const kSpotlight_delta_size = [4]t.int8{ -7, 7, 7, 7 };
const kSpotlight_goal = [4]t.uint8{ 0, 126, 35, 126 };
const kConfigureSpotlightTable_Helper_Tab = [129]t.uint8{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0xfc, 0xfc, 0xfc, 0xfb, 0xfb, 0xfb, 0xfa, 0xfa, 0xf9, 0xf9, 0xf8, 0xf8,
    0xf7, 0xf7, 0xf6, 0xf6, 0xf5, 0xf5, 0xf4, 0xf3, 0xf3, 0xf2, 0xf1, 0xf1, 0xf0, 0xef, 0xee, 0xee, 0xed, 0xec, 0xeb, 0xea, 0xe9, 0xe9, 0xe8, 0xe7, 0xe6, 0xe5, 0xe4, 0xe3, 0xe2, 0xe1, 0xdf, 0xde,
    0xdd, 0xdc, 0xdb, 0xda, 0xd8, 0xd7, 0xd6, 0xd5, 0xd3, 0xd2, 0xd0, 0xcf, 0xcd, 0xcc, 0xca, 0xc9, 0xc7, 0xc6, 0xc4, 0xc2, 0xc1, 0xbf, 0xbd, 0xbb, 0xb9, 0xb7, 0xb6, 0xb4, 0xb1, 0xaf, 0xad, 0xab,
    0xa9, 0xa7, 0xa4, 0xa2, 0x9f, 0x9d, 0x9a, 0x97, 0x95, 0x92, 0x8f, 0x8c, 0x89, 0x86, 0x82, 0x7f, 0x7b, 0x78, 0x74, 0x70, 0x6c, 0x67, 0x63, 0x5e, 0x59, 0x53, 0x4d, 0x46, 0x3f, 0x37, 0x2d, 0x1f,
    0,
};
const kGraphicsHalfSlotPacks = [20]t.uint8{
    1, 1, 8, 8, 9, 9, 2, 2, 2, 2, 3, 3, 4, 4, 5, 5,
    8, 8, 8, 8,
};
const kGraphicsLoadSp6 = [20]t.int8{
    10, -1, 3,  -1, 0,  -1, -1, -1, 1,  -1,
    2,  -1, 0,  -1, -1, -1, -1, -1, -1, -1,
};
const kMirrorWarp_LoadNext_NmiLoad = [15]t.uint8{ 0, 14, 15, 16, 17, 0, 0, 0, 0, 0, 0, 18, 19, 20, 0 };

fn GetCompSpritePtr(i: c_int) ?[*]const t.uint8 {
    return kSprGfx(i).ptr;
}

pub export fn ApplyPaletteFilter_bounce() void {
    const base: [*]const t.uint16 = &kPaletteFilteringBits;
    const off: usize = @as(usize, @intFromBool(v.palette_filter_countdown().* >= 0x10));
    const load_ptr = base + off;

    const mask: t.uint16 = kUpperBitmasks[@as(usize, v.palette_filter_countdown().* & 0xf)];
    const dt: t.uint16 = if (v.darkening_or_lightening_screen().* != 0) 1 else 0xffff;
    var j: usize = 0;
    while (true) {
        var c: t.uint16 = v.main_palette_buffer()[j];
        const a: t.uint16 = v.aux_palette_buffer()[j];
        if ((load_ptr[@as(usize, a & 0x1f) * 2] & mask) == 0)
            c +%= dt;
        if ((load_ptr[@as(usize, (a & 0x3e0) >> 4)] & mask) == 0)
            c +%= dt << 5;
        if ((load_ptr[@as(usize, (a & 0x7c00) >> 9)] & mask) == 0)
            c +%= dt << 10;
        v.main_palette_buffer()[j] = c;
        j += 1;
        if (j == 1) {
            j = 0x20;
        } else if (j == 0xd8) {
            j = 0xe0;
        } else if (j == 0xf0) {
            break;
        }
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
    if (v.darkening_or_lightening_screen().* == 0) {
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* != @as(t.uint16, v.mosaic_target_level().*)) return;
    } else {
        const prev = v.palette_filter_countdown().*;
        v.palette_filter_countdown().* -%= 1;
        if (prev != @as(t.uint16, v.mosaic_target_level().*)) return;
    }
    v.darkening_or_lightening_screen().* ^= 2;
    v.palette_filter_countdown().* = 0;
    v.subsubmodule_index().* +%= 1;
}

pub export fn PaletteFilter_Range(from: c_int, to: c_int) void {
    const base: [*]const t.uint16 = &kPaletteFilteringBits;
    const off: usize = @as(usize, @intFromBool(v.palette_filter_countdown().* >= 0x10));
    const load_ptr = base + off;
    const mask: t.uint16 = kUpperBitmasks[@as(usize, v.palette_filter_countdown().* & 0xf)];
    const dt: t.uint16 = if (v.darkening_or_lightening_screen().* != 0) 1 else 0xffff;
    var j: c_int = from;
    while (j != to) : (j += 1) {
        const idx: usize = @intCast(j);
        var c: t.uint16 = v.main_palette_buffer()[idx];
        const a: t.uint16 = v.aux_palette_buffer()[idx];
        if ((load_ptr[@as(usize, a & 0x1f) * 2] & mask) == 0)
            c +%= dt;
        if ((load_ptr[@as(usize, (a & 0x3e0) >> 4)] & mask) == 0)
            c +%= dt << 5;
        if ((load_ptr[@as(usize, (a & 0x7c00) >> 9)] & mask) == 0)
            c +%= dt << 10;
        v.main_palette_buffer()[idx] = c;
    }
}

pub export fn PaletteFilter_IncrCountdown() void {
    v.palette_filter_countdown().* +%= 1;
    if (v.palette_filter_countdown().* == 0x1f) {
        v.palette_filter_countdown().* = 0;
        v.darkening_or_lightening_screen().* ^= 2;
        if (v.darkening_or_lightening_screen().* != 0)
            t.word(v.link_actual_vel_y()).* +%= 1; // wtf?
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn LoadItemAnimationGfxOne(dst: [*]t.uint8, num: c_int, r12: c_int, from_temp: bool) [*]t.uint8 {
    const kIntro_LoadGfx_Tab = [10]t.uint8{ 0, 11, 8, 38, 42, 45, 34, 3, 33, 46 };
    const numu: usize = @intCast(num);
    var src: [*]const t.uint8 = if (from_temp) @ptrCast(&v.g_ram[0x14000]) else GetCompSpritePtr(0).?;
    const base_src: [*]const t.uint8 = src;
    src += @as(usize, kIntro_LoadGfx_Tab[@as(usize, @intCast(r12))]) * 24;
    Expand3To4High(dst, src, base_src, num);
    Expand3To4High(dst + 0x20 * numu, src + 0x180, base_src, num);
    return dst + 0x40 * numu;
}

pub export fn snes_divide(dividend: t.uint16, divisor: t.uint8) t.uint16 {
    return if (divisor != 0) dividend / @as(t.uint16, divisor) else 0xffff;
}

pub export fn EraseTileMaps_normal() void {
    EraseTileMaps(0x7f, 0x1ec);
}

fn DecompAndUpload2bpp(vram_ptr: [*]t.uint16, pack: t.uint8) void {
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), @as(c_int, pack));
    const src: [*]const t.uint8 = @ptrCast(&v.g_ram[0x14000]);
    const dst: [*]t.uint8 = @ptrCast(vram_ptr);
    @memcpy(dst[0 .. 1024 * @sizeOf(t.uint16)], src[0 .. 1024 * @sizeOf(t.uint16)]);
}

pub export fn RecoverPegGFXFromMapping() void {
    if (t.byte(v.orange_blue_barrier_state()).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x180, 0x0);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x0, 0x180);
    }
}

pub export fn LoadOverworldMapPalette() void {
    const idx: usize = if ((v.overworld_screen_index().* & 0x40) != 0) 0x80 else 0;
    const src: [*]const t.uint8 = @ptrCast(kOverworldMapPaletteData() + idx);
    const dst: [*]t.uint8 = @ptrCast(v.main_palette_buffer());
    @memcpy(dst[0..256], src[0..256]);
}

pub export fn EraseTileMaps_triforce() void { // 808333
    EraseTileMaps(0xa9, 0x7f);
}

pub export fn EraseTileMaps_dungeonmap() void { // 80833f
    EraseTileMaps(0x7f, 0x300);
}

pub export fn EraseTileMaps(r2: t.uint16, r0: t.uint16) void { // 808355
    var dst: [*]t.uint16 = v.g_zenv.vram.?;
    var i: usize = 0;
    while (i < 0x2000) : (i += 1) {
        dst[i] = r0;
    }

    dst = v.g_zenv.vram.? + 0x6000;
    i = 0;
    while (i < 0x800) : (i += 1) {
        dst[i] = r2;
    }
}

pub export fn EnableForceBlank() void { // 80893d
    v.INIDISP_copy().* = 0x80;
    v.HDMAEN_copy().* = 0;
}

pub export fn LoadItemGFXIntoWRAM4BPPBuffer() void { // 80d231
    var dst: [*]t.uint8 = @ptrCast(&v.g_ram[0x9000 + 0x480]);
    dst = LoadItemAnimationGfxOne(dst, 7, 0, false); // rod
    dst = LoadItemAnimationGfxOne(dst, 7, 1, false); // hammer
    dst = LoadItemAnimationGfxOne(dst, 3, 2, false); // bow

    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 95);
    dst = LoadItemAnimationGfxOne(dst, 4, 3, true); // shovel
    dst = LoadItemAnimationGfxOne(dst, 3, 4, true); // sleeping zzz
    dst = LoadItemAnimationGfxOne(dst, 1, 5, true); // misc #2
    dst = LoadItemAnimationGfxOne(dst, 4, 6, false); // hookshot

    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 96);
    dst = LoadItemAnimationGfxOne(dst, 14, 7, true); // bugnet
    dst = LoadItemAnimationGfxOne(dst, 7, 8, true); // cane

    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 95);
    dst = LoadItemAnimationGfxOne(dst, 2, 9, true); // book of mudora
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 84);

    dst = @ptrCast(&v.g_ram[0xa480]);
    Expand3To4High(dst, @ptrCast(&v.g_ram[0x14000]), @ptrCast(&v.g_ram[0]), 8);
    Expand3To4High(dst + 8 * 0x20, @ptrCast(&v.g_ram[0x14180]), @ptrCast(&v.g_ram[0]), 8);

    // rupees
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 96);
    dst = @ptrCast(&v.g_ram[0xb280]);
    Expand3To4High(dst, @ptrCast(&v.g_ram[0x14000]), @ptrCast(&v.g_ram[0]), 3);
    Expand3To4High(dst + 3 * 0x20, @ptrCast(&v.g_ram[0x14180]), @ptrCast(&v.g_ram[0]), 3);

    LoadItemGFX_Auxiliary();
}

pub export fn DecompressSwordGraphics() void { // 80d2c8
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), 0x5f);
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x5e);
    const off: usize = kSwordTypeToGfxOffs[@as(usize, v.link_sword_type().*)];
    const src: [*]const t.uint8 = @as([*]const t.uint8, @ptrCast(&v.g_ram[0x14000])) + off;
    Expand3To4High(@ptrCast(&v.g_ram[0x9000 + 0]), src, @ptrCast(&v.g_ram[0]), 12);
    Expand3To4High(@ptrCast(&v.g_ram[0x9000 + 0x180]), src + 0x180, @ptrCast(&v.g_ram[0]), 12);
}

pub export fn DecompressShieldGraphics() void { // 80d308
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), 0x5f);
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x5e);
    const off: usize = kShieldTypeToGfxOffs[@as(usize, v.link_shield_type().*)];
    const src: [*]const t.uint8 = @as([*]const t.uint8, @ptrCast(&v.g_ram[0x14000])) + off;
    Expand3To4High(@ptrCast(&v.g_ram[0x9000 + 0x300]), src, @ptrCast(&v.g_ram[0]), 6);
    Expand3To4High(@ptrCast(&v.g_ram[0x9000 + 0x3c0]), src + 0x180, @ptrCast(&v.g_ram[0]), 6);
}

pub export fn DecompressAnimatedDungeonTiles(a: t.uint8) void { // 80d337
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, a));
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x1680]), @ptrCast(&v.g_ram[0x14000]), 48);
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), 0x5c);
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x1C80]), @ptrCast(&v.g_ram[0x14000]), 48);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const p: [*]t.uint8 = @ptrCast(&v.g_ram[0x9000 + i * 2]);
        const x: t.uint16 = t.word(&p[0x1880]).*;
        t.word(&p[0x1880]).* = t.word(&p[0x1C80]).*;
        t.word(&p[0x1C80]).* = t.word(&p[0x1E80]).*;
        t.word(&p[0x1E80]).* = t.word(&p[0x1A80]).*;
        t.word(&p[0x1A80]).* = x;
    }
    v.animated_tile_vram_addr().* = 0x3b00;
}

pub export fn DecompressAnimatedOverworldTiles(a: t.uint8) void { // 80d394
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, a));
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x1680]), @ptrCast(&v.g_ram[0x14000]), 64);
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, a) + 1);
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x1E80]), @ptrCast(&v.g_ram[0x14000]), 32);
    v.animated_tile_vram_addr().* = 0x3c00;
}

pub export fn LoadItemGFX_Auxiliary() void { // 80d3c6
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), 0xf);
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x2340]), @ptrCast(&v.g_ram[0x14000]), 16);

    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x58);
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x2540]), @ptrCast(&v.g_ram[0x14000]), 32);

    _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), 0x5);
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x9000 + 0x2dc0]), @ptrCast(&v.g_ram[0x14480]), 2);
}

pub export fn LoadFollowerGraphics() void { // 80d423
    var yv: t.uint8 = 0x64;
    if (v.follower_indicator().* != 1) {
        yv = 0x66;
        if (v.follower_indicator().* >= 9) {
            yv = 0x59;
            if (v.follower_indicator().* >= 12)
                yv = 0x58;
        }
    }
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), @as(c_int, yv));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x65);
    const off: usize = kTagalongWhich[@as(usize, v.follower_indicator().*)];
    Do3To4Low16Bit(@as([*]t.uint8, @ptrCast(&v.g_ram[0x9000])) + 0x2940, @ptrCast(&v.g_ram[0x14000 + off]), 0x20);
}

pub export fn WriteTo4BPPBuffer_at_7F4000(a: t.uint8) void { // 80d4db
    const off: usize = kDecodeAnimatedSpriteTile_Tab[@as(usize, a)];
    const src: [*]t.uint8 = @ptrCast(&v.g_ram[0x14000 + off]);
    Expand3To4High(@as([*]t.uint8, @ptrCast(&v.g_ram[0x9000])) + 0x2d40, src, @ptrCast(&v.g_ram[0]), 2);
    Expand3To4High(@as([*]t.uint8, @ptrCast(&v.g_ram[0x9000])) + 0x2d40 + 0x40, src + 0x180, @ptrCast(&v.g_ram[0]), 2);
}

pub export fn DecodeAnimatedSpriteTile_variable(a: t.uint8) void { // 80d4ed
    const y: t.uint8 = if (a == 0x23 or a >= 0x37) 0x5d else if (a == 0xc or a >= 0x24) 0x5c else 0x5b;
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), @as(c_int, y));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x5a);
    WriteTo4BPPBuffer_at_7F4000(a);
}

// Comma-operator loop in the C source (`src += 2, src2 += 1, dst += 2;`):
// translated as sequential statements in the same left-to-right order,
// and the pointer-difference bit test `!(src - base & 0x78)` keeps the C
// precedence (`-` before `&`) via the explicit `diff & 0x78` grouping below.
pub export fn Expand3To4High(dst_in: [*]t.uint8, src_in: [*]const t.uint8, base: [*]const t.uint8, num: c_int) void { // 80d61c
    var dst = dst_in;
    var src = src_in;
    var numc = num;
    while (true) {
        var src2 = src + 0x10;
        var n: c_int = 8;
        while (true) {
            const tv: t.uint16 = t.word(&src[0]).*;
            const u: t.uint8 = src2[0];
            t.word(&dst[0]).* = tv;
            t.word(&dst[0x10]).* = ((tv | (tv >> 8) | @as(t.uint16, u)) << 8) | @as(t.uint16, u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        const diff: usize = @intFromPtr(src) - @intFromPtr(base);
        if ((diff & 0x78) == 0)
            src += 0x180;
        numc -= 1;
        if (numc == 0) break;
    }
}

pub export fn LoadTransAuxGFX() void { // 80d66e
    const dst: [*]t.uint8 = @ptrCast(&v.g_ram[0x6000]);
    const p = &kAuxTilesets[@as(usize, v.aux_tile_theme_index().*)];

    if (p[0] != 0) {
        v.aux_bg_subset_0().* = p[0];
        const len = Decomp_bg(dst, @as(c_int, v.aux_bg_subset_0().*));
        std.debug.assert(len == 0x600);
    }
    if (p[1] != 0) {
        v.aux_bg_subset_1().* = p[1];
        const len = Decomp_bg(dst + 0x600, @as(c_int, v.aux_bg_subset_1().*));
        std.debug.assert(len == 0x600);
    }
    if (p[2] != 0) {
        v.aux_bg_subset_2().* = p[2];
        const len = Decomp_bg(dst + 0x600 * 2, @as(c_int, v.aux_bg_subset_2().*));
        std.debug.assert(len == 0x600);
    }
    if (p[3] != 0) {
        v.aux_bg_subset_3().* = p[3];
        const len = Decomp_bg(dst + 0x600 * 3, @as(c_int, v.aux_bg_subset_3().*));
        std.debug.assert(len == 0x600);
    }
    Gfx_LoadSpritesInner(dst + 0x600 * 4);
}

pub export fn LoadTransAuxGFX_sprite() void { // 80d6f9
    Gfx_LoadSpritesInner(@ptrCast(&v.g_ram[0x7800]));
}

pub export fn Gfx_LoadSpritesInner(dst: [*]t.uint8) void { // 80d706
    const p = &kSpriteTilesets[@as(usize, v.sprite_graphics_index().*)];

    if (p[0] != 0)
        v.sprite_gfx_subset_0().* = p[0];
    var len = Decomp_spr(dst, @as(c_int, v.sprite_gfx_subset_0().*));
    std.debug.assert(len == 0x600);

    if (p[1] != 0)
        v.sprite_gfx_subset_1().* = p[1];
    len = Decomp_spr(dst + 0x600, @as(c_int, v.sprite_gfx_subset_1().*));
    std.debug.assert(len == 0x600);

    if (p[2] != 0)
        v.sprite_gfx_subset_2().* = p[2];
    len = Decomp_spr(dst + 0x600 * 2, @as(c_int, v.sprite_gfx_subset_2().*));
    std.debug.assert(len == 0x600);

    if (p[3] != 0)
        v.sprite_gfx_subset_3().* = p[3];
    len = Decomp_spr(dst + 0x600 * 3, @as(c_int, v.sprite_gfx_subset_3().*));
    std.debug.assert(len == 0x600);

    v.incremental_counter_for_vram().* = 0;
}

pub export fn ReloadPreviouslyLoadedSheets() void { // 80d788
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x6000]), @as(c_int, v.aux_bg_subset_0().*));
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x6600]), @as(c_int, v.aux_bg_subset_1().*));
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x6c00]), @as(c_int, v.aux_bg_subset_2().*));
    _ = Decomp_bg(@ptrCast(&v.g_ram[0x7200]), @as(c_int, v.aux_bg_subset_3().*));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x7800]), @as(c_int, v.sprite_gfx_subset_0().*));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x7e00]), @as(c_int, v.sprite_gfx_subset_1().*));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x8400]), @as(c_int, v.sprite_gfx_subset_2().*));
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x8a00]), @as(c_int, v.sprite_gfx_subset_3().*));
    v.incremental_counter_for_vram().* = 0;
}

pub export fn Attract_DecompressStoryGFX() void { // 80d80e
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), 0x67);
    _ = Decomp_spr(@ptrCast(&v.g_ram[0x14800]), 0x68);
}

pub export fn AnimateMirrorWarp() void { // 80d864
    const st: c_int = @as(c_int, v.overworld_map_state().*);
    v.overworld_map_state().* +%= 1;
    const nmi_val = kMirrorWarp_LoadNext_NmiLoad[@as(usize, @intCast(st))];
    v.nmi_subroutine_index().* = nmi_val;
    v.nmi_disable_core_updates().* = nmi_val;
    const xt: usize = if ((v.overworld_screen_index().* & 0x40) != 0) 8 else 0;
    var bt: t.uint8 = undefined;

    switch (st) {
        0 => {
            v.mirror_vars().ctr2 +%= 1;
            if (v.mirror_vars().ctr2 != 32) {
                v.overworld_map_state().* = 0;
            } else {
                SetTargetOverworldWarpToPyramid();
            }
        },
        1 => {
            AnimateMirrorWarp_DecompressNewTileSets();
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, kVariousPacks[xt]));
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14600]), @as(c_int, kVariousPacks[xt + 1]));
            Do3To4High16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 64);
            Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10800]), @ptrCast(&v.g_ram[0x14600]), 64);
        },
        2 => {
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, kVariousPacks[xt + 2]));
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14600]), @as(c_int, kVariousPacks[xt + 3]));
            Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 64);
            Do3To4High16Bit(@ptrCast(&v.g_ram[0x10800]), @ptrCast(&v.g_ram[0x14600]), 64);
        },
        3 => {
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, v.aux_bg_subset_1().*));
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14600]), @as(c_int, v.aux_bg_subset_2().*));
            Do3To4High16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 128);
        },
        4 => {
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14000]), @as(c_int, kVariousPacks[xt + 4]));
            _ = Decomp_bg(@ptrCast(&v.g_ram[0x14600]), @as(c_int, kVariousPacks[xt + 5]));
            Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 128);
        },
        5 => {
            PreOverworld_LoadOverlays();
            const b = t.byte(v.overworld_screen_index()).*;
            if (b == 27 or b == 91)
                v.TS_copy().* = 1;
            v.submodule_index().* -%= 1;
            v.nmi_subroutine_index().* = 12;
            v.nmi_disable_core_updates().* = 12;
        },
        6, 9 => {
            v.nmi_subroutine_index().* = 13;
            v.nmi_disable_core_updates().* = 13;
        },
        7 => {
            Overworld_DrawScreenAtCurrentMirrorPosition();
            v.nmi_disable_core_updates().* +%= 1;
        },
        8 => {
            MirrorWarp_LoadSpritesAndColors();
            v.nmi_subroutine_index().* = 12;
            v.nmi_disable_core_updates().* = 12;
        },
        10 => {
            bt = t.byte(v.overworld_screen_index()).* & 0xbf;
            DecompressAnimatedOverworldTiles(if (bt == 3 or bt == 5 or bt == 7) 0x58 else 0x5a);
        },
        11 => {
            bt = t.byte(v.overworld_screen_index()).*;
            v.TS_copy().* = @intFromBool(bt == 0 or bt == 0x70 or bt == 0x40 or bt == 0x5b or bt == 3 or bt == 5 or bt == 7 or bt == 0x43 or bt == 0x45 or bt == 0x47);
            Do3To4High16Bit(@ptrCast(&v.g_ram[0x10000]), GetCompSpritePtr(@as(c_int, kVariousPacks[xt + 6])).?, 64);
        },
        12 => {
            _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), @as(c_int, v.sprite_gfx_subset_0().*));
            _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), @as(c_int, v.sprite_gfx_subset_1().*));
            const tt: t.uint16 = t.word(v.sprite_gfx_subset_0()).*;
            if (tt == 0x52 or tt == 0x53 or tt == 0x5a or tt == 0x5b) {
                Do3To4High16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 64);
            } else {
                Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 64);
            }
            Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10800]), @ptrCast(&v.g_ram[0x14600]), 64);
        },
        13 => {
            _ = Decomp_spr(@ptrCast(&v.g_ram[0x14000]), @as(c_int, v.sprite_gfx_subset_2().*));
            _ = Decomp_spr(@ptrCast(&v.g_ram[0x14600]), @as(c_int, v.sprite_gfx_subset_3().*));
            Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x14000]), 128);
            HandleFollowersAfterMirroring();
        },
        14 => {
            v.overworld_map_state().* = 14;
        },
        else => {},
    }
}

pub export fn AnimateMirrorWarp_DecompressNewTileSets() void { // 80d8fe
    const mt = &kMainTilesets[@as(usize, v.main_tile_theme_index().*)];
    const at = &kAuxTilesets[@as(usize, v.aux_tile_theme_index().*)];

    v.aux_bg_subset_0().* = if (at[0] != 0) at[0] else mt[3];
    v.aux_bg_subset_1().* = if (at[1] != 0) at[1] else mt[4];
    v.aux_bg_subset_2().* = if (at[2] != 0) at[2] else mt[5];
    v.aux_bg_subset_3().* = if (at[3] != 0) at[3] else mt[6];

    const p = &kSpriteTilesets[@as(usize, v.sprite_graphics_index().*)];
    if (p[0] != 0) v.sprite_gfx_subset_0().* = p[0];
    if (p[1] != 0) v.sprite_gfx_subset_1().* = p[1];
    if (p[2] != 0) v.sprite_gfx_subset_2().* = p[2];
    if (p[3] != 0) v.sprite_gfx_subset_3().* = p[3];
}

pub export fn Graphics_IncrementalVRAMUpload() void { // 80deff
    if (v.incremental_counter_for_vram().* == 16)
        return;

    const kGraphics_IncrementalVramUpload_Dst = [16]t.uint8{ 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f };
    const kGraphics_IncrementalVramUpload_Src = [16]t.uint8{ 0x0, 0x2, 0x4, 0x6, 0x8, 0xa, 0xc, 0xe, 0x10, 0x12, 0x14, 0x16, 0x18, 0x1a, 0x1c, 0x1e };

    const idx: usize = @intCast(v.incremental_counter_for_vram().*);
    v.nmi_update_tilemap_dst().* = kGraphics_IncrementalVramUpload_Dst[idx];
    v.nmi_update_tilemap_src().* = @as(t.uint16, kGraphics_IncrementalVramUpload_Src[idx]) << 8;
    v.incremental_counter_for_vram().* +%= 1;
}

pub export fn PrepTransAuxGfx() void { // 80df1a
    Do3To4High16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x6000]), 0x40);
    if (v.aux_tile_theme_index().* >= 32) {
        Do3To4High16Bit(@ptrCast(&v.g_ram[0x10800]), @ptrCast(&v.g_ram[0x6600]), 0x80);
        Do3To4Low16Bit(@ptrCast(&v.g_ram[0x11800]), @ptrCast(&v.g_ram[0x7200]), 0x40);
    } else {
        Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10800]), @ptrCast(&v.g_ram[0x6600]), 0xC0);
    }
}

pub export fn Do3To4High16Bit(dst_in: [*]t.uint8, src_in: [*]const t.uint8, num: c_int) void { // 80df4f
    var dst = dst_in;
    var src = src_in;
    var numc = num;
    while (true) {
        var src2 = src + 0x10;
        var n: c_int = 8;
        while (true) {
            const tv: t.uint16 = t.word(&src[0]).*;
            const u: t.uint8 = src2[0];
            t.word(&dst[0]).* = tv;
            t.word(&dst[0x10]).* = ((tv | (tv >> 8) | @as(t.uint16, u)) << 8) | @as(t.uint16, u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        numc -= 1;
        if (numc == 0) break;
    }
}

pub export fn Do3To4Low16Bit(dst_in: [*]t.uint8, src_in: [*]const t.uint8, num: c_int) void { // 80dfb8
    var dst = dst_in;
    var src = src_in;
    var numc = num;
    while (true) {
        var src2 = src + 0x10;
        var n: c_int = 8;
        while (true) {
            t.word(&dst[0]).* = t.word(&src[0]).*;
            t.word(&dst[0x10]).* = @as(t.uint16, src2[0]);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        numc -= 1;
        if (numc == 0) break;
    }
}

pub export fn LoadNewSpriteGFXSet() void { // 80e031
    Do3To4Low16Bit(@ptrCast(&v.g_ram[0x10000]), @ptrCast(&v.g_ram[0x7800]), 0xC0);
    const s3 = v.sprite_gfx_subset_3().*;
    if (s3 == 0x52 or s3 == 0x53 or s3 == 0x5a or s3 == 0x5b) {
        Do3To4High16Bit(@ptrCast(&v.g_ram[0x11800]), @ptrCast(&v.g_ram[0x8a00]), 0x40);
    } else {
        Do3To4Low16Bit(@ptrCast(&v.g_ram[0x11800]), @ptrCast(&v.g_ram[0x8a00]), 0x40);
    }
}

pub export fn InitializeTilesets() void { // 80e19b
    LoadCommonSprites();

    const p = &kSpriteTilesets[@as(usize, v.sprite_graphics_index().*)];
    if (p[0] != 0) v.sprite_gfx_subset_0().* = p[0];
    if (p[1] != 0) v.sprite_gfx_subset_1().* = p[1];
    if (p[2] != 0) v.sprite_gfx_subset_2().* = p[2];
    if (p[3] != 0) v.sprite_gfx_subset_3().* = p[3];

    LoadSpriteGraphics(v.g_zenv.vram.? + 0x5000, @as(c_int, v.sprite_gfx_subset_0().*), @ptrCast(&v.g_ram[0x7800]));
    LoadSpriteGraphics(v.g_zenv.vram.? + 0x5400, @as(c_int, v.sprite_gfx_subset_1().*), @ptrCast(&v.g_ram[0x7e00]));
    LoadSpriteGraphics(v.g_zenv.vram.? + 0x5800, @as(c_int, v.sprite_gfx_subset_2().*), @ptrCast(&v.g_ram[0x8400]));
    LoadSpriteGraphics(v.g_zenv.vram.? + 0x5c00, @as(c_int, v.sprite_gfx_subset_3().*), @ptrCast(&v.g_ram[0x8a00]));

    const mt = &kMainTilesets[@as(usize, v.main_tile_theme_index().*)];
    const at = &kAuxTilesets[@as(usize, v.aux_tile_theme_index().*)];

    v.aux_bg_subset_0().* = if (at[0] != 0) at[0] else mt[3];
    v.aux_bg_subset_1().* = if (at[1] != 0) at[1] else mt[4];
    v.aux_bg_subset_2().* = if (at[2] != 0) at[2] else mt[5];
    v.aux_bg_subset_3().* = if (at[3] != 0) at[3] else mt[6];

    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x2000, @as(c_int, mt[0]), 7, @ptrCast(&v.g_ram[0x14000]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x2400, @as(c_int, mt[1]), 6, @ptrCast(&v.g_ram[0x14000]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x2800, @as(c_int, mt[2]), 5, @ptrCast(&v.g_ram[0x14000]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x2c00, @as(c_int, v.aux_bg_subset_0().*), 4, @ptrCast(&v.g_ram[0x6000]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x3000, @as(c_int, v.aux_bg_subset_1().*), 3, @ptrCast(&v.g_ram[0x6600]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x3400, @as(c_int, v.aux_bg_subset_2().*), 2, @ptrCast(&v.g_ram[0x6c00]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x3800, @as(c_int, v.aux_bg_subset_3().*), 1, @ptrCast(&v.g_ram[0x7200]));
    LoadBackgroundGraphics(v.g_zenv.vram.? + 0x3c00, @as(c_int, mt[7]), 0, @ptrCast(&v.g_ram[0x14000]));
}

pub export fn LoadDefaultGraphics() void { // 80e2d0
    var src: [*]const t.uint8 = GetCompSpritePtr(0).?;

    var vram_ptr: [*]t.uint16 = v.g_zenv.vram.? + 0x4000;
    const tmp: [*]align(1) t.uint16 = @ptrCast(&v.g_ram[0xbf]);
    var num: c_int = 64;
    while (true) {
        var i: c_int = 7;
        while (i >= 0) : (i -= 1) {
            vram_ptr[0] = t.word(&src[0]).*;
            vram_ptr += 1;
            tmp[@intCast(i)] = @as(t.uint16, src[0]) | @as(t.uint16, src[1]);
            src += 2;
        }
        i = 7;
        while (i >= 0) : (i -= 1) {
            const s0: t.uint16 = src[0];
            vram_ptr[0] = s0 | ((s0 | tmp[@intCast(i)]) << 8);
            vram_ptr += 1;
            src += 1;
        }
        num -= 1;
        if (num == 0) break;
    }

    // Load 2bpp graphics used for hud
    DecompAndUpload2bpp(v.g_zenv.vram.? + 0x7000, 0x6a);
    DecompAndUpload2bpp(v.g_zenv.vram.? + 0x7400, 0x6b);
    DecompAndUpload2bpp(v.g_zenv.vram.? + 0x7800, 0x69);
}

pub export fn Attract_LoadBG3GFX() void { // 80e36d
    // load 2bpp gfx for attract images
    DecompAndUpload2bpp(v.g_zenv.vram.? + 0x7800, 0x67);
}

pub export fn Graphics_LoadChrHalfSlot() void { // 80e3fa
    var k: c_int = @as(c_int, v.load_chr_halfslot_even_odd().*);
    if (k == 0)
        return;

    const sp6: t.int8 = kGraphicsLoadSp6[@as(usize, @intCast(k - 1))];
    if (sp6 >= 0) {
        v.palette_sp6r_indoors().* = @intCast(sp6);
        if (k == 1) {
            v.palette_sp6r_indoors().* = 10;
            v.overworld_palette_aux_or_main().* = 0x200;
            Palette_Load_SpriteEnvironment();
            v.flag_update_cgram_in_nmi().* +%= 1;
        } else {
            v.overworld_palette_aux_or_main().* = 0x200;
            Palette_Load_SpriteEnvironment_Dungeon();
            v.flag_update_cgram_in_nmi().* +%= 1;
        }
    }
    var tilebytes: c_int = 0x44;
    var bank_offs: c_int = 0;
    v.load_chr_halfslot_even_odd().* +%= 1;

    if ((v.load_chr_halfslot_even_odd().* & 1) != 0) {
        v.load_chr_halfslot_even_odd().* = 0;
        if (k != 18) {
            bank_offs = 0x300;
            tilebytes = 0x46;
            if (k == 2)
                v.flag_custom_spell_anim_active().* = 0;
        }
    }
    t.byte(v.nmi_load_target_addr()).* = @intCast(tilebytes);
    v.nmi_subroutine_index().* = 11;

    k = @as(c_int, kGraphicsHalfSlotPacks[@as(usize, @intCast(k - 1))]);
    if (k == 1)
        k = @as(c_int, v.misc_sprites_graphics_index().*);

    var srcp: [*]const t.uint8 = GetCompSpritePtr(k).? + @as(usize, @intCast(bank_offs));
    var sprdata: [24]t.uint8 = undefined;
    var num: c_int = 32;
    var dst: [*]t.uint8 = @ptrCast(&v.g_ram[0x11000]);

    while (true) {
        var i: usize = 0;
        while (i < 24) : (i += 1) {
            sprdata[i] = srcp[0];
            srcp += 1;
        }

        var src: [*]t.uint8 = @ptrCast(&sprdata[0]);
        var src2: [*]t.uint8 = @ptrCast(&sprdata[16]);
        var n: c_int = 8;
        while (true) {
            const tv: t.uint16 = t.word(&src[0]).*;
            const u: t.uint8 = src2[0];
            t.word(&dst[0]).* = tv;
            t.word(&dst[16]).* = ((tv | (tv >> 8) | @as(t.uint16, u)) << 8) | @as(t.uint16, u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn TransferFontToVRAM() void { // 80e556
    const blk = FindIndexInMemblk(kDialogueFont(0), 0);
    const dst: [*]t.uint8 = @ptrCast(v.g_zenv.vram.? + 0x7000);
    const src: [*]const t.uint8 = blk.ptr.?;
    @memcpy(dst[0 .. 0x800 * @sizeOf(t.uint16)], src[0 .. 0x800 * @sizeOf(t.uint16)]);
}

pub export fn Do3To4High(vram_ptr_in: [*]t.uint16, decomp_addr_in: [*]const t.uint8) void { // 80e5af
    var vram_ptr = vram_ptr_in;
    var decomp_addr = decomp_addr_in;
    var j: c_int = 0;
    while (j < 64) : (j += 1) {
        const tarr: [*]align(1) t.uint16 = @ptrCast(v.dung_line_ptrs_row0());
        var i: c_int = 7;
        while (i >= 0) : (i -= 1) {
            const d: t.uint16 = t.word(&decomp_addr[0]).*;
            tarr[@intCast(i)] = (d | (d >> 8)) & 0xff;
            vram_ptr[0] = d;
            vram_ptr += 1;
            decomp_addr += 2;
        }
        i = 7;
        while (i >= 0) : (i -= 1) {
            const d: t.uint8 = decomp_addr[0];
            vram_ptr[0] = @as(t.uint16, d) | ((tarr[@intCast(i)] | @as(t.uint16, d)) << 8);
            vram_ptr += 1;
            decomp_addr += 1;
        }
    }
}

pub export fn Do3To4Low(vram_ptr_in: [*]t.uint16, decomp_addr_in: [*]const t.uint8) void { // 80e63c
    var vram_ptr = vram_ptr_in;
    var decomp_addr = decomp_addr_in;
    var j: c_int = 0;
    while (j < 64) : (j += 1) {
        var i: c_int = 0;
        while (i < 8) : (i += 1) {
            vram_ptr[0] = t.word(&decomp_addr[0]).*;
            vram_ptr += 1;
            decomp_addr += 2;
        }
        i = 0;
        while (i < 8) : (i += 1) {
            vram_ptr[0] = @as(t.uint16, decomp_addr[0]);
            vram_ptr += 1;
            decomp_addr += 1;
        }
    }
}

pub export fn LoadSpriteGraphics(vram_ptr: [*]t.uint16, gfx_pack: c_int, decomp_addr: [*]t.uint8) void { // 80e583
    _ = Decomp_spr(decomp_addr, gfx_pack);
    if (gfx_pack == 0x52 or gfx_pack == 0x53 or gfx_pack == 0x5a or gfx_pack == 0x5b or
        gfx_pack == 0x5c or gfx_pack == 0x5e or gfx_pack == 0x5f)
    {
        Do3To4High(vram_ptr, decomp_addr);
    } else {
        Do3To4Low(vram_ptr, decomp_addr);
    }
}

pub export fn LoadBackgroundGraphics(vram_ptr: [*]t.uint16, gfx_pack: c_int, slot: c_int, decomp_addr: [*]t.uint8) void { // 80e609
    _ = Decomp_bg(decomp_addr, gfx_pack);
    const use_high = if (v.main_tile_theme_index().* >= 0x20)
        (slot == 7 or slot == 2 or slot == 3 or slot == 4)
    else
        (slot >= 4);
    if (use_high) {
        Do3To4High(vram_ptr, decomp_addr);
    } else {
        Do3To4Low(vram_ptr, decomp_addr);
    }
}

pub export fn LoadCommonSprites() void { // 80e6b7
    Do3To4High(v.g_zenv.vram.? + 0x4400, GetCompSpritePtr(@as(c_int, v.misc_sprites_graphics_index().*)).?);
    if (v.main_module_index().* != 1) {
        Do3To4Low(v.g_zenv.vram.? + 0x4800, GetCompSpritePtr(6).?);
        Do3To4Low(v.g_zenv.vram.? + 0x4c00, GetCompSpritePtr(7).?);
    } else {
        // select file
        LoadSpriteGraphics(v.g_zenv.vram.? + 0x4800, 94, @ptrCast(&v.g_ram[0x14000]));
        LoadSpriteGraphics(v.g_zenv.vram.? + 0x4c00, 95, @ptrCast(&v.g_ram[0x14000]));
    }
}

pub export fn Decomp_spr(dst: [*]t.uint8, gfx_in: c_int) c_int { // 80e772
    var gfx = gfx_in;
    if (gfx < 12)
        gfx = 12; // ensure it wont decode bad sheets.
    const blk = kSprGfx(gfx);
    _ = GetCompSpritePtr(gfx);
    // If the size is not 0x600 then it's compressed
    if (gfx >= 103 or blk.size != 0x600)
        return Decompress(dst, blk.ptr.?);
    const src: [*]const t.uint8 = blk.ptr.?;
    @memcpy(dst[0..0x600], src[0..0x600]);
    return 0x600;
}

pub export fn Decomp_bg(dst: [*]t.uint8, gfx: c_int) c_int { // 80e78f
    return Decompress(dst, kBgGfx(gfx).ptr.?);
}

pub export fn Decompress(dst: [*]t.uint8, src_in: [*]const t.uint8) c_int { // 80e79e
    const dst_org: [*]t.uint8 = dst;
    var d: [*]t.uint8 = dst;
    var src: [*]const t.uint8 = src_in;
    var len: c_int = undefined;
    while (true) {
        var cmd: t.uint8 = src[0];
        src += 1;
        if (cmd == 0xff)
            return @intCast(@intFromPtr(d) - @intFromPtr(dst_org));
        if ((cmd & 0xe0) != 0xe0) {
            len = @as(c_int, cmd & 0x1f) + 1;
            cmd &= 0xe0;
        } else {
            var l: c_int = src[0];
            src += 1;
            l += (@as(c_int, cmd & 3) << 8) + 1;
            len = l;
            cmd = (cmd << 3) & 0xe0;
        }
        if (cmd == 0) {
            var n = len;
            while (true) {
                d[0] = src[0];
                d += 1;
                src += 1;
                n -= 1;
                if (n == 0) break;
            }
        } else if ((cmd & 0x80) != 0) {
            var offs: t.uint32 = src[0];
            src += 1;
            offs |= @as(t.uint32, src[0]) << 8;
            src += 1;
            var n = len;
            while (true) {
                d[0] = dst_org[offs];
                offs +%= 1;
                d += 1;
                n -= 1;
                if (n == 0) break;
            }
        } else if ((cmd & 0x40) == 0) {
            const val: t.uint8 = src[0];
            src += 1;
            var n = len;
            while (true) {
                d[0] = val;
                d += 1;
                n -= 1;
                if (n == 0) break;
            }
        } else if ((cmd & 0x20) == 0) {
            const lo: t.uint8 = src[0];
            src += 1;
            const hi: t.uint8 = src[0];
            src += 1;
            var n = len;
            while (true) {
                d[0] = lo;
                d += 1;
                n -= 1;
                if (n == 0) break;
                d[0] = hi;
                d += 1;
                n -= 1;
                if (n == 0) break;
            }
        } else {
            // copy bytes with the byte incrementing by 1 in between
            var val: t.uint8 = src[0];
            src += 1;
            var n = len;
            while (true) {
                d[0] = val;
                d += 1;
                val +%= 1;
                n -= 1;
                if (n == 0) break;
            }
        }
    }
}

pub export fn ResetHUDPalettes4and5() void { // 80eb29
    var i: usize = 0;
    while (i < 8) : (i += 1)
        v.main_palette_buffer()[16 + i] = 0;
    v.palette_filter_countdown().* = 0;
    v.darkening_or_lightening_screen().* = 2;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilterHistory() void { // 80eb5e
    PaletteFilter_Range(0x10, 0x18);
    PaletteFilter_IncrCountdown();
}

pub export fn PaletteFilter_WishPonds() void { // 80ebc5
    v.TS_copy().* = 2;
    v.CGADSUB_copy().* = 0x30;
    PaletteFilter_WishPonds_Inner();
}

pub export fn PaletteFilter_Crystal() void { // 80ebcf
    v.TS_copy().* = 1;
    PaletteFilter_WishPonds_Inner();
}

pub export fn PaletteFilter_WishPonds_Inner() void { // 80ebd3
    var i: usize = 0;
    while (i < 8) : (i += 1)
        v.main_palette_buffer()[0xd0 + i] = 0;
    v.palette_filter_countdown().* = 0;
    v.darkening_or_lightening_screen().* = 2;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_RestoreSP5F() void { // 80ebf2
    var i: c_int = 7;
    while (i >= 0) : (i -= 1)
        v.main_palette_buffer()[@intCast(208 + i)] = v.aux_palette_buffer()[@intCast(208 + i)];
    v.TS_copy().* = 0;
    v.CGADSUB_copy().* = 32;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_SP5F() void { // 80ec0d
    var i: c_int = 0;
    while (i != 2) : (i += 1) {
        PaletteFilter_Range(208, 216);
        PaletteFilter_IncrCountdown();
        if (v.palette_filter_countdown().* == 0)
            break;
    }
}

pub export fn KholdstareShell_PaletteFiltering() void { // 80ec79
    const tt: usize = if ((enhanced_features0().* & kFeatures0_MiscBugFixes) != 0) 0x50 else 0x40;
    if (v.subsubmodule_index().* == 0) {
        @memcpy(v.main_palette_buffer()[tt .. tt + 8], v.aux_palette_buffer()[tt .. tt + 8]);
        v.palette_filter_countdown().* = 0;
        v.darkening_or_lightening_screen().* = 0;
        v.flag_update_cgram_in_nmi().* +%= 1;
        v.subsubmodule_index().* = 1;
        return;
    }
    var i: c_int = 0;
    while (i != 2) : (i += 1) {
        PaletteFilter_Range(@intCast(tt), @intCast(tt + 8));
        PaletteFilter_IncrCountdown();
        if (v.palette_filter_countdown().* == 0) {
            v.TS_copy().* = 0;
            break;
        }
    }
}

pub export fn AgahnimWarpShadowFilter(k: c_int) void { // 80ecca
    const ku: usize = @intCast(k);
    v.palette_filter_countdown().* = v.agahnim_pal_setting()[ku];
    v.darkening_or_lightening_screen().* = v.agahnim_pal_setting()[ku + 3];
    const tt: c_int = kPaletteFilter_Agahnim_Tab[ku] >> 1;
    var i: c_int = 0;
    while (i < 2) : (i += 1) {
        PaletteFilter_Range(tt, tt + 8);
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* == 0x1f) {
            v.palette_filter_countdown().* = 0;
            v.darkening_or_lightening_screen().* ^= 2;
            break;
        }
    }
    v.agahnim_pal_setting()[ku] = v.palette_filter_countdown().*;
    v.agahnim_pal_setting()[ku + 3] = v.darkening_or_lightening_screen().*;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_FadeIntroOneStep() void { // 80ed7c
    PaletteFilter_RestoreAdditive(0x100, 0x1a0);
    PaletteFilter_RestoreAdditive(0xc0, 0x100);
    t.byte(v.palette_filter_countdown()).* -%= 1;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_FadeIntro2() void { // 80ed8f
    PaletteFilter_RestoreAdditive(0x40, 0xc0);
    PaletteFilter_RestoreAdditive(0x40, 0xc0);
    t.byte(v.palette_filter_countdown()).* -%= 1;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_RestoreAdditive(from_in: c_int, to_in: c_int) void { // 80edca
    var from: usize = @intCast(from_in >> 1);
    const to: usize = @intCast(to_in >> 1);
    while (true) {
        const c: t.uint16 = v.main_palette_buffer()[from];
        var cx: t.uint16 = c;
        const d: t.uint16 = v.aux_palette_buffer()[from];
        if ((c & 0x1f) != (d & 0x1f))
            cx +%= 1;
        if ((c & 0x3e0) != (d & 0x3e0))
            cx +%= 0x20;
        if ((c & 0x7c00) != (d & 0x7c00))
            cx +%= 0x400;
        v.main_palette_buffer()[from] = cx;
        from += 1;
        if (from == to) break;
    }
}

pub export fn PaletteFilter_RestoreSubtractive(from_in: t.uint16, to_in: t.uint16) void { // 80ee21
    var from: usize = from_in >> 1;
    const to: usize = to_in >> 1;
    while (true) {
        const c: t.uint16 = v.main_palette_buffer()[from];
        var cx: t.uint16 = c;
        const d: t.uint16 = v.aux_palette_buffer()[from];
        if ((c & 0x1f) != (d & 0x1f))
            cx -%= 1;
        if ((c & 0x3e0) != (d & 0x3e0))
            cx -%= 0x20;
        if ((c & 0x7c00) != (d & 0x7c00))
            cx -%= 0x400;
        v.main_palette_buffer()[from] = cx;
        from += 1;
        if (from == to) break;
    }
}

pub export fn PaletteFilter_InitializeWhiteFilter() void { // 80ee78
    var i: usize = 0;
    while (i < 256) : (i += 1)
        v.aux_palette_buffer()[i] = 0x7fff;
    v.main_palette_buffer()[32] = v.main_palette_buffer()[0];
    v.palette_filter_countdown().* = 0;
    v.darkening_or_lightening_screen().* = 2;
    if (v.overworld_screen_index().* == 27) {
        v.aux_palette_buffer()[0] = 0;
        v.aux_palette_buffer()[32] = 0;
        v.main_palette_buffer()[0] = 0;
        v.main_palette_buffer()[32] = 0;
    }
    v.mirror_vars().ctr = 8;
    v.mirror_vars().ctr2 = 0;
}

pub export fn MirrorWarp_RunAnimationSubmodules() void { // 80eee7
    v.mirror_vars().ctr -%= 1;
    if (v.mirror_vars().ctr != 0) {
        AnimateMirrorWarp();
        return;
    }
    v.mirror_vars().ctr = 2;
    PaletteFilter_BlindingWhite();
}

pub export fn PaletteFilter_BlindingWhite() void { // 80eef1
    if (v.darkening_or_lightening_screen().* == 0xff)
        return;

    if (v.darkening_or_lightening_screen().* == 2) {
        PaletteFilter_RestoreAdditive(0x40, 0x1b0);
        PaletteFilter_RestoreAdditive(0x1c0, 0x1e0);
    } else {
        PaletteFilter_RestoreSubtractive(0x40, 0x1b0);
        PaletteFilter_RestoreSubtractive(0x1c0, 0x1e0);
    }
    PaletteFilter_StartBlindingWhite();
}

pub export fn PaletteFilter_StartBlindingWhite() void { // 80ef27
    v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
    if (v.darkening_or_lightening_screen().* == 0) {
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* == 66) {
            v.darkening_or_lightening_screen().* = 0xff;
            v.mirror_vars().ctr = 32;
        }
    } else {
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* == 31) {
            v.darkening_or_lightening_screen().* ^= 2;
            if (v.main_module_index().* != 21)
                return;
            zelda_snes_dummy_write(HDMAEN, 0);
            v.HDMAEN_copy().* = 0;
            var i: usize = 0;
            while (i < 240) : (i += 1)
                v.hdma_table_dynamic()[i] = 0x778;
            v.HDMAEN_copy().* = 0xc0;
        }
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_BlindingWhiteTriforce() void { // 80ef8a
    PaletteFilter_RestoreAdditive(0x40, 0x200);
    PaletteFilter_StartBlindingWhite();
}

pub export fn PaletteFilter_WhirlpoolBlue() void { // 80ef97
    if ((v.frame_counter().* & 1) != 0) {
        var i: usize = 0x20;
        while (i != 0x100) : (i += 1) {
            var tt: t.uint16 = v.main_palette_buffer()[i];
            if ((tt & 0x7c00) != 0x7c00)
                tt +%= 0x400;
            v.main_palette_buffer()[i] = tt;
        }
        v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
        if ((v.palette_filter_countdown().* & 1) == 0)
            v.mosaic_level().* +%= 16;
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* == 31) {
            v.palette_filter_countdown().* = 0;
            v.subsubmodule_index().* +%= 1;
            v.mosaic_level().* = 0xf0;
        }
    }
    v.BGMODE_copy().* = 9;
    v.MOSAIC_copy().* = v.mosaic_level().* | 3;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_IsolateWhirlpoolBlue() void { // 80f00c
    var i: usize = 0x20;
    while (i != 0x100) : (i += 1) {
        var tt: t.uint16 = v.main_palette_buffer()[i];
        if ((tt & 0x3e0) != 0)
            tt -%= 0x20;
        if ((tt & 0x1f) != 0)
            tt -%= 1;
        v.main_palette_buffer()[i] = tt;
    }
    v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
    v.palette_filter_countdown().* +%= 1;
    if (v.palette_filter_countdown().* == 31) {
        v.palette_filter_countdown().* = 0;
        v.subsubmodule_index().* +%= 1;
        v.mosaic_level().* = 0xf0;
    }
    v.BGMODE_copy().* = 9;
    v.MOSAIC_copy().* = v.mosaic_level().* | 3;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_WhirlpoolRestoreBlue() void { // 80f04a
    if ((v.frame_counter().* & 1) != 0) {
        var i: usize = 0x20;
        while (i != 0x100) : (i += 1) {
            const u: t.uint16 = v.aux_palette_buffer()[i] & 0x7c00;
            var tt: t.uint16 = v.main_palette_buffer()[i];
            if ((tt & 0x7c00) != u)
                tt -%= 0x400;
            v.main_palette_buffer()[i] = tt;
        }
        v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
        if ((v.palette_filter_countdown().* & 1) == 0)
            v.mosaic_level().* -%= 16;
        v.palette_filter_countdown().* +%= 1;
        if (v.palette_filter_countdown().* == 31) {
            v.palette_filter_countdown().* = 0;
            v.subsubmodule_index().* +%= 1;
            v.mosaic_level().* = 0;
        }
    }
    v.BGMODE_copy().* = 9;
    v.MOSAIC_copy().* = v.mosaic_level().* | 3;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_WhirlpoolRestoreRedGreen() void { // 80f0c7
    var i: usize = 0x20;
    while (i != 0x100) : (i += 1) {
        const um0: t.uint16 = v.aux_palette_buffer()[i] & 0x3e0;
        const um1: t.uint16 = v.aux_palette_buffer()[i] & 0x1f;
        var tt: t.uint16 = v.main_palette_buffer()[i];
        if ((tt & 0x3e0) != um0)
            tt +%= 0x20;
        if ((tt & 0x1f) != um1)
            tt +%= 1;
        v.main_palette_buffer()[i] = tt;
    }
    v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
    v.palette_filter_countdown().* +%= 1;
    if (v.palette_filter_countdown().* == 31) {
        v.palette_filter_countdown().* = 0;
        v.subsubmodule_index().* +%= 1;
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_RestoreBGSubstractiveStrict() void { // 80f135
    if (v.darkening_or_lightening_screen().* == 255)
        return;
    PaletteFilter_RestoreSubtractive(0x40, 0x100);
    v.palette_filter_countdown().* +%= 1;
    if (v.palette_filter_countdown().* == 0x20) {
        v.darkening_or_lightening_screen().* = 255;
        t.word(v.TS_copy()).* = 0;
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn PaletteFilter_RestoreBGAdditiveStrict() void { // 80f169
    PaletteFilter_RestoreAdditive(0x40, 0x100);
    v.palette_filter_countdown().* +%= 1;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Trinexx_FlashShellPalette_Red() void { // 80f183
    if (v.byte_7E04BE().* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const val: t.uint16 = v.main_palette_buffer()[0x41 + i];
            v.main_palette_buffer()[0x41 + i] = (val & 0xffe0) | ((val & 0x1f) +% @intFromBool((val & 0x1f) != 0x1f));
        }
        v.flag_update_cgram_in_nmi().* +%= 1;
        v.byte_7E04C0().* +%= 1;
        if (v.byte_7E04C0().* >= 12) {
            v.byte_7E04C0().* = 0;
            v.byte_7E04BE().* = 0;
            return;
        }
        v.byte_7E04BE().* = 3;
    }
    v.byte_7E04BE().* -%= 1;
}

pub export fn Trinexx_UnflashShellPalette_Red() void { // 80f1cf
    if (v.byte_7E04BE().* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const u: t.uint16 = v.aux_palette_buffer()[0x41 + i];
            const val: t.uint16 = v.main_palette_buffer()[0x41 + i];
            v.main_palette_buffer()[0x41 + i] = (val & 0xffe0) | ((val & 0x1f) -% @intFromBool((val & 0x1f) != (u & 0x1f)));
        }
        v.flag_update_cgram_in_nmi().* +%= 1;
        v.byte_7E04C0().* +%= 1;
        if (v.byte_7E04C0().* >= 12) {
            v.byte_7E04C0().* = 0;
            v.byte_7E04BE().* = 0;
            return;
        }
        v.byte_7E04BE().* = 3;
    }
    v.byte_7E04BE().* -%= 1;
}

pub export fn Trinexx_FlashShellPalette_Blue() void { // 80f207
    if (v.byte_7E04BF().* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const val: t.uint16 = v.main_palette_buffer()[0x41 + i];
            v.main_palette_buffer()[0x41 + i] = (val & ~@as(t.uint16, 0x7c00)) | ((val & 0x7c00) +% (@as(t.uint16, @intFromBool((val & 0x7c00) != 0x7c00)) << 10));
        }
        v.flag_update_cgram_in_nmi().* +%= 1;
        v.byte_7E04C1().* +%= 1;
        if (v.byte_7E04C1().* >= 12) {
            v.byte_7E04C1().* = 0;
            v.byte_7E04BF().* = 0;
            return;
        }
        v.byte_7E04BF().* = 3;
    }
    v.byte_7E04BF().* -%= 1;
}

pub export fn Trinexx_UnflashShellPalette_Blue() void { // 80f253
    if (v.byte_7E04BF().* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const u: t.uint16 = v.aux_palette_buffer()[0x41 + i];
            const val: t.uint16 = v.main_palette_buffer()[0x41 + i];
            v.main_palette_buffer()[0x41 + i] = (val & ~@as(t.uint16, 0x7c00)) | ((val & 0x7c00) -% (@as(t.uint16, @intFromBool((val & 0x7c00) != (u & 0x7c00))) << 10));
        }
        v.flag_update_cgram_in_nmi().* +%= 1;
        v.byte_7E04C1().* +%= 1;
        if (v.byte_7E04C1().* >= 12) {
            v.byte_7E04C1().* = 0;
            v.byte_7E04BF().* = 0;
            return;
        }
        v.byte_7E04BF().* = 3;
    }
    v.byte_7E04BF().* -%= 1;
}

pub export fn IrisSpotlight_close() void { // 80f28b
    SpotlightInternal(0x7e, 0);
}

pub export fn Spotlight_open() void { // 80f295
    SpotlightInternal(0, 2);
}

pub export fn SpotlightInternal(x: t.uint8, y: t.uint8) void { // 80f29d
    v.spotlight_var1().* = x;
    v.spotlight_var2().* = y;

    zelda_snes_dummy_write(HDMAEN, 0);
    HdmaSetup(0xF2FB, 0xF2FB, 0x41, @as(t.uint8, @truncate(WH0)), @as(t.uint8, @truncate(WH0)), 0);

    v.W12SEL_copy().* = 0x33;
    v.W34SEL_copy().* = 3;
    v.WOBJSEL_copy().* = 0x33;
    v.TMW_copy().* = v.TM_copy().*;
    v.TSW_copy().* = v.TS_copy().*;
    if (v.player_is_indoors().* == 0) {
        v.COLDATA_copy0().* = 0x20;
        v.COLDATA_copy1().* = 0x40;
        v.COLDATA_copy2().* = 0x80;
    }
    IrisSpotlight_ConfigureTable();
    v.HDMAEN_copy().* = 0x80;
    v.INIDISP_copy().* = 0xf;
}

pub export fn IrisSpotlight_ConfigureTable() void { // 80f312
    const r14: t.uint16 = v.link_y_coord().* -% v.BG2VOFS_copy2().* +% 12;
    v.spotlight_y_lower().* = r14 -% v.spotlight_var1().*;
    v.spotlight_y_upper().* = r14 +% v.spotlight_var1().*;
    v.spotlight_var3().* = v.link_x_coord().* -% v.BG2HOFS_copy2().* +% 8;
    v.spotlight_var4().* = v.spotlight_var1().*;
    var r6: t.uint16 = r14 *% 2;
    if (r6 < 224) r6 = 224;
    var r4: t.uint16 = r14 *% 2 -% r6;
    while (true) {
        var r8: t.uint16 = 0xff;
        if (r6 < v.spotlight_y_upper().*) {
            const tt: t.uint8 = @truncate(v.spotlight_var4().*);
            if (v.spotlight_var4().* != 0) v.spotlight_var4().* -%= 1;
            r8 = IrisSpotlight_CalculateCircleValue(tt);
        }
        if (r4 < 240) v.hdma_table_dynamic()[@as(usize, r4)] = r8;
        if (r6 < 240) v.hdma_table_dynamic()[@as(usize, r6)] = r8;
        if (r4 == r14) break;
        r4 +%= 1;
        r6 -%= 1;
    }

    var i: usize = 224;
    while (i < 240) : (i += 1) v.hdma_table_dynamic()[i] = 0;

    @memcpy(v.hdma_table_unused()[0..224], v.hdma_table_dynamic()[0..224]);

    const idx: usize = @as(usize, v.spotlight_var2().* >> 1);
    const delta: t.int8 = kSpotlight_delta_size[idx];
    v.spotlight_var1().* +%= @as(t.uint16, @bitCast(@as(t.int16, delta)));

    if (v.spotlight_var1().* != @as(t.uint16, kSpotlight_goal[idx])) return;

    if (v.spotlight_var2().* == 0) {
        v.INIDISP_copy().* = 0x80;
    } else {
        IrisSpotlight_ResetTable();
    }
    v.subsubmodule_index().* = 0;
    v.submodule_index().* = 0;

    if (v.main_module_index().* == 7 or v.main_module_index().* == 16) {
        if (v.player_is_indoors().* == 0)
            v.sound_effect_ambient().* = v.overworld_music()[@as(usize, t.byte(v.overworld_screen_index()).*)] >> 4;
        if (v.queued_music_control().* != 0xff)
            v.music_control().* = v.queued_music_control().*;
    }
    v.main_module_index().* = v.saved_module_for_menu().*;
    if (v.main_module_index().* == 6) Sprite_ResetAll();
}

pub export fn IrisSpotlight_ResetTable() void { // 80f427
    var i: usize = 0;
    while (i < 240) : (i += 1)
        v.hdma_table_dynamic()[i] = 0xff00;
}

pub export fn IrisSpotlight_CalculateCircleValue(a: t.uint8) t.uint16 { // 80f4cc
    const tt: t.uint8 = @truncate(snes_divide(@as(t.uint16, a) << 8, @truncate(v.spotlight_var1().*)) >> 1);
    const r10: t.uint8 = kConfigureSpotlightTable_Helper_Tab[@as(usize, tt)];
    const spot1_byte: t.uint8 = @truncate(v.spotlight_var1().*);
    const prod: t.uint16 = @as(t.uint16, r10) *% @as(t.uint16, spot1_byte);
    const inner: t.uint8 = @truncate(prod >> 8);
    const p: t.uint16 = @as(t.uint16, inner) *% 2;
    if (r10 == 0) return 0xff;
    const r2_0: t.uint16 = v.spotlight_var3().* +% p;
    const r0_0: t.uint16 = v.spotlight_var3().* -% p;
    const r0_1: t.uint16 = if (t.sign16(r0_0) != 0) 0 else if (r0_0 < 255) r0_0 else 255;
    const r2_1: t.uint16 = if (r2_0 < 255) r2_0 else 255;
    const result: t.uint16 = r0_1 | (r2_1 << 8);
    return if (result == 0xffff) 0xff else result;
}

pub export fn AdjustWaterHDMAWindow() void { // 80f649
    const r10: t.uint16 = v.water_hdma_var1().* -% v.BG2VOFS_copy2().*;
    v.spotlight_y_lower().* = r10 -% v.water_hdma_var2().*;
    v.spotlight_y_upper().* = r10 +% v.water_hdma_var2().*;
    AdjustWaterHDMAWindow_X(r10);
}

pub export fn AdjustWaterHDMAWindow_X(r10_in: t.uint16) void { // 80f660
    const r10 = r10_in;
    v.spotlight_var3().* = v.water_hdma_var0().* -% v.BG2HOFS_copy2().*;
    const r12_0: t.uint16 = if (v.water_hdma_var3().* != 0) v.water_hdma_var3().* -% 1 else 0;
    const r2_0: t.uint16 = v.spotlight_var3().* +% r12_0;
    const r0_0: t.uint16 = v.spotlight_var3().* -% r12_0;

    const r0_1: t.uint16 = if (r0_0 < 255) r0_0 else 255;
    const r2_1: t.uint16 = if (r2_0 < 255) r2_0 else 255;
    const r12: t.uint16 = r0_1 | (r2_1 << 8);

    var r6: t.uint16 = r10 *% 2;
    if (r6 < 0xe0) r6 = 0xe0;
    var r4: t.uint16 = 2 *% r10 -% r6;
    var a: t.uint16 = undefined;

    while (true) {
        if (t.sign16(r4) == 0) {
            if (t.sign16(v.spotlight_y_lower().*) == 0 and r4 < v.spotlight_y_lower().*)
                a = 0xff
            else
                a = r12;
            if (r4 < 240)
                v.hdma_table_dynamic()[@as(usize, r4)] = if (a != 0xffff) a else 0xff;
        }
        if (r6 >= v.spotlight_y_upper().*) {
            a = 0xff;
        } else {
            if (r6 >= 225 and v.word_7E0678().* != 0)
                v.word_7E0678().* -%= 1;
            a = r12;
        }
        if (r6 < 240)
            v.hdma_table_dynamic()[@as(usize, r6)] = if (a != 0xffff) a else 0xff;

        r6 -%= 1;
        const cont = r10 != r4;
        r4 +%= 1;
        if (!cont) break;
    }
}

pub export fn FloodDam_PrepFloodHDMA() void { // 80f734
    v.spotlight_y_lower().* = v.water_hdma_var1().* -% v.BG2VOFS_copy2().*;
    v.spotlight_var3().* = v.water_hdma_var0().* -% v.BG2HOFS_copy2().*;
    const r14: t.uint16 = v.water_hdma_var3().* ^ 1;
    var r12: t.uint16 = ((v.spotlight_var3().* +% r14) << 8) | @as(t.uint16, @as(t.uint8, @truncate(v.spotlight_var3().* -% r14)));

    var r4: c_int = 0;
    while (true) {
        v.hdma_table_dynamic()[@as(usize, @intCast(r4))] = 0xff00;
        r4 += 1;
        if (r4 == @as(c_int, v.spotlight_y_upper().*)) break;
    }

    r12 = r14 -% 7 +% 8;
    r12 = ((v.spotlight_var3().* +% r12) << 8) | @as(t.uint16, @as(t.uint8, @truncate(v.spotlight_var3().* -% r12)));
    const r10: t.uint16 = (v.spotlight_y_upper().* +% v.water_hdma_var2().*) ^ 1;

    while (true) {
        if (r4 >= @as(c_int, r10)) {
            v.hdma_table_dynamic()[@as(usize, @intCast(r4))] = 0xff;
        } else {
            var a: t.uint16 = @as(t.uint16, @intCast(r4));
            while (true) {
                a *%= 2;
                if (a < 480) break;
            }
            v.hdma_table_dynamic()[@as(usize, a >> 1)] = if (r12 == 0xffff) 0xff else r12;
        }
        r4 += 1;
        if (r4 >= 225) break;
    }
}

pub export fn ResetStarTileGraphics() void { // 80fda4
    v.byte_7E04BC().* = 0;
    Dungeon_RestoreStarTileChr();
}

pub export fn Dungeon_RestoreStarTileChr() void { // 80fda7
    var xx: usize = 0;
    var yy: usize = 32;
    if (v.byte_7E04BC().* != 0) {
        xx = 32;
        yy = 0;
    }
    const p: [*]align(1) t.uint8 = @ptrCast(v.messaging_buf());
    @memcpy(p[0..32], v.g_ram[0xbdc0 + xx .. 0xbdc0 + xx + 32]);
    @memcpy(p[32..64], v.g_ram[0xbdc0 + yy .. 0xbdc0 + yy + 32]);
    v.nmi_subroutine_index().* = 0x18;
}

pub export fn LinkZap_HandleMosaic() void { // 81fed2
    var level: c_int = @intCast(v.mosaic_level().*);
    if (v.mosaic_inc_or_dec().* == 0) {
        level += 0x10;
        if (level == 0xc0) v.mosaic_inc_or_dec().* = 1;
    } else {
        level -= 0x10;
        if (level == 0) v.mosaic_inc_or_dec().* = 0;
    }
    v.mosaic_level().* = @intCast(level);
    v.MOSAIC_copy().* = @as(t.uint8, @intCast(level >> 1)) | 3;
    v.BGMODE_copy().* = 9;
}

pub export fn Player_SetCustomMosaicLevel(a: t.uint8) void { // 81fef0
    v.mosaic_inc_or_dec().* = 0;
    v.mosaic_level().* = a;
    v.MOSAIC_copy().* = (v.mosaic_level().* >> 1) | 3;
    v.BGMODE_copy().* = 9;
}

pub export fn Module07_16_UpdatePegs_Step1() void { // 829739
    if (t.byte(v.orange_blue_barrier_state()).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x80, 0x100);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x100, 0x80);
    }
}

pub export fn Module07_16_UpdatePegs_Step2() void { // 82974d
    if (t.byte(v.orange_blue_barrier_state()).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x100, 0x80);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x80, 0x100);
    }
}

pub export fn Dungeon_UpdatePegGFXBuffer(x: c_int, y: c_int) void { // 829773
    const src: [*]align(1) const t.uint16 = @ptrCast(&v.g_ram[0xb340]);
    var i: usize = 0;
    while (i < 64) : (i += 1)
        v.messaging_buf()[i] = src[@as(usize, @intCast(x >> 1)) + i];
    i = 0;
    while (i < 64) : (i += 1)
        v.messaging_buf()[64 + i] = src[@as(usize, @intCast(y >> 1)) + i];
    v.nmi_subroutine_index().* = 23;
}

pub export fn Dungeon_HandleTranslucencyAndPalette() void { // 82a1e9
    if (v.palette_swap_flag().* != 0)
        Palette_RevertTranslucencySwap();

    v.CGWSEL_copy().* = 2;
    v.CGADSUB_copy().* = 0xb3;

    var torch: t.uint8 = v.dung_num_lit_torches().*;
    if (v.dung_want_lights_out().* == 0) {
        var a: t.uint8 = 0x20;
        var enter_block = false;
        blk: {
            a = 0x20;
            if (v.dung_hdr_bg2_properties().* == 0) break :blk;
            a = 0x32;
            if (v.dung_hdr_bg2_properties().* == 7) break :blk;
            a = 0x62;
            if (v.dung_hdr_bg2_properties().* == 4) break :blk;
            a = 0x20;
            if (v.dung_hdr_bg2_properties().* != 2) break :blk;
            enter_block = true;
        }
        if (enter_block) {
            Palette_AssertTranslucencySwap();
            if (t.byte(v.dungeon_room_index()).* == 13) {
                var i: usize = 0;
                while (i < 6) : (i += 1) v.agahnim_pal_setting()[i] = 0;
                Palette_LoadAgahnim();
            }
            a = 0x70;
        }
        v.CGADSUB_copy().* = a;
        torch = 3;
    }
    v.overworld_fixed_color_plusminus().* = kLitTorchesColorPlus[@as(usize, torch)];
    v.palette_filter_countdown().* = 31;
    v.mosaic_target_level().* = 0;
    v.darkening_or_lightening_screen().* = 2;
    v.overworld_palette_aux_or_main().* = 0;
    Palette_Load_DungeonSet();
    Palette_Load_Sp0L();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    v.subsubmodule_index().* +%= 1;
}

pub export fn Overworld_LoadAllPalettes() void { // 82c5b2
    var i: usize = 0x180 / 2;
    while (i < 0x180 / 2 + 64) : (i += 1) v.aux_palette_buffer()[i] = 0;
    i = 0;
    while (i < 256) : (i += 1) v.main_palette_buffer()[i] = 0;

    v.overworld_palette_mode().* = 5;
    v.overworld_palette_aux1_bp2to4_hi().* = 3;
    v.overworld_palette_aux2_bp5to7_hi().* = 3;
    v.overworld_palette_aux3_bp7_lo().* = 0;
    v.palette_sp6r_indoors().* = 5;
    v.palette_sp0l().* = 11;
    v.palette_swap_flag().* = 0;
    v.overworld_palette_aux_or_main().* = 0;
    Palette_BgAndFixedColor_Black();
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_OWBGMain();
    Palette_Load_OWBG1();
    Palette_Load_OWBG2();
    Palette_Load_OWBG3();
    Palette_Load_SpriteEnvironment_Dungeon();
    Palette_Load_HUD();

    i = 0;
    while (i < 8) : (i += 1) v.main_palette_buffer()[0x1b0 / 2 + i] = v.aux_palette_buffer()[0x1d0 / 2 + i];
}

pub export fn Dungeon_LoadPalettes() void { // 82c630
    v.overworld_palette_aux_or_main().* = 0;
    Palette_BgAndFixedColor_Black();
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_Sword();
    Palette_Load_Shield();
    Palette_Load_SpriteEnvironment();
    Palette_Load_LinkArmorAndGloves();
    Palette_Load_HUD();
    Palette_Load_DungeonSet();
    Overworld_LoadPalettesInner();
}

pub export fn Overworld_LoadPalettesInner() void { // 82c65f
    v.overworld_pal_unk1().* = v.palette_main_indoors().*;
    v.overworld_pal_unk2().* = v.overworld_palette_aux3_bp7_lo().*;
    v.overworld_pal_unk3().* = v.byte_7E0AB7().*;
    v.darkening_or_lightening_screen().* = 2;
    v.palette_filter_countdown().* = 0;
    t.word(v.mosaic_target_level()).* = 0;
    Overworld_CopyPalettesToCache();
}

pub export fn OverworldLoadScreensPaletteSet() void { // 82c692
    const sc: t.uint8 = @truncate(v.overworld_screen_index().* & 0x3f);
    var x: t.uint8 = if (sc == 3 or sc == 5 or sc == 7) 2 else 0;
    x +%= if ((v.overworld_screen_index().* & 0x40) != 0) @as(t.uint8, 1) else 0;
    Overworld_LoadAreaPalettesEx(x);
}

pub export fn Overworld_LoadAreaPalettesEx(x: t.uint8) void { // 82c6ad
    v.overworld_palette_mode().* = x;
    v.overworld_palette_aux_or_main().* &= 0xff;
    Palette_Load_SpriteMain();
    Palette_Load_SpriteEnvironment();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_Sword();
    Palette_Load_Shield();
    Palette_Load_LinkArmorAndGloves();
    v.palette_sp0l().* = if ((v.savegame_is_darkworld().* & 0x40) != 0) 3 else 1;
    Palette_Load_Sp0L();
    Palette_Load_HUD();
    Palette_Load_OWBGMain();
}

pub export fn SpecialOverworld_CopyPalettesToCache() void { // 82c6eb
    var i: usize = 32;
    while (i < 32 * 8) : (i += 1) v.main_palette_buffer()[i] = 0;
    i = 0;
    while (i < 8) : (i += 1) {
        v.main_palette_buffer()[i] = v.aux_palette_buffer()[i];
        v.main_palette_buffer()[i + 0x8] = v.aux_palette_buffer()[i + 0x8];
        v.main_palette_buffer()[i + 0x10] = v.aux_palette_buffer()[i + 0x10];
        v.main_palette_buffer()[i + 0x18] = v.aux_palette_buffer()[i + 0x18];
        v.main_palette_buffer()[i + 0xd8] = v.aux_palette_buffer()[i + 0xd8];
        v.main_palette_buffer()[i + 0xe8] = v.aux_palette_buffer()[i + 0xe8];
        v.main_palette_buffer()[i + 0xf0] = v.aux_palette_buffer()[i + 0xf0];
        v.main_palette_buffer()[i + 0xf8] = v.aux_palette_buffer()[i + 0xf8];
    }
    v.MOSAIC_copy().* = 0xf7;
    v.mosaic_level().* = 0xf7;
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Overworld_CopyPalettesToCache() void { // 82c769
    var i: usize = 0;
    while (i < 256) : (i += 1) v.main_palette_buffer()[i] = v.aux_palette_buffer()[i];
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Overworld_LoadPalettes(bg: t.uint8, spr: t.uint8) void { // 8ed5a8
    v.overworld_palette_aux_or_main().* = 0;

    var d: [*]const t.int8 = @ptrCast(&kOwBgPalInfo[0]);
    d += @as(usize, bg) * 3;
    if (d[0] >= 0) v.overworld_palette_aux1_bp2to4_hi().* = @intCast(d[0]);
    if (d[1] >= 0) v.overworld_palette_aux2_bp5to7_hi().* = @intCast(d[1]);
    if (d[2] >= 0) v.overworld_palette_aux3_bp7_lo().* = @intCast(d[2]);

    d = @ptrCast(&kOwSprPalInfo[0]);
    d += @as(usize, spr) * 2;
    if (d[0] >= 0) v.palette_sp5l().* = @intCast(d[0]);
    if (d[1] >= 0) v.palette_sp6l().* = @intCast(d[1]);
    Palette_Load_OWBG1();
    Palette_Load_OWBG2();
    Palette_Load_OWBG3();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
}

pub export fn Palette_BgAndFixedColor_Black() void { // 8ed5f4
    Palette_SetBgAndFixedColor(0);
}

pub export fn Palette_SetBgAndFixedColor(color: t.uint16) void { // 8ed5f9
    v.main_palette_buffer()[0] = color;
    v.main_palette_buffer()[32] = color;
    v.aux_palette_buffer()[0] = color;
    v.aux_palette_buffer()[32] = color;
    SetBackdropcolorBlack();
}

pub export fn SetBackdropcolorBlack() void { // 8ed60b
    v.COLDATA_copy0().* = 0x20;
    v.COLDATA_copy1().* = 0x40;
    v.COLDATA_copy2().* = 0x80;
}

pub export fn Palette_SetOwBgColor() void { // 8ed618
    Palette_SetBgAndFixedColor(Palette_GetOwBgColor());
}

pub export fn Palette_SpecialOw() void { // 8ed61d
    const c: t.uint16 = Palette_GetOwBgColor();
    v.aux_palette_buffer()[0] = c;
    v.aux_palette_buffer()[32] = c;
    SetBackdropcolorBlack();
}

pub export fn Palette_GetOwBgColor() t.uint16 { // 8ed622
    if (v.overworld_screen_index().* < 0x80)
        return if ((v.overworld_screen_index().* & 0x40) != 0) 0x2A32 else 0x2669;
    if (v.dungeon_room_index().* == 0x180 or v.dungeon_room_index().* == 0x182 or v.dungeon_room_index().* == 0x183)
        return 0x19C6;
    return 0x2669;
}

pub export fn Palette_AssertTranslucencySwap() void { // 8ed657
    Palette_SetTranslucencySwap(true);
}

pub export fn Palette_SetTranslucencySwap(swap: bool) void { // 8ed65c
    v.palette_swap_flag().* = if (swap) 1 else 0;
    var a: t.uint16 = undefined;
    var b: t.uint16 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        a = v.aux_palette_buffer()[i + 0x80];
        b = v.aux_palette_buffer()[i + 0xf0];
        v.aux_palette_buffer()[i + 0xf0] = a;
        v.main_palette_buffer()[i + 0xf0] = a;
        v.aux_palette_buffer()[i + 0x80] = b;
        v.main_palette_buffer()[i + 0x80] = b;

        a = v.aux_palette_buffer()[i + 0x88];
        b = v.aux_palette_buffer()[i + 0xf8];
        v.aux_palette_buffer()[i + 0xf8] = a;
        v.main_palette_buffer()[i + 0xf8] = a;
        v.aux_palette_buffer()[i + 0x88] = b;
        v.main_palette_buffer()[i + 0x88] = b;

        a = v.aux_palette_buffer()[i + 0xb8];
        b = v.aux_palette_buffer()[i + 0xd8];
        v.aux_palette_buffer()[i + 0xd8] = a;
        v.main_palette_buffer()[i + 0xd8] = a;
        v.aux_palette_buffer()[i + 0xb8] = b;
        v.main_palette_buffer()[i + 0xb8] = b;
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_RevertTranslucencySwap() void { // 8ed6bb
    Palette_SetTranslucencySwap(false);
}

pub export fn LoadActualGearPalettes() void { // 8ed6c0
    LoadGearPalettes(v.link_sword_type().*, v.link_shield_type().*, v.link_armor().*);
    if ((enhanced_features0().* & kFeatures0_MiscBugFixes) != 0)
        Palette_UpdateGlovesColor();
}

pub export fn Palette_ElectroThemedGear() void { // 8ed6d1
    LoadGearPalettes(2, 2, 4);
}

pub export fn LoadGearPalettes_bunny() void { // 8ed6dd
    LoadGearPalettes(v.link_sword_type().*, v.link_shield_type().*, 3);
}

pub export fn LoadGearPalettes(sword: t.uint8, shield: t.uint8, armor: t.uint8) void { // 8ed6e8
    var src: [*]align(1) const t.uint16 = kPalette_Sword() + @as(usize, if (sword != 0 and sword != 255) sword - 1 else 0) * 3;
    Palette_LoadMultiple_Arbitrary(src, 0x1b2, 2);

    src = kPalette_Shield() + @as(usize, if (shield != 0) shield - 1 else 0) * 4;
    Palette_LoadMultiple_Arbitrary(src, 0x1b8, 3);

    src = kPalette_ArmorAndGloves() + @as(usize, armor) * 15;
    Palette_LoadMultiple_Arbitrary(src, 0x1e2, 14);
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn LoadGearPalette(dst: c_int, src: [*]align(1) const t.uint16, n: c_int) void { // 8ed741
    const off: usize = @intCast(dst >> 1);
    const nu: usize = @intCast(n);
    var i: usize = 0;
    while (i < nu) : (i += 1) {
        v.aux_palette_buffer()[off + i] = src[i];
        v.main_palette_buffer()[off + i] = src[i];
    }
}

pub export fn Filter_Majorly_Whiten_Bg() void { // 8ed757
    var i: usize = 32;
    while (i < 128) : (i += 1) v.main_palette_buffer()[i] = Filter_Majorly_Whiten_Color(v.aux_palette_buffer()[i]);
    v.main_palette_buffer()[0] = if (v.aux_palette_buffer()[0] != 0) v.main_palette_buffer()[32] else 0;
}

pub export fn Filter_Majorly_Whiten_Color(c: t.uint16) t.uint16 { // 8ed7fe
    const amt: c_int = if ((enhanced_features0().* & kFeatures0_DimFlashes) != 0) 3 else 14;
    var r: c_int = @as(c_int, c & 0x1f) + amt;
    var g: c_int = @as(c_int, c & 0x3e0) + (amt << 5);
    var b: c_int = @as(c_int, c & 0x7c00) + (amt << 10);
    if (r > 0x1f) r = 0x1f;
    if (g > 0x3e0) g = 0x3e0;
    if (b > 0x7c00) b = 0x7c00;
    return @intCast(r | g | b);
}

pub export fn Palette_Restore_BG_From_Flash() void { // 8ed83a
    var i: usize = 32;
    while (i < 128) : (i += 1) v.main_palette_buffer()[i] = v.aux_palette_buffer()[i];
    v.main_palette_buffer()[0] = v.main_palette_buffer()[32];
    Palette_Restore_Coldata();
}

pub export fn Palette_Restore_Coldata() void { // 8ed8ae
    if (v.player_is_indoors().* == 0) {
        const rgb: t.uint32 = switch (t.byte(v.overworld_screen_index()).*) {
            3, 5, 7 => 0x8c4c26,
            0x43, 0x45, 0x47 => 0x874a26,
            0x5b => 0x894f33,
            else => 0x804020,
        };
        v.COLDATA_copy0().* = @truncate(rgb);
        v.COLDATA_copy1().* = @truncate(rgb >> 8);
        v.COLDATA_copy2().* = @truncate(rgb >> 16);
    }
}

pub export fn Palette_Restore_BG_And_HUD() void { // 8ed8fb
    var i: usize = 0;
    while (i < 128) : (i += 1) v.main_palette_buffer()[i] = v.aux_palette_buffer()[i];
    v.flag_update_cgram_in_nmi().* +%= 1;
    Palette_Restore_Coldata();
}

// Summary of sprite palette usage:
//   0l: kPalette_SpriteAux3[palette_sp0l]
//   0r: kPalette_MiscSprite[7 / 9] or kPalette_DungBgMain[(palette_main_indoors >> 1) * 90]
//   1 : common sprites
//   2 :      -"-
//   3 :      -"-
//   4 :      -"-
//   5l: palette_sp5l
//   5r: link sword/shield
//   6l: palette_sp6l
//   6r: kPalette_MiscSprite[6 / 8] or kPalette_MiscSprite[palette_sp6r_indoors]
//   7 : link armor and gloves

const kPal_sp0l: c_int = 0x102;
const kPal_sp0r: c_int = 0x112;
const kPal_sp1to4: c_int = 0x122; // This is used for 64 colors, colors switched if in darkworld mode
const kPal_sp5l: c_int = 0x1a2;
const kPal_Sword: c_int = 0x1b2;
const kPal_Shield: c_int = 0x1b8;
const kPal_sp6l: c_int = 0x1c2;
const kPal_sp6r: c_int = 0x1d2;
const kPal_sp7l: c_int = 0x1e2;
const kPal_sp7r: c_int = 0x1f2;
const kPal_ArmorGloves: c_int = 0x1e2;
const kPal_PalaceMap: c_int = 0x182;

const kSrmOffs_Gloves: usize = 0x354;
const kSrmOffs_Sword: usize = 0x359;
const kSrmOffs_Shield: usize = 0x35a;
const kSrmOffs_Armor: usize = 0x35b;

pub export fn Palette_Load_Sp0L() void { // 9bec77
    const src = kPalette_SpriteAux3() + @as(usize, v.palette_sp0l().*) * 7;
    Palette_LoadSingle(src, if (v.palette_swap_flag().* != 0) kPal_sp7l else kPal_sp0l, 6);
}

pub export fn Palette_Load_SpriteMain() void { // 9bec9e
    const src = kPalette_MainSpr() + @as(usize, if ((v.overworld_screen_index().* & 0x40) != 0) 60 else 0);
    Palette_LoadMultiple(src, kPal_sp1to4, 14, 3);
}

pub export fn Palette_Load_Sp5L() void { // 9becc5
    const src = kPalette_SpriteAux1() + @as(usize, v.palette_sp5l().*) * 7;
    Palette_LoadSingle(src, kPal_sp5l, 6);
}

pub export fn Palette_Load_Sp6L() void { // 9bece4
    const src = kPalette_SpriteAux1() + @as(usize, v.palette_sp6l().*) * 7;
    Palette_LoadSingle(src, kPal_sp6l, 6);
}

pub export fn Palette_Load_Sword() void { // 9bed03
    // wtf: zelda reads offset 0xff
    const sword_signed: t.int8 = @bitCast(v.link_sword_type().*);
    const idx: usize = if (sword_signed > 0) @as(usize, v.link_sword_type().*) - 1 else 0;
    const src = kPalette_Sword() + idx * 3;
    Palette_LoadMultiple_Arbitrary(src, kPal_Sword, 2);
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_Load_Shield() void { // 9bed29
    const idx: usize = if (v.link_shield_type().* != 0) @as(usize, v.link_shield_type().*) - 1 else 0;
    const src = kPalette_Shield() + idx * 4;
    Palette_LoadMultiple_Arbitrary(src, kPal_Shield, 3);
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_Load_SpriteEnvironment() void { // 9bed6e
    if (v.player_is_indoors().* != 0) {
        Palette_Load_SpriteEnvironment_Dungeon();
    } else {
        Palette_MiscSprite_Outdoors();
    }
}

pub export fn Palette_Load_SpriteEnvironment_Dungeon() void { // 9bed72
    const src = kPalette_MiscSprite() + @as(usize, v.palette_sp6r_indoors().*) * 7;
    Palette_LoadSingle(src, kPal_sp6r, 6);
}

pub export fn Palette_MiscSprite_Outdoors() void { // 9bed91
    const idx: usize = if ((v.overworld_screen_index().* & 0x40) != 0) 9 else 7;
    const src = kPalette_MiscSprite() + idx * 7;
    Palette_LoadSingle(src, if (v.palette_swap_flag().* != 0) kPal_sp7r else kPal_sp0r, 6);
    Palette_LoadSingle(src - 7, kPal_sp6r, 6);
}

pub export fn Palette_Load_DungeonMapSprite() void { // 9beddd
    Palette_LoadMultiple(kPalette_PalaceMapSpr(), kPal_PalaceMap, 6, 2);
}

pub export fn Palette_Load_LinkArmorAndGloves() void { // 9bedf9
    const src = kPalette_ArmorAndGloves() + @as(usize, v.link_armor().*) * 15;
    Palette_LoadMultiple_Arbitrary(src, kPal_ArmorGloves, 14);
    Palette_UpdateGlovesColor();
}

pub export fn Palette_UpdateGlovesColor() void { // 9bee1b
    if (v.link_item_gloves().* != 0) {
        const color = kGlovesColor[v.link_item_gloves().* - 1];
        v.main_palette_buffer()[0xfd] = color;
        v.aux_palette_buffer()[0xfd] = color;
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn Palette_Load_DungeonMapBG() void { // 9bee3a
    Palette_LoadMultiple(kPalette_PalaceMapBg(), 0x40, 15, 5);
}

pub export fn Palette_Load_HUD() void { // 9bee52
    const src = kHudPalData() + @as(usize, v.hud_palette().*) * 32;
    Palette_LoadMultiple(src, 0x0, 15, 1);
}

pub export fn Palette_Load_DungeonSet() void { // 9bee74
    const src = kPalette_DungBgMain() + @as(usize, v.palette_main_indoors().* >> 1) * 90;
    Palette_LoadMultiple(src, 0x42, 14, 5);
    Palette_LoadSingle(src, if (v.palette_swap_flag().* != 0) kPal_sp7r else kPal_sp0r, 6);
}

pub export fn Palette_Load_OWBG3() void { // 9beea8
    const src = kPalette_OverworldBgAux3() + @as(usize, v.overworld_palette_aux3_bp7_lo().*) * 7;
    Palette_LoadSingle(src, 0xE2, 6);
}

pub export fn Palette_Load_OWBGMain() void { // 9beec7
    const src = kPalette_OverworldBgMain() + @as(usize, v.overworld_palette_mode().*) * 35;
    Palette_LoadMultiple(src, 0x42, 6, 4);
}

pub export fn Palette_Load_OWBG1() void { // 9beee8
    const src = kPalette_OverworldBgAux12() + @as(usize, v.overworld_palette_aux1_bp2to4_hi().*) * 21;
    Palette_LoadMultiple(src, 0x52, 6, 2);
}

pub export fn Palette_Load_OWBG2() void { // 9bef0c
    const src = kPalette_OverworldBgAux12() + @as(usize, v.overworld_palette_aux2_bp5to7_hi().*) * 21;
    Palette_LoadMultiple(src, 0xB2, 6, 2);
}

pub export fn Palette_LoadSingle(src: [*]align(1) const t.uint16, dst: c_int, x_ents: c_int) void { // 9bef30
    const off: usize = @intCast((dst + @as(c_int, v.overworld_palette_aux_or_main().*)) >> 1);
    const n: usize = @intCast(x_ents + 1);
    @memcpy(v.aux_palette_buffer()[off .. off + n], src[0..n]);
}

pub export fn Palette_LoadMultiple(src_in: [*]align(1) const t.uint16, dst_in: c_int, x_ents_in: c_int, y_pals_in: c_int) void { // 9bef4b
    var src = src_in;
    var dst = dst_in;
    var y_pals = y_pals_in;
    const n: usize = @intCast(x_ents_in + 1);
    while (true) {
        const off: usize = @intCast((dst + @as(c_int, v.overworld_palette_aux_or_main().*)) >> 1);
        @memcpy(v.aux_palette_buffer()[off .. off + n], src[0..n]);
        src += n;
        dst += 32;
        y_pals -= 1;
        if (y_pals < 0) break;
    }
}

pub export fn Palette_LoadMultiple_Arbitrary(src: [*]align(1) const t.uint16, dst: c_int, x_ents: c_int) void { // 9bef7b
    const off: usize = @intCast(dst >> 1);
    const n: usize = @intCast(x_ents + 1);
    @memcpy(v.aux_palette_buffer()[off .. off + n], src[0..n]);
    @memcpy(v.main_palette_buffer()[off .. off + n], src[0..n]);
}

pub export fn Palette_LoadForFileSelect() void { // 9bef96
    var src = v.g_zenv.sram.?;
    var i: c_int = 0;
    while (i < 3) : (i += 1) {
        Palette_LoadForFileSelect_Armor(i * 0x20, src[kSrmOffs_Armor], src[kSrmOffs_Gloves]);
        Palette_LoadForFileSelect_Sword(i * 0x20, src[kSrmOffs_Sword]);
        Palette_LoadForFileSelect_Shield(i * 0x20, src[kSrmOffs_Shield]);
        src += 0x500;
    }
    var j: usize = 0;
    while (j < 7) : (j += 1) {
        const c1 = kPalette_MainSpr()[7 + j];
        v.aux_palette_buffer()[0xe8 + j] = c1;
        v.main_palette_buffer()[0xe8 + j] = c1;
        const c2 = kPalette_MainSpr()[15 + 7 + j];
        v.aux_palette_buffer()[0xf8 + j] = c2;
        v.main_palette_buffer()[0xf8 + j] = c2;
    }
}

pub export fn Palette_LoadForFileSelect_Armor(k: c_int, armor: t.uint8, gloves: t.uint8) void { // 9bf032
    const pal = kPalette_ArmorAndGloves() + @as(usize, armor) * 15;
    const base: usize = @intCast(k + 0x81);
    var i: usize = 0;
    while (i != 15) : (i += 1) {
        const c = pal[i];
        v.aux_palette_buffer()[base + i] = c;
        v.main_palette_buffer()[base + i] = c;
    }
    if (gloves != 0) {
        const idx: usize = @intCast(k + 0x8d);
        const color = kGlovesColor[gloves - 1];
        v.aux_palette_buffer()[idx] = color;
        v.main_palette_buffer()[idx] = color;
    }
}

pub export fn Palette_LoadForFileSelect_Sword(k: c_int, sword: t.uint8) void { // 9bf072
    const idx: usize = if (sword != 0) @as(usize, sword) - 1 else 0;
    const src = kPalette_Sword() + idx * 3;
    const base: usize = @intCast(k + 0x99);
    var i: usize = 0;
    while (i != 3) : (i += 1) {
        const c = src[i];
        v.aux_palette_buffer()[base + i] = c;
        v.main_palette_buffer()[base + i] = c;
    }
}

pub export fn Palette_LoadForFileSelect_Shield(k: c_int, shield: t.uint8) void { // 9bf09a
    const idx: usize = if (shield != 0) @as(usize, shield) - 1 else 0;
    const src = kPalette_Shield() + idx * 4;
    const base: usize = @intCast(k + 0x9c);
    var i: usize = 0;
    while (i != 4) : (i += 1) {
        const c = src[i];
        v.aux_palette_buffer()[base + i] = c;
        v.main_palette_buffer()[base + i] = c;
    }
}

pub export fn Palette_LoadAgahnim() void { // 9bf0c2
    var src = kPalette_SpriteAux1() + 14 * 7;
    Palette_LoadMultiple_Arbitrary(src, 0x162, 6);
    Palette_LoadMultiple_Arbitrary(src, 0x182, 6);
    Palette_LoadMultiple_Arbitrary(src, 0x1a2, 6);
    src = kPalette_SpriteAux1() + 21 * 7;
    Palette_LoadMultiple_Arbitrary(src, 0x1c2, 6);
    v.flag_update_cgram_in_nmi().* +%= 1;
}

pub export fn HandleScreenFlash() void { // 9de9b6
    const j: c_int = v.intro_times_pal_flash().*;
    if (j == 0 or v.submodule_index().* != 0) return;
    v.intro_times_pal_flash().* -%= 1;
    if (v.intro_times_pal_flash().* == 0) {
        Palette_Restore_BG_And_HUD();
        return;
    }
    if ((j & 1) != 0) {
        Filter_Majorly_Whiten_Bg();
    } else {
        Palette_Restore_BG_From_Flash();
    }
    v.flag_update_cgram_in_nmi().* +%= 1;
}
