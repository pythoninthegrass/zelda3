// Difftest-side stubs for tile_detect.c's overworld.c externs (the map8/map16
// attribute lookup tables). The renamed tile_detect_c_ref object calls these
// through c_-prefixed references; overworld.c stays out of the Tier-B link.
// Table contents are owned by the Zig harness so C and Zig share one buffer.

#include "src/types.h"

const uint8 *c_GetMap8toTileAttr(void);
const uint16 *c_GetMap16toMap8Table(void);

extern const uint8 tile_detect_difftest_map8toattr[512];
extern const uint16 tile_detect_difftest_map16tomap8[];

const uint8 *c_GetMap8toTileAttr(void) { return tile_detect_difftest_map8toattr; }
const uint16 *c_GetMap16toMap8Table(void) { return tile_detect_difftest_map16tomap8; }
