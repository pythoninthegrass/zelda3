---
id: TASK-003.09
title: Port snes/snes_other.c to snes_other.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-003.08
parent_task_id: TASK-003
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/snes_other.c (misc SNES support) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is the last snes/ file before cpu.c/tracing.c, which stay as C oracle code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 snes_other.c is removed from the C build and snes_other.zig is compiled instead
- [ ] #2 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
- [ ] #3 snes/cpu.c and snes/tracing.c remain C and continue compiling as the RAM-compare oracle's CPU core
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
