---
id: TASK-004.14
title: Port src/messaging.c to messaging.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.13
parent_task_id: TASK-004
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/messaging.c (text/dialogue rendering and HUD map, 2,935 lines, includes multiple function-pointer jump tables: kDungMapInit, kDungMapSubmodules, kText_Render, kMessaging_Text) to idiomatic Zig. Map each jump table to a Zig `const [_]*const fn(...) callconv(.c)` array.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 messaging.c is removed from the C build and messaging.zig is compiled instead
- [ ] #2 All jump tables (kDungMapInit, kDungMapSubmodules, kText_Render, kMessaging_Text) are Zig fn-pointer arrays with identical dispatch behavior
- [ ] #3 Dialogue text rendering and dungeon map HUD behave identically
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
