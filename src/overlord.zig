// Port of src/overlord.c: the "overlord" sprite-spawner logic (per-room
// scripted spawn/trigger objects — cannons, trap doors, falling tiles,
// wallmaster/blob/wizzrobe/zoro factories, the Armos Knights coordinator,
// etc). Every exported function keeps its exact C-ABI name and signature so
// the remaining .c callers link unchanged. All game state lives in g_ram
// (variables.zig accessors), byte-for-byte where the original 65816 code and
// the RAM-compare oracle expect it.

const t = @import("types.zig");
const v = @import("variables.zig");

// sprite.h: SpriteSpawnInfo, mirrored field-for-field (extern struct) since
// sprite.c (the struct's home) is not yet ported.
const SpriteSpawnInfo = extern struct {
    r0_x: t.uint16,
    r2_y: t.uint16,
    r4_z: t.uint8,
    r5_overlord_x: t.uint16,
    r7_overlord_y: t.uint16,
};

extern const kSinusLookupTable: [256]t.uint16; // sprite_main.c

extern fn GetRandomNumber() t.uint8; // misc.c
extern fn SpriteSfx_QueueSfx2WithPan(k: c_int, a: t.uint8) void; // misc.c
extern fn SpriteSfx_QueueSfx3WithPan(k: c_int, a: t.uint8) void; // misc.c
extern fn CalculateSfxPan_Arbitrary(a: t.uint8) t.uint8; // misc.c

extern fn Sprite_SetX(k: c_int, x: t.uint16) void; // sprite.c
extern fn Sprite_SetY(k: c_int, y: t.uint16) void; // sprite.c
extern fn GetTileAttribute(floor: t.uint8, x: *t.uint16, y: t.uint16) t.uint8; // sprite.c
extern fn Sprite_SpawnDynamically(k: c_int, what: t.uint8, info: *SpriteSpawnInfo) c_int; // sprite.c
extern fn Sprite_SpawnDynamicallyEx(k: c_int, what: t.uint8, info: *SpriteSpawnInfo, j: c_int) c_int; // sprite.c

extern fn GarnishAlloc() c_int; // sprite_main.c
extern fn Sprite_TransmuteToBomb(k: c_int) void; // sprite_main.c

pub export fn Overlord_GetX(k: c_int) t.uint16 { // 89b6e0 (approx, not annotated in C)
    const i: usize = @intCast(k);
    return @as(t.uint16, v.overlord_x_lo()[i]) | (@as(t.uint16, v.overlord_x_hi()[i]) << 8);
}

pub export fn Overlord_GetY(k: c_int) t.uint16 {
    const i: usize = @intCast(k);
    return @as(t.uint16, v.overlord_y_lo()[i]) | (@as(t.uint16, v.overlord_y_hi()[i]) << 8);
}

const HandlerFuncK = fn (k: c_int) callconv(.c) void;

const kOverlordFuncs = [26]*const HandlerFuncK{
    &Overlord01_PositionTarget,
    &Overlord02_FullRoomCannons,
    &Overlord03_VerticalCannon,
    &Overlord_StalfosFactory,
    &Overlord05_FallingStalfos,
    &Overlord06_BadSwitchSnake,
    &Overlord07_MovingFloor,
    &Overlord08_BlobSpawner,
    &Overlord09_WallmasterSpawner,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord14_TileRoom,
    &Overlord15_WizzrobeSpawner,
    &Overlord16_ZoroSpawner,
    &Overlord17_PotTrap,
    &Overlord18_InvisibleStalfos,
    &Overlord19_ArmosCoordinator_bounce,
    &Overlord06_BadSwitchSnake,
};

fn ArmosMult(a: t.uint16, b: t.uint8) t.uint8 {
    if (a >= 256) return b;
    const p: u32 = @as(u32, a) *% @as(u32, b);
    return @truncate((p >> 8) +% ((p >> 7) & 1));
}

fn ArmosSin(a: t.uint16, b: t.uint8) t.int8 {
    const tt = ArmosMult(kSinusLookupTable[a & 0xff], b);
    return if ((a & 0x100) != 0) 0 -% @as(t.int8, @bitCast(tt)) else @bitCast(tt);
}

pub export fn Overlord_StalfosFactory(k: c_int) void { // unused
    _ = k;
    @panic("Overlord_StalfosFactory: unused");
}

pub export fn Overlord_SetX(k: c_int, val: t.uint16) void {
    const i: usize = @intCast(k);
    v.overlord_x_lo()[i] = @truncate(val);
    v.overlord_x_hi()[i] = @truncate(val >> 8);
}

