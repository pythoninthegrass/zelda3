---
id: TASK-002.04
title: Port src/config.c to config.zig
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 20:39'
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
- [x] #1 config.c is removed from the C build and config.zig is compiled instead
- [x] #2 zelda3.ini parsing behavior is unchanged (all documented settings still take effect)
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
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

author: supervisor
created: 2026-08-02 19:57
---
## Supervisor fix request (2026-08-02, after 4 attempts: all converge on the same design, all run out of turns near the finish line)

Every attempt independently lands on the SAME correct design and gets the port + Tier-A tests + build wiring green, but the Tier-B differential-test harness (needed to dodge the real KeyMapHash_Add duplicate-leak bug in the original config.c under repeated in-process ParseConfigFile calls -- see the prior fix-request comment, still valid, do not re-diagnose it) keeps eating the full 150-turn budget fighting Zig 0.16 API churn. This is now a turn-budget problem, not a design problem: BURN_MAX_TURNS has been raised for this resume, and this comment distills the FULLY VALIDATED design from two near-complete attempts so you can implement it directly instead of rediscovering it.

VALIDATED DESIGN for config_difftest.zig (fresh process per randomized-ini iteration):

1. The test binary re-execs ITSELF via /proc/self/exe with env vars ZELDA3_CFG_WORKER=c|z and ZELDA3_CFG_INI=<path>. Put the dispatch check in the FIRST-declared test in the file (Zig runs tests in declaration order) -- it checks getenv("ZELDA3_CFG_WORKER"), and if set, runs ParseConfigFile (C or Zig flavour per the env value) and dumps results via libc fprintf, then calls _exit() directly. This means a custom test runner is NOT needed -- the env-var short-circuit in the first test is sufficient and simpler than trying to write a custom runner (one earlier attempt tried a custom runner and it was more complex than necessary).

2. For output, use libc directly: extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int; extern fn fflush(stream: ?*anyopaque) c_int; extern var stdout: *anyopaque; extern fn _exit(status: c_int) noreturn; Do NOT use std.fs.File.stdout() (does not exist in 0.16), std.io.bufferedWriter, or ArrayList.writer (removed) -- all of these were dead ends in prior attempts. Dump g_config as a hex byte string plus the FindCmdForSdlKey/FindCmdForGamepadButton probe matrix (keycodes x modifiers, gamepad buttons x modifiers) via fprintf, then fflush(stdout) before returning.

3. Parent test process spawns two child processes per randomized ini (one with ZELDA3_CFG_WORKER=c, one =z) via libc fork/exec or popen (std.process.Child's API requires an Io handle in 0.16 and was a dead end in every attempt -- do not use it), captures each child's stdout, and diffs the two dumps byte-for-byte.

4. objcopy --redefine-sym only renames DEFINED symbols in the object being renamed -- it does NOT rename that object's own references to symbols defined elsewhere. If config_c_ref (the renamed config.c) calls util.c helper functions (NextDelim, StringEqualsNoCase, etc.), you must EITHER add those same util symbol names to config_c_ref's own rename list (so its call-sites point at c_* to match a correspondingly-renamed util reference object), OR link a matching renamed util_c_ref object that defines the same c_*-prefixed names. Get this wrong and the C-flavour child fails to link with undefined symbols.

5. config.zig should declare the util helper functions it needs as plain extern fn declarations rather than importing util.zig as a Zig module -- this avoids duplicate-export-shape problems when config.zig and util.zig are each compiled as separate objects (via b.addObject()) and linked together into the exe.

6. Any additional Zig module linked as a second ported unit (config.zig here) goes into the build via b.addObject(...) + exe.root_module.addObjectFile(obj.getEmittedBin()) -- a plain anonymous @import is NOT analyzed as its own compilation unit for this purpose in Zig 0.16.

7. The PARENT config_difftest.zig test binary itself imports config.zig (for the in-process ParseBool/FindCmd fixed-spelling checks that don't need process isolation) -- that parent binary needs its OWN plain (non-renamed) util object linked in too, or config.zig's plain util externs go unresolved in the parent. This was the single missing piece in the closest-to-passing attempt.

Gate status confirmed stable across multiple independent attempts (do not need rechecking, just keep green): task zig:build, task zig:test. Focus all effort on finishing config_difftest.zig with the design above, run task zig:difftest to green, then task zig:parity, task zig:parity-replay (~3 min, let it finish), task build, then the backlog CLI check-offs and commit.
---
<!-- COMMENTS:END -->
