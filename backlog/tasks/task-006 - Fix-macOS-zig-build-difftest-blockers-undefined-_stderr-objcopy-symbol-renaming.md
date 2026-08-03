---
id: TASK-006
title: >-
  Fix macOS zig build/difftest blockers (undefined _stderr, objcopy symbol
  renaming)
status: Done
assignee:
  - claude
created_date: '2026-08-03 03:12'
updated_date: '2026-08-03 03:43'
labels: []
dependencies: []
references:
  - snes/apu.zig
  - src/config.zig
  - build.zig
  - taskfile.yml
modified_files:
  - build.zig
  - src/config.zig
  - src/config_difftest.zig
  - snes/apu_difftest.zig
  - snes/cart_difftest.zig
  - snes/input_difftest.zig
  - src/poly_difftest.zig
  - src/tile_detect_difftest.zig
  - src/util_difftest.zig
priority: medium
ordinal: 500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two independent, pre-existing macOS-only toolchain issues currently block verifying zig-ported modules end-to-end on macOS dev machines (confirmed present on unmodified master via `git stash`, unrelated to any specific port — surfaced while finalizing TASK-003.03, port of snes/apu.c to apu.zig).

1. **Undefined `_stderr` at link time.** `task build` / `zig build` fails linking the full `zelda3` binary with `Undefined symbols for architecture arm64: "_stderr"`, referenced from `config.o` (`ParseConfigFile` / `config.ParseOneConfigFile` in `src/config.zig`). macOS's libSystem exposes `__stderrp` and defines the `stderr` macro in terms of it rather than exporting a plain `stderr` symbol the way glibc does — `src/config.zig`'s extern reference to `stderr` needs to target the platform-correct symbol (likely via a small platform-specific extern shim, or by calling through a C helper) instead of assuming a directly linkable `stderr` global.
2. **`zig build difftest` fails via objcopy.** GNU `objcopy` is not installed/on PATH on macOS dev machines. `llvm-objcopy` (from Homebrew's `llvm` package) is present as a substitute, but its `--redefine-sym` does not actually rename symbols in Mach-O objects the way GNU objcopy does on ELF, producing "duplicate symbol definition" link errors for every Tier-B differential test target (e.g. `util_c_ref`, `poly_c_ref`, `cart_c_ref`, `apu_c_ref`, etc.) — none of them can currently run on macOS.

Both were confirmed via `git stash`/rebuild on clean master to reproduce identically with zero apu.zig changes present, so they are general build-tooling gaps, not specific to any one ported module.

Impact: macOS is currently unusable for verifying `task build` or `zig build difftest` for this project; all Tier-B (differential) test coverage and full-binary link verification for zig-ported modules has only ever been exercised on the `mf` Linux host.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `task build` (or `zig build`) links the full zelda3 binary cleanly on macOS with no undefined-symbol errors
- [x] #2 `zig build difftest` runs to completion on macOS for all existing Tier-B differential test targets (util, poly, cart, apu, tile_detect, config, input, sdl_keyname), producing correctly-renamed C reference objects with no duplicate-symbol link errors
- [x] #3 Fix does not change behavior or build output on Linux (mf host) or break the existing zig:parity / zig:parity-replay verification there
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Investigation findings (2026-08-02)

- Blocker 1 (_stderr): confirmed. `zig build` fails linking exe with `undefined symbol: _stderr` (18 refs from config.o). macOS libSystem has no `stderr` symbol; the C macro expands to `__stderrp`. Affects src/config.zig:25 and src/config_difftest.zig:43.
- Blocker 2 (objcopy): task premise was WRONG. Tested llvm-objcopy AND Homebrew GNU objcopy on Mach-O: both DO rename symbols (defs + undefined cross-TU refs) when given the leading-underscore Mach-O name (`--redefine-sym _foo=_c_foo`). build.zig:357 passes bare names -> no-op on Mach-O. `zig objcopy` (0.16.0) is broken here.
- Blocker 3 (not in task desc): config_difftest.zig is Linux-only — re-execs via /proc/self/exe (selfExePath, line 47). Needed for AC#2's `config` target on macOS. Other 6 difftests don't re-exec.

## Approved approach (decisions confirmed with Lance)

1. stderr: cross-platform resolver via `@extern` (`__stderrp` on Darwin, `stderr` else) in config.zig + config_difftest.zig; route fprintf call sites through it. No Linux behavior change.
2. Rename mechanism: DROP objcopy. Compile each C reference with `-D<sym>=c_<sym>` preprocessor flags using the SAME symbol lists -> identical symbol tables + link topology on ELF and Mach-O, no external objcopy dependency. Touches compileRenamedCRef + addRenamedSdlKeyStub in build.zig.
3. config_difftest self-exe: add macOS `_NSGetExecutablePath` branch to selfExePath (INCLUDED in this task per decision).

## Steps
1. config.zig: replace `extern var stderr` with stderrPtr() resolver; update 10 fprintf sites.
2. config_difftest.zig: same stderr resolver; add Darwin selfExePath branch.
3. build.zig: rewrite compileRenamedCRef to pass -D flags instead of objcopy; same for addRenamedSdlKeyStub. Remove now-dead objcopy plumbing.
4. Verify on macOS: `zig build` links clean (AC#1); `zig build difftest` runs all 7 targets (AC#2).
5. Verify on mf/Linux: task build, zig:parity, zig:parity-replay, zig build difftest still pass (AC#3).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Outcome (2026-08-02)

All three blockers resolved; both macOS and mf/Linux verify green.

### 1. Undefined `_stderr` (AC#1)
`src/config.zig` + `src/config_difftest.zig`: replaced `extern var stderr` with an inline `stderrPtr()` resolver using `@extern(*(*anyopaque), .{ .name = ... })` — `"__stderrp"` on Darwin, `"stderr"` elsewhere. Routed all fprintf call sites through it. `zig build` now links the full exe clean on macOS (exit 0). No Linux change (resolves the same `stderr` global there).

### 2. objcopy symbol renaming (AC#2)
Dropped objcopy entirely. `compileRenamedCRef` and the SDL key stub now rename via preprocessor `-D<sym>=c_<sym>` flags built from the same symbol lists. The preprocessor rewrites every token occurrence in the TU (definition + same-TU references), which matches objcopy's symbol-table rewrite (definitions + undefined cross-TU references) and works identically on ELF and Mach-O with no external tool. Removed all `addSystemCommand("objcopy")` plumbing; updated the objcopy-referencing comments across the 5 other difftest files.

### 3. config_difftest self-exe on macOS (AC#2, `config` target)
Added a Darwin branch to `selfExePath` using `_NSGetExecutablePath` (macOS has no `/proc/self/exe`); Linux path unchanged (guarded by `comptime builtin.os.tag.isDarwin()`).

### Plan deviation: latent apu_difftest bug surfaced
Running `zig build difftest` on macOS for the first time exposed a pre-existing, platform-independent logic bug in `snes/apu_difftest.zig`'s "diff saveload" test (added in the apu port, bec6296). `apu_saveload` invokes the callback three times (apu->ram, then dsp->ram, then spc->a); the callback overwrote a single `seen` slot, so it only ever held the LAST (spc, size 15) region, yet the test asserted `seen.data == &apu->ram`. That assertion can never hold on any platform. Rewrote the test to record the full region sequence and assert: first region == apu->ram, and C-vs-Zig region count + size sequence match. Verified this fixed test passes on BOTH macOS and mf/Linux (proving it was a test bug, not a real behavioral or macOS-specific difference; the C and Zig ports are structurally identical).

### Verification
- macOS: `zig build` exit 0 (exe linked); `zig build difftest` exit 0 (all targets: util, poly, cart, apu, tile_detect, config, input, sdl_keyname).
- mf/Linux: `zig build difftest` exit 0; `task build` exit 0; `zig:parity` zero mismatches; `zig:parity-replay` zero mismatches across all 13 reference-save replays.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed two pre-existing macOS-only toolchain blockers so zig-ported modules can be verified end-to-end on macOS (previously only possible on the mf Linux host).

**stderr link error:** `src/config.zig` and `src/config_difftest.zig` resolved `stderr` through a platform-aware `stderrPtr()` helper (`__stderrp` on Darwin via `@extern`, plain `stderr` elsewhere), fixing the `Undefined symbols: "_stderr"` full-binary link failure on macOS.

**objcopy symbol renaming:** Replaced the objcopy-based c_-prefix renaming in `build.zig` with preprocessor `-D<sym>=c_<sym>` flags (same symbol lists), which is tool-free and works identically on ELF and Mach-O. Removed all objcopy plumbing and corrected the mechanism comments in the 6 difftest files.

**config_difftest self-exe:** Added a macOS `_NSGetExecutablePath` branch to `selfExePath` so the config differential test's re-exec works without `/proc/self/exe`.

**apu_difftest fix (surfaced by first macOS difftest run):** The apu "diff saveload" test had a latent last-callback-wins bug — it asserted the recorded region equaled `apu->ram` but only ever kept the final (spc) region. Rewrote it to record and compare the full save-region sequence; now correct and passing on both platforms.

Verified green on macOS (`zig build`, `zig build difftest`) and on mf/Linux (`zig build difftest`, `task build`, `zig:parity`, `zig:parity-replay` — all zero RAM-compare mismatches). No behavior or output change on Linux.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Verified on a clean macOS checkout (not just mf/Linux) that both `task build` and `zig build difftest` complete without the errors described above
- [x] #3 No regression on the mf Linux host: task build, zig:parity, and zig:parity-replay still pass there after the fix
<!-- DOD:END -->
