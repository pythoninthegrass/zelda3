---
id: TASK-004.23
title: >-
  Port the RAM-compare oracle (zelda_cpu_infra.c, snes/cpu.c) to Zig — final
  phase
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.22
parent_task_id: TASK-004
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the last remaining C files: src/zelda_cpu_infra.c (RunEmulatedFunc/RunEmulatedFuncSilent, VerifySnapshotsEq, the frame-by-frame comparison harness) and snes/cpu.c (the 65816 CPU emulator used only by the oracle) plus snes/tracing.c, to idiomatic Zig. This is the very last step — until now these files have been kept as working C throughout the entire port specifically so the oracle they implement could keep verifying every other file's translation. Port them last, and once done, the entire src/ and snes/ codebase is Zig; only third_party/gl_core and third_party/opus-1.3.1-stripped remain C by design.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zelda_cpu_infra.c, snes/cpu.c, and snes/tracing.c are removed from the C build; Zig equivalents are compiled instead
- [ ] #2 VerifySnapshotsEq's exact whitelist of intentionally-divergent addresses is preserved byte-for-byte
- [ ] #3 The RAM-compare oracle continues to catch injected mismatches correctly (verify by temporarily introducing a deliberate 1-byte divergence and confirming it's detected, then reverting)
- [ ] #4 A full reference playthrough shows zero RAM-compare mismatches
- [ ] #5 Only third_party/gl_core and third_party/opus-1.3.1-stripped remain as C in the build
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
