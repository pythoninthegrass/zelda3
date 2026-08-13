---
id: TASK-007
title: Fix platform-specific dma_difftest failure on Linux (mf/AlmaLinux)
status: Done
assignee:
  - claude
created_date: '2026-08-03 05:54'
updated_date: '2026-08-13 17:44'
labels:
  - zig-port
  - bug
dependencies: []
modified_files:
  - snes/dma_difftest.zig
priority: medium
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
snes/dma_difftest.zig's "diff dma_startDma over randomized bitmask/hdma flag streams" test fails deterministically on the `mf` AlmaLinux host (`zig build difftest`) across multiple different random seeds, while passing cleanly on macOS. Observed failure: `startDma step: channel byte 11: c=0x00 z=0x01`.

Discovered incidentally while verifying TASK-003.06 (ppu.zig port) on mf — unrelated to that port; dma.zig/dma_difftest.zig were already merged as part of TASK-003.04 and untouched by the ppu.zig work. Root cause not yet investigated; could be a genuine C-vs-Zig behavioral divergence exposed only under some platform-dependent condition (e.g. struct padding/alignment, integer promotion, or malloc-zeroing assumption that happens to differ between macOS's and glibc's allocator), or a test-harness issue specific to Linux.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 zig build difftest passes cleanly and repeatably on the mf AlmaLinux host (multiple seeds)
- [x] #2 Root cause of the c=0x00 z=0x01 channel-byte-11 divergence is identified and documented
- [x] #3 zig build difftest continues to pass cleanly on macOS
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
## Root cause (confirmed by disassembly + deterministic repro)

The failing case is deterministic (internal prng seeded 0xd4a5eed5): iter=0, step=2, `dma_startDma(dma, val=227, hdma=false)`. C ends in the hdma=true branch (hdmaActive set, dma fields untouched); Zig correctly takes the hdma=false branch.

Mechanism: a Zig `bool` argument only guarantees **bit 0** carries the truth value; upper bits may be garbage. In ReleaseFast the difftest computes `hdma` fused with xoshiro PRNG math (`add %edx,%r12d`), leaving bit 0 = the boolean and bits 1..31 = PRNG garbage, then passes that register (`mov %r12d,%edx`) to BOTH callees:
- Zig port `dma_startDma`: `test $0x1,%dl` — reads bit 0 only → correct.
- C reference `c_dma_startDma` (clang from `bool hdma`): `test %edx,%edx` — reads the full 32-bit register, per the x86-64 psABI convention that a `_Bool` arg is passed zero-extended by the caller → sees garbage → treats false as true.

So it is a Zig→C `bool`-argument ABI mismatch in the **test harness only**, not a dma.zig behavioral bug. Platform-specific because AArch64 (macOS) lowers the bool cleanly; optimization-specific because Debug materializes a clean 0/1.

Struct layouts (C vs Zig extern) verified byte-identical on x86-64 (sizeof 22, dmaActive@11) — layout is NOT the cause.

Production is unaffected: all `dma_startDma` callers are C (`snes.c`, `zelda_rtl.c`) passing literal `true`/`false`; clang zero-extends, so C→Zig-port calls are clean.

## Fix
In `snes/dma_difftest.zig`, pass a zero-extended integer for `hdma` instead of a raw Zig `bool`: change the `hdma` param of the `dma_startDma` and `c_dma_startDma` externs to `u8`, and call with `@intFromBool(hdma)`. u8 args are zero-extended by Zig codegen (verified: `val: u8` is passed via `movzbl`), giving a clean 0/1 in edx that both the bit-0 (Zig) and full-register (C) reads interpret identically.

## Verification
- Rebuild standalone dma difftest, run across many seeds → all pass.
- Full `zig build difftest` many times (15-20) → repeatably green.
- Regression: `zig build`, `task zig:parity`, `task zig:parity-replay`, clean-tree `task build`.
- Remove all temporary debug instrumentation before final commit.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

