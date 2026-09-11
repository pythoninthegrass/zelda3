// Port of src/misc.c: the top-level game-state dispatcher (Module_MainRouting,
// called every frame from ZeldaRunGameLoop), the NMI sprite-prep DMA source
// tables, dungeon torch lighting, the item-receipt (AncillaAdd_ItemReceipt)
// pipeline, SFX panning helpers, and assorted module-level helpers
// (load-file, boss-victory, Kill-Agahnim cutscene, save-and-quit, ...).
// Every exported function keeps its exact C-ABI name and signature so the
// remaining .c callers link unchanged. All game state lives in g_ram
// (variables.zig accessors), byte-for-byte where the original 65816 code and
// the RAM-compare oracle expect it.

const std = @import("std");
const t = @import("types.zig");
const v = @import("variables.zig");

// assets.h: kSoundBank_* and kPredefinedTileData are g_asset_ptrs-indexed
// macros; the table itself stays defined in C.
extern var g_asset_ptrs: [165]?[*]const t.uint8; // assets.c

extern const kLitTorchesColorPlus: [4]t.uint8; // zelda_rtl.c
extern const kUpperBitmasks: [16]t.uint16; // zelda_rtl.c

// zelda_rtl.h
extern fn LoadSongBank(p: [*]const t.uint8) void;
extern fn HdmaSetup(addr6: t.uint32, addr7: t.uint32, transfer_unit: t.uint8, reg6: t.uint8, reg7: t.uint8, indirect_bank: t.uint8) void;

// hud.c
extern fn Hud_SearchForEquippedItem() void;
extern fn Hud_Rebuild() void;
extern fn Hud_RebuildIndoor() void;
extern fn Hud_UpdateEquippedItem() void;
extern fn Hud_RefillHealth() bool;
extern fn Hud_RefillMagicPower() bool;
extern fn Hud_RefillLogic() void;
extern fn Hud_RefreshIcon() void;
extern fn EnableForceBlank() void;

// dungeon.c
extern fn Module_PreDungeon() void;
extern fn LoadOWMusicIfNeeded() void;
extern fn Module07_Dungeon() void;
extern fn Module11_DungeonFallingEntrance() void;
extern fn SaveDungeonKeys() void;
extern fn Dungeon_FlagRoomData_Quadrants() void;
extern fn Dungeon_LoadPalettes() void;
extern fn Dungeon_ResetTorchBackgroundAndPlayerInner() void;
extern fn HandleItemTileAction_Dungeon(x: t.uint16, y: t.uint16) t.uint8;

// overworld.c
extern fn InitializeMirrorHDMA() void;
extern fn MirrorWarp_BuildWavingHDMATable() void;
extern fn MirrorWarp_BuildDewavingHDMATable() void;
extern fn Module08_OverworldLoad() void;
extern fn Module09_Overworld() void;
extern fn Module0F_SpotlightClose() void;
extern fn Module10_SpotlightOpen() void;
extern fn Dungeon_PrepExitWithSpotlight() void;
extern fn Spotlight_ConfigureTableAndControl() void;
extern fn ResetAncillaAndCutscene() void;
extern fn Overworld_LoadGFXAndScreenSize() void;
extern fn Overworld_SetSongList() void;
extern fn Overworld_ToolAndTileInteraction(x: t.uint16, y: t.uint16) t.uint16;
extern fn OpenSpotlight_Next2() void;
extern fn Sprite_LoadGraphicsProperties() void;

// load_gfx.c
extern fn EraseTileMaps_normal() void;
extern fn LoadDefaultGraphics() void;
extern fn DecompressSwordGraphics() void;
extern fn DecompressShieldGraphics() void;
extern fn LoadFollowerGraphics() void;
extern fn ReloadPreviouslyLoadedSheets() void;
extern fn DecodeAnimatedSpriteTile_variable(a: t.uint8) void;
extern fn Palette_Load_Sword() void;
extern fn Palette_Load_Shield() void;
extern fn Palette_UpdateGlovesColor() void;
extern fn PaletteFilter_InitializeWhiteFilter() void;
extern fn Palette_RevertTranslucencySwap() void;

// sprite.c
extern fn Sprite_Main() void;
extern fn Sprite_ResetAll() void;
extern fn Sprite_GetX(k: c_int) t.uint16;

// player.c
extern fn Link_Main() void;
extern fn Link_Initialize() void;
extern fn Link_ResetProperties_A() void;
extern fn Link_AnimateVictorySpin() void;

// ancilla.c
extern fn Ancilla_AddAncilla(a: t.uint8, y: t.uint8) c_int;
extern fn Ancilla_SetXY(k: c_int, x: t.uint16, y: t.uint16) void;
extern fn Ancilla_TerminateSelectInteractives(y: t.uint8) t.uint8;
extern fn AncillaAdd_VictorySpin() void;
extern fn AncillaAdd_CapePoof(a: t.uint8, y: t.uint8) void;
extern fn AncillaAdd_MSCutscene(a: t.uint8, y: t.uint8) void;

// player_oam.c (player_oam.zig)
extern fn LinkOam_Main() void;

// select_file.c
extern fn Module01_FileSelect() void;
extern fn Module02_CopyFile() void;
extern fn Module03_KILLFile() void;
extern fn Module04_NameFile() void;

// messaging.c
extern fn Module0E_Interface() void;
extern fn Module12_GameOver() void;
extern fn Module1B_SpawnSelect() void;
extern fn RenderText() void;

// ending.c
extern fn Module00_Intro() void;
extern fn Module18_GanonEmerges() void;
extern fn Module19_TriforceRoom() void;
extern fn Module1A_Credits() void;
extern fn Death_Func15(count_as_death: bool) void;
extern fn ResetSomeThingsAfterDeath(a: t.uint8) void;

// attract.c
extern fn Module14_Attract() void;

// zelda_rtl.h: PlayerHandlerFunc = void (*)(); snes/snes_regs.h: WH0.
const WH0: t.uint16 = 0x2126;

const kPlayerState_Ground: t.uint8 = 0;
const kPlayerState_Mirror: t.uint8 = 20;

const VoidFunc = *const fn () callconv(.c) void;

const kModule_BossVictory: [6]VoidFunc = .{
    &BossVictory_Heal,
    &Dungeon_StartVictorySpin,
    &Dungeon_RunVictorySpin,
    &Dungeon_CloseVictorySpin,
    &Dungeon_PrepExitWithSpotlight,
    &Spotlight_ConfigureTableAndControl,
};
const kModule_KillAgahnim: [13]VoidFunc = .{
    &KillAgahnim_LoadMusic,
    &KillAghanim_Init,
    &KillAghanim_Func2,
    &KillAghanim_Func3,
    &KillAghanim_Func4,
    &KillAghanim_Func5,
    &KillAghanim_Func6,
    &KillAghanim_Func7,
    &KillAghanim_Func8,
    &BossVictory_Heal,
    &Dungeon_StartVictorySpin,
    &Dungeon_RunVictorySpin,
    &KillAghanim_Func12,
};
const kMainRouting: [28]VoidFunc = .{
    &Module00_Intro,
    &Module01_FileSelect,
    &Module02_CopyFile,
    &Module03_KILLFile,
    &Module04_NameFile,
    &Module05_LoadFile,
    &Module_PreDungeon,
    &Module07_Dungeon,
    &Module08_OverworldLoad,
    &Module09_Overworld,
    &Module08_OverworldLoad,
    &Module09_Overworld,
    &Module_Unknown0,
    &Module_Unknown1,
    &Module0E_Interface,
    &Module0F_SpotlightClose,
    &Module10_SpotlightOpen,
    &Module11_DungeonFallingEntrance,
    &Module12_GameOver,
    &Module13_BossVictory_Pendant,
    &Module14_Attract,
    &Module15_MirrorWarpFromAga,
    &Module16_BossVictory_Crystal,
    &Module17_SaveAndQuit,
    &Module18_GanonEmerges,
    &Module19_TriforceRoom,
    &Module1A_Credits,
    &Module1B_SpawnSelect,
};

