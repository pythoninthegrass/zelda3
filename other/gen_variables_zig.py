#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# ///
"""Generate src/variables.zig from src/variables.h.

One-way mechanical port of the g_ram accessor bank: every
`#define name (*(type*)(g_ram+off))` becomes an inline fn returning a
*align(1) pointer into the extern g_ram symbol, every
`#define name ((type*)(g_ram+off))` becomes an inline fn returning a
many-item pointer. Struct-overlay macros (room_bounds_y/ow_scroll_vars0 at
0x600, mirror_vars at 0x6A0, ...) get hand-maintained entries in STRUCT_DEFS /
SPECIAL below, since they reference C typedefs declared inline in
variables.h; everything else is emitted in file order, with duplicate names
(variables.h redefines several scratch-region names) folded into doc
comments on the first definition, matching the C preprocessor's
first-definition-wins semantics.

Usage: uv run other/gen_variables_zig.py [--check|--verify]
  default:    rewrite src/variables.zig
  --check:    exit 1 if src/variables.zig would differ (for CI-style diffs)
  --verify:   cross-reference every accessor in src/variables.zig against
              src/variables.h (name, offset, type, shape); exit 1 on drift
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "variables.h"
OUT = ROOT / "src" / "variables.zig"

SCALAR_RE = re.compile(
    r"^#define (\w+) \(\*\((uint8|uint16)\*\)\(g_ram\+(0x[0-9A-Fa-f]+|\d+)\)\)$"
)
PTR_RE = re.compile(
    r"^#define (\w+) \(\((uint8|uint16)\*\)\(g_ram\+(0x[0-9A-Fa-f]+|\d+)\)\)$"
)

# Decimal-offset aliases in variables.h (R10 at g_ram+10 etc.); emitted by
# SPECIAL verbatim, so the mechanical pass skips them.
DECIMAL_OFFSET_NAMES = {"R10", "R12", "R14"}

# The struct-overlay and other non-pattern macros, as (zig shape, C type,
# byte offset); --verify checks these against the hand-written SPECIAL block.
SPECIAL_DEFS = {
    "R10": ("scalar", "uint16", 10),
    "R12": ("scalar", "uint16", 12),
    "R14": ("scalar", "uint16", 14),
    "srm_var1": ("sram", "uint16", 0x1FFE),
    "uvram_screen": ("scalar", "UploadVram_32x32", 0x1000),
    "uvram": ("scalar", "UploadVram_3", 0x1000),
    "movable_block_datas": ("ptr", "MovableBlockData", 0xF940),
    "oam_buf": ("ptr", "t.OamEnt", 0x800),
    "room_bounds_y": ("scalar", "RoomBounds", 0x600),
    "room_bounds_x": ("scalar", "RoomBounds", 0x608),
    "ow_scroll_vars0": ("scalar", "OwScrollVars", 0x600),
    "ow_scroll_vars1": ("scalar", "OwScrollVars", 0x608),
    "ow_scroll_vars0_exit": ("scalar", "OwScrollVars", 0xC154),
    "mirror_vars": ("scalar", "MirrorHdmaVars", 0x6A0),
}

ZIG_TYPE = {"uint8": "t.uint8", "uint16": "t.uint16"}

HEADER = """\
// Port of src/variables.h: the g_ram accessor bank. Every C macro of the
// form `(*(type*)(g_ram+off))` / `((type*)(g_ram+off))` becomes an inline
// fn returning a *align(1) (or many-item) pointer into the extern g_ram
// symbol, which stays defined in C (zelda_rtl.c) during the migration.
// Dereference the result to read, assign through it to write:
//   v.link_y_coord().*     <-> link_y_coord
//   v.oam_buf()[i]         <-> oam_buf[i]
//   v.room_bounds_y().a0   <-> room_bounds_y.a0
//
// Every offset is preserved exactly as in variables.h, including the
// deliberate overlays (aliased views of the same bytes, used by disjoint
// modules and never simultaneously):
//   room_bounds_y / ow_scroll_vars0        at 0x600
//   room_bounds_x / ow_scroll_vars1        at 0x608
//   mirror_vars / star_shaped_switches_tile at 0x6A0
//   uvram_screen / vram_upload_offset/data/tile_buf at 0x1000
//   attract_var12 / link_y_coord           at 0x20 (attract scratch aliases)
// plus the whole blastwall_/skullwoodsfire_/quake_/bombos_/weathervane_/
// breaktowerseal_/happiness_pond_ families sharing 0x10000 and 0x15800.
// DO NOT "deduplicate" these: moving any address breaks the RAM-compare
// oracle against the original 65816 code and savestate compatibility.
//
// Regenerate after editing variables.h with: uv run other/gen_variables_zig.py

