---
id: TASK-004.09
title: Port src/sprite_main.c to Zig (25.8k LOC — subdivide by sprite/switch group)
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.08
parent_task_id: TASK-004
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/sprite_main.c, the dominant file in the codebase (25,878 lines, 108 switch statements — per-sprite AI/behavior for every enemy and object type) to idiomatic Zig. This is too large for one atomic task: subdivide into subtasks grouped by related sprite IDs/switch-case clusters (the file's own section comments/sprite-ID ranges are the natural boundaries), each subtask porting a contiguous cluster of sprite handler functions, exporting the same C-ABI symbols, and independently parity-verified before moving to the next cluster. Create the actual subtask breakdown by reading the file's structure first (grep for `void Sprite_` function definitions and existing section banners) rather than guessing boundaries upfront.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The file is fully subdivided into subtasks covering 100% of sprite_main.c's functions with no gaps or overlaps
- [ ] #2 Each subtask independently satisfies full parity verification before the next begins
- [ ] #3 Once complete, sprite_main.c is removed from the C build entirely and all sprite AI is Zig
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
