---
id: TASK-004.05
title: Port src/player_oam.c to player_oam.zig
status: Done
assignee:
  - '@claude'
created_date: '2026-08-02 04:20'
updated_date: '2026-08-15 06:12'
labels: []
dependencies:
  - TASK-004.04
modified_files:
  - src/player_oam.zig
  - build.zig
parent_task_id: TASK-004
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/player_oam.c (Link's OAM sprite assembly) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. Closes out the Phase 3 leaf batch before the deep core files begin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 player_oam.c is removed from the C build and player_oam.zig is compiled instead
- [x] #2 Link's on-screen sprite rendering is unaffected
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
Port src/player_oam.c (1289 lines, 11 externally/internally used functions + ~40 static const data tables) to src/player_oam.zig, following the exact conventions established in nmi.zig/overlord.zig (TASK-004.03/004.04).

1. Header comment (module purpose, C-ABI symbol preservation note) + `const t = @import("types.zig");` `const v = @import("variables.zig");` plus any needed `extern fn`/`extern var` for cross-module C symbols still in .c files (misc.c's non-static helpers, if any are actually called - verify during implementation; GetOamCurPtr/FindInByteArray/FindInWordArray are `static inline` in misc.h with no C-ABI symbol, so reimplement them as local Zig fns, not extern).

2. Data tables: mechanical 1:1 translation of all ~40 `static const` arrays (int8/uint8/uint16, up to 511 elements) to Zig `const kName: [N]t.intN = .{...}` preserving exact values/order/naming. `LinkSpriteBody` (y:int8, x:int8, tile:uint8) becomes a local plain Zig struct (`extern struct` not required - never crosses FFI boundary, file-internal only) with `kLinkSpriteBodys: [303]LinkSpriteBody`.

3. Local constants needed because player.c/player.h and features.h have no Zig port yet:
   - 9 `kPlayerState_*` values actually referenced (Ether=8, Bombos=9, Quake=10, SpinAttacking=3, SpinAttackMotion=30, AsleepInBed=22, Swimming=4, TurtleRock=5, Hookshot=19) as local `const ...: t.uint8/c_int` matching player.h's enum.
   - `enhanced_features0()` + `kFeatures0_WidescreenVisualFixes = 1024`, reimplemented locally exactly like the existing precedent in load_gfx.zig:77-83 (`inline fn enhanced_features0() *align(1) t.uint32 { return @ptrCast(&v.g_ram[0x64c]); }`).
   - Local `FindInByteArray`/`FindInWordArray`/`GetOamCurPtr` reimplementations matching misc.h's static inline bodies exactly (linear reverse scan returning -1 on miss; GetOamCurPtr casts &g_ram[oam_cur_ptr] to *OamEnt via v.g_ram + v.oam_cur_ptr()).

4. All 11 functions from player_oam.h get `pub export fn` (matching non-static C linkage regardless of current external callers, per established precedent): PlayerOam_WantInvokeSword, CalculateSwordHitBox, LinkOam_Main, FindMostSignificantBit, LinkOam_SetWeaponVRAMOffsets, LinkOam_SetEquipmentVRAMOffsets, LinkOam_CalculateSwordSparklePosition, LinkOam_UnusedWeaponSettings, LinkOam_DrawDungeonFallShadow, LinkOam_DrawFootObject, LinkOam_CalculateXOffsetRelativeLink. `SwordResult` (int/uint8 fields, per player_oam.h) becomes a plain internal Zig struct - not referenced by any other .c file (only player_oam.c/.h), so no extern-struct C-layout pinning needed.

5. `LinkOam_Main`'s 17 `goto` statements (targets: `continue_after_set:`, `link_state_is_empty:`) become labeled blocks:
   - Outer `compute: { ...; break :compute .{yt, rt}; }` (or equivalent) replacing every `goto continue_after_set;` - every path through that block ends in a break, verified against the C control flow.
   - Inner block wrapping the link_auxiliary_state / player_near_pit_state / link_state_bits three-check sequence; the single `goto link_state_is_empty;` (in the TurtleRock sub-branch) becomes a bare `break` out of that inner block, matching C fallthrough to the label.
   - Wrapping arithmetic (`+%`/`-%`/`*%`) applied wherever the C relies on 8/16-bit overflow (very likely throughout this file given OAM coordinate math).
   - `t.byte()/t.hibyte()/t.word()` for all `BYTE()/HIBYTE()/WORD()` punning call sites (confirmed: two `HIBYTE()` sites in LinkOam_DrawFootObject).

6. build.zig: remove `"src/player_oam.c",` from the `sources` array; add `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "player_oam"));` immediately after the existing `"overlord"` line, before `snes/*` module wiring.

7. No Tier-A/Tier-B test files added (established precedent for this class of deeply-g_ram-stateful port, confirmed on TASK-004.04 - no test suite exists project-wide; correctness is validated via the RAM-compare oracle and reference-save replay per AGENTS.md).

8. Verification: `task zig:build` (clean compile) -> `task zig:parity` (zero "Memory compare failed" against zelda3.sfc) -> `task zig:parity-replay` (all saves/ref/Chapter*.sav replay clean) -> confirm legacy `task build`/`task clean:obj build` (pure-C taskfile.yml) still compiles src/player_oam.c unchanged and links.

9. Branch `task-004.05-player_oam-zig`, commit `feat(port): player_oam.c → player_oam.zig (TASK-004.05)` (no Co-Authored-By trailer per user's global git rules), merge to master matching the established merge pattern from TASK-004.01-004.04.

10. Finalize per backlog://workflow/task-finalization: check AC/DoD boxes with evidence, record Final Summary mirroring TASK-004.04's structure, mark Done.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported src/player_oam.c (1289 lines, 11 externally-visible functions plus 59 static const data tables covering Link's OAM/sprite assembly: body pose, sword, shield, shadow, dungeon-fall shadow, foot objects) to src/player_oam.zig, following the nmi.zig/overlord.zig conventions established in TASK-004.03/.04. All C-ABI symbol names/signatures preserved unchanged (`pub export fn`); player_oam.c removed from build.zig's C `sources` array and replaced with `addPortedModule(b, target, optimize, "player_oam")`.

During systematic verification (self-initiated QA plus the RAM-compare oracle), found and fixed one transcription bug: the 124-entry `kPlayerOam_Spr2Y` table (int8 y-offsets used by the Spr2Bank OAM-writing block in `LinkOam_Main`) had a value inserted one position early around index 62, shifting all subsequent table entries by one slot through the rest of the array. This produced a wrong y-coordinate for `oam_buf[101].y` (address 0x995) starting at frame 133 of the Chapter-1 reference-save replay. Root-caused by adding temporary `std.debug.print` instrumentation at each of the file's 7 OAM-writing call sites (Spr1Bank, Spr2Bank, sword, shield, shadow, body, widescreen-hide) to identify which code path produced the diverging OAM index, then confirming the exact table divergence via a programmatic diff (extract-and-diff both C and Zig array literals, one value per line) against the C source. Fixed by replacing the array literal with values transcribed directly from the C source, re-verified via the same diff (zero differences, 124/124 matching). All temporary debug instrumentation was removed before finalizing.

As a precaution given this precedent, wrote a script to mechanically extract and diff all 59 `static const` tables (by name) between player_oam.c and player_oam.zig — confirmed `kPlayerOam_Spr2Y` was the only one with a divergence; the other 58 tables (including the 303-entry `kLinkSpriteBodys`) are byte-for-byte identical.

Verification evidence:
- `zig build` (forced rebuild after removing zig-out/bin/zelda3): clean, zero errors.
- `task zig:parity` (zelda3.sfc, 10s run): "PARITY OK: zero RAM-compare mismatches".
- `task zig:parity-replay` (all 13 saves/ref/Chapter*.sav replayed via headless sway+wtype+grim, run to completion in background): "PARITY-REPLAY OK: zero RAM-compare mismatches across 13 reference-save replays" — including the previously-failing Chapter 1 save.
- `task clean:obj build` (legacy C-only taskfile.yml build, still compiling src/player_oam.c unchanged): compiles and links cleanly to ./zelda3.
- zelda3.bak left untouched.
<!-- SECTION:FINAL_SUMMARY:END -->
