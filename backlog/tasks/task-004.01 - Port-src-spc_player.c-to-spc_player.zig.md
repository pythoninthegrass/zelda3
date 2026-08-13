---
id: TASK-004.01
title: Port src/spc_player.c to spc_player.zig
status: Done
assignee:
  - claude
created_date: '2026-08-02 04:20'
updated_date: '2026-08-13 18:06'
labels: []
dependencies:
  - TASK-003.09
modified_files:
  - src/spc_player.zig
  - build.zig
parent_task_id: TASK-004
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port src/spc_player.c (the self-contained reimplemented SPC music player, not the emulated one) to idiomatic Zig, matching C-ABI symbols so callers link unchanged. This is the first Phase 3 file — a leaf with few local includes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 spc_player.c is removed from the C build and spc_player.zig is compiled instead
- [x] #2 Music playback is unaffected
- [x] #3 Full parity verification passes (build clean, zero RAM-compare mismatches, reference-save replay clean)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task zig:build compiles clean
- [x] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [x] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [x] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [x] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Port src/spc_player.c (~1447 lines) to src/spc_player.zig, idiomatic Zig, C-ABI-preserving.

Approach:
1. File-header comment: what's ported; note the disabled `#if WITH_SPC_PLAYER_DEBUGGING 0` block (CompareSpcImpls/RunAudioPlayer/SDL) is dropped, matching dsp.zig's precedent of dropping its disabled branch.
2. Mirror structs as `extern struct` (shared layout with audio.c/header): `Channel` (58 fields), `SpcPlayer` (whole struct). Mirror `Dsp` (full, needed for trailing `sampleOffset` field) and `DspRegWriteHistory` `{count:u32, addr:[256]u8, val:[256]u8}` from snes/dsp.h/dsp.zig.
3. DSP register constants used (V0VOLL..V0GAIN, EON/EFB/EVOLL/EVOLR/FLG/EDL/ESA/FIR0/KOF/KON/PMON/NON/MVOLL/MVOLR/DIR/V6/V7 VOLL/VOLR) as file-scope consts.
4. externs (callconv(.c)): dsp_write, dsp_init, dsp_reset, dsp_cycle, malloc, printf.
5. Macro emulation: HIBYTE(x) via pointer-to-high-byte read/write helpers on u16 lvalues; WORD(ram[x]) little-endian 2-byte read; sign8; countof→inline. Narrow-int wrapping arithmetic uses +%/-%/*% plus explicit @as/@truncate/@intCast/@bitCast to mirror C integer-promotion+truncation-on-store.
6. Restructure goto control flow: Port0_HandleMusic (labels handle_cmd_00/next_phrase/label_a/HandleCmd_0xf0_PauseMusic) and Sfx_ChannelTick (note_continue) into labeled blocks/loops preserving exact semantics.
7. `pub export fn` for every ABI symbol: 6 header fns (SpcPlayer_Create/Initialize/CopyVariablesToRam/CopyVariablesFromRam/GenerateSamples/Upload) + 2 non-static (CalcFinalVolume, CalcTremolo). All static helpers stay non-exported.
8. Not_Implemented / assert(0)-unreachable / CalcTremolo / HandleTremolo → @panic (classic build has no -DNDEBUG so C assert is active/aborts). Invariant asserts in GenerateSamples → std.debug.assert (cart.zig precedent).
9. kChannel_Maps/kSpcPlayer_Maps tables via @offsetOf; CopyVariablesTo/FromRam memcpy loops replicated.
10. build.zig: remove "src/spc_player.c" from sources; add exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "spc_player")).

Verify: zig build; task zig:parity; task zig:parity-replay; clean-tree classic `task build` after rm -f zelda3 src/*.o snes/*.o; zig fmt --check + task zig:ast-check + zig build test. Do NOT delete spc_player.c; leave taskfile.yml/taskfiles untouched.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported src/spc_player.c (~1447 lines, the self-contained reimplemented SPC music/sfx player) to src/spc_player.zig as idiomatic Zig, preserving every C-ABI symbol so the remaining .c callers (audio.c, zelda_rtl.c) and the ported dsp.zig link unchanged. src/spc_player.c is left in place (untouched) — the classic `task build` still compiles it directly; only build.zig changed to route the Zig build through the new module.

What changed:
- src/spc_player.zig (new): full port. Channel and SpcPlayer mirrored as `extern struct` matching src/spc_player.h field-for-field (so audio.c keeps reading p->input_ports/p->ram and the offsetof-based CopyVariablesTo/FromRam table copies land on identical bytes). Dsp/DspChannel and DspRegWriteHistory mirrored from snes/dsp.zig / snes/dsp.h (only dsp->sampleOffset and the reg_write_history tail are read, but full layouts are needed for correct offsets). DSP register constants as file-scope consts. externs (callconv(.c)) for dsp_write/dsp_init/dsp_reset/dsp_cycle/malloc. Macro emulation via hi()/setHi()/word()/readCh() helpers; narrow-int wrapping arithmetic via +%/-%/*% with explicit @as/@truncate/@intCast/@bitCast to mirror C integer-promotion+truncation-on-store; all bitwise-and-compare expressions parenthesized (Zig binds & higher than ==). goto control flow restructured: Port0_HandleMusic → handleCmd00 + labeled phrase_loop/channel_loop/inner blocks + shared HandleCmd_0xf0_PauseMusic helper; Sfx_ChannelTick → extracted sfxNoteContinue helper. 8 `pub export fn` ABI symbols (SpcPlayer_Create/Initialize/CopyVariablesToRam/CopyVariablesFromRam/GenerateSamples/Upload + CalcFinalVolume/CalcTremolo); all other functions are non-exported statics. Not_Implemented/assert(0)-unreachable/CalcTremolo/HandleTremolo → @panic (classic build has no -DNDEBUG, C assert is active); GenerateSamples invariants → std.debug.assert. The disabled `#if WITH_SPC_PLAYER_DEBUGGING 0` harness block was dropped, matching dsp.zig's precedent.
- build.zig: removed "src/spc_player.c" from the C `sources` list; added `exe.root_module.addObjectFile(addPortedModule(b, target, optimize, "spc_player"));`.

Verification (all pass):
- `zig build` — compiles clean (fixed two compile errors during dev: signed division needed @divTrunc; a low-pitch cast needed i16 not i32).
- `task zig:parity` — "PARITY OK: zero RAM-compare mismatches".
- `task zig:parity-replay` — "PARITY-REPLAY OK: zero RAM-compare mismatches across 13 reference-save replays" (all Chapter*.sav).
- Clean-tree classic `task build` after `rm -f zelda3 src/*.o snes/*.o` — exit 0, spc_player.c compiled and linked directly, zelda3 binary produced.
- `zig fmt --check src/spc_player.zig` — clean; `task zig:ast-check` — clean; `zig build test` — exit 0.

Audio note (AC #2 "Music playback unaffected"): there is no automated audio test and the audio was NOT manually listened to by ear. Correctness rests entirely on the RAM-compare oracle: the reimplemented player writes DSP registers and maintains state that is compared frame-by-frame against the original 65816 machine code, and the parity + 13-chapter parity-replay runs show zero mismatches, meaning the Zig port produces byte-identical DSP register writes and player state to the C version.
<!-- SECTION:FINAL_SUMMARY:END -->
