---
id: TASK-001.03
title: Add taskfiles/zig.yml and wire it into taskfile.yml
status: Done
assignee:
  - '@claude'
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 05:01'
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
- [x] #1 `task zig:build` runs `zig build` successfully
- [x] #2 `task zig:clean` removes zig-out/ and .zig-cache/
- [x] #3 `task zig:parity` runs the Zig binary against zelda3.sfc and surfaces RAM-compare failures if any occur
- [x] #4 Existing `task build`, `task clean`, `task assets` behavior is unchanged
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Create taskfiles/zig.yml with tasks: build (`zig build`), run (`zig build run`, depends on build), clean (`rm -rf zig-out .zig-cache`), parity (depends on build + root `:assets`; runs the built binary against zelda3.sfc with a 10s timeout, greps stderr for 'Memory compare failed', exits nonzero on any match).
2. Wire it into root taskfile.yml via `includes: { zig: taskfiles/zig.yml }`, without touching any existing C build tasks.
3. Verify: task zig:build compiles clean; task zig:parity reports zero RAM-compare mismatches; task build / task assets / zelda3.bak remain untouched (git diff on taskfile.yml only shows the added includes block; cmp zelda3 zelda3.bak identical).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Included taskfiles inherit `version`/`set` from the parent taskfile.yml, so taskfiles/zig.yml omits those (per user correction) and only declares `vars`/`tasks`.

Environment quirk (not a taskfile issue): this session's shell PATH has a stale hardcoded zig 0.14.0 install dir ahead of the mise shims, which caused a Mach-O linker failure (undefined symbols like _clock_gettime, _exit) when `zig build` picked up 0.14.0. Prepending the 0.16.0 install dir to PATH (or having correctly-ordered mise shims, as in a normal interactive shell) resolves it — no workaround needed in the taskfile itself.

Verified: task zig:build produces zig-out/bin/zelda3; task zig:parity runs it against zelda3.sfc and reports 'PARITY OK: zero RAM-compare mismatches'; task zig:clean removes zig-out/.zig-cache/; cmp zelda3 zelda3.bak shows byte-identical; git diff taskfile.yml shows only the added includes block, no changes to existing build/assets/clean tasks.

DoD #3 (reference-save replay of saves/ref/Chapter*.sav) left unverified here — no scripted/headless replay path exists yet (same gap noted in TASK-001.02); that verification belongs to TASK-001.04.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `taskfiles/zig.yml` providing four Zig-namespaced tasks — `zig:build` (`zig build`), `zig:run` (build + `zig build run`), `zig:clean` (`rm -rf zig-out .zig-cache`), and `zig:parity` (depends on `zig:build` + root `:assets`; runs the built binary against `zelda3.sfc` under a 10s timeout, greps stderr for `Memory compare failed`, and exits nonzero on any match or unexpected crash) — and wired it into `taskfile.yml` via a single `includes: { zig: taskfiles/zig.yml }` block.

**Scope discipline:** no existing tasks in `taskfile.yml` (`build`, `compile`, `assets`, `clean`, `clean:obj`, `clean:gen`, `install`, `link-res`) were touched; the diff is a 3-line addition.

**Verification:** `task zig:build` compiles clean and produces `zig-out/bin/zelda3`; `task zig:parity` reports "PARITY OK: zero RAM-compare mismatches" against `zelda3.sfc`; `task zig:clean` removes `zig-out/`/`.zig-cache/`; `cmp zelda3 zelda3.bak` confirms the C-built reference binary is untouched; `git diff taskfile.yml` shows only the added `includes` block.

**Correction applied during review:** initially included redundant `version`/`set` keys in `taskfiles/zig.yml` — removed since included taskfiles inherit these from the parent `taskfile.yml`.

**Deferred to TASK-001.04:** DoD #3 (scripted replay of `saves/ref/Chapter*.sav`) — no headless replay path exists yet, same gap already noted in TASK-001.02.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