pub export fn Overlord_SetY(k: c_int, val: t.uint16) void {
    const i: usize = @intCast(k);
    v.overlord_y_lo()[i] = @truncate(val);
    v.overlord_y_hi()[i] = @truncate(val >> 8);
}

pub export fn Overlord_SpawnBoulder() void { // 89b714
    if (v.player_is_indoors().* != 0 or v.byte_7E0FFD().* == 0 or
        (v.submodule_index().* | v.flag_unk1().*) != 0 or blk: {
            v.byte_7E0FFE().* +%= 1;
            break :blk (v.byte_7E0FFE().* & 63) != 0;
        }) return;

    if (t.sign8(@truncate(((v.BG2VOFS_copy2().* >> 8) -% (v.sprcoll_y_base().* >> 8)) -% 2)) != 0)
        return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(0, 0xc2, &info);
    if (j >= 0) {
        Sprite_SetX(j, v.BG2HOFS_copy2().* +% (@as(t.uint16, GetRandomNumber()) & 127) +% 64);
        Sprite_SetY(j, v.BG2VOFS_copy2().* -% 0x30);
        const jj: usize = @intCast(j);
        v.sprite_floor()[jj] = 0;
        v.sprite_D()[jj] = 0;
        v.sprite_z()[jj] = 0;
    }
}

pub export fn Overlord_Main() void { // 89b773
    Overlord_ExecuteAll();
    Overlord_SpawnBoulder();
}

pub export fn Overlord_ExecuteAll() void { // 89b77e
    if ((v.submodule_index().* | v.flag_unk1().*) != 0) return;
    var i: c_int = 7;
    while (i >= 0) : (i -= 1) {
        if (v.overlord_type()[@intCast(i)] != 0)
            Overlord_ExecuteSingle(i);
    }
}

pub export fn Overlord_ExecuteSingle(k: c_int) void { // 89b793
    const j = v.overlord_type()[@intCast(k)];
    Overlord_CheckIfActive(k);
    kOverlordFuncs[j - 1](k);
}

pub export fn Overlord19_ArmosCoordinator_bounce(k: c_int) void { // 89b7dc
    const kArmosCoordinator_BackWallX = [6]t.uint8{ 49, 77, 105, 131, 159, 187 };

    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] != 0)
        v.overlord_gen2()[ki] -%= 1;
    switch (v.overlord_gen1()[ki]) {
        0 => { // wait for knight activation
            if (v.sprite_A()[0] != 0) {
                v.overlord_x_lo()[ki] = 120;
                v.overlord_floor()[ki] = 255;
                v.overlord_x_lo()[2] = 64;
                v.overlord_x_lo()[0] = 192;
                v.overlord_x_lo()[1] = 1;
                ArmosCoordinator_RotateKnights(k);
            }
        },
        1 => { // wait knight under coercion
            if (ArmosCoordinator_CheckKnights()) {
                v.overlord_gen1()[ki] +%= 1;
                v.overlord_gen2()[ki] = 0xff;
            }
        },
        2, 4 => { // timed rotate then transition
            ArmosCoordinator_RotateKnights(k);
        },
        3 => { // radial contraction
            v.overlord_x_lo()[2] -%= 1;
            if (v.overlord_x_lo()[2] == 32) {
                v.overlord_gen1()[ki] +%= 1;
                v.overlord_gen2()[ki] = 64;
            }
            ArmosCoordinator_Rotate(k);
        },
        5 => { // radial dilation
            v.overlord_x_lo()[2] +%= 1;
            if (v.overlord_x_lo()[2] == 64) {
                v.overlord_gen1()[ki] +%= 1;
                v.overlord_gen2()[ki] = 64;
            }
            ArmosCoordinator_Rotate(k);
        },
        6 => { // order knights to back wall
            if (v.overlord_gen2()[ki] != 0) return;
            ArmosCoordinator_DisableCoercion(k);
            var j: c_int = 5;
            while (j >= 0) : (j -= 1) {
                const jj: usize = @intCast(j);
                v.overlord_x_hi()[jj] = kArmosCoordinator_BackWallX[jj];
                v.overlord_gen2()[jj] = 48;
            }
            v.overlord_gen1()[ki] +%= 1;
            v.overlord_gen2()[ki] = 255;
        },
        7 => { // cascade knights to front wall
            if (v.overlord_gen2()[ki] != 0) return;
            var j: c_int = 5;
            while (j >= 0) : (j -= 1) {
                const jj: usize = @intCast(j);
                v.overlord_gen2()[jj] +%= 1;
                if (v.overlord_gen2()[jj] == 192) {
                    v.overlord_gen1()[ki] = 1;
                    v.overlord_floor()[ki] = 0 -% v.overlord_floor()[ki];
                    ArmosCoordinator_DisableCoercion(k);
                    ArmosCoordinator_Rotate(k);
                    return;
                }
            }
        },
        else => {},
    }
}

