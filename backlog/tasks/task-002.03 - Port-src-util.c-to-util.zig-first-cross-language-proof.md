---
id: TASK-002.03
title: Port src/util.c to util.zig (first cross-language proof)
status: Done
assignee: []
created_date: '2026-08-02 04:19'
updated_date: '2026-08-02 16:54'
labels: []
dependencies:
  - TASK-002.02
parent_task_id: TASK-002
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/util.c — a true leaf module with minimal includes — to util.zig as the first real proof that the Zig/C interop workflow (export fn with callconv(.c), matching C symbol names, linking into the existing build) works end to end. Every other .c file that currently calls into util.c's functions must keep linking without any source changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 util.c is removed from the C build and util.zig is compiled instead
- [x] #2 All exported symbols use callconv(.c) and match the original C names exactly
- [x] #3 Every remaining .c file that included util.h and called its functions compiles and links with zero changes
- [x] #4 Full Phase 0-style verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: supervisor
created: 2026-08-02 16:14
---
## Supervisor fix request (2026-08-02, after 2 bailed attempts)

Both automated attempts bailed on the same root cause: `StrFmt`, the one C-variadic function in util.c (`char *StrFmt(const char *fmt, ...)`).

- Attempt 1 tried exporting StrFmt directly from Zig with `std.builtin.VaList` forwarded into vsnprintf — this segfaulted after 3 in-session fix tries.
- Attempt 2 tried a more careful version: export StrFmt from Zig via `@cVaStart()`, forwarding the resulting va_list by pointer into a small C thunk (StrFmtVa.c) that calls vsnprintf. This is architecturally closer to correct but burned the entire 150-turn budget iterating on VaList type mismatches (VaListX86_64 vs VaList across Zig 0.16) and never finished verification.

Confirmed by grep: `StrFmt` has **zero in-tree callers** (`grep -rn "StrFmt(" src/ --include=*.c --include=*.h` matches nothing outside util.c/util.h). It only needs to exist as a linkable C-ABI symbol — nothing in this repo actually invokes it at runtime, so there is no need to prove correct varargs *behavior*, only correct *linkage*.

Recommended approach for this attempt — skip the VaList interop entirely:
1. Leave StrFmt itself as a tiny, permanently-C function in a new one-function file (e.g. src/util_strfmt.c), essentially the current 8-line C body verbatim (buf/vsnprintf/strdup). Do not declare or export StrFmt from util.zig at all.
2. Add that new .c file to build.zig's C source list the same way other not-yet-ported .c files are compiled today (same object, same symbol name, same signature) — zero Zig-side varargs code needed.
3. Everything else in util.c (NextDelim, StringEqualsNoCase, StringStartsWithNoCase, ReadWholeFile, NextLineStripComments, NextPossiblyQuotedString, ReplaceFilenameWithNewPath, SplitKeyValue, SkipPrefix, StrSet, ByteArray_*, FindIndexInMemblk, ApplyBps, BpsDecodeInt, crc32) has no varargs and should port to util.zig normally.
4. If the linker drops the now-unreferenced StrFmt symbol under --gc-sections, do not spend turns on forceUndefinedSymbol/undefSymbol tricks — this is a minor bookkeeping concern (AC #2/#3 care about symbol *shape*, not liveness), so the simplest fix (e.g. compiling that one object without section GC, or just leaving it as-is if it links fine) is sufficient. Do not over-engineer it.

Address this note first, then proceed with the rest of the task normally.
---
<!-- COMMENTS:END -->
