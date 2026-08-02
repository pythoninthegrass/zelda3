---
id: TASK-001
title: Phase 0 — Build infrastructure for the Zig port
status: Done
assignee: []
created_date: '2026-08-02 04:18'
updated_date: '2026-08-02 05:13'
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
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Phase 0 complete: all four subtasks (backup + gitignore, build.zig compiling the unmodified C codebase, taskfiles/zig.yml wired into taskfile.yml, and end-to-end parity verification) are done. The Zig toolchain, build, task runner integration, and RAM-compare verification workflow are all proven with zero game code yet ported to Zig, and the C reference build (zelda3.bak / task build) remains untouched throughout. Ready to begin Phase 1 (TASK-002).
<!-- SECTION:FINAL_SUMMARY:END -->
