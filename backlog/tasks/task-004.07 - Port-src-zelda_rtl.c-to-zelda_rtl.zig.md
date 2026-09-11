---
id: TASK-004.07
title: Port src/zelda_rtl.c to zelda_rtl.zig
status: Done
assignee: []
created_date: '2026-08-02 04:20'
updated_date: '2026-08-18 14:30'
labels: []
dependencies:
  - TASK-004.06
parent_task_id: TASK-004
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/zelda_rtl.c (the runtime core / frame loop glue: g_ram definition and ownership, ZeldaRunFrame/ZeldaRunFrameInternal, ZeldaInitialize, ZeldaDrawPpuFrame, the g_zenv global env) to idiomatic Zig. This file currently owns `uint8 g_ram[131072]` — moving its definition to Zig means updating variables.zig's `extern var g_ram` to instead be the actual Zig-owned definition, and re-declaring it `extern` from the remaining C files. Handle this transition carefully since every g_ram accessor across the whole codebase depends on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 zelda_rtl.c is removed from the C build and zelda_rtl.zig is compiled instead
- [x] #2 g_ram is defined once (in Zig) and all C files reference it via extern with no behavior change
- [x] #3 The frame loop (ZeldaRunFrame, ZeldaRunFrameInternal, NMI dispatch) behaves identically
- [x] #4 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Port src/zelda_rtl.c (889 lines) to src/zelda_rtl.zig, idiomatic Zig, C-ABI-preserving.