pub export const kReceiveItemGfx: [76]t.uint8 = .{
    6,    0x18, 0x18, 0x18, 0x2d, 0x20, 0x2e, 9,    9,    0xa,  8,    5,    0x10, 0xb,  0x2c, 0x1b,
    0x1a, 0x1c, 0x14, 0x19, 0xc,  7,    0x1d, 0x2f, 7,    0x15, 0x12, 0xd,  0xd,  0xe,  0x11, 0x17,
    0x28, 0x27, 4,    4,    0xf,  0x16, 3,    0x13, 1,    0x1e, 0x10, 0,    0,    0,    0,    0,
    0,    0x30, 0x22, 0x21, 0x24, 0x24, 0x24, 0x23, 0x23, 0x23, 0x29, 0x2a, 0x2c, 0x2b, 3,    3,
    0x34, 0x35, 0x31, 0x33, 2,    0x32, 0x36, 0x37, 0x2c, 6,    0xc,  0x38,
};

pub export const kMemoryLocationToGiveItemTo: [76]t.uint16 = .{
    0xf359, 0xf359, 0xf359, 0xf359,
    0xf35a, 0xf35a, 0xf35a, 0xf345,
    0xf346, 0xf34b, 0xf342, 0xf340,
    0xf341, 0xf344, 0xf35c, 0xf347,
    0xf348, 0xf349, 0xf34a, 0xf34c,
    0xf34c, 0xf350, 0xf35c, 0xf36b,
    0xf351, 0xf352, 0xf353, 0xf354,
    0xf354, 0xf34e, 0xf356, 0xf357,
    0xf37a, 0xf34d, 0xf35b, 0xf35b,
    0xf36f, 0xf364, 0xf36c, 0xf375,
    0xf375, 0xf344, 0xf341, 0xf35c,
    0xf35c, 0xf35c, 0xf36d, 0xf36e,
    0xf36e, 0xf375, 0xf366, 0xf368,
    0xf360, 0xf360, 0xf360, 0xf374,
    0xf374, 0xf374, 0xf340, 0xf340,
    0xf35c, 0xf35c, 0xf36c, 0xf36c,
    0xf360, 0xf360, 0xf372, 0xf376,
    0xf376, 0xf373, 0xf360, 0xf360,
    0xf35c, 0xf359, 0xf34c, 0xf355,
};

const kValueToGiveItemTo: [76]t.int8 = .{
    1,    2,   3,   4,
    1,    2,   3,   1,
    1,    1,   1,   1,
    1,    2,   -1,  1,
    1,    1,   1,   1,
    2,    1,   -1,  -1,
    1,    1,   2,   1,
    2,    1,   1,   1,
    -1,   1,   -1,  2,
    -1,   -1,  -1,  -1,
    -1,   -1,  2,   -1,
    -1,   -1,  -1,  -1,
    -1,   -1,  -1,  -1,
    -1,   -5,  -20, -1,
    -1,   -1,  1,   3,
    -1,   -1,  -1,  -1,
    -100, -50, -1,  1,
    10,   -1,  -1,  -1,
    -1,   1,   3,   1,
};

pub export const kReceiveItem_Tab1: [76]t.uint8 = .{
    0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 2, 2, 2,
    2, 2, 2, 0, 2, 0, 2, 2, 0, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 0, 0, 2, 0, 2, 2, 2, 0, 2, 2,
};
const kReceiveItem_Tab2: [76]t.int8 = .{
    -5, -5, -5, -5, -5, -4, -4, -5, -5, -4, -4, -4, -2, -4, -4, -4,
    -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4,
    -4, -4, -4, -5, -4, -4, -4, -4, -4, -4, -2, -4, -4, -4, -4, -4,
    -4, -4, -4, -4, -2, -2, -2, -4, -4, -4, -4, -4, -4, -4, -4, -4,
    -4, -4, -2, -2, -4, -2, -4, -4, -4, -5, -4, -4,
};
const kReceiveItem_Tab3: [76]t.uint8 = .{
    4, 4, 4, 4, 4, 0, 0, 4, 4, 4, 4, 4, 5, 0, 0, 0,
    0, 0, 0, 4, 0, 4, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 4, 4, 0, 4, 0, 0, 0, 4, 0, 0,
};

const kDungeon_DefaultAttr: [384]t.uint8 = .{
    1,    1,    1,    0,    2,    1,    2,    0,    1,    1,    2,    2,    2,    2,    2,    2,
    2,    2,    2,    0,    0,    1,    0,    0,    2,    0,    0,    2,    2,    2,    2,    2,
    2,    2,    2,    2,    1,    1,    1,    2,    2,    2,    2,    2,    1,    1,    0,    0,
    2,    2,    2,    2,    2,    2,    1,    2,    2,    2,    2,    2,    1,    1,    0,    0,
    0,    0,    0,    0x2a, 1,    0x20, 1,    1,    4,    1,    1,    0x18, 1,    2,    0x1c, 1,
    0x28, 0x28, 0x2a, 0x2a, 1,    2,    1,    1,    4,    0,    0,    0,    0x28, 1,    0xa,  0,
    1,    1,    0xc,  0xc,  2,    2,    2,    2,    0x28, 0x2a, 0x20, 0x20, 0x20, 2,    8,    0,
    4,    4,    1,    1,    1,    2,    2,    2,    0,    0,    0x20, 0x20, 0,    2,    0,    0,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    2,    2,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    0x18, 0x10, 0x10, 1,    1,    1,
    1,    1,    4,    4,    4,    4,    4,    4,    1,    2,    2,    0,    0,    0,    0,    0,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    2,    2,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x62, 0x62,
    0,    0,    0x24, 0x24, 0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x62, 0x62,
    0x27, 2,    2,    2,    0x27, 0x27, 1,    0,    0,    0,    0,    0x24, 0,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x10, 2,    1,    0,    0,    0,    0x24, 0,    0,    0,    0,
    0x27, 2,    2,    2,    0x27, 0x27, 0x27, 0x27, 2,    2,    2,    0x24, 0,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x20, 2,    2,    1,    2,    2,    0x23, 2,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x20, 2,    0x27, 2,    0x54, 0,    0,    0x27, 2,    2,    2,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x27, 2,    0x27, 2,    0x54, 0,    0,    0x27, 2,    2,    2,
    0x27, 0x27, 0,    0x27, 0x60, 0x60, 1,    1,    1,    1,    2,    2,    0xd,  0,    0,    0x4b,
    0x67, 0x67, 0x67, 0x67, 0x66, 0x66, 0x66, 0x66, 0,    0,    0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x27, 0x63, 0x27, 0x55, 0x55, 1,    0x44, 0,    1,    0x20, 2,    2,    0x1c, 0x3a, 0x3b, 0,
    0x27, 0x63, 0x27, 0x53, 0x53, 1,    0x44, 1,    0xd,  0,    0,    0,    9,    9,    9,    9,
};

// assets.h: #define kPredefinedTileData ((uint16*)g_asset_ptrs[69])
fn PredefinedTileData() [*]align(1) const t.uint16 {
    return @as([*]align(1) const t.uint16, @ptrCast(g_asset_ptrs[69].?));
}

pub export fn SrcPtr(src: t.uint16) [*]align(1) const t.uint16 {
    return PredefinedTileData() + (src >> 1);
}

