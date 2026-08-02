---
id: TASK-004.21
title: Port src/main.c to main.zig (SDL entry point)
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.20
parent_task_id: TASK-004
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/main.c (SDL window/input/audio glue and the top-level frame loop, 882 lines) to idiomatic Zig — this becomes the Zig program's actual entry point (root_source_file in build.zig), replacing the C `main()`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 main.c is removed from the C build; build.zig's root_source_file becomes main.zig
- [ ] #2 SDL window creation, event polling, input handling, and the frame loop behave identically
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
