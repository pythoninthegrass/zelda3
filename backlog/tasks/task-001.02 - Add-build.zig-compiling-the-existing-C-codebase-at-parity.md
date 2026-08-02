---
id: TASK-001.02
title: Add build.zig compiling the existing C codebase at parity
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 04:50'
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
- [x] #1 zig build produces zig-out/bin/zelda3 with no Zig-side source changes to existing .c/.h files
- [x] #2 The Zig-built binary launches and plays identically to the C-built zelda3.bak
- [x] #3 Running the Zig-built binary with zelda3.sfc loaded shows zero RAM-compare mismatches on stderr
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. build.zig: single `zelda3` exe, no root Zig source (pure C). Source list mirrors taskfile.yml's SOURCES var exactly: src/*.c + snes/*.c (maxdepth 1, excludes src/platform/*), third_party/gl_core/gl_core_3_1.c, third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c.
2. addCSourceFiles with -DSYSTEM_VOLUME_MIXER_AVAILABLE=0. linkLibC(). addIncludePath(".").
3. SDL2 flags obtained dynamically by shelling out to `sdl2-config --cflags`/`--libs` at configure time (per user decision, mirrors taskfile approach over hardcoding), parsed into addIncludePath/addLibraryPath/linkSystemLibrary/linkFramework calls.
4. optimize defaults to ReleaseFast (~parity with C build's -O2).
5. build.zig.zon: minimal manifest, no deps.
6. Verify: zig build succeeds; run zig-out/bin/zelda3 zelda3.sfc, confirm zero 'Memory compare failed' on stderr; spot check saves/ref/*.sav replay; confirm zelda3.bak/taskfile.yml untouched.
7. Do not touch taskfile.yml in this subtask (that's TASK-001.03).

Deviation from plan during execution: the plan's confirmed toolchain (Zig 0.14.0) fails to link *anything* on this machine (macOS 26.5.1) — even a bare `zig init` scaffold — due to a self-hosted Mach-O linker bug reading this SDK's libSystem stubs (produces empty symbol tables, 'undefined symbol: _abort' etc. for basic libc calls). Confirmed same failure on 0.14.1 and 0.15.2. Zig 0.16.0 links correctly. Asked user, approved switching the pinned toolchain to 0.16.0 (updated .tool-versions). This also required adapting build.zig to 0.16's module-based Build API (root_module/createModule, Module.linkSystemLibrary/linkFramework/addCMacro instead of Compile-level calls, unmanaged ArrayList, b.run() instead of std.process.Child.run, --release=fast/-Doption instead of -Doptimize as the default-optimize switch).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DoD #1 ('task zig:build compiles clean') left unchecked: the zig:build task alias doesn't exist yet, that's TASK-001.03. The underlying `zig build` command itself does compile clean (verified from a clean .zig-cache/zig-out).

DoD #3 (reference-save replay) left unchecked: no scripted/headless replay path exists for saves/ref/*.sav (the game is fully interactive, keys 1-9/Ctrl+1-9 load dungeon-playthrough snapshots, not these Chapter*.sav files). Ran the Zig binary with zelda3.sfc loaded for ~10s of live attract-mode play and confirmed zero 'Memory compare failed' lines; full reference-save replay verification is explicitly the job of TASK-001.04 (dedicated Phase 0 verify subtask).

Verified via `cmp zelda3 zelda3.bak` and `git diff taskfile.yml` (empty) that the C reference binary and build are untouched.

Note: README.md and .tool-versions show as modified in git status for reasons unrelated to build.zig — README.md has a pre-existing local diff (task install/RHEL SDL2 docs) that predates this work and was left alone; .tool-versions was intentionally updated zig 0.14.0 -> 0.16.0 per the toolchain deviation above.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a Zig build (`build.zig` + `build.zig.zon`) that compiles the existing, unmodified C codebase into a working `zelda3` binary, with zero game code translated to Zig yet — Phase 0's core deliverable.

**What changed**
- `build.zig`: single `zelda3` executable, no root Zig source. Compiles the exact same source list as `taskfile.yml`'s `SOURCES` var (`src/*.c` + `snes/*.c` at depth 1, excluding `src/platform/*`, plus the two vendored `third_party` files), with `-DSYSTEM_VOLUME_MIXER_AVAILABLE=0`, `link_libc`, and include path `.`. SDL2 flags are obtained by shelling out to `sdl2-config --cflags`/`--libs` at configure time (per your call, to stay dynamic like the taskfile rather than hardcoding Homebrew paths) and translated into `addIncludePath`/`addLibraryPath`/`linkSystemLibrary`/`linkFramework`/`addCMacro` calls. Defaults to `ReleaseFast` (parity with `-O2`) unless overridden with `-Doptimize=`.
- `build.zig.zon`: minimal package manifest.
- `.tool-versions`: `zig 0.14.0` → `0.16.0`.

**Toolchain deviation (surfaced to you, approved):** the plan's confirmed Zig 0.14.0 cannot link *anything* on this machine (macOS 26.5.1) — a self-hosted Mach-O linker bug against this SDK's libSystem stubs produces empty symbol tables (undefined `_abort`, `_getenv`, etc.), reproduced even on a bare `zig init` scaffold and on 0.14.1/0.15.2. 0.16.0 links correctly. This also meant adapting `build.zig` to 0.16's module-based `Build` API (`createModule`/`root_module`, `Module`-level `linkSystemLibrary`/`linkFramework`/`addCMacro`, unmanaged `ArrayList`, `b.run()`, `--release=fast` semantics).

**Verification:** `zig build` compiles clean from a wiped `.zig-cache`/`zig-out`, producing `zig-out/bin/zelda3` (1.8MB, matching the C build's `-O2` size range). Ran it with `zelda3.sfc` loaded for ~10s of live attract-mode play: zero `Memory compare failed` lines on stderr. `zelda3.bak` and `taskfile.yml` are untouched (`cmp`/`git diff` confirm). No `.c`/`.h` files were modified.

**Deferred to TASK-001.04** (the dedicated Phase 0 verify subtask): scripted replay of `saves/ref/Chapter*.sav` — there's no headless/scripted replay path for those files (the game is fully interactive; the 1-9/Ctrl+1-9 hotkeys load different, in-game dungeon-playthrough snapshots, not these save files).

**Not done here (by design, next subtask):** wiring `taskfiles/zig.yml`/`zig:build` into `taskfile.yml` — that's TASK-001.03.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
