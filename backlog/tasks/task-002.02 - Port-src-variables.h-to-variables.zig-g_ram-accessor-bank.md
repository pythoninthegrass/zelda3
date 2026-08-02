---
id: TASK-002.02
title: Port src/variables.h to variables.zig (g_ram accessor bank)
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 08:40'
labels: []
dependencies:
  - TASK-002.01
parent_task_id: TASK-002
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create variables.zig mirroring src/variables.h's ~1,037 macros of the form `#define name (*(type*)(g_ram+offset))`. g_ram itself stays defined in C (`extern uint8 g_ram[131072]` in zelda_rtl.c) during migration; Zig declares it `extern var g_ram: [0x20000]u8` and each macro becomes an inline accessor function, e.g. `pub inline fn link_y_coord() *align(1) u16 { return @ptrCast(@alignCast(&g_ram[0x20])); }`. Three shapes to handle: scalar deref, array/pointer, and struct-overlay (e.g. room_bounds_y at 0x600 as an extern struct with align(1) fields). CRITICAL: preserve every offset exactly, including deliberately overlapping overlays (room_bounds_y / ow_scroll_vars0 both at 0x600) — any drift breaks the RAM-compare oracle and savestate compatibility. Generate the bulk mechanically with a one-off script reading variables.h, then hand-review every struct-overlay and overlap case.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 variables.zig provides an accessor for every macro in src/variables.h, matching name and exact byte offset
- [x] #2 Struct-overlay macros use extern struct with align(1) fields; overlapping-offset pairs (e.g. room_bounds_y/ow_scroll_vars0) are both represented and documented as intentional aliases
- [x] #3 A generation script exists (kept in the repo, e.g. under other/ or assets/) so the mapping can be regenerated/diffed against variables.h
- [x] #4 Spot-checking 20+ random accessors against variables.h shows byte-identical offsets and types
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
