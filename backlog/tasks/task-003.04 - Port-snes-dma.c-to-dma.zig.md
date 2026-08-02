---
id: TASK-003.04
title: Port snes/dma.c to dma.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-003.03
parent_task_id: TASK-003
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/dma.c (DMA/HDMA emulation — used both by the live renderer's g_zenv.dma and the RAM-compare oracle) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is live rendering code, so visual regressions surface immediately.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 dma.c is removed from the C build and dma.zig is compiled instead
- [ ] #2 DMA/HDMA-driven visual effects (gradients, raster effects) render identically
- [ ] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
