---
id: TASK-003.05
title: Port snes/dsp.c to dsp.zig
status: In Progress
assignee: []
created_date: '2026-08-02 04:20'
updated_date: '2026-08-03 00:46'
labels: []
dependencies:
  - TASK-003.04
parent_task_id: TASK-003
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/dsp.c (audio DSP emulator) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 dsp.c is removed from the C build and dsp.zig is compiled instead
- [ ] #2 Audio output (music/SFX mixing) is unaffected
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
