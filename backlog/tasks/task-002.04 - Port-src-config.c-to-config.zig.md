---
id: TASK-002.04
title: Port src/config.c to config.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-002.03
parent_task_id: TASK-002
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/config.c (INI config parsing for zelda3.ini) to idiomatic Zig, following the pattern established by the util.c port: same C-ABI exported symbols, no changes required to callers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 config.c is removed from the C build and config.zig is compiled instead
- [ ] #2 zelda3.ini parsing behavior is unchanged (all documented settings still take effect)
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