pub export fn Overlord18_InvisibleStalfos(k: c_int) void { // 89b7f5
    const kRedStalfosTrap_X = [4]t.int8{ 0, 0, -48, 48 };
    const kRedStalfosTrap_Y = [4]t.int8{ -40, 56, 8, 8 };
    const kRedStalfosTrap_Delay = [4]t.uint8{ 0x30, 0x50, 0x70, 0x90 };

    const ki: usize = @intCast(k);
    const x: t.uint16 = @as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8);
    const y: t.uint16 = @as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8);
    if ((x -% v.link_x_coord().* +% 24) >= 48 or (y -% v.link_y_coord().* +% 24) >= 48)
        return;
    v.overlord_type()[ki] = 0;
    v.tmp_counter().* = 3;
    while (true) {
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0xa7, &info, 12);
        if (j < 0) return;
        const jj: usize = @intCast(j);
        const ci: usize = @intCast(v.tmp_counter().*);
        Sprite_SetX(j, v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(i16, kRedStalfosTrap_X[ci]))));
        Sprite_SetY(j, v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(i16, kRedStalfosTrap_Y[ci]))));
        v.sprite_delay_main()[jj] = kRedStalfosTrap_Delay[ci];
        v.sprite_floor()[jj] = v.overlord_floor()[ki];
        v.sprite_E()[jj] = 1;
        v.sprite_flags2()[jj] = 3;
        v.sprite_D()[jj] = 2;
        v.tmp_counter().* -%= 1;
        if (t.sign8(v.tmp_counter().*) != 0) break;
    }
}

pub export fn Overlord17_PotTrap(k: c_int) void { // 89b884
    const ki: usize = @intCast(k);
    const x: t.uint16 = @as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8);
    const y: t.uint16 = @as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8);
    if ((x -% v.link_x_coord().* +% 32) < 64 and (y -% v.link_y_coord().* +% 32) < 64) {
        v.overlord_type()[ki] = 0;
        v.byte_7E0B9E().* +%= 1;
    }
}

pub export fn Overlord16_ZoroSpawner(k: c_int) void { // 89b8d1
    const kOverlordZoroFactory_X = [8]t.int8{ -4, -2, 0, 2, 4, 6, 8, 12 };
    const ki: usize = @intCast(k);
    v.overlord_gen2()[ki] -%= 1;
    var x = Overlord_GetX(k) +% 8;
    const y = Overlord_GetY(k) +% 8;
    if (GetTileAttribute(v.overlord_floor()[ki], &x, y) != 0x82) return;
    if (v.overlord_gen2()[ki] >= 0x18 or (v.overlord_gen2()[ki] & 3) != 0) return;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x9c, &info, 12);
    if (j >= 0) {
        const jj: usize = @intCast(j);
        const idx: usize = @intCast(GetRandomNumber() & 7);
        Sprite_SetX(j, info.r5_overlord_x +% @as(t.uint16, @bitCast(@as(i16, kOverlordZoroFactory_X[idx]))) +% 8);
        v.sprite_y_lo()[jj] = @truncate(info.r7_overlord_y +% 8);
        v.sprite_y_hi()[jj] = @truncate(info.r7_overlord_y >> 8);
        v.sprite_floor()[jj] = v.overlord_floor()[ki];
        v.sprite_flags4()[jj] = 1;
        v.sprite_E()[jj] = 1;
        v.sprite_ignore_projectile()[jj] = 1;
        v.sprite_y_vel()[jj] = 16;
        v.sprite_flags2()[jj] = 32;
        v.sprite_oam_flags()[jj] = 13;
        v.sprite_subtype2()[jj] = GetRandomNumber();
        v.sprite_delay_main()[jj] = 48;
        v.sprite_bump_damage()[jj] = 3;
    }
}

