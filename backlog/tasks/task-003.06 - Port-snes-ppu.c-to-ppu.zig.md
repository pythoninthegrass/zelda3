---
id: TASK-003.06
title: Port snes/ppu.c to ppu.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-003.05
parent_task_id: TASK-003
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/ppu.c (the PPU/picture emulator — the live rendering backend via g_zenv.ppu, also the RAM-compare oracle's VRAM reference) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is the largest and highest-risk file in snes/ (1,548 lines) since it drives all actual on-screen rendering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ppu.c is removed from the C build and ppu.zig is compiled instead
- [ ] #2 On-screen rendering (backgrounds, sprites, effects) is pixel-identical across a full playthrough segment
- [ ] #3 VRAM portion of the RAM-compare oracle shows zero mismatches
- [ ] #4 Full parity verification passes (build clean, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
