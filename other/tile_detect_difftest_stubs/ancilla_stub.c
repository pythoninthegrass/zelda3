// Difftest-side stubs for tile_detect.c's cross-module externs, one file per
// C module that would otherwise need to be linked whole into the Tier-B test
// binary (dragging in the rest of the game). The renamed tile_detect_c_ref
// object calls these through its c_-prefixed symbol references.
//
// The exported names use the c_ prefix so the stubs satisfy the renamed C
// object's references while the Zig side's plain names resolve against the
// harness's own g_ram-backed lookups. Ancilla_GetX/Y mirror ancilla.c's
// lo|hi<<8 composition over the same g_ram arrays.

#include "src/types.h"
#include "src/variables.h"

uint16 c_Ancilla_GetX(int k);
uint16 c_Ancilla_GetY(int k);

uint16 c_Ancilla_GetX(int k) { return ancilla_x_lo[k] | ancilla_x_hi[k] << 8; }
uint16 c_Ancilla_GetY(int k) { return ancilla_y_lo[k] | ancilla_y_hi[k] << 8; }