fn PlaySfx_SetPan(a: t.uint8) t.uint8 {
    v.byte_7E0CF8().* = a;
    return a | Link_CalculateSfxPan();
}

pub export fn Ancilla_Sfx2_Near(a: t.uint8) t.uint8 {
    v.sound_effect_1().* = PlaySfx_SetPan(a);
    return v.sound_effect_1().*;
}

pub export fn Ancilla_Sfx3_Near(a: t.uint8) void {
    v.sound_effect_2().* = PlaySfx_SetPan(a);
}

pub export fn LoadDungeonRoomRebuildHUD() void {
    v.mosaic_level().* = 0;
    v.MOSAIC_copy().* = 7;
    Hud_SearchForEquippedItem();
    Hud_Rebuild();
    Hud_UpdateEquippedItem();
    Module_PreDungeon();
}

pub export fn Module_Unknown0() void {
    // assert(0) in C
    std.process.abort();
}

pub export fn Module_Unknown1() void {
    // assert(0) in C
    std.process.abort();
}

fn KillAgahnim_LoadMusic() callconv(.c) void {
    v.nmi_disable_core_updates().* = 0;
    v.overworld_map_state().* += 1;
    v.submodule_index().* += 1;
    LoadOWMusicIfNeeded();
}

fn KillAghanim_Init() callconv(.c) void {
    v.music_control().* = 8;
    t.byte(v.overworld_screen_trans_dir_bits()).* = 8;
    InitializeMirrorHDMA();
    v.overworld_map_state().* = 0;
    PaletteFilter_InitializeWhiteFilter();
    Overworld_LoadGFXAndScreenSize();
    v.submodule_index().* += 1;
    v.link_player_handler_state().* = kPlayerState_Mirror;
    v.bg1_x_offset().* = 0;
    v.bg1_y_offset().* = 0;
    v.dung_savegame_state_bits().* = 0;
    t.word(v.link_y_vel()).* = 0;
    v.main_palette_buffer()[0] = 0x7fff;
    v.main_palette_buffer()[32] = 0x7fff;
    _ = Ancilla_TerminateSelectInteractives(0);
    Link_ResetProperties_A();
}

fn KillAghanim_Func2() callconv(.c) void {
    v.HDMAEN_copy().* = 192;
    MirrorWarp_BuildWavingHDMATable();
    v.submodule_index().* += 1;
    v.subsubmodule_index().* = 0;
}

fn KillAghanim_Func3() callconv(.c) void {
    MirrorWarp_BuildWavingHDMATable();
    if (v.subsubmodule_index().* != 0) {
        v.subsubmodule_index().* = 0;
        v.submodule_index().* += 1;
    }
}

fn KillAghanim_Func4() callconv(.c) void {
    MirrorWarp_BuildDewavingHDMATable();
    if (v.subsubmodule_index().* != 0) {
        v.subsubmodule_index().* = 0;
        v.submodule_index().* += 1;
    }
}

fn KillAghanim_Func5() callconv(.c) void {
    HdmaSetup(0, 0xf2fb, 0x41, 0, @as(t.uint8, @truncate(WH0)), 0);
    for (0..240) |i|
        v.hdma_table_dynamic()[i] = 0xff00;
    v.palette_filter_countdown().* = 0;
    v.darkening_or_lightening_screen().* = 0;
    v.dialogue_message_index().* = 0x35;
    Main_ShowTextMessage();
    ReloadPreviouslyLoadedSheets();
    Hud_RebuildIndoor();
    v.HDMAEN_copy().* = 0x80;
    v.main_module_index().* = 21;
    v.submodule_index().* = 6;
    v.subsubmodule_index().* = 24;
}

fn KillAghanim_Func6() callconv(.c) void {
    v.subsubmodule_index().* -%= 1;
    if (v.subsubmodule_index().* == 0) {
        v.submodule_index().* += 1;
        v.sound_effect_ambient().* = 9;
    }
}

fn KillAghanim_Func7() callconv(.c) void {
    RenderText();
    if (v.submodule_index().* == 0) {
        v.overworld_map_state().* = 0;
        v.sound_effect_ambient().* = 5;
        if (v.link_item_moon_pearl().* == 0) {
            v.dialogue_message_index().* = 0x36;
            Main_ShowTextMessage();
            v.sound_effect_ambient().* = 0;
            v.main_module_index().* = 21;
            v.submodule_index().* = 8;
        } else {
            v.submodule_index().* = 9;
        }
    }
}

fn KillAghanim_Func8() callconv(.c) void {
    RenderText();
    if (v.submodule_index().* == 0) {
        v.subsubmodule_index().* = 32;
        v.submodule_index().* = 12;
    }
}

fn KillAghanim_Func12() callconv(.c) void {
    v.subsubmodule_index().* -%= 1;
    if (v.subsubmodule_index().* != 0)
        return;
    ResetAncillaAndCutscene();
    Overworld_SetSongList();
    v.save_ow_event_info()[0x1b] |= 32;
    t.byte(v.cur_palace_index_x2()).* = 255;
    v.submodule_index().* = 0;
    v.overworld_map_state().* = 0;
    v.nmi_disable_core_updates().* = 0;
    v.main_module_index().* = 9;
    t.byte(v.BG1VOFS_copy2()).* = 0;
    v.music_control().* = if (v.link_item_moon_pearl().* != 0) 9 else 4;
    v.savegame_map_icons_indicator().* = 6;
}

