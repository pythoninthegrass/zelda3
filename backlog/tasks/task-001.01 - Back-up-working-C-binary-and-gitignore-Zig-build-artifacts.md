---
id: TASK-001.01
title: Back up working C binary and gitignore Zig build artifacts
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 04:33'
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
- [x] #1 zelda3.bak exists and is a copy of the currently-working C-built binary
- [x] #2 .gitignore excludes zelda3.bak, zig-out/, and .zig-cache/
- [x] #3 git status shows no unintended tracked artifacts from the Zig build
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
zelda3.bak already exists, is byte-identical to the current working zelda3 binary, and is already gitignored via the existing `*.bak` wildcard rule (.gitignore:6). No copy step needed. Remaining gap: add `zig-out/` and `.zig-cache/` to .gitignore (they aren't covered by any existing rule). Then verify `git status` is clean with no unintended tracked artifacts.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified zelda3.bak is byte-identical to zelda3 (cmp). Added /zig-out/ and /.zig-cache/ to .gitignore; confirmed via git check-ignore -v that both patterns match. git status shows only .gitignore as modified — no build artifacts tracked.

DoD #1-4 (zig:build compiles, RAM-compare oracle, ref-save replay, C-ABI symbol parity) are the project-wide defaults applied to every port subtask, but none apply yet — no build.zig exists until TASK-001.02. Leaving them unchecked here; they become meaningful starting with the next subtask. #5 verified: zelda3.bak still byte-identical to zelda3, taskfile.yml untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Backed up the working C-built zelda3 binary and closed the .gitignore gap for upcoming Zig build artifacts, ahead of any Zig toolchain work.

**Findings:** zelda3.bak already existed and was byte-identical to the current zelda3 binary, and was already covered by the existing `*.bak` gitignore wildcard — no copy step was needed.

**Changes:** Added `/zig-out/` and `/.zig-cache/` to `.gitignore` (the two Zig build output/cache directories that had no prior rule).

**Verification:** `cmp zelda3 zelda3.bak` confirms identical; `git check-ignore -v` confirms both new patterns match; `git status` shows only the `.gitignore` edit, no stray tracked artifacts.

**Note:** DoD items #1-4 (zig build/parity/ABI checks) are the shared project-wide defaults and don't apply to this subtask specifically since no Zig build exists yet — they'll be exercised starting with TASK-001.02.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
