---
id: TASK-004.05
title: Port src/player_oam.c to player_oam.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.04
parent_task_id: TASK-004
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/player_oam.c (Link's OAM sprite assembly) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. Closes out the Phase 3 leaf batch before the deep core files begin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 player_oam.c is removed from the C build and player_oam.zig is compiled instead
- [ ] #2 Link's on-screen sprite rendering is unaffected
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
