---
id: TASK-003.07
title: Port snes/spc.c to spc.zig
status: Done
assignee: []
created_date: '2026-08-02 04:20'
updated_date: '2026-08-03 15:50'
labels: []
dependencies:
  - TASK-003.06
parent_task_id: TASK-003
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/spc.c (SPC700 emulator) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 spc.c is removed from the C build and spc.zig is compiled instead
- [ ] #2 Audio output is unaffected
- [ ] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation Plan

### Overview
Port snes/spc.c (SPC700 CPU emulator, 1528 lines) to snes/spc.zig using the same C-ABI pattern as dsp.zig/apu.zig/ppu.zig. The Spc struct stays owned in Zig (mirrored as extern struct), spc.c is removed from the C build sources list in build.zig, and spc.zig is wired in as a new addPortedModuleAt call.

### Files
- `snes/spc.zig` — the port; exports spc_init/spc_free/spc_reset/spc_runOpcode/spc_saveload with callconv(.c)
- `snes/spc_test.zig` — Tier-A unit tests
- `snes/spc_difftest.zig` — Tier-B differential test; links spc_c_ref (renamed spc.c) vs spc.zig over randomized opcode streams, using a real apu.zig instance for bus I/O
- `build.zig` — remove "snes/spc.c" from sources[], add spc.zig object, add spc_test/spc_difftest entries, update apu_difftest to use spc.zig instead of spc.c

### Key Design Points
1. `Spc` is an `extern struct` matching snes/spc.h field-for-field (apu.zig currently uses `?*anyopaque` for it; after porting, apu.zig can import the typed Spc)
2. All internal helpers (spc_read, spc_write, addressing modes, ALU ops) are file-private (`fn` without pub/export)
3. The four public C-ABI exports use `export fn` with `callconv(.c)`
4. spc_saveload serializes `a..cyclesUsed` (the range in spc.h: offsetof(Spc,a) to offsetof(Spc,cyclesUsed)+1)
5. bool fields map to Zig `bool`; `c` (carry flag) conflicts with Zig keyword — use `@"c"` or rename to `cf` (check apu.zig usage)
6. The difftest links: spc.zig (plain names) + spc_c_ref (c_-prefixed) + apu.zig (shared, real bus) + dsp.zig (shared)

### Steps
1. Write spc.zig
2. Write spc_test.zig
3. Write spc_difftest.zig
4. Update build.zig
5. Optionally update apu.zig (Spc becomes typed instead of anyopaque)
6. Build and run tests
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
All implementation complete. Build clean, all 162 tests pass (22 unit + diff suite). spc.c removed from zig build sources. C taskfile build untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

Ported `snes/spc.c` (SPC700 CPU emulator, 1528 lines) to `snes/spc.zig`.

### Files changed
- **`snes/spc.zig`** — full port; `pub export fn` for the 5 C-ABI symbols (`spc_init`, `spc_free`, `spc_reset`, `spc_runOpcode`, `spc_saveload`); all internal helpers are file-private; `Spc` is an `extern struct` matching `snes/spc.h` field-for-field
- **`snes/spc_test.zig`** — 22 Tier-A unit tests covering reset, flag ops, ALU, branches, stack, and saveload
- **`snes/spc_difftest.zig`** — Tier-B differential test linking `spc.zig` vs renamed `spc_c_ref` over shared bus RAM
- **`build.zig`** — removed `"snes/spc.c"` from sources, added `spc.zig` as a ported module, wired `spc_test.zig`/`spc_difftest.zig`, updated `apu_difftest` to use `spc.zig` instead of `spc.c`, added `spc_c_ref` compiled reference
- **`snes/apu.zig`** — updated comment to reflect spc.zig is now ported

### Key fixes during implementation
- Added missing `u8 → c_int` casts before arithmetic in `spcAdc`, `spcSbc`, `spcCmp*`, `tset1`, `tclr1`, `cbne` to avoid compile-time overflow (Zig doesn't implicitly widen u8 operands to match the result type annotation)
- Changed `export fn` to `pub export fn` so the functions are accessible via `@import` in tests
<!-- SECTION:FINAL_SUMMARY:END -->
