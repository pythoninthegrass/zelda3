---
id: TASK-004.02
title: Port src/load_gfx.c to load_gfx.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
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
- [ ] #1 load_gfx.c is removed from the C build and load_gfx.zig is compiled instead
- [ ] #2 All in-game graphics (tiles, sprites, palettes) load and render correctly
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