pub export fn Overlord15_WizzrobeSpawner(k: c_int) void { // 89b986
    const kOverlordWizzrobe_X = [4]t.int8{ 48, -48, 0, 0 };
    const kOverlordWizzrobe_Y = [4]t.int8{ 16, 16, 64, -32 };
    const kOverlordWizzrobe_Delay = [4]t.uint8{ 0, 16, 32, 48 };
    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] != 128) {
        if ((v.frame_counter().* & 1) != 0)
            v.overlord_gen2()[ki] -%= 1;
        return;
    }
    v.overlord_gen2()[ki] = 127;
    var i: c_int = 3;
    while (i >= 0) : (i -= 1) {
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0x9b, &info, 12);
        if (j >= 0) {
            const jj: usize = @intCast(j);
            const ii: usize = @intCast(i);
            Sprite_SetX(j, v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(i16, kOverlordWizzrobe_X[ii]))));
            Sprite_SetY(j, v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(i16, kOverlordWizzrobe_Y[ii]))));
            v.sprite_delay_main()[jj] = kOverlordWizzrobe_Delay[ii];
            v.sprite_floor()[jj] = v.overlord_floor()[ki];
            v.sprite_B()[jj] = 1;
        }
    }
    v.tmp_counter().* = 0xff;
}

pub export fn Overlord14_TileRoom(k: c_int) void { // 89b9e8
    const ki: usize = @intCast(k);
    const x = (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8)) -% v.BG2HOFS_copy2().*;
    const y = (@as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8)) -% v.BG2VOFS_copy2().*;
    if ((x & 0xff00) != 0 or (y & 0xff00) != 0) return;
    v.overlord_gen2()[ki] -%= 1;
    if (v.overlord_gen2()[ki] != 0x80) return;
    const j = TileRoom_SpawnTile(k);
    if (j < 0) {
        v.overlord_gen2()[ki] = 0x81;
        return;
    }
    v.overlord_gen1()[ki] +%= 1;
    if (v.overlord_gen1()[ki] != 22)
        v.overlord_gen2()[ki] = 0xE0
    else
        v.overlord_type()[ki] = 0;
}

pub export fn TileRoom_SpawnTile(k: c_int) c_int { // 89ba56
    const kSpawnFlyingTile_X = [22]t.uint8{
        0x70, 0x80, 0x60, 0x90, 0x90, 0x60, 0x70, 0x80, 0x80, 0x70, 0x50, 0xa0, 0xa0, 0x50, 0x50, 0xa0,
        0xa0, 0x50, 0x70, 0x80, 0x80, 0x70,
    };
    const kSpawnFlyingTile_Y = [22]t.uint8{
        0x80, 0x80, 0x70, 0x90, 0x70, 0x90, 0x60, 0xa0, 0x60, 0xa0, 0x60, 0xb0, 0x60, 0xb0, 0x80, 0x90,
        0x80, 0x90, 0x70, 0x90, 0x70, 0x90,
    };
    const ki: usize = @intCast(k);
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x94, &info);
    if (j < 0) return j;
    const jj: usize = @intCast(j);
    v.sprite_E()[jj] = 1;
    const i: usize = @intCast(v.overlord_gen1()[ki]);
    v.sprite_x_lo()[jj] = kSpawnFlyingTile_X[i];
    v.sprite_y_lo()[jj] = kSpawnFlyingTile_Y[i] -% 8;
    v.sprite_y_hi()[jj] = v.overlord_y_hi()[ki];
    v.sprite_x_hi()[jj] = v.overlord_x_hi()[ki];
    v.sprite_floor()[jj] = v.overlord_floor()[ki];
    v.sprite_health()[jj] = 4;
    v.sprite_flags5()[jj] = 0;
    v.sprite_health()[jj] = 0;
    v.sprite_defl_bits()[jj] = 8;
    v.sprite_flags2()[jj] = 4;
    v.sprite_oam_flags()[jj] = 1;
    v.sprite_bump_damage()[jj] = 4;
    return j;
}

pub export fn Overlord10_PirogusuSpawner_left(k: c_int) void { // 89baac
    const kOverlordPirogusu_A = [4]t.uint8{ 2, 3, 0, 1 };

    const ki: usize = @intCast(k);
    v.tmp_counter().* = v.overlord_type()[ki] -% 16;
    if (v.overlord_gen2()[ki] != 128) {
        v.overlord_gen2()[ki] -%= 1;
        return;
    }
    v.overlord_gen2()[ki] = (GetRandomNumber() & 31) +% 96;
    var n: c_int = 0;
    var i: c_int = 0;
    while (i != 16) : (i += 1) {
        const ii: usize = @intCast(i);
        if (v.sprite_state()[ii] != 0 and v.sprite_type()[ii] == 0x10)
            n += 1;
    }
    if (n >= 5) return;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x94, &info, 12);
    if (j >= 0) {
        const jj: usize = @intCast(j);
        const ci: usize = @intCast(v.tmp_counter().*);
        Sprite_SetX(j, info.r5_overlord_x);
        Sprite_SetY(j, info.r7_overlord_y);
        v.sprite_floor()[jj] = v.overlord_floor()[ki];
        v.sprite_delay_main()[jj] = 32;
        v.sprite_D()[jj] = v.tmp_counter().*;
        v.sprite_A()[jj] = kOverlordPirogusu_A[ci];
    }
}