pub export fn Module_MainRouting() void { // 8080b5
    kMainRouting[@intCast(v.main_module_index().*)]();
}
pub export fn NMI_PrepareSprites() void { // 8085fc
    const kLinkDmaSources1: [303]t.uint16 = .{
        0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
        0x9440, 0x8080, 0x8080, 0x8080, 0x9400, 0x8040, 0x80c0, 0x80c0, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
        0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0xa8c0, 0xa900, 0x8000, 0xa8c0, 0xa900,
        0x9100, 0x8080, 0x8080, 0x90c0, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x9a00, 0x9140, 0x9180, 0x8000, 0x9500,
        0x9480, 0x94c0, 0x94c0, 0x9ae0, 0x8080, 0x8080, 0x9a60, 0x80c0, 0x80c0, 0x9aa0, 0x8000, 0x8000, 0x9aa0, 0x8000, 0x8000, 0x8080,
        0x8080, 0x8100, 0x8100, 0x85c0, 0x8000, 0x8000, 0x85c0, 0x8000, 0x8000, 0xadc0, 0xadc0, 0xadc0, 0xadc0, 0xadc0, 0xad40, 0xad40,
        0xad40, 0xad40, 0xad40, 0xad80, 0xad80, 0xad80, 0xad80, 0xad80, 0xad80, 0x8040, 0x9400, 0x8040, 0x8000, 0x8080, 0x8080, 0x9440,
        0x8000, 0x8000, 0x8000, 0x8000, 0x8080, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0xc440, 0x8140, 0x8140,
        0xca40, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8040, 0x85c0, 0x8040, 0x85c0, 0x8100, 0x80c0, 0x91c0, 0x8080, 0x8080,
        0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8080, 0x8080, 0x9100, 0xa0c0, 0xa100, 0xa100, 0xa1c0, 0xa400, 0xa440, 0xa1c0,
        0xa400, 0xa440, 0x8080, 0xc480, 0x8080, 0x8040, 0x8040, 0xca80, 0xca80, 0xca00, 0xc400, 0xca00, 0xc400, 0x81c0, 0x8080, 0x8080,
        0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0xa8c0, 0xa900,
        0x8000, 0x8000, 0xa8c0, 0xa900, 0x8000, 0xa8c0, 0xa900, 0x8000, 0x8000, 0xa8c0, 0xa900, 0x8040, 0x8040, 0x8040, 0x8080, 0x8080,
        0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0xd080, 0x8080, 0x90c0, 0xd000, 0x9080, 0xd040, 0x9080, 0xd040,
        0xd080, 0xd080, 0xd080, 0xd080, 0xd080, 0xd000, 0xd000, 0xd000, 0xd000, 0xd000, 0xd040, 0xd040, 0xd040, 0xd040, 0xd040, 0xd040,
        0x8040, 0xd000, 0x85c0, 0x85c0, 0x85c0, 0xdc40, 0xdc40, 0xdc40, 0x85c0, 0x85c0, 0x85c0, 0xdc40, 0xdc40, 0xdc40, 0xe1c0, 0xd000,
        0x8000, 0xe400, 0xe400, 0xe440, 0x90c0, 0x90c0, 0xd000, 0x8000, 0x8000, 0xd040, 0x8000, 0x8000, 0xd040, 0xe400, 0xe400, 0xe400,
        0x9080, 0xa5c0, 0xac40, 0xe480, 0x8180, 0x90c0, 0x80c0, 0xe180, 0xd000, 0xe4c0, 0xe4c0, 0xe840, 0xe840, 0xe840, 0xe540, 0xe540,
        0xe540, 0xe900, 0xe900, 0xe900, 0xe900, 0x8080, 0x8080, 0x8000, 0xa9c0, 0x8080, 0x8140, 0x91c0, 0x8040, 0xa800, 0xa840,
    };
    const kLinkDmaSources2: [303]t.uint16 = .{
        0x8840, 0x8800, 0x8580, 0x8800, 0x8580, 0x84c0, 0x8500, 0x8540, 0x8500, 0x8540, 0x8400, 0x8440, 0x8480, 0x8400, 0x8440, 0x8480,
        0x9640, 0x8c40, 0x8c80, 0xad00, 0x9600, 0x8980, 0x8c00, 0xacc0, 0x8880, 0x88c0, 0x8900, 0x8940, 0x8880, 0x88c0, 0x8900, 0x8940,
        0xb0c0, 0xb100, 0xb140, 0xb100, 0xb140, 0xb000, 0xb040, 0xb080, 0xec80, 0xecc0, 0xb180, 0xd440, 0xb1c0, 0xb180, 0xd440, 0xb1c0,
        0x8c80, 0xad00, 0x95c0, 0x99c0, 0xb440, 0x9580, 0xb480, 0xb4c0, 0x9580, 0xb480, 0xb4c0, 0x9c20, 0x8000, 0x8000, 0x8000, 0x9700,
        0x9680, 0x96c0, 0x96c0, 0x9ce0, 0x8c80, 0xb540, 0x9c60, 0xb580, 0x8c00, 0x9ca0, 0x8900, 0xb500, 0x9ca0, 0x8900, 0xb500, 0x8c40,
        0xec40, 0x8c00, 0xec00, 0x8dc0, 0x9540, 0x89c0, 0x8dc0, 0x9540, 0x89c0, 0xb940, 0xb980, 0xb9c0, 0xb980, 0xb9c0, 0xb5c0, 0xb800,
        0xb840, 0xb800, 0xb840, 0xb880, 0xb8c0, 0xb900, 0xb880, 0xb8c0, 0xb900, 0x8980, 0x9600, 0xbcc0, 0x8400, 0xbc80, 0x8c40, 0x9640,
        0xa040, 0xa080, 0xa000, 0xbc40, 0xbd40, 0x8500, 0xbd00, 0xbd80, 0xbd80, 0x88c0, 0x8900, 0xe9c0, 0x8900, 0xc640, 0xc040, 0xc000,
        0xcc40, 0x8940, 0x88c0, 0x8900, 0xe9c0, 0x8900, 0x8940, 0x8d40, 0x8d80, 0x8d40, 0x8d80, 0xbd00, 0xb000, 0xb000, 0xa480, 0xa480,
        0xa480, 0xa480, 0xac00, 0xac00, 0xac00, 0xac00, 0xa140, 0xa180, 0xa180, 0xa4c0, 0xa4c0, 0xa500, 0x9d40, 0x9d80, 0x9dc0, 0x9d40,
        0x9d80, 0x9dc0, 0x8d00, 0xc680, 0xc180, 0xc140, 0x8c00, 0xcc80, 0xcc80, 0xcc00, 0xc600, 0xcc00, 0xc600, 0xbd00, 0x8580, 0x8800,
        0xc9c0, 0xccc0, 0xcdc0, 0xcd00, 0xcd40, 0xcd80, 0x8500, 0x8540, 0xc940, 0xc980, 0x8540, 0xc940, 0xc980, 0x8440, 0x8480, 0xc1c0,
        0xc900, 0xc580, 0xc5c0, 0xc8c0, 0x8440, 0x8480, 0xc1c0, 0xc900, 0xc580, 0xc5c0, 0xc8c0, 0xbd00, 0xacc0, 0xc040, 0xd540, 0xd580,
        0xd4c0, 0xd500, 0xd4c0, 0xd500, 0xd440, 0xd480, 0xd440, 0xd480, 0xd1c0, 0xd400, 0xd100, 0xd100, 0xd140, 0xd180, 0xd140, 0xd180,
        0xb0c0, 0xb100, 0xb140, 0xb100, 0xb140, 0xdd40, 0xdd80, 0xddc0, 0xdd80, 0xddc0, 0xdc80, 0xdcc0, 0xdd00, 0xdc80, 0xdcc0, 0xdd00,
        0xd100, 0xd100, 0xe000, 0xe040, 0xe080, 0xe0c0, 0xe100, 0xe140, 0xe000, 0xe040, 0xe080, 0xe0c0, 0xe100, 0xe140, 0x8000, 0xd0c0,
        0x8000, 0xb940, 0xb980, 0xb940, 0xdd40, 0xdd80, 0xdd40, 0xdc80, 0xdcc0, 0xc0c0, 0xdc80, 0xdcc0, 0xc0c0, 0xb9c0, 0xb980, 0xb9c0,
        0xa560, 0xa5a0, 0xac80, 0xed00, 0x8000, 0x8cc0, 0xbd00, 0xe380, 0xbdc0, 0xe500, 0xe500, 0xe880, 0xe8c0, 0xe8c0, 0xe800, 0xe5c0,
        0xe5c0, 0xe940, 0xe980, 0xe940, 0xe980, 0xbd40, 0x8c80, 0xa080, 0x8000, 0xa980, 0xbd00, 0xbdc0, 0xb400, 0xa880, 0xedc0,
    };
    const kLinkDmaSources3: [27]t.uint16 = .{
        0x9a40, 0x9e00, 0x9d20, 0x9f20, 0x9b20, 0xbc20, 0xbc20, 0xbe20, 0xbe20, 0xbe00, 0xbe00, 0xbe00, 0xbe00, 0xa540, 0xa540, 0xa540,
        0xa540, 0xbc00, 0xbc00, 0xbc00, 0xbc00, 0xa740, 0xa740, 0xa740, 0xa740, 0xe780, 0xe780,
    };
    const kLinkDmaSources4: [8]t.uint16 = .{ 0x9000, 0x9020, 0x9060, 0x91e0, 0x90a0, 0x90c0, 0x9100, 0x9140 };
    const kLinkDmaSources5: [3]t.uint16 = .{ 0x9300, 0x9340, 0x9380 };
    const kLinkDmaSources6: [128]t.uint16 = .{
        0x9480, 0x94c0, 0x94e0, 0x95c0, 0x9500, 0x9520, 0x9540, 0x9480, 0x9640, 0x9680, 0x96a0, 0x9780, 0x96c0, 0x96e0, 0x9700, 0x9480,
        0x9800, 0x9840, 0x98a0, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9ac0, 0x9b00, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
        0x9bc0, 0x9c00, 0x9c40, 0x9c80, 0x9cc0, 0x9d00, 0x9d40, 0x9480, 0x9f40, 0x9f80, 0x9fc0, 0x9fe0, 0xa000, 0x9480, 0x9480, 0x9480,
        0xa100, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
        0x98c0, 0x9900, 0x99c0, 0x99e0, 0x9a00, 0x9a20, 0x9a40, 0x9a60, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
        0x9a80, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
        0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
        0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    };
    const kLinkDmaSources7: [16]t.uint16 = .{ 0xe0, 0xe0, 0x60, 0x80, 0x1c0, 0xe0, 0x40, 0, 0x80, 0, 0x40, 0, 0, 0, 0, 0 };
    const kLinkDmaCtrs0: [6]t.uint16 = .{ 14, 4, 6, 16, 6, 8 };
    const kLinkDmaSources9: [15]t.uint16 = .{ 0, 0x20, 0x40, 0, 0x20, 0x40, 0, 0x40, 0x80, 0, 0x40, 0x80, 0xb340, 0xb400, 0xb4c0 };
    const kLinkDmaSources8: [4]t.uint16 = .{ 0xa480, 0xa4c0, 0xa500, 0xa540 };

    const ext = v.extended_oam();
    const bytewise = v.bytewise_extended_oam();
    for (0..32) |i| {
        const b0: u32 = @as(u32, bytewise[4 * i + 0]);
        const b1: u32 = @as(u32, bytewise[4 * i + 1]);
        const b2: u32 = @as(u32, bytewise[4 * i + 2]);
        const b3: u32 = @as(u32, bytewise[4 * i + 3]);
        ext[i] = @as(t.uint8, @truncate((b3 << 6) | (b2 << 4) | (b1 << 2) | b0));
    }

    v.dma_source_addr_3().* = kLinkDmaSources1[@as(usize, v.link_dma_graphics_index().* >> 1)];
    v.dma_source_addr_0().* = v.dma_source_addr_3().* +% 0x200;
    v.dma_source_addr_4().* = kLinkDmaSources2[@as(usize, v.link_dma_graphics_index().* >> 1)];
    v.dma_source_addr_1().* = v.dma_source_addr_4().* +% 0x200;
    v.dma_source_addr_5().* = kLinkDmaSources3[@as(usize, v.link_dma_var1().* >> 1)];
    v.dma_source_addr_2().* = kLinkDmaSources3[@as(usize, v.link_dma_var2().* >> 1)];

    v.dma_source_addr_6().* = kLinkDmaSources4[@as(usize, v.link_dma_var3().* >> 1)];
    v.dma_source_addr_11().* = v.dma_source_addr_6().* +% 0x180;

    if (v.link_dma_var4().* == 0x8b) {
        v.dma_source_addr_7().* = 0xe099;
    } else {
        v.dma_source_addr_7().* = kLinkDmaSources5[@as(usize, v.link_dma_var4().* >> 1)];
    }
    v.dma_source_addr_12().* = v.dma_source_addr_7().* +% 0xc0;

    const j: usize = (@as(usize, v.link_dma_var5().*) & 0xf8) >> 3;
    v.dma_source_addr_8().* = kLinkDmaSources6[@as(usize, v.link_dma_var5().*)];
    v.dma_source_addr_13().* = v.dma_source_addr_8().* +% kLinkDmaSources7[j];
    v.dma_source_addr_10().* = kLinkDmaSources8[v.pushedblocks_some_index().* & 3];
    v.dma_source_addr_15().* = v.dma_source_addr_10().* +% 0x100;

    v.bg_tile_animation_countdown().* -%= 1;
    if (v.bg_tile_animation_countdown().* == 0) {
        const overlay_lo = t.byte(v.overlay_index()).*;
        v.bg_tile_animation_countdown().* = if (overlay_lo == 0xb5 or overlay_lo == 0xbc) 0x17 else 9;

        var tt: t.uint16 = v.word_7EC00F().* +% 0x400;
        if (tt == 0xc00)
            tt = 0;
        v.word_7EC00F().* = tt;
        v.animated_tile_data_src().* = 0xa680 +% tt;
    }

    v.word_7EC013().* -%= 1;
    if (v.word_7EC013().* == 0) {
        var tt: i32 = @as(i32, v.word_7EC015().*) + 2;
        if (tt == 12)
            tt = 0;
        v.word_7EC015().* = @as(t.uint16, @intCast(tt));
        const idx: usize = @as(usize, @as(t.uint16, @intCast(tt))) >> 1;
        v.word_7EC013().* = kLinkDmaCtrs0[idx];
        v.dma_source_addr_9().* = kLinkDmaSources9[idx] +% 0xb280;
        v.dma_source_addr_14().* = v.dma_source_addr_9().* +% 0x60;
    }

    v.dma_source_addr_16().* = @as(t.uint16, @truncate(0xB940 + @as(u32, v.dma_var6().*) * 2));
    v.dma_source_addr_18().* = v.dma_source_addr_16().* +% 0x200;

    v.dma_source_addr_17().* = @as(t.uint16, @truncate(0xB940 + @as(u32, v.dma_var7().*) * 2));
    v.dma_source_addr_19().* = v.dma_source_addr_17().* +% 0x200;

    v.dma_source_addr_20().* = @as(t.uint16, @truncate(0xB540 + @as(u32, v.flag_travel_bird().*) * 2));
    v.dma_source_addr_21().* = v.dma_source_addr_20().* +% 0x200;
}

