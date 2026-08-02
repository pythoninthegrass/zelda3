---
id: TASK-004.22
title: Port src/opengl.c and src/glsl_shader.c to Zig
status: To Do
assignee: []
created_date: '2026-08-02 04:21'
labels: []
dependencies:
  - TASK-004.21
parent_task_id: TASK-004
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/opengl.c (OpenGL renderer backend, 266 lines) and src/glsl_shader.c (GLSL shader loading, 659 lines) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. Keep third_party/gl_core (the OpenGL function loader) as C — do not port it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 opengl.c and glsl_shader.c are removed from the C build; their Zig equivalents are compiled instead
- [ ] #2 The OpenGL rendering backend (used when configured in zelda3.ini) renders identically to the SDL backend
- [ ] #3 third_party/gl_core remains C and unmodified
- [ ] #4 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean) with the OpenGL backend selected
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->