const t = @import("types.zig");

/// Mirror of the C `g_ram` symbol (extern uint8 g_ram[131072] in zelda_rtl.c).
pub extern var g_ram: [0x20000]u8;

// C ABI twin of ZeldaEnv's sram member (src/zelda_rtl.h); only the one
// field variables.h's srm_var1 accessor reaches through.
pub const ZeldaEnv = extern struct {
    ram: ?[*]t.uint8,
    sram: ?[*]t.uint8,
    vram: ?[*]t.uint16,
    ppu: ?*anyopaque,
    player: ?*anyopaque,
    dma: ?*anyopaque,
    dialogue_blk: t.MemBlk,
    dialogue_font_blk: t.MemBlk,
    dialogue_flags: t.uint8,
};
pub extern var g_zenv: ZeldaEnv;
"""

STRUCT_DEFS = """\
// Struct-overlay twins of the C typedefs in variables.h. Plain extern
// structs with align(1) fields: g_ram offsets are frequently odd and the
// C overlays are cast onto raw WRAM, so no natural alignment can be assumed.
// Word arrays ride in single-array structs (Words2/Words4/...) so the field
// can be align(1)'d without tripping Zig's element-alignment rules — size
// and layout are byte-identical to the C uint16[N] members.

pub const Words2 = extern struct { v: [2]t.uint16 };
pub const Words4 = extern struct { v: [4]t.uint16 };
pub const Words32 = extern struct { v: [32]t.uint16 };

pub const MovableBlockData = extern struct {
    room: t.uint16 align(1),
    tilemap: t.uint16 align(1),
};

pub const OamEntSigned = extern struct {
    x: t.int8,
    y: t.int8,
    charnum: t.uint8,
    flags: t.uint8,
};

pub const RoomBoundsFields = extern struct {
    a0: t.uint16 align(1),
    b0: t.uint16 align(1),
    a1: t.uint16 align(1),
    b1: t.uint16 align(1),
};

pub const RoomBounds = extern union {
    f: RoomBoundsFields,
    v: Words4 align(1),
};

pub const OwScrollVars = extern struct {
    ystart: t.uint16 align(1),
    yend: t.uint16 align(1),
    xstart: t.uint16 align(1),
    xend: t.uint16 align(1),
};

pub const MirrorHdmaVars = extern struct {
    var0: t.uint16 align(1),
    var1: Words2 align(1),
    var3: Words2 align(1),
    var5: t.uint16 align(1),
    var6: t.uint16 align(1),
    var7: t.uint16 align(1),
    var8: t.uint16 align(1),
    var9: t.uint16 align(1),
    var10: t.uint16 align(1),
    var11: t.uint16 align(1),
    pad: t.uint16 align(1),
    ctr2: t.uint8,
    ctr: t.uint8,
};

pub const UploadVram_Row = extern struct {
    col: Words32 align(1),
};

pub const UploadVram_32x32 = extern struct {
    row: [32]UploadVram_Row,
};

pub const UploadVram_3 = extern struct {
    pad: [256]t.uint8,
    data: Words4 align(1),
};
"""

# Hand-maintained accessors for the non-scalar shapes: struct overlays,
# the sram reach-through, and variables.h's decimal-offset aliases (g_ram+10
# is 0xA, etc. — kept decimal in the comment, exact either way).
SPECIAL = """\
/// R10: *(uint16*)(g_ram+10)
pub inline fn R10() *align(1) t.uint16 {
    return @ptrCast(&g_ram[10]);
}