pub export fn Sound_LoadIntroSongBank() void { // 808901
    LoadSongBank(g_asset_ptrs[0].?);
}

pub export fn LoadOverworldSongs() void { // 808913
    LoadSongBank(g_asset_ptrs[0].?);
}

pub export fn LoadDungeonSongs() void { // 808925
    LoadSongBank(g_asset_ptrs[1].?);
}

pub export fn LoadCreditsSongs() void { // 808931
    LoadSongBank(g_asset_ptrs[2].?);
}
pub export fn Dungeon_LightTorch() void { // 81f3ec
    if (v.byte_7E0333().* & 0xf0 != 0xc0) {
        v.byte_7E0333().* = 0;
        return;
    }
    const r8: t.uint8 = if (@as(t.uint8, @truncate(v.dungeon_room_index().*)) == 0) 0x80 else 0xc0;

    const i: usize = @as(usize, v.byte_7E0333().* & 0xf) + (@as(usize, v.dung_index_of_torches_start().*) >> 1);
    const opos: usize = @intCast(v.dung_object_pos_in_objdata()[i]);
    if (v.dung_object_tilemap_pos()[i] & 0x8000 != 0)
        return;
    v.dung_object_tilemap_pos()[i] |= 0x8000;
    if (r8 == 0)
        v.dung_torch_data()[opos] = v.dung_object_tilemap_pos()[i];

    const x: t.uint16 = v.dung_object_tilemap_pos()[i] & 0x3fff;
    RoomDraw_AdjustTorchLightingChange(x, 0xeca, x);

    v.sound_effect_1().* = 42 | CalculateSfxPan_Arbitrary(@as(t.uint8, @truncate((x & 0x7f) * 2)));

    v.nmi_copy_packets_flag().* = 1;
    if (v.dung_want_lights_out().* != 0) {
        const old_lit_torches = v.dung_num_lit_torches().*;
        v.dung_num_lit_torches().* = old_lit_torches + 1;
        if (old_lit_torches < 3) {
            v.TS_copy().* = 0;
            v.overworld_fixed_color_plusminus().* = kLitTorchesColorPlus[@as(usize, v.dung_num_lit_torches().*)];
            v.submodule_index().* = 10;
            v.subsubmodule_index().* = 0;
        }
    }

    v.dung_torch_timers()[v.byte_7E0333().* & 0xf] = r8;
    v.byte_7E0333().* = 0;
}