Key finding (supersedes the description's mechanism): variables.h:1522 ALREADY declares
`extern uint8 g_ram[131072]` for every C TU, so moving the definition to Zig needs zero
C-side edits. Also, five test files (poly_test/tile_detect_test/variables_test + the two
difftests) each `export var g_ram` in their own binary, so defining g_ram in variables.zig
would create duplicate-symbol collisions there. Therefore g_ram (and the other globals
this file owns) is DEFINED in zelda_rtl.zig; variables.zig keeps its `extern var g_ram`
/ `extern var g_zenv` as-is (only its header comment is corrected). AC #2 ("defined once
in Zig, C references via extern") is satisfied.

Approach:
1. Defined globals in zelda_rtl.zig (pub export var): g_ram: [0x20000]u8 = zeroed;
   g_zenv: v.ZeldaEnv (layout-proven twin, all fields initially null/zero);
   g_wanted_zelda_features: t.uint32 = 0 (features.h extern); frame_ctr_dbg: c_int = 0
   (zelda_rtl.h extern).
2. Exported consts currently defined here (misc.zig already externs the first two
   "from zelda_rtl.c"): kUpperBitmasks [16]u16, kLitTorchesColorPlus [4]u8,
   kDungeonCrystalPendantBit [13]u8, kGetBestActionToPerformOnTile_x/y [4]i8.
3. Exact C-ABI exports (callconv(.c), zelda_rtl.h signatures unchanged):
   zelda_ppu_write(_word), HdmaSetup, ZeldaInitialize, ZeldaReset(bool),
   ZeldaDrawPpuFrame, ZeldaRunFrameInternal, ZeldaRunFrame(int)->bool,
   ByteArray_AppendVl, saveFunc/loadFunc, ReadFromFile, StateRecorder_Init/
   RecordCmd/Record/RecordPatchByte/Load/Save/ClearKeyLog/ReadNextReplayState/
   StopReplay, StateRecoderMultiPatch_Init/Commit/Patch, ZeldaSetLanguage,
   SaveLoadSlot, PatchCommand, ZeldaReadSram/ZeldaWriteSram, ZeldaSetupEmuCallbacks.
   Statics stay non-exported: SimpleHdma_*, ConfigurePpuSideSpace, ZeldaRunGameLoop,
   ZeldaRunPolyLoop, ZeldaInitializationCode, Startup_InitializeMemory, ClearOamBuffer,
   IncrementCrystalCountdown, EmuSynchronizeWholeState/EmuSyncMemoryRegion,
   Load/SaveSnesState, InternalSaveLoad. The _DEBUG-only InputStateReadFromFile is
   dropped (not compiled by the C build either). state_recorder + g_emu_memory_ptr/
   g_emu_runframe/g_emu_syncall become module-level statics (no external C references).
4. StateRecorder/LoadFuncState/StateRecoderMultiPatch/SimpleHdma mirrored as extern
   struct twins (byte-identical layout; no external C callers found, but keep the shape).
5. extern fns — ported Zig modules: Module_MainRouting, NMI_PrepareSprites,
   Sound_LoadIntroSongBank (misc.zig); Interrupt_NMI (nmi.zig); Poly_RunFrame
   (poly.zig); FindIndexInMemblk + ByteArray_Resize/Destroy/AppendData/AppendByte
   (util.zig, ByteArray mirrored as local extern struct {data, size, capacity});
   dma_init/reset/write/saveload/startDma + Dma/DmaChannel twins (snes/dma.zig);
   ppu_init (NO arg in ppu.zig)/reset/write/runLine/saveload/PpuBeginDrawing/
   PpuSetExtraSideSpace/PpuSetMode7PerspectiveCorrection + Ppu twin (snes/ppu.zig);
   SpcPlayer_Create/Initialize (spc_player.zig); dsp_saveload (snes/dsp.zig).
   g_zenv.ppu/dma/player are ?*anyopaque in v.ZeldaEnv.
   Struct-field reach-ins (refinement of the typed-twin idea): ppu.zig's Ppu and
   spc_player.zig's SpcPlayer are too large to mirror safely, so — per the
   established precedent (PpuCopyCgramFromBuffer in ppu.zig, documented in
   nmi.zig's header) — tiny opaque-pointer accessors are ADDED to the owning
   ported modules: ppu.zig gets PpuGetCurrentMode(ppu:*anyopaque) u8,
   PpuGetVram(ppu:*anyopaque) [*]u16, PpuGetExtraSideSpace(ppu:*anyopaque) u8;
   spc_player.zig gets SpcPlayer_GetRam(p:*anyopaque) [*]u8 and
   SpcPlayer_GetDsp(p:*anyopaque) ?*anyopaque. Dma/DmaChannel ARE mirrored as
   local extern struct twins in zelda_rtl.zig (small; mirrors snes/dma.h the
   way the C file did). All function externs use opaque pointer params.
   extern fns — remaining C:
   ZeldaApuLock/ZeldaApuUnlock (main.c); ZeldaIsMusicPlaying, ZeldaPushApuState,
   ZeldaRestoreMusicAfterLoad_Locked, ZeldaSaveMusicStateToRam_Locked (audio.c);
   FindInAssetArray (assets, kDialogue/kDialogueFont/kDialogueMap = indices 94/95/96);
   Die (types.h); libc via raw externs in the util.zig style: fopen/fread/fwrite/
   fclose/rename/printf/fprintf/sprintf/strlen/memcmp/calloc/free.
6. Macro emulations: WORD(x) = little-endian u16 of a u16 lvalue;
   hdma_table_dynamic = @ptrCast(&v.g_ram[0x1DBA0]); kPpuExtraLeftRight = 96;
   kPpuRenderFlags_4x4Mode7 = 2 / Height240 = 4; kRam_APUI00=0x648 /
   CrystalRotateCounter=0x649 / BugsFixed=0x64a / Features0=0x64c;
   kBugFix_PolyRenderer = kBugFix_Latest = 1; kSaveLoad_Save/Load/Replay = 0/1/2;
   PPU reg addrs from snes/snes_regs.h (INIDISP 0x2100, BG3HOFS 0x2111, BG3VOFS
   0x2112, STAT78 0x213f, NMITIMEN 0x4200, MDMAEN 0x420b, HDMAEN 0x420c,
   DMAP6/BBAD6/A1T6L/A1T6H/A1B6/DAS60 = 0x4360..0x4367, DMAP7..DAS70 = 0x4370..0x4377);
   kMapMode_Zooms1/2 extern const [240]u16 from attract.c; IntMax as inline if;
   zelda_snes_dummy_write is a C no-op inline — calls dropped.
7. Semantics care: align(1) @ptrCast through v.*() accessors for every odd-offset
   lvalue; wrapping u8 arithmetic for rep_count/frames VL-encoding (match C int
   promotion then truncate on store); assert(0) switch-defaults -> std.debug.assert
   (release no-op, matching C release behavior); memcpy/memset via std.mem/std.mem
   (overlap-safe); exact InternalSaveLoad component order/lengths preserved
   (savestate format); kReferenceSaves 13-name table preserved byte-for-byte.
8. build.zig: remove "src/zelda_rtl.c" from the sources list; add
   exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "zelda_rtl"))
   after the "misc" entry. zelda_rtl.c itself is NOT deleted (reference/difftest
   precedent); taskfile.yml, taskfiles/, zelda3.bak untouched.

