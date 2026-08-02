---
id: TASK-004.01
title: Port src/spc_player.c to spc_player.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-003.09
parent_task_id: TASK-004
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/spc_player.c (the self-contained reimplemented SPC music player, not the emulated one) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is the first Phase 3 file — a leaf with few local includes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 spc_player.c is removed from the C build and spc_player.zig is compiled instead
- [ ] #2 Music playback is unaffected
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
