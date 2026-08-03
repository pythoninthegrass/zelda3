---
id: TASK-007
title: Fix platform-specific dma_difftest failure on Linux (mf/AlmaLinux)
status: To Do
assignee: []
created_date: '2026-08-03 05:54'
labels:
  - zig-port
  - bug
dependencies: []
priority: medium
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
snes/dma_difftest.zig's "diff dma_startDma over randomized bitmask/hdma flag streams" test fails deterministically on the `mf` AlmaLinux host (`zig build difftest`) across multiple different random seeds, while passing cleanly on macOS. Observed failure: `startDma step: channel byte 11: c=0x00 z=0x01`.

Discovered incidentally while verifying TASK-003.06 (ppu.zig port) on mf — unrelated to that port; dma.zig/dma_difftest.zig were already merged as part of TASK-003.04 and untouched by the ppu.zig work. Root cause not yet investigated; could be a genuine C-vs-Zig behavioral divergence exposed only under some platform-dependent condition (e.g. struct padding/alignment, integer promotion, or malloc-zeroing assumption that happens to differ between macOS's and glibc's allocator), or a test-harness issue specific to Linux.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zig build difftest passes cleanly and repeatably on the mf AlmaLinux host (multiple seeds)
- [ ] #2 Root cause of the c=0x00 z=0x01 channel-byte-11 divergence is identified and documented
- [ ] #3 zig build difftest continues to pass cleanly on macOS
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