Verify (same gauntlet as 004.01-004.06): task zig:build; task zig:parity (zero
"Memory compare failed" with zelda3.sfc); task zig:parity-replay (saves/ref/
Chapter*.sav clean); zig build test; zig fmt --check + task zig:ast-check; classic
`task build` still compiles clean.

Verification results (2026-08-18, all on zig 0.16.0):
- zig build clean; zig build test + zig build difftest exit 0; zig ast-check clean;
  zig fmt clean.
- RAM-compare oracle: zero "Memory compare failed" lines (10s run with zelda3.sfc).
- parity-replay: all 13 saves/ref/Chapter*.sav replays clean under headless sway
  (verified genuine: no wtype connection failures, game log present).
- Classic root `task build` (C sources incl. zelda_rtl.c + the seven earlier
  compile-zig-* modules) still compiles and links clean; taskfile.yml,
  taskfiles/ and zelda3.bak untouched.

Implementation notes that deviate from the plan text above:
- assert(0) switch-default paths became @panic (the C build compiles with
  asserts active — no -DNDEBUG — so the abort behavior is preserved, not
  relaxed).
- C implicit narrowing (u32 reg adr -> u8 ppu_write/dma_write values, u16 -> u8
  stores, u32 -> u8 crystal-countdown wrap) is emulated with @truncate; the
  first draft used checked @intCast, which SIGTRAP'd on zelda_ppu_write(0x2118)
  at startup (ReleaseFast keeps @intCast range checks).
- Zig 0.16 removed std.mem.readIntLittle/zeroBytes and copyForwards now takes
  slices: word_at is an explicit LE byte-pair, zeroing is @memset, and
  loadFunc builds a dst slice before copyForwards. (Feeding an inline
  @ptrCast of the wrong pointee to copyForwards SEGVs the 0.16.0 compiler
  instead of reporting a type error — avoid that shape.)
- C do-while loops (not in the Zig language) were restructured to
  while (true) + break with identical iteration semantics.
- PPU/DSP/SPC-player access from this module uses the opaque-accessor
  precedent (small PpuGetCurrentMode/PpuGetVram/PpuGetExtraSideSpace accessors
  added to snes/ppu.zig; SpcPlayer_GetRam/GetDsp to src/spc_player.zig)
  rather than @importing those modules.
- Environment: in sandboxed agent sessions the default zig global cache
  (~/.cache/zig) is read-only — build via
  ZIG_GLOBAL_CACHE_DIR=<workspace>/.zig-cache-global (or --global-cache-dir),
  and parity-replay needs XDG_RUNTIME_DIR pointed at a writable workspace dir
  (the stale system-wide wayland socket is not deletable there).
<!-- SECTION:PLAN:END -->
