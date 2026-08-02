---
id: TASK-003.01
title: Port snes/input.c to input.zig
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 22:14'
labels: []
dependencies:
  - TASK-002.06
parent_task_id: TASK-003
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/input.c (controller input, 40 lines — smallest snes/ file, good first proof for the island) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 input.c is removed from the C build and input.zig is compiled instead
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
