---
id: TASK-004.11
title: Port src/ancilla.c to ancilla.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.10
parent_task_id: TASK-004
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/ancilla.c (ancillary objects: projectiles, effects — 7,156 lines, 58 gotos) to idiomatic Zig, converting every goto to structured control flow, one routine at a time with parity re-verification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ancilla.c is removed from the C build and ancilla.zig is compiled instead
- [ ] #2 No goto remains; control flow is restructured with identical semantics
- [ ] #3 Projectiles and effects (arrows, bombs, sword beams, etc.) behave identically
- [ ] #4 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
