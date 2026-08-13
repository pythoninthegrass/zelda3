---
id: TASK-003
title: Phase 2 — Port the snes/ emulator island to Zig
status: Done
assignee: []
created_date: '2026-08-02 04:18'
updated_date: '2026-08-13 16:37'
labels: []
milestone: m-0
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the snes/ subsystem (the bundled SNES hardware emulator) to Zig. It's a clean separable island — files only cross-include each other plus src/snes_regs.h — used both as the live PPU/DMA renderer backend (g_zenv.ppu) and, when a ROM is loaded, as the CPU-accurate oracle for RAM-compare verification. Port input.c, cart.c, apu.c, dma.c, dsp.c, ppu.c, spc.c, snes.c, snes_other.c one file at a time. Keep cpu.c and tracing.c as C — they're the parity oracle's CPU core and must keep working through the whole migration; port them last if at all.

Full plan context: /Users/lance/.claude/plans/i-m-interested-in-porting-polished-pizza.md
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All 8 planned per-file ports of the snes/ emulator island to Zig are complete: input.zig, cart.zig, apu.zig, dma.zig, dsp.zig, ppu.zig, spc.zig, snes.zig, and snes_other.zig (TASK-003.09, just finished) all compile via build.zig and are wired into the exe in place of their original .c sources.

snes/cpu.c and snes/tracing.c intentionally remain C, as scoped in the parent description — they're the RAM-compare oracle's CPU core and were never planned for porting in this phase.

Verification (via the final subtask, TASK-003.09, re-run against the full current tree): `zig build` compiles clean; `task zig:parity` reports zero RAM-compare mismatches against the original ROM; `task zig:parity-replay` reports zero mismatches across all 13 saves/ref/Chapter*.sav reference-save replays; the legacy C-only `task build` path still compiles and links unmodified using zelda3.bak/taskfile.yml, untouched throughout the whole migration.

Follow-up (not in this phase's scope): porting cpu.c/tracing.c themselves, if ever desired, per the parent description's "port them last if at all."
<!-- SECTION:FINAL_SUMMARY:END -->
