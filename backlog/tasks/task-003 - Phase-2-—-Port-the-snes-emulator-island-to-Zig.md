---
id: TASK-003
title: Phase 2 — Port the snes/ emulator island to Zig
status: To Do
assignee: []
created_date: '2026-08-02 04:18'
labels: []
milestone: m-0
dependencies: []
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the snes/ subsystem (the bundled SNES hardware emulator) to Zig. It's a clean separable island — files only cross-include each other plus src/snes_regs.h — used both as the live PPU/DMA renderer backend (g_zenv.ppu) and, when a ROM is loaded, as the CPU-accurate oracle for RAM-compare verification. Port input.c, cart.c, apu.c, dma.c, dsp.c, ppu.c, spc.c, snes.c, snes_other.c one file at a time. Keep cpu.c and tracing.c as C — they're the parity oracle's CPU core and must keep working through the whole migration; port them last if at all.

Full plan context: /Users/lance/.claude/plans/i-m-interested-in-porting-polished-pizza.md
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
