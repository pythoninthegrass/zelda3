---
id: TASK-004.08
title: Port src/sprite.c to sprite.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.07
parent_task_id: TASK-004
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/sprite.c (the shared sprite engine used by all enemy/object AI in sprite_main.c) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. Must be done before sprite_main.c since sprite_main.c depends on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 sprite.c is removed from the C build and sprite.zig is compiled instead
- [ ] #2 Sprite lifecycle (spawn/despawn/collision plumbing shared across all sprite types) is unaffected
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
