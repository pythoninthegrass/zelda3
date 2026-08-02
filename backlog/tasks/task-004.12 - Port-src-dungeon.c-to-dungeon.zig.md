---
id: TASK-004.12
title: Port src/dungeon.c to dungeon.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.11
parent_task_id: TASK-004
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/dungeon.c (dungeon room logic, 8,796 lines, 46 gotos, includes the kDungTagroutines[] function-pointer jump table) to idiomatic Zig. Map kDungTagroutines[] to a Zig `const [_]*const fn(...) callconv(.c) void` array; convert gotos to structured control flow one routine at a time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 dungeon.c is removed from the C build and dungeon.zig is compiled instead
- [ ] #2 kDungTagroutines[] and other jump tables are Zig fn-pointer arrays with identical dispatch behavior
- [ ] #3 No goto remains; control flow is restructured with identical semantics
- [ ] #4 Dungeon room state (doors, chests, pushable blocks, tag routines) behaves identically
- [ ] #5 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
