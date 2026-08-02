---
id: TASK-004.15
title: Port src/ending.c to ending.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.14
parent_task_id: TASK-004
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/ending.c (the ending sequence, 2,658 lines) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ending.c is removed from the C build and ending.zig is compiled instead
- [ ] #2 The ending sequence plays identically (verified via save-state or debug entry point, since it's late-game content)
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
