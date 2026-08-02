---
id: TASK-002.03
title: Port src/util.c to util.zig (first cross-language proof)
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-002.02
parent_task_id: TASK-002
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/util.c — a true leaf module with minimal includes — to util.zig as the first real proof that the Zig/C interop workflow (export fn with callconv(.c), matching C symbol names, linking into the existing build) works end to end. Every other .c file that currently calls into util.c's functions must keep linking without any source changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 util.c is removed from the C build and util.zig is compiled instead
- [ ] #2 All exported symbols use callconv(.c) and match the original C names exactly
- [ ] #3 Every remaining .c file that included util.h and called its functions compiles and links with zero changes
- [ ] #4 Full Phase 0-style verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
