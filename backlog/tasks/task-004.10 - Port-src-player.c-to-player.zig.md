---
id: TASK-004.10
title: Port src/player.c to player.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.09
parent_task_id: TASK-004
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/player.c (Link's movement/state machine, 6,664 lines, 66 gotos — the largest goto count of any file) to idiomatic Zig. Convert every goto to labeled break/continue, early return, or restructured while(true) loops; do this routine-by-routine, re-verifying parity after each routine given how central player control is to every test playthrough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 player.c is removed from the C build and player.zig is compiled instead
- [ ] #2 No goto remains; control flow is restructured with labeled break/continue/loops with identical semantics
- [ ] #3 Link's movement, actions, and state transitions are indistinguishable from before across a full playthrough segment
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
