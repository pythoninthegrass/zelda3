---
id: TASK-006
title: >-
  Fix macOS zig build/difftest blockers (undefined _stderr, objcopy symbol
  renaming)
status: In Progress
assignee: []
created_date: '2026-08-03 03:12'
updated_date: '2026-08-03 03:13'
labels: []
dependencies: []
references:
  - snes/apu.zig
  - src/config.zig
  - build.zig
  - taskfile.yml
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
- [ ] #1 `task build` (or `zig build`) links the full zelda3 binary cleanly on macOS with no undefined-symbol errors
- [ ] #2 `zig build difftest` runs to completion on macOS for all existing Tier-B differential test targets (util, poly, cart, apu, tile_detect, config, input, sdl_keyname), producing correctly-renamed C reference objects with no duplicate-symbol link errors
- [ ] #3 Fix does not change behavior or build output on Linux (mf host) or break the existing zig:parity / zig:parity-replay verification there
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Verified on a clean macOS checkout (not just mf/Linux) that both `task build` and `zig build difftest` complete without the errors described above
- [ ] #3 No regression on the mf Linux host: task build, zig:parity, and zig:parity-replay still pass there after the fix
<!-- DOD:END -->
