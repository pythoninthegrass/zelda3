---
id: TASK-002.05
title: Port src/poly.c to poly.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-002.04
parent_task_id: TASK-002
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/poly.c (the polyhedral/triforce intro renderer) to idiomatic Zig, following the pattern established by the util.c port.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poly.c is removed from the C build and poly.zig is compiled instead
- [ ] #2 The intro/attract-mode polyhedral effect renders identically
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
