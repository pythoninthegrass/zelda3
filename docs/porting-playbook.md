# Porting playbook (`src/*.c` → `src/*.zig`, `snes/*.c` → `snes/*.zig`)

Read this before starting a `TASK-004.*`-style port. It's the procedure every prior port
task re-derived by hand; skip straight to the verify gauntlet once you've read it. Symptom
→ fix traps that are Zig-language-level rather than procedural live in
`docs/development.md` ("Zig porting hazards").

## Procedure

1. Read the `.c` file being ported and its declarations in the matching `.h`.
2. Write the `.zig` file, preserving the C ABI exactly (see "C-ABI conventions" below).
3. Wire it into `build.zig`: remove the `.c` from `SOURCES` in `taskfile.yml` if the classic
   C build no longer needs to compile it directly, and add
   `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "<name>"));` (for
   `src/<name>.zig`) or `addPortedModuleAt(b, target, optimize, "<name>", "snes/<name>.zig")`
   (for `snes/*.zig`) alongside the other `addPortedModule*` calls in `build.zig`.
4. Run the verify gauntlet (below).
5. Finalize (below).

**Don't delete the `.c` file** — it stays for reference and for `*_difftest.zig` comparison.
Don't touch `taskfile.yml`'s task structure, `taskfiles/`, or `zelda3.bak`.

## Verify gauntlet

Prefer these `task zig:*` wrappers over hand-rolling `zig build`/headless-sway/parity
checks — they already exist and pin the right zig (see `taskfile.yml`'s `{{.ZIG}}` var):

```sh
task zig:build          # zig build
task zig:test           # Tier-A unit tests
task zig:difftest       # Tier-B C-vs-Zig differential tests
task zig:ast-check      # fast syntax/unused-var check over every ported .zig file
task zig:parity         # run the Zig binary against zelda3.sfc, check RAM-compare
task zig:parity-replay  # headless-sway/wtype/grim replay of saves/ref/Chapter*.sav
zig fmt --check src snes
task build               # classic C build still links cleanly
```

## Cross-module rule: no `@import` between ported modules

Two ported `.zig` files must never `@import` each other — each is compiled as its own
translation unit (`zig build-obj` or a `build.zig` module), so importing one from another
duplicates its `pub export fn` symbols and fails to link. Cross-module calls go through
`extern fn` declarations taking opaque `*anyopaque` params, with the *owning* module
exporting a small accessor. Precedents: `PpuGetCurrentMode`/`PpuGetVram` (`snes/ppu.zig`),
`SpcPlayer_GetRam`/`SpcPlayer_GetDsp` (`src/spc_player.zig`), both consumed via `extern fn`
in `src/zelda_rtl.zig`.

## Struct-twin rule

- Small structs shared across modules (e.g. `Dma`/`DmaChannel`) → mirror as a local
  `extern struct` with matching field layout.
- Large/opaque structs (`Ppu`, `SpcPlayer`) → keep behind an opaque pointer plus accessor
  functions per the cross-module rule above; don't mirror their full layout.

## Globals / `g_ram` ownership

`src/variables.h` already declares the C globals `extern`. Define the real backing storage
**once**, in the `.zig` file that owns it (e.g. `pub export var g_ram: [0x20000]u8 = .{0} **
0x20000;` in `src/zelda_rtl.zig`); `src/variables.zig` keeps `extern var` mirrors for every
other module to reference. Watch the duplicate-symbol trap: every `*_test.zig`/
`*_difftest.zig` file also declares its own `export var g_ram` — that's correct and
intentional (each test binary is a separate translation unit), don't "deduplicate" it.

## Macro-emulation cookbook

`WORD(x)`, `IntMax`, `enhanced_features0`, `kRam_*` offsets, `@ptrCast(&g_ram[...])`,
`align(1)` for lvalues at an odd byte offset. **Always grep `variables.h` and sibling
`.zig` files for an existing canonical table/extern before writing a new one** — a real
parity bug (TASK-004.06) came from re-deriving an 8-entry table instead of reusing the
already-`extern`'d 16-entry `kUpperBitmasks` (see `docs/development.md`).

## C-ABI conventions

- `pub export fn` with the exact original C name (no renaming, no name-mangling surprises).
- Varargs functions calling into libc need `callconv(.c)`.

## Finalize

Branch `task-XXXX-<slug>`. Two commits:

```text
feat(port): <file>.c → <file>.zig (TASK-XXXX)
chore(backlog): mark TASK-XXXX done
```

Merge to master. No `Co-Authored-By` trailers (only `pythoninthegrass` as author).
