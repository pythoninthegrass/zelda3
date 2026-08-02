---
id: TASK-002.06
title: Port src/tile_detect.c to tile_detect.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-002.05
parent_task_id: TASK-002
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/tile_detect.c (tile collision detection) to idiomatic Zig, following the pattern established by the util.c port. This closes out the Phase 1 leaf-file batch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tile_detect.c is removed from the C build and tile_detect.zig is compiled instead
- [ ] #2 Tile collision behavior is unchanged across a full playthrough segment
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
