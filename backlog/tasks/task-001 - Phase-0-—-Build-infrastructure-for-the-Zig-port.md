---
id: TASK-001
title: Phase 0 — Build infrastructure for the Zig port
status: To Do
assignee: []
created_date: '2026-08-02 04:18'
labels: []
milestone: m-0
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Stand up a Zig build (build.zig) that compiles the existing, unmodified C codebase (src/, snes/, third_party/) into a working zelda3 binary, wired into taskfile.yml via taskfiles/zig.yml, before any C-to-Zig code translation begins. This proves the toolchain and parity workflow (RAM-compare against the original ROM) work end-to-end while zero game code is Zig yet, de-risking every later phase. The existing C build (taskfile.yml, task build) must keep working unchanged throughout — retain the current working binary as zelda3.bak until the full port reaches parity.

Full plan context: /Users/lance/.claude/plans/i-m-interested-in-porting-polished-pizza.md
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
