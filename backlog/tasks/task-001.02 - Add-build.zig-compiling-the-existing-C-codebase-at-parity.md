---
id: TASK-001.02
title: Add build.zig compiling the existing C codebase at parity
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies:
  - TASK-001.01
parent_task_id: TASK-001
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add build.zig (+ build.zig.zon) that compiles all existing, unmodified .c files from src/, snes/, third_party/gl_core, and third_party/opus-1.3.1-stripped into a zelda3 binary — reproducing what taskfile.yml's `task build` does today, with zero Zig game code yet. Use addCSourceFiles with the same flags the C build uses (-DSYSTEM_VOLUME_MIXER_AVAILABLE=0, include path '.'), linkLibC(), linkSystemLibrary(\"SDL2\") (+ -lm), and addIncludePath for SDL2 headers (from `sdl2-config --cflags`). Match optimization roughly to the C build's -O2 (use ReleaseFast). Output to zig-out/bin/zelda3. This is pure build-system work — no source files change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zig build produces zig-out/bin/zelda3 with no Zig-side source changes to existing .c/.h files
- [ ] #2 The Zig-built binary launches and plays identically to the C-built zelda3.bak
- [ ] #3 Running the Zig-built binary with zelda3.sfc loaded shows zero RAM-compare mismatches on stderr
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
