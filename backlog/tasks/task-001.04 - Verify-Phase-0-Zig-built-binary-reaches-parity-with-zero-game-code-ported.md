---
id: TASK-001.04
title: 'Verify Phase 0: Zig-built binary reaches parity with zero game code ported'
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-001.03
parent_task_id: TASK-001
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
End-to-end verification that the Zig build infrastructure is solid before any C-to-Zig code translation starts. This is the gate for beginning Phase 1. Play the Zig-built binary interactively, run it with the ROM loaded to exercise the frame-by-frame RAM-compare oracle (src/zelda_cpu_infra.c VerifySnapshotsEq), and replay the reference save files. Confirm the C reference build (taskfile.yml `task build`, producing zelda3.bak-equivalent output) still works unmodified.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Zig-built zelda3 launches, renders, and accepts input identically to the C build
- [ ] #2 Running with zelda3.sfc loaded produces zero 'Memory compare failed' lines across at least one full playthrough segment (e.g. intro through first dungeon)
- [ ] #3 Replaying saves/ref/Chapter*.sav shows no RAM-compare mismatches
- [ ] #4 `task build` (C) still produces a working binary, confirming the reference path is untouched
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