pub export fn RoomDraw_AdjustTorchLightingChange(x_in: t.uint16, y: t.uint16, r8: t.uint16) void { // 81f746
    const ptr = SrcPtr(y);
    const x: usize = @as(usize, @intCast(x_in)) >> 1;
    v.overworld_tileattr()[x + 0] = ptr[0];
    v.overworld_tileattr()[x + 64] = ptr[1];
    v.overworld_tileattr()[x + 1] = ptr[2];
    v.overworld_tileattr()[x + 65] = ptr[3];
    _ = Dungeon_PrepOverlayDma_nextPrep(0, r8);
}

pub export fn Dungeon_PrepOverlayDma_nextPrep(dst: c_int, r8: t.uint16) c_int { // 81f764
    const r6: t.uint16 = 0x880 + @as(t.uint16, @intFromBool((r8 & 0x3f) >= 0x3a));
    return Dungeon_PrepOverlayDma_watergate(dst, r8, r6, 4);
}

pub export fn Dungeon_PrepOverlayDma_watergate(dst: c_int, r8: t.uint16, r6: t.uint16, loops: c_int) c_int { // 81f77c
    var d: usize = @intCast(dst);
    var r8v: t.uint16 = r8;
    for (0..@intCast(loops)) |_| {
        const x: usize = @as(usize, r8v) >> 1;
        const vram = v.vram_upload_tile_buf();
        const attr = v.overworld_tileattr();
        vram[d + 0] = @as(t.uint16, @truncate(
            (r8v & 0x40) << 4 | (r8v & 0x303f) >> 1 | (r8v & 0xf80) >> 2,
        ));
        vram[d + 1] = r6;
        vram[d + 2] = attr[x + 0];
        if (r6 & 1 == 0) {
            vram[d + 3] = attr[x + 1];
            vram[d + 4] = attr[x + 2];
            vram[d + 5] = attr[x + 3];
            r8v += 128;
        } else {
            vram[d + 3] = attr[x + 64];
            vram[d + 4] = attr[x + 128];
            vram[d + 5] = attr[x + 192];
            r8v += 2;
        }
        d += 6;
    }
    v.vram_upload_tile_buf()[d] = 0xffff;
    return @intCast(d);
}

pub export fn Module05_LoadFile() void { // 828136
    EnableForceBlank();
    v.overworld_map_state().* = 0;
    v.dung_unk6().* = 0;
    v.byte_7E02D4().* = 0;
    v.byte_7E02D7().* = 0;
    v.tagalong_var5().* = 0;
    v.byte_7E0379().* = 0;
    v.byte_7E03FD().* = 0;
    EraseTileMaps_normal();
    LoadDefaultGraphics();
    Sprite_LoadGraphicsProperties();
    Init_LoadDefaultTileAttr();
    DecompressSwordGraphics();
    DecompressShieldGraphics();
    Link_Initialize();
    LoadFollowerGraphics();
    v.sprite_gfx_subset_0().* = 70;
    v.sprite_gfx_subset_1().* = 70;
    v.sprite_gfx_subset_2().* = 70;
    v.sprite_gfx_subset_3().* = 70;
    v.word_7E02CD().* = 0x200;
    v.virq_trigger().* = 48;
    if (v.savegame_is_darkworld().* != 0) {
        if (v.player_is_indoors().* != 0) {
            LoadDungeonRoomRebuildHUD();
            return;
        }
        Hud_SearchForEquippedItem();
        Hud_Rebuild();
        Hud_UpdateEquippedItem();
        v.death_var5().* = 0;
        v.dungeon_room_index().* = 32;
        v.main_module_index().* = 8;
        v.submodule_index().* = 0;
        v.subsubmodule_index().* = 0;
        v.death_var4().* = 0;
    } else {
        if (v.mosaic_level().* != 0 or
            (v.death_var5().* != 0 and v.death_var4().* == 0) or
            v.sram_progress_indicator().* < 2 or
            v.which_starting_point().* == 5)
        {
            LoadDungeonRoomRebuildHUD();
            return;
        }
        v.dialogue_message_index().* = if (v.link_item_mirror().* == 2) 0x185 else 0x184;
        Main_ShowTextMessage();
        Dungeon_LoadPalettes();
        v.INIDISP_copy().* = 15;
        v.TM_copy().* = 4;
        v.TS_copy().* = 0;
        v.main_module_index().* = 27;
    }
}

pub export fn Module13_BossVictory_Pendant() void { // 829c4a
    kModule_BossVictory[@intCast(v.submodule_index().*)]();
    Sprite_Main();
    LinkOam_Main();
}

fn BossVictory_Heal() callconv(.c) void { // 829c59
    if (Hud_RefillMagicPower() == false)
        v.overworld_map_state().* += 1;
    if (Hud_RefillHealth() == false)
        v.overworld_map_state().* += 1;
    if (v.overworld_map_state().* == 0) {
        v.button_mask_b_y().* &= ~@as(t.uint8, 0x40);
        Dungeon_ResetTorchBackgroundAndPlayerInner();
        v.link_direction_facing().* = 2;
        v.link_direction_last().* = 2 << 1;
        v.flag_update_hud_in_nmi().* += 1;
        v.submodule_index().* += 1;
        v.subsubmodule_index().* = 16;
        v.flag_is_link_immobilized().* += 1;
    }
    v.overworld_map_state().* = 0;
    Hud_RefillLogic();
}

fn Dungeon_StartVictorySpin() callconv(.c) void { // 829c93
    v.subsubmodule_index().* -%= 1;
    if (v.subsubmodule_index().* != 0)
        return;
    v.flag_is_link_immobilized().* = 0;
    v.link_direction_facing().* = 2;
    Link_AnimateVictorySpin();
    _ = Ancilla_TerminateSelectInteractives(0);
    AncillaAdd_VictorySpin();
    v.submodule_index().* += 1;
}

fn Dungeon_RunVictorySpin() callconv(.c) void { // 829cad
    Link_Main();
    if (v.link_player_handler_state().* != 0)
        return;
    if ((v.link_sword_type().* +% 1) & 0xfe != 0)
        v.sound_effect_1().* = 0x2C;
    v.link_force_hold_sword_up().* = 1;
    v.subsubmodule_index().* = 32;
    v.submodule_index().* += 1;
}

fn Dungeon_CloseVictorySpin() callconv(.c) void { // 829cd1
    v.subsubmodule_index().* -%= 1;
    if (v.subsubmodule_index().* != 0)
        return;
    v.submodule_index().* += 1;
    v.link_y_vel().* = 0;
    v.link_x_vel().* = 0;
    v.overworld_fixed_color_plusminus().* = 0;
}

pub export fn Module15_MirrorWarpFromAga() void { // 829cfc
    kModule_KillAgahnim[@intCast(v.submodule_index().*)]();
    if (v.submodule_index().* < 2 or v.submodule_index().* >= 5) {
        Sprite_Main();
        LinkOam_Main();
    }
}

pub export fn Module16_BossVictory_Crystal() void { // 829e8a
    switch (v.submodule_index().*) {
        0 => BossVictory_Heal(),
        1 => Dungeon_StartVictorySpin(),
        2 => Dungeon_RunVictorySpin(),
        3 => Dungeon_CloseVictorySpin(),
        4 => Module16_04_FadeAndEnd(),
        else => {},
    }
    Sprite_Main();
    LinkOam_Main();
}