/// R12: *(uint16*)(g_ram+12)
pub inline fn R12() *align(1) t.uint16 {
    return @ptrCast(&g_ram[12]);
}

/// R14: *(uint16*)(g_ram+14)
pub inline fn R14() *align(1) t.uint16 {
    return @ptrCast(&g_ram[14]);
}

/// srm_var1: *(uint16*)(g_zenv.sram+0x1ffe)
pub inline fn srm_var1() *align(1) t.uint16 {
    return @ptrCast(g_zenv.sram.? + 0x1ffe);
}

/// uvram_screen: *(UploadVram_32x32*)&g_ram[0x1000]
pub inline fn uvram_screen() *align(1) UploadVram_32x32 {
    return @ptrCast(&g_ram[0x1000]);
}

/// uvram: *(UploadVram_3*)(&g_ram[0x1000])
pub inline fn uvram() *align(1) UploadVram_3 {
    return @ptrCast(&g_ram[0x1000]);
}

/// movable_block_datas: (MovableBlockData*)(g_ram+0xf940)
pub inline fn movable_block_datas() [*]align(1) MovableBlockData {
    return @ptrCast(&g_ram[0xf940]);
}

/// oam_buf: (OamEnt*)(g_ram+0x800)
pub inline fn oam_buf() [*]align(1) t.OamEnt {
    return @ptrCast(&g_ram[0x800]);
}

/// room_bounds_y: *(RoomBounds*)(g_ram+0x600) — intentional alias of ow_scroll_vars0
pub inline fn room_bounds_y() *align(1) RoomBounds {
    return @ptrCast(&g_ram[0x600]);
}

/// room_bounds_x: *(RoomBounds*)(g_ram+0x608) — intentional alias of ow_scroll_vars1
pub inline fn room_bounds_x() *align(1) RoomBounds {
    return @ptrCast(&g_ram[0x608]);
}

/// ow_scroll_vars0: *(OwScrollVars*)(g_ram+0x600) — intentional alias of room_bounds_y
pub inline fn ow_scroll_vars0() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0x600]);
}

/// ow_scroll_vars1: *(OwScrollVars*)(g_ram+0x608) — intentional alias of room_bounds_x
pub inline fn ow_scroll_vars1() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0x608]);
}

/// ow_scroll_vars0_exit: *(OwScrollVars*)(g_ram+0xC154)
pub inline fn ow_scroll_vars0_exit() *align(1) OwScrollVars {
    return @ptrCast(&g_ram[0xC154]);
}

