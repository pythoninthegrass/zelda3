---
id: TASK-002.01
title: Port src/types.h to types.zig (base types + aliasing helpers)
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 08:01'
labels: []
dependencies:
  - TASK-001.04
parent_task_id: TASK-002
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/types.h's base integer typedefs and the type-punning helper macros BYTE/WORD/DWORD/HIBYTE/load24 to Zig. These helpers reinterpret an lvalue's address as a different integer width — in Zig this becomes inline generic functions using @ptrCast/@alignCast over *align(1) pointers, since many g_ram offsets are unaligned (odd addresses) and Zig disallows implicit unaligned access. This file is a pure dependency of every other ported file, so get the API shape right before Phase 1 continues.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 types.zig defines the base integer typedefs matching src/types.h
- [x] #2 BYTE/WORD/DWORD/HIBYTE/load24 equivalents exist as Zig inline fns using *align(1) pointers, handling unaligned offsets correctly
- [x] #3 No existing .c file needs to change to use these (or the change is limited to swapping the #include for the ported symbols)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
types.zig: u8/u16/... typedefs, kEnableLargeScreen/kPpuExtraLeftRight/kDebugFlag consts, BYTE/HIBYTE/WORD/DWORD/load24 as inline generic fns returning *align(1) pointers (read via .*, assign through the pointer) so odd g_ram offsets work; abs8/abs16/IntMin/IntMax/UintMin/UintMax/swap16/sign8/sign16/arraysize/countof/xy helpers; C-ABI extern struct twins for Point16U/PointU8/Pair16U/PairU8/ProjectSpeedRet/OamEnt/MemBlk with comptime layout asserts. types_test.zig Tier-A tests added to unit_test_files. Tier-B difftest skipped: types.h has no linkable symbols (header-only inlines/macros), so there is no C object to diff against. No .c file changes; types.h left in place for remaining C TUs.
<!-- SECTION:NOTES:END -->