fn Module16_04_FadeAndEnd() callconv(.c) void { // 829e9a
    v.INIDISP_copy().* -%= 1;
    if (v.INIDISP_copy().* != 0)
        return;
    v.bg1_x_offset().* = 0;
    v.bg1_y_offset().* = 0;
    v.link_y_vel().* = 0;
    v.flag_is_link_immobilized().* = 0;
    Palette_RevertTranslucencySwap();
    v.link_player_handler_state().* = kPlayerState_Ground;
    v.link_receiveitem_index().* = 0;
    v.link_pose_for_item().* = 0;
    v.link_disable_sprite_damage().* = 0;
    v.main_module_index().* = v.saved_module_for_menu().*;
    v.submodule_index().* = 0;
    v.subsubmodule_index().* = 0;
    OpenSpotlight_Next2();
}
pub export fn TriforceRoom_LinkApproachTriforce() void { // 87f49c
    const y: t.uint8 = @as(t.uint8, @truncate(v.link_y_coord().*));
    if (y < 152) {
        v.link_animation_steps().* = 0;
        v.link_direction().* = 0;
        v.link_direction_last().* = 0;
        v.link_delay_timer_spin_attack().* -%= 1;
        if (v.link_delay_timer_spin_attack().* == 0) {
            v.link_pose_for_item().* = 2;
            v.subsubmodule_index().* += 1;
        }
    } else {
        if (y < 169)
            v.link_speed_setting().* = 0x14;
        v.link_direction().* = 8;
        v.link_direction_last().* = 8;
        v.link_direction_facing().* = 0;
        v.link_delay_timer_spin_attack().* = 64;
    }
}

