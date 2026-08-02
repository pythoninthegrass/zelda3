---
id: TASK-004.06
title: Port src/misc.c to misc.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.05
parent_task_id: TASK-004
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/misc.c, containing Module_MainRouting — the top-level game-state dispatcher called every frame from ZeldaRunGameLoop — to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is a deeply interconnected core file (18 includes); go carefully and re-verify parity thoroughly given how central Module_MainRouting is.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 misc.c is removed from the C build and misc.zig is compiled instead
- [ ] #2 Module_MainRouting dispatches every game module/state identically to before
- [ ] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean across all major game states: overworld, dungeon, menus)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
