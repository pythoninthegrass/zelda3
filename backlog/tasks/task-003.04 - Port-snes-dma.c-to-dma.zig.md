---
id: TASK-003.04
title: Port snes/dma.c to dma.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:19'
updated_date: '2026-08-03 04:20'
labels: []
dependencies:
  - TASK-003.03
parent_task_id: TASK-003
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port snes/dma.c (DMA/HDMA emulation — used both by the live renderer's g_zenv.dma and the RAM-compare oracle) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is live rendering code, so visual regressions surface immediately.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dma.c is removed from the C build and dma.zig is compiled instead
- [x] #2 DMA/HDMA-driven visual effects (gradients, raster effects) render identically
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Port snes/dma.c to dma.zig following the established cart.zig/apu.zig pattern:

1. snes/dma.zig: mirror Dma/DmaChannel structs from dma.h field-for-field (dma.h stays unchanged in place — src/zelda_cpu_infra.c does memcpy(..., sizeof(Dma)-offsetof(Dma,channel)) and src/zelda_rtl.c pokes DmaChannel fields directly via SimpleHdma_Init, so C-visible layout must be byte-identical). Mirror a partial Snes struct (openBus field only, like cart.zig's). Port all 10 exported fns (dma_init/free/reset/saveload/read/write/doDma/initHdma/doHdma/cycle/startDma) plus private dma_transferByte, calling snes_read/snes_write/snes_readBBus/snes_writeBBus as extern opaque bus callbacks (same pattern as apu.zig calling spc_*/dsp_*). Preserve exact wraparound arithmetic (post-increment offIndex/tableAdr/size semantics, unsigned wrap on aAdr -1, hdmaTimer -2 wrap).

2. snes/dma_test.zig (Tier-A): golden-value unit tests via exported functions only.

3. snes/dma_difftest.zig (Tier-B): renamed dma_c_ref (from snes/dma.c) diffed against dma.zig over randomized op streams. snes_read/write/readBBus/writeBBus don't exist as standalone objects, so implement them as `export fn` shims directly in the difftest file, backed by per-flavor fake memory buffers dispatched by comparing the passed Snes* pointer against the known C/Z fake-snes buffer addresses (both flavors call the same plain symbol names, unrenamed).

4. build.zig: add "dma" via addPortedModuleAt into the exe's object list, remove snes/dma.c from the `sources` list, add dma_test.zig/dma_difftest.zig to the test file lists, add a dma_c_ref via compileRenamedCRef with dma.h's function names.

5. Verify: zig build test, zig build difftest, task zig:build.

6. Run binary with zelda3.sfc loaded, watch stderr for zero RAM-compare mismatches; replay saves/ref/Chapter*.sav reference saves and confirm clean.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Recovery note: another agent's `git checkout --` accidentally reverted this file's In Progress/assignee/plan fields (a pre-existing uncommitted change from before this session). Recovered verbatim from this session's own transcript (the task_edit tool_use call is preserved there) and reapplied — no data lost.

build.zig wiring complete: dma.zig replaces dma.c in `sources`; dma_test.zig/dma_difftest.zig wired into unit_test_files/diff_test_files; dma_c_ref added via compileRenamedCRef (snes_read/write/readBBus/writeBBus left unrenamed, supplied by the difftest file's own pointer-identity-dispatched stubs, matching the apu.zig precedent).

zig build test: pass (fixed 11 var/const mutability nits in dma_test.zig, no logic bugs found). zig build difftest: pass clean on first run. task zig:build: compiles clean. task zig:parity (macOS, zelda3.sfc loaded, 10s run): PARITY OK, zero RAM-compare mismatches. dma.h untouched, taskfile.yml/zelda3.bak untouched (DoD #4/#5 confirmed via git diff).

DoD #3 (reference-save replay) blocked for now: the `mf` Linux host (192.168.8.69) used for task-003.03's headless sway+wtype+grim replay is currently unreachable (no route to host). macOS interactive fallback (osascript/System Events key injection) is also blocked in this session — not authorized to send Apple events to System Events. Will retry `task zig:parity-replay` on mf once reachable.

mf host was behind origin/master by 4 commits with stale pre-apu.zig WIP dirty state; stashed that WIP (kept, not dropped) and fast-forwarded to 0b3e32c, then rsynced local build.zig/dma.zig/dma_test.zig/dma_difftest.zig over. task zig:build (Linux/AlmaLinux): clean. task zig:parity: PARITY OK, zero RAM-compare mismatches. task zig:parity-replay (headless sway+wtype+grim, all 13 saves/ref/Chapter*.sav): PARITY-REPLAY OK, zero mismatches across all 13 chapters. All DoD items and acceptance criteria now verified; closing task.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported snes/dma.c (DMA/HDMA emulation) to snes/dma.zig, matching every C-ABI symbol name/signature so remaining .c callers (snes.c, src/zelda_cpu_infra.c, src/zelda_rtl.c) link unchanged.

Key implementation details:
- `Dma`/`DmaChannel` extern structs mirror dma.h field-for-field (byte-identical layout required: zelda_cpu_infra.c does `memcpy(..., sizeof(Dma) - offsetof(Dma, channel))` and zelda_rtl.c's SimpleHdma_Init pokes DmaChannel fields directly).
- Partial `Snes` mirror struct (openBus field only), matching the cart.zig/apu.zig precedent.
- snes_read/snes_write/snes_readBBus/snes_writeBBus (owned by not-yet-ported snes.c) declared as plain `extern fn`, resolved by whatever object supplies them at link time.
- All 10 exported functions plus private dma_transferByte ported 1:1, preserving C's unsigned wraparound arithmetic (`+%=`/`-%=`) and post-increment-in-expression semantics (offIndex++, tableAdr++, size++).

Testing:
- snes/dma_test.zig (Tier-A, 13 unit tests): pass.
- snes/dma_difftest.zig (Tier-B, differential vs renamed dma_c_ref over randomized op streams, pointer-identity-dispatched bus stubs): pass.
- zig build test / zig build difftest: clean on both macOS and mf (AlmaLinux).
- task zig:build: clean on both hosts.
- task zig:parity (zelda3.sfc loaded): zero RAM-compare mismatches on both hosts.
- task zig:parity-replay (mf, headless sway+wtype+grim, all 13 saves/ref/Chapter*.sav): zero RAM-compare mismatches across all 13 chapters.

build.zig wiring: dma.zig replaces dma.c in the sources list; dma_test.zig/dma_difftest.zig added to the unit/diff test file lists; dma_c_ref added via compileRenamedCRef (11-symbol rename list; snes_read/write/readBBus/writeBBus left unrenamed since both flavours share the difftest file's own stubs).

dma.h and taskfile.yml untouched; zelda3.bak unaffected.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
