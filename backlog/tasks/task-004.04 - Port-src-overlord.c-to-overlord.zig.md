---
id: TASK-004.04
title: Port src/overlord.c to overlord.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:20'
updated_date: '2026-08-14 21:18'
labels: []
dependencies:
  - TASK-004.03
parent_task_id: TASK-004
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/overlord.c ('overlord' sprite spawner logic) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 overlord.c is removed from the C build and overlord.zig is compiled instead
- [x] #2 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
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
Following the established TASK-004.02/.03 pattern (load_gfx.zig, nmi.zig):

1. Create src/overlord.zig porting all 653 lines of src/overlord.c 1:1, preserving exact
   symbol names/signatures for C-ABI compat:
   - `int k` params -> `k: c_int`; array indexing into variables.zig accessors
     (`v.overlord_type()[@intCast(k)]` etc, all overlord_* fields already exist in
     variables.zig from TASK-002.02).
   - Static-only helpers (ArmosMult, ArmosSin) stay private fns, not exported.
   - kOverlordFuncs dispatch table -> `const HandlerFuncK = fn (k: c_int) callconv(.c) void;`
     array of `&Overlord_XX_...`, mirroring nmi.zig's kNmiSubroutines pattern.
   - SpriteSpawnInfo (src/sprite.h) needed as a field-for-field `extern struct` (sprite.c is
     not yet ported) — mirrors the extern struct pattern in spc_player.zig/poly.zig.
   - extern fn declarations for not-yet-ported dependencies: Sprite_SpawnDynamically,
     Sprite_SpawnDynamicallyEx, Sprite_SetX, Sprite_SetY, GetRandomNumber,
     SpriteSfx_QueueSfx2WithPan, SpriteSfx_QueueSfx3WithPan, GetTileAttribute,
     CalculateSfxPan_Arbitrary, GarnishAlloc, Sprite_TransmuteToBomb, and
     `extern const kSinusLookupTable: [256]t.uint16` (defined in sprite_main.c).
   - WORD()/BYTE() punning macros (e.g. `WORD(overlord_x_lo[0])`) -> `t.word(&v.overlord_x_lo()[0]).*`.
   - `assert(0)` in the unused Overlord_StalfosFactory -> `@panic(...)`, matching the
     spc_player.zig Not_Implemented precedent.
   - All uint8/uint16 arithmetic that can wrap (counters, subtraction like
     `--overlord_gen2[k]`, `x - link_x_coord`) must use wrapping operators (`+%`/`-%`/`*%`)
     since the Zig build defaults to ReleaseFast where overflow is UB, not the C
     implicit-wraparound behavior the original code relies on.
2. Wire into build.zig: add `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "overlord"));`
   and remove `"src/overlord.c"` from the `sources` array (build.zig:496).
3. No Tier-A/Tier-B test wiring — following the load_gfx.zig/nmi.zig precedent, modules this
   entangled with live global sprite/overlord state and unported C dependencies (sprite.c)
   don't get unit/difftest files; there is no update needed to unit_test_files/diff_test_files.
4. Verify: `task zig:build`, `task zig:parity` (zero RAM-compare mismatches against zelda3.sfc),
   `task zig:parity-replay` (all 13 reference saves clean), and confirm the legacy `task build`
   (C-only) still compiles and runs unaffected.
5. Commit on branch task-004.04-overlord-zig, merge to master (matching prior port tasks'
   merge-commit history), mark task Done with final summary.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported src/overlord.c (653 lines, 26-entry kOverlordFuncs dispatch table + Armos Knights coordinator state machine) to src/overlord.zig (749 lines), following the nmi.zig/load_gfx.zig conventions established in TASK-004.02/.03. All C-ABI symbol names/signatures preserved unchanged; overlord.c removed from build.zig's C sources array and replaced with addPortedModule(b, target, optimize, "overlord").

During a systematic line-by-line re-verification pass against the original C (self-initiated QA, not from compiler errors), found and fixed two semantic divergences before running parity checks:
1. ArmosCoordinator_RotateKnights indexed overlord_gen2()[0] instead of overlord_gen2()[k] (copy-paste slip).
2. Overlord16_ZoroSpawner computed sprite_y_hi from (r7_overlord_y + 8) >> 8 instead of the original's r7_overlord_y >> 8 (the +8 only applies to sprite_y_lo; the original relies on the dropped carry not propagating into the hi byte).

A third bug survived the manual review and was only caught by task zig:parity-replay: in Overlord19_ArmosCoordinator_bounce's `case 2, 4` branch, the port called ArmosCoordinator_Rotate(k) directly instead of ArmosCoordinator_RotateKnights(k), silently skipping the `if (!overlord_gen2[k]) overlord_gen1[k]++` state transition. This desynced the Armos Knights coordinator's state machine (stuck at gen1=2 instead of advancing to 3) starting at frame 217 of the "Chapter 13 - After Ganon's Tower" reference-save replay, causing a permanent one-byte RAM-compare mismatch at overlord_gen1[7] (0xB2F) for the rest of the run. Root-caused via temporary instrumentation (a std.debug.print trace inside Overlord19_ArmosCoordinator_bounce gated on frame_counter, since the game's own RAM-compare dump's a/b argument order — "mine" is b->ram, "theirs" is a->ram, easy to mis-swap when improvising an ad-hoc dump) and fixed by calling ArmosCoordinator_RotateKnights(k) as the original does. All temporary debug instrumentation was removed before finalizing.

Verification evidence:
- `zig build`: clean, zero errors, produces zig-out/bin/zelda3.
- `task zig:parity` (zelda3.sfc, 10s run): "PARITY OK: zero RAM-compare mismatches".
- `task zig:parity-replay` (all 13 saves/ref/Chapter*.sav replayed via headless sway+wtype+grim): "PARITY-REPLAY OK: zero RAM-compare mismatches across 13 reference-save replays" — including the previously-failing Chapter 13 save.
- `task clean:obj build` (legacy C-only taskfile.yml build, still compiling src/overlord.c unchanged): compiles and links cleanly to ./zelda3.
- zelda3.bak left untouched (mtime unchanged, predates this session).
<!-- SECTION:FINAL_SUMMARY:END -->
