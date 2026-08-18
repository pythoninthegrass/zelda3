# Development notes

## Zig porting hazards (C → Zig, `src/*.zig`)

Lessons from headless agent runs porting `src/*.c` files to Zig, verified against the
RAM-compare oracle (see `AGENTS.md` "RAM-compare verification").

### `@as(T, x) OP y` parses surprisingly

A builtin call's result followed directly by a binary operator does not always bind the
way C intuition expects — e.g. `@as(t.uint16, 0x8000) >> shift` can mis-parse under certain
surrounding context, producing confusing type-mismatch errors (`expected type 'u4', found
'u32'`) that look like a compiler bug but aren't. Same trap with an `if`-expression operand:
`@as(i32, x) + if (cond) -8 else 0` swallows the `if` into the wrong place.

**Fix the parse, not the semantics**: wrap the non-`@as` side in parens —
`@as(t.uint16, 0x8000) >> (shift)`, `@as(i32, x) + (if (cond) -8 else 0)`. Do **not**
work around the error by substituting different logic (a new lookup table, a different
condition, etc.) — that fixes the symptom while quietly changing behavior.

This exact mistake caused a real parity bug (TASK-004.06, frame-19 RAM-compare divergence,
2026-08-18): hitting this parse trap in `AncillaAdd_ItemReceipt`, the agent replaced
`t.word(p).* |= 0x8000 >> shift` with a hand-rolled 8-entry `kPalaceBits` table instead of
adding parens — silently truncating the correct 16-entry `kUpperBitmasks` table already
declared `extern` from `zelda_rtl.c` and used elsewhere in the port (`load_gfx.zig`). Always
grep `variables.h` and sibling `.zig` files for an existing canonical table/extern before
writing a new one during a mechanical port.

### Zig 0.16 removed standalone `|%` / `^%`

The wrapping-OR/XOR operators no longer parse as standalone binary operators
(`error: expected expression, found '%'`). Compound-assignment forms still work
(`|=`, `^=`, `+%=`), and standalone `+%` still works. For `uint8`/`uint16` OR/XOR (which
can't overflow), plain `|`/`^` is equivalent and simplest.

### `zig` on PATH may not be the pinned version

`~/.local/share/mise/installs/zig/mach-latest/bin/zig` (a 0.14.0-dev nightly) can sit ahead
of the mise shim for the pinned 0.16.0 on `PATH`, causing `zig build`/`task zig:build` to
silently use the wrong compiler and produce misleading `build.zig.zon` parse errors. Verify
with `mise which zig` before treating a build error as a real bug. This has independently
bitten both a human session and a headless agent run.

## Headless/agent session hygiene

Observed in a headless pi run (TASK-004.06, session `01a01310-4efa-72b8-a7a4-16cc49955ada`,
2026-08-18): the session ended on an empty final message immediately after finding the root
cause of a bug, having added `fprintf` debug traces to three tracked files
(`dungeon.c`, `zelda_cpu_infra.c`, `misc.zig`) and never removed them, applied the fix, or
left a summary of what was tried. Anyone resuming from that checkpoint inherits an
uncommitted, debug-instrumented tree with no context.

Rules for any agent run (headless or interactive) that leaves temporary debug
instrumentation in tracked files mid-investigation:

- Before ending the session, either remove the instrumentation or explicitly call it out
  (in the final message and ideally a code comment) as temporary and unremoved.
- Always end with a status summary, even on failure/timeout: what was tried, what was
  found, what's still broken. Never end on an empty message.
- Prefer `git status`/`git diff` review before ending, to catch stray edits.