pub export fn Overlord0A_FallingSquare(k: c_int) void { // 89bbb2
    const kCrumbleTilePathData = [108 + 1]t.uint8{
        2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3,
        3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0xff,
    };
    const kCrumbleTilePathOffs = [7]t.uint8{ 0, 25, 66, 77, 87, 98, 108 };
    const kCrumbleTilePath_X = [4]t.int8{ 16, -16, 0, 0 };
    const kCrumbleTilePath_Y = [4]t.int8{ 0, 0, 16, -16 };

    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] != 0) {
        if (v.overlord_gen3()[ki] != 0) {
            v.overlord_gen2()[ki] -%= 1;
            return;
        }
        const x = Overlord_GetX(k) -% v.BG2HOFS_copy2().*;
        const y = Overlord_GetY(k) -% v.BG2VOFS_copy2().*;
        if (!((x & 0xff00) != 0 or (y & 0xff00) != 0))
            v.overlord_gen3()[ki] +%= 1;
        return;
    }

    v.overlord_gen2()[ki] = 16;
    SpawnFallingTile(k);
    const j: usize = @intCast(v.overlord_type()[ki] -% 10);
    const i: usize = @intCast(v.overlord_gen1()[ki]);
    v.overlord_gen1()[ki] +%= 1;
    if (i == kCrumbleTilePathOffs[j + 1] -% kCrumbleTilePathOffs[j]) {
        v.overlord_type()[ki] = 0;
    }
    const tIdx: usize = kCrumbleTilePathOffs[j] + i;
    const tt = kCrumbleTilePathData[tIdx];
    if (tt == 0xff) {
        Overlord_SetX(k, Overlord_GetX(k) +% 0xc1a);
        Overlord_SetY(k, Overlord_GetY(k) +% 0xbb66);
    } else {
        const ti: usize = @intCast(tt);
        Overlord_SetX(k, Overlord_GetX(k) +% @as(t.uint16, @bitCast(@as(i16, kCrumbleTilePath_X[ti]))));
        Overlord_SetY(k, Overlord_GetY(k) +% @as(t.uint16, @bitCast(@as(i16, kCrumbleTilePath_Y[ti]))));
    }
}

pub export fn SpawnFallingTile(k: c_int) void { // 89bc31
    const ki: usize = @intCast(k);
    const j = GarnishAlloc();
    if (j >= 0) {
        const jj: usize = @intCast(j);
        v.garnish_type()[jj] = 3;
        v.garnish_x_hi()[jj] = v.overlord_x_hi()[ki];
        v.garnish_x_lo()[jj] = v.overlord_x_lo()[ki];
        v.sound_effect_1().* = CalculateSfxPan_Arbitrary(v.garnish_x_lo()[jj]) | 0x1f;
        const y = Overlord_GetY(k) +% 16;
        v.garnish_y_lo()[jj] = @truncate(y);
        v.garnish_y_hi()[jj] = @truncate(y >> 8);
        v.garnish_countdown()[jj] = 31;
        v.garnish_active().* = 31;
    }
}

pub export fn Overlord09_WallmasterSpawner(k: c_int) void { // 89bc7b
    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] != 128) {
        if ((v.frame_counter().* & 1) == 0)
            v.overlord_gen2()[ki] -%= 1;
        return;
    }
    v.overlord_gen2()[ki] = 127;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x90, &info, 12);
    if (j < 0) return;
    const jj: usize = @intCast(j);
    Sprite_SetX(j, v.link_x_coord().*);
    Sprite_SetY(j, v.link_y_coord().*);
    v.sprite_z()[jj] = 208;
    SpriteSfx_QueueSfx2WithPan(j, 0x20);
    v.sprite_floor()[jj] = v.link_is_on_lower_level().*;
}

