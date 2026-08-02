---
id: TASK-001.03
title: Add taskfiles/zig.yml and wire it into taskfile.yml
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-001.02
parent_task_id: TASK-001
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create taskfiles/zig.yml providing zig:build (`zig build`), zig:run, zig:clean (`rm -rf zig-out .zig-cache`), and zig:parity (runs the Zig-built binary with the ROM to exercise the RAM-compare oracle and report pass/fail). Wire it into the root taskfile.yml via `includes: { zig: taskfiles/zig.yml }`. zig:parity should depend on the root `assets` task (call via `task: :assets`) so zelda3_assets.dat exists before running. Do not remove or modify existing C build tasks in taskfile.yml — this only adds the Zig namespace alongside them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `task zig:build` runs `zig build` successfully
- [ ] #2 `task zig:clean` removes zig-out/ and .zig-cache/
- [ ] #3 `task zig:parity` runs the Zig binary against zelda3.sfc and surfaces RAM-compare failures if any occur
- [ ] #4 Existing `task build`, `task clean`, `task assets` behavior is unchanged
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
