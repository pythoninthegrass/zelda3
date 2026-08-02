---
id: TASK-002.04
title: Port src/config.c to config.zig
status: To Do
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 18:17'
labels: []
dependencies:
  - TASK-002.03
parent_task_id: TASK-002
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/config.c (INI config parsing for zelda3.ini) to idiomatic Zig, following the pattern established by the util.c port: same C-ABI exported symbols, no changes required to callers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 config.c is removed from the C build and config.zig is compiled instead
- [ ] #2 zelda3.ini parsing behavior is unchanged (all documented settings still take effect)
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

## Comments

<!-- COMMENTS:BEGIN -->
author: supervisor
created: 2026-08-02 18:17
---
## Supervisor fix request (2026-08-02, after 2 attempts: turn-exhaustion then a well-diagnosed BAIL)

Attempt 2 did solid work and left a correct diagnosis: the port (config.zig), Tier-A tests, and build.zig/taskfile.yml wiring are all green and should NOT be redone. The ONLY red gate was zig:difftest, and the root cause is a real latent bug in the ORIGINAL config.c, faithfully preserved by the port -- do not "fix" it, the byte-for-byte RAM-compare oracle requires matching the original exactly:

KeyMapHash_Add increments keymap_hash_size before walking the duplicate-key chain, so every rejected duplicate key leaks one dead entry. Each ParseConfigFile call inserts ~130 keys (most of them duplicates across sections), so each call leaks ~130 entries and the backing table grows/reallocs every ~2 calls. In the REAL game this never matters -- ParseConfigFile runs exactly ONCE per process. But config_difftest.zig calls ParseConfigFile in a loop, accumulating state across N randomized-ini iterations in a single process, and after ~5-6 cumulative calls (~780 accumulated entries) the table corrupts/overwrites live entries -- in BOTH the C reference and the Zig port identically, confirming the port is faithful and the harness is the problem.

FIX: restructure config_difftest.zig so each randomized-ini comparison starts from FRESH keymap/joymap state, matching how ParseConfigFile is actually used in production (once per process) -- do not accumulate calls in a shared process. The cleanest options, in order of preference:
1. Fork/exec a fresh child process per iteration (or per small batch) so the hash tables start zeroed each time -- mirrors real usage exactly.
2. If a reset function is cheap to add on BOTH sides symmetrically (Zig port AND the renamed C reference object), add an explicit KeyMapHash/joymap reset call between iterations instead of re-exec -- but only if it can be added identically to both sides without touching the ported logic itself.
Do NOT paper over this by just lowering the iteration count further (attempt 2 already found the corruption starts as early as parse 5-6, which is too low to give the differential test any real coverage) -- restructure so each iteration gets clean state instead.

Also: attempt 2 left the worktree dirty with temporary debug exports (dbg_keymap_size/dbg_keymap_ent/dbg_keymap_first/dbg_keymap_ptr in config.zig) and a scratch src/standalone_test.zig used for GDB-watchpoint investigation -- both were discarded with the worktree, so attempt 3 starts clean; no cleanup needed, just do not reintroduce them into the final commit.

Once zig:difftest is restructured and green, re-run zig:parity and zig:parity-replay (not yet run in either prior attempt) and task build before finishing.
---
<!-- COMMENTS:END -->