pub export fn Overlord08_BlobSpawner(k: c_int) void { // 89bcc3
    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] != 0) {
        v.overlord_gen2()[ki] -%= 1;
        return;
    }
    v.overlord_gen2()[ki] = 0xa0;
    var n: c_int = 0;
    var i: c_int = 0;
    while (i != 16) : (i += 1) {
        const ii: usize = @intCast(i);
        if (v.sprite_state()[ii] != 0 and v.sprite_type()[ii] == 0x8f)
            n += 1;
    }
    if (n >= 5) return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x8f, &info, 12);
    if (j >= 0) {
        const kOverlordZol_X = [4]t.int8{ 0, 0, -48, 48 };
        const kOverlordZol_Y = [4]t.int8{ -40, 56, 8, 8 };
        const jj: usize = @intCast(j);
        const idx: usize = @intCast(v.link_direction_facing().* >> 1);
        Sprite_SetX(j, v.link_x_coord().* +% @as(t.uint16, @bitCast(@as(i16, kOverlordZol_X[idx]))));
        Sprite_SetY(j, v.link_y_coord().* +% @as(t.uint16, @bitCast(@as(i16, kOverlordZol_Y[idx]))));
        v.sprite_z()[jj] = 192;
        v.sprite_floor()[jj] = v.link_is_on_lower_level().*;
        v.sprite_ai_state()[jj] = 2;
        v.sprite_E()[jj] = 2;
        v.sprite_C()[jj] = 2;
        v.sprite_head_dir()[jj] = (GetRandomNumber() & 31) | 16;
    }
}

pub export fn Overlord07_MovingFloor(k: c_int) void { // 89bd3f
    const ki: usize = @intCast(k);
    if (v.sprite_state()[0] == 4) {
        v.overlord_type()[ki] = 0;
        t.byte(v.dung_floor_move_flags()).* = 1;
        return;
    }
    if (v.overlord_gen1()[ki] == 0) {
        v.overlord_gen2()[ki] +%= 1;
        if (v.overlord_gen2()[ki] == 32) {
            v.overlord_gen2()[ki] = 0;
            t.byte(v.dung_floor_move_flags()).* = (GetRandomNumber() & (if (v.overlord_x_lo()[ki] != 0) @as(t.uint8, 3) else 1)) *% 2;
            v.overlord_gen2()[ki] = (GetRandomNumber() & 127) +% 128;
            v.overlord_gen1()[ki] +%= 1;
        } else {
            t.byte(v.dung_floor_move_flags()).* = 1;
        }
    } else {
        v.overlord_gen2()[ki] -%= 1;
        if (v.overlord_gen2()[ki] == 0)
            v.overlord_gen1()[ki] = 0;
    }
}

pub export fn Sprite_Overlord_PlayFallingSfx(k: c_int) void { // 89bdfd
    SpriteSfx_QueueSfx2WithPan(k, 0x20);
}

pub export fn Overlord05_FallingStalfos(k: c_int) void { // 89be0f
    const kStalfosTrap_Trigger = [8]t.uint8{ 255, 224, 192, 160, 128, 96, 64, 32 };

    const ki: usize = @intCast(k);
    const x = (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8)) -% v.BG2HOFS_copy2().*;
    const y = (@as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8)) -% v.BG2VOFS_copy2().*;
    if ((x & 0xff00) != 0 or (y & 0xff00) != 0) return;
    if (v.overlord_gen1()[ki] == 0) {
        if (v.byte_7E0B9E().* != 0)
            v.overlord_gen1()[ki] +%= 1;
        return;
    }
    const trigger = v.overlord_gen1()[ki];
    v.overlord_gen1()[ki] +%= 1;
    if (trigger == kStalfosTrap_Trigger[ki]) {
        v.overlord_type()[ki] = 0;
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0x85, &info, 12);
        if (j < 0) return;
        const jj: usize = @intCast(j);
        Sprite_SetX(j, info.r5_overlord_x);
        Sprite_SetY(j, info.r7_overlord_y);
        v.sprite_z()[jj] = 224;
        v.sprite_floor()[jj] = v.overlord_floor()[ki];
        v.sprite_D()[jj] = 0; // zelda bug: unitialized
        Sprite_Overlord_PlayFallingSfx(j);
    }
}

