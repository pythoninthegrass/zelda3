---
id: TASK-001.01
title: Back up working C binary and gitignore Zig build artifacts
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
labels: []
dependencies: []
parent_task_id: TASK-001
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Copy the current working zelda3 binary to zelda3.bak so a known-good C-built reference always exists during the port. Add zelda3.bak, zig-out/, and .zig-cache/ to .gitignore. This is a prerequisite for every later Zig build step — the C reference must survive untouched until the full port reaches parity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zelda3.bak exists and is a copy of the currently-working C-built binary
- [ ] #2 .gitignore excludes zelda3.bak, zig-out/, and .zig-cache/
- [ ] #3 git status shows no unintended tracked artifacts from the Zig build
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
