---
id: TASK-004.03
title: Port src/nmi.c to nmi.zig
status: Done
assignee: []
created_date: '2026-08-02 04:20'
updated_date: '2026-08-14 20:40'
labels: []
dependencies:
  - TASK-004.02
parent_task_id: TASK-004
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/nmi.c (NMI/vblank handling) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 nmi.c is removed from the C build and nmi.zig is compiled instead
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
Port every function in src/nmi.c (4 static helpers, 32 exported C-ABI functions, kNmiVramAddrs/kNmiSubroutines tables) to src/nmi.zig using the established TASK-004.01/004.02 idioms: `pub export fn` for non-static C functions (preserving exact names/signatures from nmi.h), plain `fn` for static helpers, v.<name>() RAM accessors from variables.zig, t.byte/word/hibyte for C type-punning macros, wrapping arithmetic (*%/+%) where C relies on unsigned overflow.

Key architectural decision: nmi.c needs g_zenv.ppu->cgram/oam access, but g_zenv.ppu is `?*anyopaque` in variables.zig specifically so callers don't need to @import snes/ppu.zig's module graph. Importing it would both mis-resolve (Zig @import resolves relative to the importing file's directory, so `@import("snes/ppu.zig")` from src/nmi.zig would look for src/snes/ppu.zig, not repo-root snes/ppu.zig) and — even with a corrected import path — would duplicate every `pub export fn` in ppu.zig into nmi.zig's own object (ppu.zig is separately compiled/linked via its own addPortedModuleAt), causing link-time duplicate-symbol errors. Fix: added two new `pub export fn PpuCopyCgramFromBuffer(ppu: *anyopaque, src: [*]const u8)` / `PpuCopyOamFromBuffer(...)` helpers directly in snes/ppu.zig that cast the opaque pointer internally; nmi.zig declares them as plain `extern fn` taking *anyopaque. Zero build.zig changes needed for this part.

build.zig wiring: removed "src/nmi.c" from the C `sources` array, added `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "nmi"))` alongside the other ported modules.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verification method for standalone `zig build-obj <file>.zig` on files with the pre-existing `pub fn main() callconv(.c) c_int { return 0; }` stub (present in all snes/*.zig ported modules): must pass `-lc` (matching build.zig's link_libc=true) or Zig's std.start machinery errors on main's return type even with entry disabled. Confirmed via git stash that this is pre-existing/unrelated to this port, not a regression.

Manually line-by-line diffed the full nmi.c (461 lines) against nmi.zig after compilation succeeded, confirming: all 32 exported functions match nmi.h signatures exactly, all 4 static helpers (CopyToVram, CopyToVramVertical, CopyToVramLow, Interrupt_NMI_AudioParts_Locked) stay unexported, kNmiVramAddrs (35 entries) and kNmiSubroutines (25 entries) tables match order/values exactly, WritePpuRegisters register writes match snes_regs.h ordering, and the two do-while loops (NMI_UpdateOWScroll, NMI_HandleArbitraryTileMap, NMI_DoUpdates' copy-packets loop) translate correctly to Zig while(true)+break patterns.

Local variable names `t` (in NMI_UpdateLoadLightWorldMap/NMI_UploadDarkWorldMap) and `v` (in HandleStripes14) collided with this project's module aliases (types.zig/variables.zig) and were renamed (dst0/dstv, val) during the port.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported src/nmi.c (461 lines: 4 static helpers, 32 exported functions, 2 lookup tables) to src/nmi.zig, following the TASK-004.01/004.02 pattern.

**Key fix**: nmi.c needs g_zenv.ppu->cgram/oam, but g_zenv.ppu is `?*anyopaque` — importing snes/ppu.zig from nmi.zig would mis-resolve (Zig @import is relative to the importing file's own directory) and, even fixed, would duplicate ppu.zig's exported symbols into nmi.zig's object (ppu.zig is separately linked via its own addPortedModuleAt). Instead added `PpuCopyCgramFromBuffer`/`PpuCopyOamFromBuffer` — two `pub export fn(ppu: *anyopaque, src: [*]const u8)` helpers in snes/ppu.zig that do the cast internally — and declared them as plain `extern fn` in nmi.zig. No build.zig changes needed for this part.

**build.zig**: removed "src/nmi.c" from the C `sources` array; added `addPortedModule(b, target, optimize, "nmi")`.

**Verification**:
- `zig ast-check` and `zig build-obj src/nmi.zig -I. -lc` clean (the `-lc` flag is required for standalone verification of any file carrying the pre-existing `pub fn main()` stub — confirmed via git-stash that this is unrelated pre-existing behavior, not a regression).
- Manual line-by-line diff of the full nmi.c against nmi.zig: all 32 exported functions match nmi.h signatures, all 4 static helpers stay unexported, both lookup tables (kNmiVramAddrs 35 entries, kNmiSubroutines 25 entries) match exactly, WritePpuRegisters register writes match snes_regs.h ordering, do-while loops correctly become Zig while(true)+break.
- `task zig:build`: clean.
- `task zig:parity`: PARITY OK, zero RAM-compare mismatches.
- `task zig:parity-replay`: PARITY-REPLAY OK across all 13 reference-save replays.
- `task build` (legacy C-only taskfile.yml path): unaffected, still compiles src/nmi.c untouched, links clean.

Done in worktree /home/lance/git/zelda3.task-004.03-nmi-zig, branch task-004.03-nmi-zig off master.
<!-- SECTION:FINAL_SUMMARY:END -->
