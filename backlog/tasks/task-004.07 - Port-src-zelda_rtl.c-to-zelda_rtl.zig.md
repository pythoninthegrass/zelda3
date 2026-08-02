---
id: TASK-004.07
title: Port src/zelda_rtl.c to zelda_rtl.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:20'
labels: []
dependencies:
  - TASK-004.06
parent_task_id: TASK-004
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/zelda_rtl.c (the runtime core / frame loop glue: g_ram definition and ownership, ZeldaRunFrame/ZeldaRunFrameInternal, ZeldaInitialize, ZeldaDrawPpuFrame, the g_zenv global env) to idiomatic Zig. This file currently owns `uint8 g_ram[131072]` — moving its definition to Zig means updating variables.zig's `extern var g_ram` to instead be the actual Zig-owned definition, and re-declaring it `extern` from the remaining C files. Handle this transition carefully since every g_ram accessor across the whole codebase depends on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zelda_rtl.c is removed from the C build and zelda_rtl.zig is compiled instead
- [ ] #2 g_ram is defined once (in Zig) and all C files reference it via extern with no behavior change
- [ ] #3 The frame loop (ZeldaRunFrame, ZeldaRunFrameInternal, NMI dispatch) behaves identically
- [ ] #4 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
