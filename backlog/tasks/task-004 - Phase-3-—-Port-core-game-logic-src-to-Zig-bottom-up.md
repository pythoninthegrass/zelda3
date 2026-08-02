---
id: TASK-004
title: 'Phase 3 — Port core game logic (src/) to Zig, bottom-up'
status: To Do
assignee: []
created_date: '2026-08-02 04:18'
labels: []
milestone: m-0
dependencies: []
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the remaining ~79k LOC of game logic in src/ to hand-written idiomatic Zig, ordered by dependency depth (fewest includes first): spc_player.c, load_gfx.c, nmi.c, overlord.c, player_oam.c, then the deep core misc.c/zelda_rtl.c glue, sprite.c, sprite_main.c (25.8k LOC — the bulk, subdivide by switch-case group), player.c, ancilla.c, dungeon.c, overworld.c, messaging.c, ending.c, attract.c, select_file.c, tagalong.c, hud.c, audio.c, main.c, opengl.c, glsl_shader.c, and finally the RAM-compare oracle itself (zelda_cpu_infra.c, snes/cpu.c). Apply consistent translation patterns: convert ~359 gotos to labeled break/continue or restructured loops, map function-pointer jump tables to Zig const arrays of fn pointers, and route all g_ram access through the Phase 1 accessor layer (never scatter raw @ptrCast through logic files).

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
