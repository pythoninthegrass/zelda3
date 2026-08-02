---
id: TASK-004.20
title: Port src/audio.c to audio.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.19
parent_task_id: TASK-004
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/audio.c (audio mixing/MSU support, 542 lines) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 audio.c is removed from the C build and audio.zig is compiled instead
- [ ] #2 Audio mixing and MSU audio playback (where available) are unaffected
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