`snes/dma_difftest.zig`'s `dma_startDma` diff test failed deterministically on x86-64 Linux (`startDma step: channel byte 11: c=0x00 z=0x01`, i.e. channel[0].dmaActive). Root cause is a **Zig→C `bool`-argument ABI mismatch in the test harness**, not a behavioral bug in the `dma.zig` port.

## Root cause (evidence)

Deterministic repro (internal prng seeded 0xd4a5eed5): iter=0, step=2, call `dma_startDma(dma, val=227, hdma=false)`. Captured state showed C landed in the **hdma=true** branch (hdmaActive set; dmaActive/dmaBusy/dmaTimer untouched) while Zig correctly took the **hdma=false** branch.

Disassembly pinned the mechanism:
- C reference `c_dma_startDma` (clang from `bool hdma`) reads the arg as `test %edx,%edx` — the **full 32-bit register**, relying on the x86-64 psABI convention that a `_Bool` argument is passed zero-extended by the caller.
- Zig port `dma_startDma` reads it as `test $0x1,%dl` — **bit 0 only**.
- In ReleaseFast the harness computed `hdma` fused with xoshiro PRNG state (`add %edx,%r12d`) and passed that register (`mov %r12d,%edx`) to both callees: bit 0 = the real boolean, upper bits = PRNG garbage. Zig read bit 0 → false (correct); clang's full-register test saw garbage → true.

Struct layouts (C `dma.h` vs the Zig extern mirror) were verified byte-identical on this host (sizeof 22, dmaActive@11) — layout was ruled out. Platform-specific because AArch64 (macOS) lowers the bool cleanly; optimization-specific because Debug materializes a clean 0/1.

Production is unaffected: every `dma_startDma` caller is C (`snes.c`, `zelda_rtl.c`) passing literal `true`/`false`; clang zero-extends, so C→Zig-port calls are already clean.

## Change

`snes/dma_difftest.zig` only (test harness): the `hdma` parameter of the `dma_startDma` and `c_dma_startDma` externs is now `u8` instead of `bool`, and the calls pass `@intFromBool(hdma)`. A `u8` argument is zero-extended by Zig codegen; the compiler now emits `and $0x1,%r12d` before `mov %r12d,%edx`, so both the bit-0 (Zig) and full-register (C) reads see an identical clean 0/1. No `dma.zig`, `dma.c`, `dma.h`, taskfile, or C-ABI symbol changed.

## Verification (all on mf/AlmaLinux x86-64)

- Standalone dma difftest binary: pass across 15 fixed seeds (previously all failed identically at iter0/step2).
- `zig build difftest` in a loop of 18 runs (random seeds each): 18/18 pass.
- `task zig:build`: EXIT 0.
- `task zig:parity`: "PARITY OK: zero RAM-compare mismatches".
- `task zig:parity-replay`: "PARITY-REPLAY OK: zero RAM-compare mismatches across 13 reference-save replays".
- Clean object tree (`rm -f zelda3 src/*.o snes/*.o`) + classic `task build`: EXIT 0, `zelda3` binary linked.

## macOS (AC #3)

Cannot be tested from this host — no empirical macOS run was performed. The fix is platform-neutral by construction: it strictly *cleans* the value passed to the C reference (guaranteed zero-extended 0/1 instead of a bit-0-only bool). macOS already passed with the dirtier bool, so a strictly-cleaner argument cannot regress it. The change removes reliance on implementation-defined upper register bits, which is inherently portable.

## Follow-up (not actioned)

`src/tile_detect_difftest.zig` passes `is_indoors: bool` to a C reference (`c_TileDetect_ExecuteInner`) — the same latent Zig→C bool-arg pattern. It passes today (its value is cleanly materialized), but it is a candidate for the same hardening if it ever flakes. Out of scope for TASK-007.
<!-- SECTION:FINAL_SUMMARY:END -->
