---
id: TASK-004.02
title: Port src/load_gfx.c to load_gfx.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:20'
updated_date: '2026-08-13 23:50'
labels: []
dependencies:
  - TASK-004.01
parent_task_id: TASK-004
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/load_gfx.c (graphics decompression/loading from zelda3_assets.dat) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 load_gfx.c is removed from the C build and load_gfx.zig is compiled instead
- [x] #2 All in-game graphics (tiles, sprites, palettes) load and render correctly
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
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
Follow the same pattern as TASK-004.01 (spc_player.c -> spc_player.zig): port src/load_gfx.c function-for-function into src/load_gfx.zig as `pub export fn` with unchanged C-ABI names/signatures, using v.g_ram / t.* accessors from variables.zig/types.zig for RAM-mirrored state, then swap it into build.zig via addPortedModule and drop load_gfx.c from the C sources list.

Work happens in worktree /home/lance/git/zelda3.task-004.02-load-gfx-zig (branch task-004.02-load-gfx-zig), sibling to the main repo, matching the convention used for task-004.01 and task-007.

Steps:
1. Re-read src/load_gfx.c fully (2182 lines) and re-verify all file-local static tables (kMainTilesets, kSpriteTilesets, kAuxTilesets, kOwBgPalInfo, kOwSprPalInfo, etc.) byte-for-byte against source rather than trusting a previous partial draft's transcription (an earlier attempt at this file was deleted for having unverified table rows).
2. Port in chunks in file order, checking each chunk compiles before moving on: (a) file-local tables/consts lines ~1-330, (b) core decompression/loader helpers ~331-650, (c) ~650-950, (d) ~950-1400, (e) ~1400-1680, (f) palette loaders ~1680-2182.
3. Watch known C idioms that need care in translation: do/while loops, comma-operator loops (e.g. `while (r6--, r10 != r4++)`), pointer arithmetic on RAM buffers, and the `enum { kPal_* }` palette-index constants near line ~1985.
4. Externs/cross-module deps stay as C imports: FindInAssetArray/g_asset_ptrs (assets.h), g_zenv (variables.zig), HdmaSetup, SetTargetOverworldWarpToPyramid, PreOverworld_LoadOverlays, Overworld_DrawScreenAtCurrentMirrorPosition, MirrorWarp_LoadSpritesAndColors, HandleFollowersAfterMirroring, Sprite_ResetAll.
5. Update build.zig: remove "src/load_gfx.c" from the C sources list, add the load_gfx ported-module wiring alongside the other addPortedModule() calls.
6. Run `task zig:build`, fix compile errors.
7. Verify parity: run ./zelda3 zelda3.sfc, confirm zero "Memory compare failed" lines in stderr; replay reference saves (saves/ref/Chapter*.sav) and confirm clean.
8. Check off AC/DoD boxes with evidence, set task Done per finalization guide.

No architectural deviation from the established Zig-port pattern (same approach as the already-completed task-004.01), so proceeding without separate design review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Ported all 149 functions of src/load_gfx.c (147 non-static -> `pub export fn`, 2 file-local statics -> plain `fn`) to src/load_gfx.zig in 7 sequential chunks, each landed by a forked subagent working in worktree /home/lance/git/zelda3.task-004.02-load-gfx-zig (branch task-004.02-load-gfx-zig), verified via `zig ast-check` + `zig build-obj` after each chunk.

Found and fixed two real pre-existing bugs surfaced by full `zig build-obj` type-checking (ast-check alone misses these): (1) kSpriteTilesets table was missing one {0,0,0,0} row in each of its two all-zero runs (142 vs required 144 elements) - fixed by re-verifying against the C source byte-for-byte. (2) src/types.zig's byte/hibyte/word/dword type-punning helpers didn't preserve const-ness, causing '@ptrCast discards const qualifier' errors on legitimate read-only access through const C pointers - fixed by making them const-polymorphic (Pun() helper), verified this doesn't break spc_player.zig/poly.zig/tile_detect.zig which also depend on types.zig.

Wired load_gfx into build.zig: removed src/load_gfx.c from the C `sources` array, added addPortedModule(b, target, optimize, "load_gfx") alongside the other ported modules. Did NOT touch taskfile.yml's legacy SOURCES list or delete src/load_gfx.c from disk (matching the established precedent from TASK-004.01/spc_player.c, which is also kept on disk since the legacy `task build` C-only path still compiles it directly).

Verification: `task zig:build` compiles clean. `task zig:parity` (zig-out/bin/zelda3 run against zelda3.sfc) reports zero RAM-compare mismatches. `task zig:parity-replay` (headless Wayland sway+wtype+grim harness) replayed all 13 saves/ref/Chapter*.sav reference saves with zero RAM-compare mismatches. Legacy `task build` (untouched taskfile.yml, still compiling the original src/load_gfx.c) also verified still compiling successfully.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported src/load_gfx.c (2182 lines, 149 functions: graphics/palette decompression and loading from zelda3_assets.dat) to src/load_gfx.zig, following the same C-ABI-preserving pattern established by TASK-004.01 (spc_player.c -> spc_player.zig).

**Approach**: given the file's size and the RAM-compare-critical need for bit-exact fidelity, the port was done in 7 sequential chunks aligned to function boundaries, each chunk appended to the live file by a forked subagent and checked with `zig ast-check` (syntax) and `zig build-obj` (full semantic type-check) before moving to the next chunk. Forward references to not-yet-ported functions were bridged with temporary `extern fn` stubs, deleted by whichever later chunk landed the real definition; zero stubs remain in the final file.

**Bugs found and fixed during the port** (both via full `zig build-obj` type-checking, which catches errors `ast-check` misses):
- `kSpriteTilesets` (a 144x4 static table) was transcribed with one `{0,0,0,0}` row missing from each of its two all-zero runs (142 vs 144 elements) — fixed after re-verifying row counts against the C source.
- `src/types.zig`'s `byte`/`hibyte`/`word`/`dword` C-macro-punning helpers didn't preserve pointer const-ness, breaking legitimate read-only access through `const uint8 *` sources. Made them const-polymorphic; verified this shared-infra change doesn't regress the other three already-completed Zig ports (spc_player, poly, tile_detect).

**build.zig wiring**: removed `"src/load_gfx.c"` from the C `sources` array; added `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "load_gfx"))`. `src/load_gfx.c` itself was left on disk (not deleted), matching the TASK-004.01 precedent, since the legacy (untouched) `taskfile.yml`/`task build` C-only path still compiles it directly for its own separate binary.

**Verification** (all objective, command-driven):
- `task zig:build` — compiles clean.
- `task zig:parity` — zig-out/bin/zelda3 run against zelda3.sfc: zero "Memory compare failed" lines.
- `task zig:parity-replay` — all 13 saves/ref/Chapter*.sav reference saves replayed under headless Wayland (sway+wtype+grim): zero RAM-compare mismatches.
- Legacy `task build` (taskfile.yml, unmodified) still compiles successfully using the original src/load_gfx.c.

No test suite changes (project has none); no Tier-A/Tier-B tests were added for load_gfx.zig since the task's AC/DoD did not call for them and none of the prior Zig ports (spc_player, poly, tile_detect, config) established that as a required pattern for this task family.
<!-- SECTION:FINAL_SUMMARY:END -->
