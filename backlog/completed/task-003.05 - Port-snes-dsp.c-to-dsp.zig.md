---
id: TASK-003.05
title: Port snes/dsp.c to dsp.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:20'
updated_date: '2026-08-03 04:55'
labels: []
dependencies:
  - TASK-003.04
modified_files:
  - build.zig
  - snes/dsp.zig
  - snes/dsp_test.zig
  - snes/dsp_difftest.zig
parent_task_id: TASK-003
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/dsp.c (audio DSP emulator) to idiomatic Zig, matching C-ABI symbols so callers link unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dsp.c is removed from the C build and dsp.zig is compiled instead
- [x] #2 Audio output (music/SFX mixing) is unaffected
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Scope: only build.zig + 3 new snes/dsp*.zig files. dsp.c/dsp.h/taskfile.yml stay untouched (mirrors the TASK-003.04 dma.zig precedent: dma.c/dma.h/taskfile.yml were never modified there either — the legacy `task build` C path keeps compiling dsp.c forever; only build.zig's Zig-native exe build swaps to the port).

1. snes/dsp.zig (new): port dsp.c/dsp.h faithfully.
   - extern struct DspChannel and extern struct Dsp mirroring dsp.h field-for-field (byte-identical layout required for saves/ref/Chapter*.sav binary compatibility, same rationale as dma.zig).
   - Port rateValues[32] and gaussValues[512] const tables verbatim.
   - Port dsp_init/free/reset/cycle/read/write/getSamples/saveload as `pub export fn` with identical C-ABI signatures, plus internal helpers (cycleChannel, handleEcho, handleGain, decodeBrr, getSample, handleNoise) as plain fns.
   - dsp.c has `#define MY_CHANGES 1` gating two `#if` branches: the `#if !MY_CHANGES` dead block in dsp_cycleChannel (old deferred keyon/off-on-even-cycle timing) is DROPPED — it never compiles today. Only the `#if MY_CHANGES` immediate keyon/off-on-write behavior (in dsp_write's KON/KOF cases) is ported.
   - Register address dispatch in dsp_write ported using the same address values as dsp_regs.h's DspReg enum (V0VOLL=0x00 .. FIR7=0x7F).
   - extern fn malloc/free (like dma.zig); dead-code `pub fn main() callconv(.c) c_int { return 0; }` stub for Zig 0.16 std.start (same as dma.zig/input.zig).
2. snes/dsp_test.zig (new, Tier-A): unit tests against dsp.zig directly using a local `apu_ram` buffer — dsp_init/free, dsp_reset defaults (ENDX=0xff etc.), dsp_write/read register decode across the volume/pitch/srcn/adsr/gain/master/echo/KON/KOF/FLG/ENDX/EFB/PMON/NON/EON/DIR/ESA/EDL/FIR groups, dsp_cycle sample generation + clamping, dsp_saveload byte range (ram-offset to end), dsp_getSamples mono/stereo resampling.
3. snes/dsp_difftest.zig (new, Tier-B): randomized op-stream diff against a preprocessor-renamed dsp_c_ref (dsp.c compiled with -Dfoo=c_foo over its 8 entry points). No bus stub needed (dsp only touches an apu_ram buffer passed by pointer, no cross-module externs) — each flavor gets its own apu_ram copy seeded with the same random bytes, diffed after each op alongside the Dsp struct state.
4. build.zig: remove "snes/dsp.c" from `sources`; add `exe.root_module.addObjectFile(addPortedModuleAt(b, target, optimize, "dsp", "snes/dsp.zig"))`; add dsp_test.zig/dsp_difftest.zig to unit_test_files/diff_test_files; add dsp_ref = compileRenamedCRef(..., "snes/dsp.c", &.{dsp_init, dsp_free, dsp_reset, dsp_cycle, dsp_read, dsp_write, dsp_getSamples, dsp_saveload}) and wire the dsp_difftest.zig case; replace apu_difftest's `apu_dsp_obj = compileCStub(dsp.c)` with the ported dsp module object (real behavior, shared by both apu flavors, same as before but now sourced from the port).

Verification (per DoD): `zig build`/`task zig:build`, `zig build test`/`task zig:test`, `zig build difftest`/`task zig:difftest`, `task zig:parity` (RAM-compare oracle) locally on macOS; `task zig:parity-replay` (all 13 saves/ref/Chapter*.sav) on the `mf` AlmaLinux host via ssh since it's Linux-only, per CLAUDE.local.md sync workflow. `task build` (legacy C path) also spot-checked to confirm it's genuinely untouched/still working.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported snes/dsp.c (S-DSP audio emulator: 8-channel BRR decode, Gaussian interpolation, ADSR/gain envelope state machine, pitch modulation, noise, 8-tap FIR echo) to snes/dsp.zig with identical C-ABI exports. build.zig now compiles dsp.zig into the Zig-native exe instead of dsp.c; dsp.c/dsp.h/taskfile.yml remain untouched so the legacy `task build` C path still compiles the original source unchanged.

Added snes/dsp_test.zig (Tier-A unit tests) and snes/dsp_difftest.zig (Tier-B randomized differential tests against a preprocessor-renamed dsp.c reference).

Two real C-to-Zig semantic bugs were found and fixed via the differential tests:
1. Gain envelope decay/sustain/exponential-decrease math used truncating division (`@divTrunc`) instead of C's arithmetic right-shift on a signed int, which differ for negative operands.
2. Pitch-modulation counter clamp incorrectly clamped negative results down to 0; C's actual semantics truncate to uint16_t and only clamp the upper bound (negative results wrap to large unsigned values that clamp up to 0x3fff, never down to 0).
3. A related bug in dspHandleGain: the post-switch attack-state clamp checked the (possibly just-mutated) adsrState field instead of the state value the switch actually dispatched on, so the clamp silently no-op'd on the exact cycle attack transitioned to decay.

Also found and fixed a test-harness bug (not a port bug): dsp_difftest.zig generated register addresses over the full u8 range (0-255), but real callers (snes/apu.c) only ever invoke dsp_write/dsp_read with addresses masked to 0x00-0x7F. Addresses >=0x80 caused dsp.c's `ram[adr]` (array size 0x80) to write out of bounds into adjacent struct memory — genuine undefined behavior in the pre-existing C code that the optimizer exploited inconsistently, manifesting as a phantom "port bug". Fixed by masking generated addresses to 0x7f, matching real hardware/caller behavior.

Verification: zig build / zig build test / zig build difftest clean; task zig:build/test/difftest clean; task zig:parity (RAM-compare oracle vs real ROM) reports zero mismatches; task zig:parity-replay on the mf AlmaLinux host replayed all 13 saves/ref/Chapter*.sav reference saves with zero RAM-compare mismatches; task build (legacy C path) compiles and links successfully with dsp.c/dsp.h/taskfile.yml untouched.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