// misc.h's FindInByteArray dropped its redundant size param — Zig slices
// carry their own length (house pattern, cf. player_oam.zig).
fn FindInByteArray(data: []const t.uint8, lookfor: t.uint8) i32 {
    var i: usize = data.len;
    while (i != 0) {
        i -= 1;
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}

pub export fn AncillaAdd_ItemReceipt(ain: t.uint8, yin: t.uint8, chest_pos: c_int) void { // 8985e8
    const ancilla: c_int = Ancilla_AddAncilla(ain, yin);
    if (ancilla < 0)
        return;
    const a: usize = @intCast(ancilla);

    v.flag_is_link_immobilized().* = if (v.link_receiveitem_index().* == 0x20) 2 else 1;

    const j: i32 = @as(i32, v.link_receiveitem_index().*);
    if (j == 0) {
        v.g_ram[kMemoryLocationToGiveItemTo[4]] = @as(t.uint8, @bitCast(kValueToGiveItemTo[0]));
    }

    const vv: t.uint8 = @as(t.uint8, @bitCast(kValueToGiveItemTo[@intCast(j)]));
    const p: *align(1) t.uint8 = &v.g_ram[kMemoryLocationToGiveItemTo[@intCast(j)]];
    if (t.sign8(vv) == 0)
        p.* = vv;

    if (j == 0x1f) {
        v.link_is_bunny().* = 0;
    } else if (j == 0x4b or j == 0x1e) {
        v.link_ability_flags().* |= if (j == 0x4b) @as(t.uint8, 4) else 2;
    }

    if (j == 0x1b or j == 0x1c) {
        Palette_UpdateGlovesColor();
    } else if (j == 0x37 or j == 0x38 or j == 0x39) {
        // C: (t = 4, j == 0x37) || (t = 1, j == 0x38) || (t = 2, j == 0x39)
        const tt: t.uint8 = if (j == 0x37) 4 else if (j == 0x38) 1 else 2;
        p.* |= tt;
        if (p.* & 7 == 7)
            v.savegame_map_icons_indicator().* = 4;
        v.overworld_map_state().* += 1;
    } else if (j == 0x22) {
        if (p.* == 0)
            p.* = 1;
    } else if (j == 0x25 or j == 0x32 or j == 0x33) {
        // C: WORD(*p) |= 0x8000 >> (BYTE(cur_palace_index_x2) >> 1);
        t.word(p).* |= kUpperBitmasks[@as(usize, t.byte(v.cur_palace_index_x2()).*) >> 1];
    } else if (j == 0x3e) {
        if (v.link_state_bits().* & 0x80 != 0)
            v.link_picking_throw_state().* = 2;
    } else if (j == 0x20) {
        v.overworld_map_state().* += 1;
        var i: usize = 4;
        while (true) {
            const at = v.ancilla_type()[i];
            if (at == 7 or at == 0x2c) {
                v.ancilla_type()[i] = 0;
                v.link_state_bits().* = 0;
                v.link_picking_throw_state().* = 0;
            }
            if (i == 0)
                break;
            i -= 1;
        }
        if (v.link_cape_mode().* != 0) {
            v.link_bunny_transform_timer().* = 32;
            v.link_disable_sprite_damage().* = 0;
            v.link_cape_mode().* = 0;
            AncillaAdd_CapePoof(0x23, 4);
            v.sound_effect_1().* = 0x15 | Link_CalculateSfxPan();
        }
    } else if (j == 0x29) {
        if (v.link_item_mushroom().* != 2) {
            p.* = 1;
            Hud_RefreshIcon();
        }
    } else if (j == 0x24 or (v.item_receipt_method().* != 2 and (j == 0x27 or j == 0x28 or j == 0x31))) {
        // C comma-operator: on this branch t is 1 for 0x24, 2 for 0x27
        // (leftover from the earlier evaluated (t=4)|(t=1)|(t=2) chain),
        // 3 for 0x28, 10 for 0x31.
        const amt: t.uint8 = if (j == 0x24) 1 else if (j == 0x27) 2 else if (j == 0x28) 3 else 10;
        p.* +%= amt;
        if (p.* > 99)
            p.* = 99;
        Hud_RefreshIcon();
    } else if (j == 0x17) {
        p.* = (p.* + 1) & 3;
        v.sound_effect_2().* = 0x2d | Link_CalculateSfxPan();
    } else if (j == 1) {
        Overworld_SetSongList();
    } else {
        ItemReceipt_GiveBottledItem(@as(t.uint8, @intCast(j)));
    }

    var gfx: t.uint8 = kReceiveItemGfx[@intCast(j)];
    if (gfx == 0xff) {
        gfx = 0;
    } else if (gfx == 0x20 or gfx == 0x2d or gfx == 0x2e) {
        DecompressShieldGraphics();
        Palette_Load_Shield();
    }
    DecodeAnimatedSpriteTile_variable(gfx);

    if ((gfx == 6 or gfx == 0x18) and j != 0) {
        DecompressSwordGraphics();
        Palette_Load_Sword();
    }

    v.ancilla_item_to_link()[a] = @as(t.uint8, @intCast(j));
    v.ancilla_arr1()[a] = 0;

    if (j == 1 and v.item_receipt_method().* != 2) {
        v.ancilla_timer()[a] = 160;
        v.submodule_index().* = 43;
        t.byte(v.palette_filter_countdown()).* = 0;
        AncillaAdd_MSCutscene(0x35, 4);
        v.ancilla_arr3()[a] = 2;
    } else {
        v.ancilla_arr3()[a] = 9;
    }
    v.ancilla_arr4()[a] = 5;
    v.ancilla_step()[a] = v.item_receipt_method().*;

    v.ancilla_aux_timer()[a] = if (j == 0x20 or j == 0x37 or j == 0x38 or j == 0x39)
        0x68
    else if (j == 0x26)
        0x2
    else if (v.item_receipt_method().* != 0)
        0x38
    else
        0x60;

    var x: i32 = undefined;
    var y: i32 = undefined;
    if (v.item_receipt_method().* == 1) {
        y = (chest_pos & 0x1f80) >> 4;
        x = (chest_pos & 0x7e) << 2;
        y += v.dung_loade_bgoffs_v_copy().* & ~@as(t.uint16, 0xff);
        x += v.dung_loade_bgoffs_h_copy().* & ~@as(t.uint16, 0xff);
        y += kReceiveItem_Tab2[@intCast(j)];
        x += @as(i32, kReceiveItem_Tab3[@intCast(j)]);
    } else {
        if (v.ancilla_step()[a] == 0 and j == 1) {
            v.sound_effect_1().* = Link_CalculateSfxPan() | 0x2c;
        } else if (j == 0x20 or j == 0x37 or j == 0x38 or j == 0x39) {
            v.music_control().* = Link_CalculateSfxPan() | 0x13;
        } else if (j != 0x3e and j != 0x17) {
            v.sound_effect_2().* = Link_CalculateSfxPan() | 0xf;
        }
        const method: i32 = if (v.item_receipt_method().* == 3) 0 else @as(i32, v.item_receipt_method().*);
        x = if (method != 0)
            @as(i32, kReceiveItem_Tab3[@intCast(j)])
        else if (kReceiveItem_Tab1[@intCast(j)] == 0)
            10
        else if (j == 0x20)
            0
        else
            6;
        x += @as(i32, v.link_x_coord().*);
        y = if (method != 0) kReceiveItem_Tab2[@intCast(j)] else -14;
        y += @as(i32, v.link_y_coord().*);
        if (method == 2)
            y -= 8;
    }
    // C truncates the int x/y to uint16 on the Ancilla_SetXY call.
    const xb: u32 = @as(u32, @bitCast(x));
    const yb: u32 = @as(u32, @bitCast(y));
    Ancilla_SetXY(ancilla, @as(t.uint16, @truncate(xb)), @as(t.uint16, @truncate(yb)));
}

pub export fn ItemReceipt_GiveBottledItem(item: t.uint8) void { // 89893e
    const kBottleList: [7]t.uint8 = .{ 0x16, 0x2b, 0x2c, 0x2d, 0x3d, 0x3c, 0x48 };
    const kPotionList: [5]t.uint8 = .{ 0x2e, 0x2f, 0x30, 0xff, 0xe };
    var j: i32 = undefined;
    if (FindInByteArray(&kBottleList, item) >= 0) {
        j = FindInByteArray(&kBottleList, item);
        for (0..4) |i| {
            if (v.link_bottle_info()[i] < 2) {
                v.link_bottle_info()[i] = @as(t.uint8, @intCast(j + 2));
                return;
            }
        }
    }
    if (FindInByteArray(&kPotionList, item) >= 0) {
        j = FindInByteArray(&kPotionList, item);
        for (0..4) |i| {
            if (v.link_bottle_info()[i] == 2) {
                v.link_bottle_info()[i] = @as(t.uint8, @intCast(j + 3));
                return;
            }
        }
    }
}
pub export fn Module17_SaveAndQuit() void { // 89f79f
    // C switch fall-through from case 0 into case 1.
    if (v.submodule_index().* == 0)
        v.submodule_index().* += 1;
    if (v.submodule_index().* == 1) {
        v.INIDISP_copy().* -%= 1;
        if (v.INIDISP_copy().* == 0) {
            v.MOSAIC_copy().* = 15;
            v.subsubmodule_index().* = 1;
            Death_Func15(false);
        }
    }
    Sprite_Main();
    LinkOam_Main();
}

pub export fn WallMaster_SendPlayerToLastEntrance() void { // 8bffa8
    SaveDungeonKeys();
    Dungeon_FlagRoomData_Quadrants();
    Sprite_ResetAll();
    v.death_var4().* = 0;
    v.main_module_index().* = 17;
    v.submodule_index().* = 0;
    v.nmi_load_bg_from_vram().* = 0;
    ResetSomeThingsAfterDeath(17);
}

pub export fn GetRandomNumber() t.uint8 { // 8dba71
    const t0: t.uint8 = v.byte_7E0FA1().* +% v.frame_counter().*;
    const tv: t.uint8 = if (t0 & 1 != 0) t0 >> 1 else (t0 >> 1) ^ 0xb8;
    v.byte_7E0FA1().* = tv;
    return tv;
}

pub export fn Link_CalculateSfxPan() t.uint8 { // 8dbb67
    return CalculateSfxPan(v.link_x_coord().*);
}

pub export fn SpriteSfx_QueueSfx1WithPan(k: c_int, a: t.uint8) void { // 8dbb6e
    if (v.sound_effect_ambient().* == 0)
        v.sound_effect_ambient().* = a | Sprite_CalculateSfxPan(k);
}

pub export fn SpriteSfx_QueueSfx2WithPan(k: c_int, a: t.uint8) void { // 8dbb7c
    if (v.sound_effect_1().* == 0)
        v.sound_effect_1().* = a | Sprite_CalculateSfxPan(k);
}

pub export fn SpriteSfx_QueueSfx3WithPan(k: c_int, a: t.uint8) void { // 8dbb8a
    if (v.sound_effect_2().* == 0)
        v.sound_effect_2().* = a | Sprite_CalculateSfxPan(k);
}

pub export fn Sprite_CalculateSfxPan(k: c_int) t.uint8 { // 8dbba1
    return CalculateSfxPan(Sprite_GetX(k));
}

pub export fn CalculateSfxPan(x_in: t.uint16) t.uint8 { // 8dbba8
    const kPanTable: [3]t.uint8 = .{ 0, 0x80, 0x40 };
    var o: usize = 0;
    const x: t.uint16 = x_in -% (v.BG2HOFS_copy2().* +% 80);
    if (x >= 80)
        o = 1 + @as(usize, @intFromBool(@as(t.int16, @bitCast(x)) >= 0));
    return kPanTable[o];
}

pub export fn CalculateSfxPan_Arbitrary(a: t.uint8) t.uint8 { // 8dbbd0
    const kTorchPans: [8]t.uint8 = .{ 0x80, 0x80, 0x80, 0, 0, 0x40, 0x40, 0x40 };
    // C: kTorchPans[((a - BG2HOFS_copy2) >> 5) & 7]; a is u8 promoted to int
    // (signed difference, arithmetic shift); only the low 3 bits matter.
    const d: i32 = @as(i32, a) - @as(i32, v.BG2HOFS_copy2().*);
    return kTorchPans[@as(usize, (@as(t.uint32, @bitCast(d)) >> 5) & 7)];
}

pub export fn Init_LoadDefaultTileAttr() void { // 8e97d9
    std.mem.copyForwards(u8, v.attributes_for_tile()[0..0x140], kDungeon_DefaultAttr[0..0x140]);
    std.mem.copyForwards(u8, v.attributes_for_tile()[0x1c0..(0x1c0 + 64)], kDungeon_DefaultAttr[0x140..(0x140 + 64)]);
}

pub export fn Main_ShowTextMessage() void { // 8ffdaa
    if (v.main_module_index().* != 14) {
        v.byte_7E0223().* = 0;
        v.messaging_module().* = 0;
        v.submodule_index().* = 2;
        v.saved_module_for_menu().* = v.main_module_index().*;
        v.main_module_index().* = 14;
    }
}

pub export fn HandleItemTileAction_Overworld(x: t.uint16, y: t.uint16) t.uint8 { // 9bbd7a
    if (v.player_is_indoors().* != 0)
        return HandleItemTileAction_Dungeon(x, y);
    return @as(t.uint8, @truncate(Overworld_ToolAndTileInteraction(x, y)));
}
