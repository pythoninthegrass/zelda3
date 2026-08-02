---
id: TASK-002
title: Phase 1 — g_ram aliasing layer + first leaf files in Zig
status: Done
assignee: []
created_date: '2026-08-02 04:18'
updated_date: '2026-08-02 21:21'
labels: []
milestone: m-0
dependencies: []
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and implement the Zig equivalent of src/types.h and src/variables.h: the accessor layer over the flat g_ram[0x20000] byte array that ~1,037 C macros currently provide via pointer-cast aliasing (#define link_y_coord (*(uint16*)(g_ram+0x20))). This is the single gating design decision for the whole port — every later ported file depends on it, and it must preserve exact SNES WRAM offsets (including deliberately overlapping struct overlays) or the frame-by-frame RAM-compare oracle against the original ROM (src/zelda_cpu_infra.c) breaks. Once the accessor layer exists, port a handful of true leaf C files (few includes, self-contained) as proof: util.c, config.c, poly.c, tile_detect.c — each exporting the same C-ABI symbols so unported .c files keep linking unchanged.

Full plan context: /Users/lance/.claude/plans/i-m-interested-in-porting-polished-pizza.md
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