/// mirror_vars: *(MirrorHdmaVars*)(g_ram+0x6A0) — intentional alias of star_shaped_switches_tile
pub inline fn mirror_vars() *align(1) MirrorHdmaVars {
    return @ptrCast(&g_ram[0x6A0]);
}
"""


def offset_zig(text: str) -> str:
    """Normalize a C offset literal for Zig (decimal stays decimal)."""
    return text if text.startswith("0x") else text


def verify() -> int:
    """Cross-reference every accessor in OUT against SRC (offset/type/shape)."""
    # First definition wins, mirroring both the C preprocessor and the
    # generator's duplicate folding.
    c_defs = {}
    for raw in SRC.read_text().splitlines():
        line = raw.rstrip("\r")
        m = PTR_RE.match(line)
        if m:
            n, ty, off = m.groups()
            c_defs.setdefault(n, ("ptr", ZIG_TYPE[ty], int(off, 0)))
            continue
        m = SCALAR_RE.match(line)
        if m:
            n, ty, off = m.groups()
            c_defs.setdefault(n, ("scalar", ZIG_TYPE[ty], int(off, 0)))
    c_defs.update(SPECIAL_DEFS)

    z_defs = {}
    accessor_re = re.compile(
        r"pub inline fn (\w+)\(\) (\[\*\]|\*)align\(1\) ([\w.]+) \{\n"
        r"    return @ptrCast\((?:&g_ram\[(0x[0-9A-Fa-f]+|\d+)\]"
        r"|g_zenv\.sram\.\? \+ (0x[0-9A-Fa-f]+))\);\n\}"
    )
    for m in accessor_re.finditer(OUT.read_text()):
        n, ptrkind, ty, off, soff = m.groups()
        shape = "ptr" if ptrkind == "[*]" else "scalar"
        z_defs[n] = (shape, ty, int(off or soff, 0))

    errors = []
    for n, (shape, ty, off) in sorted(c_defs.items()):
        expect_shape = "scalar" if shape in ("scalar", "sram") else "ptr"
        expect_ty = ZIG_TYPE.get(ty, ty)  # C spellings in SPECIAL_DEFS map too
        if n not in z_defs:
            errors.append(f"{n}: missing in variables.zig")
            continue
        zs, zty, zoff = z_defs[n]
        if zoff != off:
            errors.append(f"{n}: offset C={off:#x} zig={zoff:#x}")
        if zs != expect_shape:
            errors.append(f"{n}: shape C={shape} zig={zs}")
        if zty != expect_ty:
            errors.append(f"{n}: type C={expect_ty} zig={zty}")

    extra = sorted(set(z_defs) - set(c_defs))
    if extra:
        errors.append(f"zig-only accessors with no C counterpart: {extra}")

    print(f"verified {len(c_defs)} C macros against {len(z_defs)} zig accessors")
    if errors:
        for e in errors:
            print(f"  ERROR: {e}", file=sys.stderr)
        return 1
    print("all offsets, types, and shapes match")
    return 0


def main() -> int:
    if "--verify" in sys.argv:
        return verify()

    seen = {}
    body = []
    pending_dups = []  # dup comment lines awaiting their anchor accessor
    for lineno, raw in enumerate(SRC.read_text().splitlines(), start=1):
        line = raw.rstrip("\r")
        m = SCALAR_RE.match(line) or PTR_RE.match(line)
        if not m:
            continue
        name, ctype, off = m.groups()
        if name in DECIMAL_OFFSET_NAMES:
            continue  # covered verbatim by SPECIAL
        deref = SCALAR_RE.match(line) is not None
        if name in seen:
            # variables.h redefines names across scratch regions; the first
            # definition wins in both C and Zig, so later ones fold into a
            # comment on the first accessor once it is emitted.
            prev_ctype, prev_off, prev_deref, _ = seen[name]
            same = (prev_ctype, prev_off.lower(), prev_deref) == (ctype, off.lower(), deref)
            note = "identical alias" if same else "different type/offset"
            pending_dups.append((name, lineno, note))
            continue
        seen[name] = (ctype, off, deref, lineno)
        zt = ZIG_TYPE[ctype]
        ret = f"*align(1) {zt}" if deref else f"[*]align(1) {zt}"
        shape = f"(*({ctype}*)(g_ram+{off}))" if deref else f"(({ctype}*)(g_ram+{off}))"
        body.append(
            f"\n/// variables.h:{lineno} — {name}: {shape}\n"
            f"pub inline fn {name}() {ret} {{\n"
            f"    return @ptrCast(&g_ram[{offset_zig(off)}]);\n"
            f"}}"
        )

    out = HEADER + "\n" + STRUCT_DEFS + "\n" + SPECIAL + "\n" + "".join(body) + "\n"

    # Fold each duplicate into a comment line on the first definition's doc
    # comment, matching C's first-definition-wins redefinition semantics.
    for name, lineno, note in pending_dups:
        anchor = f"pub inline fn {name}()"
        idx = out.index(anchor)
        insert_at = out.rindex("\n///", 0, idx) + 1
        out = out[:insert_at] + f"///   also defined at variables.h:{lineno} ({note})\n" + out[insert_at:]

    if "--check" in sys.argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != out:
            print(f"{OUT} is out of date; run: uv run other/gen_variables_zig.py", file=sys.stderr)
            return 1
        print(f"{OUT} is up to date")
        return 0

    OUT.write_text(out)
    n_accessors = out.count("pub inline fn")
    print(f"wrote {OUT} ({n_accessors} accessors)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