pub export fn Overlord06_BadSwitchSnake(k: c_int) void { // 89be75
    const kSnakeTrapOverlord_Tab1 = [8]t.uint8{ 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90 };

    const ki: usize = @intCast(k);
    const a = v.overlord_gen1()[ki];
    if (a == 0) {
        if (v.activate_bomb_trap_overlord().* != 0)
            v.overlord_gen1()[ki] = 1;
        return;
    }
    v.overlord_gen1()[ki] = a +% 1;

    if (a != kSnakeTrapOverlord_Tab1[ki]) return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x6e, &info);
    if (j < 0) return;
    const jj: usize = @intCast(j);
    Sprite_SetX(j, info.r5_overlord_x);
    Sprite_SetY(j, info.r7_overlord_y);

    v.sprite_z()[jj] = 192;
    v.sprite_E()[jj] = 192;

    v.sprite_flags3()[jj] |= 0x10;
    v.sprite_floor()[jj] = v.overlord_floor()[ki];
    SpriteSfx_QueueSfx2WithPan(j, 0x20);
    const kind = v.overlord_type()[ki];
    v.overlord_type()[ki] = 0;
    if (kind == 26) {
        v.sprite_type()[jj] = 74;
        Sprite_TransmuteToBomb(j);
        v.sprite_delay_aux1()[jj] = 112;
    }
}

pub export fn Overlord02_FullRoomCannons(k: c_int) void { // 89bf09
    const kAllDirectionMetalBallFactory_Idx = [16]t.uint8{ 2, 2, 2, 2, 1, 1, 1, 1, 3, 3, 3, 3, 0, 0, 0, 0 };
    const kAllDirectionMetalBallFactory_X = [16]t.uint8{ 64, 96, 144, 176, 240, 240, 240, 240, 176, 144, 96, 64, 0, 0, 0, 0 };
    const kAllDirectionMetalBallFactory_Y = [16]t.uint8{ 16, 16, 16, 16, 64, 96, 160, 192, 240, 240, 240, 240, 192, 160, 96, 64 };
    const ki: usize = @intCast(k);
    const x = (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8)) -% v.BG2HOFS_copy2().*;
    const y = (@as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8)) -% v.BG2VOFS_copy2().*;
    if (((x | y) & 0xff00) != 0 or (v.frame_counter().* & 0xf) != 0) return;

    v.byte_7E0FB6().* = 0;
    const j: usize = @intCast(GetRandomNumber() & 15);
    v.tmp_counter().* = kAllDirectionMetalBallFactory_Idx[j];
    v.overlord_x_lo()[ki] = kAllDirectionMetalBallFactory_X[j];
    v.overlord_x_hi()[ki] = v.byte_7E0FB0().*;
    v.overlord_y_lo()[ki] = kAllDirectionMetalBallFactory_Y[j];
    v.overlord_y_hi()[ki] = v.byte_7E0FB1().* +% 1;
    Overlord_SpawnCannonBall(k, 0);
}

pub export fn Overlord03_VerticalCannon(k: c_int) void { // 89bf5b
    const ki: usize = @intCast(k);
    const x = (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8)) -% v.BG2HOFS_copy2().*;
    if ((x & 0xff00) != 0) {
        v.overlord_gen2()[ki] = 255;
        return;
    }
    if ((v.frame_counter().* & 1) == 0 and v.overlord_gen2()[ki] != 0)
        v.overlord_gen2()[ki] -%= 1;
    v.tmp_counter().* = 2;
    v.byte_7E0FB6().* = 0;
    v.overlord_gen1()[ki] -%= 1;
    if (t.sign8(v.overlord_gen1()[ki]) == 0) return;
    v.overlord_gen1()[ki] = 56;
    var xd: c_int = undefined;
    if (v.overlord_gen2()[ki] == 0) {
        v.overlord_gen2()[ki] = 160;
        v.byte_7E0FB6().* = 160;
        xd = 8;
    } else {
        xd = (@as(c_int, GetRandomNumber()) & 2) * 8;
    }
    Overlord_SpawnCannonBall(k, xd);
}

pub export fn Overlord_SpawnCannonBall(k: c_int, xd: c_int) void { // 89bfaf
    const kOverlordSpawnBall_Xvel = [4]t.int8{ 24, -24, 0, 0 };
    const kOverlordSpawnBall_Yvel = [4]t.int8{ 0, 0, 24, -24 };
    const ki: usize = @intCast(k);
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x50, &info);
    if (j < 0) return;
    const jj: usize = @intCast(j);

    Sprite_SetX(j, info.r5_overlord_x +% @as(t.uint16, @bitCast(@as(i16, @truncate(xd)))));
    Sprite_SetY(j, info.r7_overlord_y -% 1);

    const ci: usize = @intCast(v.tmp_counter().*);
    v.sprite_x_vel()[jj] = @bitCast(kOverlordSpawnBall_Xvel[ci]);
    v.sprite_y_vel()[jj] = @bitCast(kOverlordSpawnBall_Yvel[ci]);
    v.sprite_floor()[jj] = v.overlord_floor()[ki];
    if (v.byte_7E0FB6().* != 0) {
        v.sprite_ai_state()[jj] = v.byte_7E0FB6().*;
        v.sprite_y_lo()[jj] = v.sprite_y_lo()[jj] +% 8;
        v.sprite_flags2()[jj] = 3;
        v.sprite_flags4()[jj] = 9;
    }
    v.sprite_delay_aux2()[jj] = 64;
    SpriteSfx_QueueSfx3WithPan(j, 0x7);
}

