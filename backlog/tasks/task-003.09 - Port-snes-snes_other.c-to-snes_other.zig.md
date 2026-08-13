---
id: TASK-003.09
title: Port snes/snes_other.c to snes_other.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:20'
updated_date: '2026-08-13 16:27'
labels: []
dependencies:
  - TASK-003.08
modified_files:
  - build.zig
  - snes/snes_other.zig
parent_task_id: TASK-003
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/snes_other.c (misc SNES support) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is the last snes/ file before cpu.c/tracing.c, which stay as C oracle code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 snes_other.c is removed from the C build and snes_other.zig is compiled instead
- [x] #2 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
- [x] #3 snes/cpu.c and snes/tracing.c remain C and continue compiling as the RAM-compare oracle's CPU core
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Follow the established snes/*.zig port pattern (cart.zig, snes.zig from TASK-003.05-08):

1. Create snes/snes_other.zig:
   - File-header comment describing the port (mirrors snes_other.c: ROM header detection/scoring and snes_loadRom).
   - Local `Snes` extern struct mirroring struct Snes in snes.h truncated to the `cart` field (snes_loadRom only touches snes->cart plus calls snes_reset separately) — same truncation convention cart.zig/snes.zig already use.
   - Opaque Cpu/Apu/Ppu/Dma/Cart placeholders (this file never dereferences them).
   - extern fn declarations for cart_load (from cart.zig) and snes_reset (from snes.zig), both callconv(.c).
   - Local (non-exported) CartHeader struct translating the C one field-for-field.
   - Private `readHeader` fn translating the static C helper 1:1, using [*]const u8 for the raw byte buffer (matches C's raw-pointer arithmetic, including the location-relative negative offsets for v2/v3 header fields).
   - `pub export fn snes_loadRom(snes: *Snes, data: [*]u8, length: c_int) bool` translating the body 1:1: 4-candidate header scoring, pick max score, headered-ROM offset adjustment, power-of-2 expansion via malloc + the existing repeated-halves padding loop, cart_load, snes_reset(snes, true), free.
   - Use Zig builtins (@memcpy/@memset) instead of externing memcpy/memset, matching cart.zig's style.
2. Wire into build.zig:
   - Remove "snes/snes_other.c" from the `sources` list.
   - Add `exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "snes_other", "snes/snes_other.zig"));` alongside the other snes/*.zig lines.
   - No entry needed in unit_test_files (snes.zig itself has none either — this is glue code exercised via the full RAM-compare/replay flow, not isolated unit tests, consistent with TASK-003.08's precedent).
3. Verification (per DoD):
   - `task zig:build` (or equivalent) compiles clean.
   - Run ./zelda3 zelda3.sfc headless (sway/wtype per AGENTS.md) and grep stderr for zero "Memory compare failed" lines.
   - Replay reference saves (saves/ref/Chapter*.sav via F5/F6 hotkeys) stays clean.
   - Confirm snes_other.c/.o no longer referenced by the C build and taskfile.yml's C-only build path still works untouched.
4. Delete snes/snes_other.c and snes/snes_other.o once the Zig object is wired in and verified (git tracks the removal; .o is gitignored build output).

Correction after inspecting the classic taskfile.yml build: it deliberately still compiles the original snes.c (from TASK-003.08) unmodified — that file was never deleted; only build.zig's `sources` list and addObjectFile wiring changed (confirmed via `git show c38608c --stat`: only build.zig + new snes.zig, no deletion). DoD #5 ('the C taskfile.yml build remains untouched and working') depends on this — the legacy build's SOURCES var / compile-zig-* deps in taskfile.yml were never touched for dma/dsp/spc/ppu/snes either. So step 4 of the original plan (deleting snes_other.c/.o) is WRONG and is dropped: snes_other.c stays in the tree, dead from build.zig's perspective but still compiled by the legacy `task build` path, matching precedent exactly.

Also noting TASK-003.08 shipped with real bugs (shift-amount overflow, opaque-pointer field access, dropped behavioral logic) caught only in a later fix commit (c8172f4) after being marked Done — so verification here must actually run `zig build` plus `task zig:parity` (and ideally `task zig:parity-replay`), not just trust a clean compile.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verification run (2026-08-13): `zig build` clean; `task zig:parity` -> 'PARITY OK: zero RAM-compare mismatches'; `task zig:parity-replay` -> 'PARITY-REPLAY OK: zero RAM-compare mismatches across 13 reference-save replays' (all saves/ref/Chapter*.sav). Also ran the classic `task build` (C-only path) from a clean object tree to confirm it still compiles/links snes_other.c/snes.c/etc. unmodified end-to-end (DoD #5) — taskfile.yml/taskfiles/ have zero diff. `zig fmt --check`, `task zig:ast-check`, and `zig build test` all pass with no output/errors.

Design note: snes_loadRom only ever touches snes->cart (passed straight to cart_load) and calls snes_reset separately, so the local Snes mirror in snes_other.zig is truncated to just the leading cpu/apu/ppu/dma/cart pointer fields — same truncation convention cart.zig and snes.zig already established. CartHeader is a plain (non-extern) Zig struct since it never crosses the C ABI.

Caught two behavioral-parity risks that TASK-003.08's port missed initially (see fix commit c8172f4) and fixed them up front here: (1) the header-size shift `0x400 << byte` needs the shift amount truncated to 5 bits (matches C's UB-but-hardware-real x86 SHL masking) rather than a Zig shift-amount-too-large panic; (2) the checksum+checksumComplement overflow check needed explicit u32 widening — C promotes both uint16_t operands to int before adding (so it never wraps at 16 bits), whereas a naive Zig u16 add would panic/wrap on overflow.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported snes/snes_other.c (ROM header detection/scoring + snes_loadRom) to snes/snes_other.zig, following the established snes/*.zig port pattern from TASK-003.05-08 (cart.zig, snes.zig).

**What changed:**
- New `snes/snes_other.zig`: translates `readHeader` (private helper, 4-candidate SNES header scoring/detection) and `pub export fn snes_loadRom` 1:1, including the power-of-2 ROM-size expansion and repeated-halves padding loop. Uses a local `Snes` extern struct truncated to just the `cart` field (the only one this file touches), matching cart.zig/snes.zig's truncated-mirror convention. `CartHeader` is a plain internal Zig struct (never crosses the C ABI). Two subtle correctness fixes applied proactively (see implementation notes): 8-bit-to-shift-amount truncation for the `0x400 << x` size calculations, and u32-widened checksum overflow check to match C's int-promotion semantics instead of wrapping at 16 bits.
- `build.zig`: removed `"snes/snes_other.c"` from the C `sources` list; added `addPortedModuleAt(b, target, optimize, "snes_other", "snes/snes_other.zig")` alongside the other ported snes/*.zig modules.

**What did not change (by design):** `snes/snes_other.c` itself is left in the tree, matching the precedent set by TASK-003.08 (`snes.c` was never deleted either) — it's dead code from build.zig's perspective but still compiled unmodified by the legacy `task build` (classic taskfile.yml) C-only path, which was not touched. `snes/cpu.c` and `snes/tracing.c` remain C, unaffected.

**Tests run:**
- `zig build` — clean.
- `task zig:parity` — zero RAM-compare mismatches against the original ROM's machine code.
- `task zig:parity-replay` — zero RAM-compare mismatches across all 13 saves/ref/Chapter*.sav reference-save replays (headless sway/wtype/grim).
- `task build` (classic C-only path, from a clean object tree) — compiles and links successfully using the untouched original snes_other.c/snes.c/etc., confirming the legacy build still works.
- `zig fmt --check`, `task zig:ast-check`, `zig build test` — all pass with no findings.

No follow-up risks identified; this was the last snes/ file scheduled for porting before cpu.c/tracing.c (which intentionally stay C as the RAM-compare oracle's CPU core per the parent TASK-003 scope).
<!-- SECTION:FINAL_SUMMARY:END -->
