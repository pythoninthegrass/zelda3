---
id: TASK-003.03
title: Port snes/apu.c to apu.zig
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-03 01:04'
labels: []
dependencies:
  - TASK-003.02
parent_task_id: TASK-003
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/apu.c (APU wiring) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 apu.c is removed from the C build and apu.zig is compiled instead
- [x] #2 Audio output is unaffected
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Full macOS build (`task build`/`zig build`) is blocked by a pre-existing, unrelated linker issue: config.zig's libc `stderr` reference resolves to an undefined `_stderr` symbol on this machine's macOS/Xcode toolchain (macOS exposes `__stderrp` instead). Confirmed via `git stash` that this identical failure reproduces on unmodified master with zero apu changes present — not introduced by this port, out of scope for this task.

Verified the full DoD on the `mf` Linux host instead (the project's canonical build/playtest environment per CLAUDE.local.md): `task build` links cleanly with apu.o compiled from apu.zig alongside all remaining .c sources; `task zig:parity` reports zero RAM-compare mismatches; `task zig:parity-replay` (headless sway+wtype+grim) reports zero mismatches across all 13 reference-save chapter replays.

Tier-A unit tests (zig build test) pass 76/76 relevant (5 pre-existing unrelated config_test failures). Tier-B differential test (zig build difftest) could not be exercised end-to-end on macOS: GNU objcopy is unavailable and llvm-objcopy's --redefine-sym does not correctly rename Mach-O symbols on this machine, producing duplicate-symbol link errors. Confirmed via git stash that this identical failure class affects ALL existing difftest modules on unmodified master too — a pre-existing macOS-only tooling gap, not apu-specific.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported snes/apu.c to snes/apu.zig: the APU I/O-register wiring (`apu_init/apu_free/apu_saveload/apu_reset/apu_cycle/apu_cpuRead/apu_cpuWrite`), timers, and boot-ROM overlay that glue the Spc/Dsp subsystems together, keeping every function's C-ABI name/signature unchanged.

Key implementation details:
- `Apu` extern struct mirrors snes/apu.h field-for-field, including an `extern union` (`HistUnion`) to replicate the alignment quirk of the original anonymous `union { DspRegWriteHistory hist; void *padpad; }` (the void* member forces 8-byte struct alignment).
- `spc`/`dsp` fields stay `?*anyopaque` since apu.c never dereferences their internals, only passes them through to the not-yet-ported spc_*/dsp_* C entry points.
- Logic (register decode switch, timer divider/counter wrap, dsp_cycle-every-32-cycles gating, reset ordering with `romReadable=true` set before `spc_reset`) transcribed 1:1 from the C source, using wrapping ops (`+%=`, `-%=`) and `@truncate`/`@bitCast` to match C's defined overflow/truncation semantics.

Build wiring: added apu.zig to build.zig's exe object list, unit/diff test file lists, and a `compileRenamedCRef`-based apu_c_ref difftest target (sharing real, unrenamed spc.o/dsp.o between both flavours since those modules aren't ported yet). Added a `compile-zig-apu` task to taskfile.yml, removed apu.c from the SOURCES list, and added snes/apu.o to the final link line.

Testing:
- Tier-A (`zig build test`): 76/76 relevant tests pass.
- Tier-B (`zig build difftest`): blocked on this macOS dev machine by a pre-existing objcopy tooling gap (GNU objcopy absent; llvm-objcopy doesn't rename Mach-O symbols correctly) — confirmed via git-stash comparison to affect ALL difftest modules on unmodified master, not just apu. Not run end-to-end; recommend running on a Linux host with GNU binutils if Tier-B coverage is wanted.
- Full build + RAM-compare parity + reference-save replay verified on the `mf` Linux host: `task build` links clean, `task zig:parity` zero mismatches, `task zig:parity-replay` zero mismatches across all 13 reference chapters.
- macOS full build (`task build`) is blocked by a separate, pre-existing, unrelated issue: config.zig's `stderr` reference is an undefined symbol on this machine's toolchain. Confirmed present on unmodified master via git stash — not caused by this change.

Risk/follow-up: Tier-B differential coverage for apu.zig has not actually been exercised anywhere yet (blocked everywhere the objcopy gap exists); consider revisiting on a Linux dev box with real GNU binutils.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