pub export fn Overlord01_PositionTarget(k: c_int) void { // 89c01e
    v.byte_7E0FDE().* = @truncate(@as(c_uint, @intCast(k)));
}

pub export fn Overlord_CheckIfActive(k: c_int) void { // 89c08d
    const kOverlordInRangeOffs = [2]t.int16{ 0x130, -0x40 };
    if (v.player_is_indoors().* != 0) return;
    const ki: usize = @intCast(k);
    const j: usize = @intCast(v.frame_counter().* & 1);
    const x: t.uint16 = v.BG2HOFS_copy2().* +% @as(t.uint16, @bitCast(kOverlordInRangeOffs[j])) -%
        (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8));
    const y: t.uint16 = v.BG2VOFS_copy2().* +% @as(t.uint16, @bitCast(kOverlordInRangeOffs[j])) -%
        (@as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8));
    if (@as(usize, x >> 15) != j or @as(usize, y >> 15) != j) {
        v.overlord_type()[ki] = 0;
        const blk = v.overlord_offset_sprite_pos()[ki];
        if (blk != 0xffff) {
            const loadedmask: t.uint8 = @as(t.uint8, 0x80) >> @intCast(blk & 7);
            v.overworld_sprite_was_loaded()[blk >> 3] &= ~loadedmask;
        }
    }
}

pub export fn ArmosCoordinator_RotateKnights(k: c_int) void { // 9deccc
    const ki: usize = @intCast(k);
    if (v.overlord_gen2()[ki] == 0)
        v.overlord_gen1()[ki] +%= 1;
    ArmosCoordinator_Rotate(k);
}

pub export fn ArmosCoordinator_Rotate(k: c_int) void { // 9decd4
    const kArmosCoordinator_Tab0 = [6]t.uint16{ 0, 425, 340, 255, 170, 85 };

    const ki: usize = @intCast(k);
    t.word(&v.overlord_x_lo()[0]).* +%= @as(t.uint16, @bitCast(@as(i16, @as(t.int8, @bitCast(v.overlord_floor()[ki])))));
    var i: usize = 0;
    while (i != 6) : (i += 1) {
        const t0: t.uint16 = t.word(&v.overlord_x_lo()[0]).* +% kArmosCoordinator_Tab0[i];
        const size = v.overlord_x_lo()[2];
        const tx: t.uint16 = (@as(t.uint16, v.overlord_x_lo()[ki]) | (@as(t.uint16, v.overlord_x_hi()[ki]) << 8)) +%
            @as(t.uint16, @bitCast(@as(i16, ArmosSin(t0, size))));
        v.overlord_x_hi()[i] = @truncate(tx);
        v.overlord_y_hi()[i] = @truncate(tx >> 8);
        const ty: t.uint16 = (@as(t.uint16, v.overlord_y_lo()[ki]) | (@as(t.uint16, v.overlord_y_hi()[ki]) << 8)) +%
            @as(t.uint16, @bitCast(@as(i16, ArmosSin(t0 +% 0x80, size))));
        v.overlord_gen2()[i] = @truncate(ty);
        v.overlord_floor()[i] = @truncate(ty >> 8);
    }
    v.tmp_counter().* = 6;
}

pub export fn ArmosCoordinator_CheckKnights() bool { // 9dedb8
    var j: c_int = 5;
    while (j >= 0) : (j -= 1) {
        const jj: usize = @intCast(j);
        if (v.sprite_state()[jj] != 0 and v.sprite_ai_state()[jj] == 0)
            return false;
    }
    return true;
}

pub export fn ArmosCoordinator_DisableCoercion(k: c_int) void { // 9dedcb
    _ = k;
    var j: c_int = 5;
    while (j >= 0) : (j -= 1) {
        v.sprite_ai_state()[@intCast(j)] = 0;
    }
}
