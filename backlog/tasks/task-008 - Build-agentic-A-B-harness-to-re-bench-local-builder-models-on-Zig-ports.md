---
id: TASK-008
title: Build agentic A/B harness to re-bench local builder models on Zig ports
status: In Progress
assignee: []
created_date: '2026-08-05 00:11'
updated_date: '2026-08-05 00:11'
labels: []
dependencies: []
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The one-shot, no-tools chat-completion bakeoff recorded in `docs/bakeoff.md` measured local models' Zig-porting ability without tools, compiler feedback, or iteration, and concluded (implicitly) that Qwen3.6-27B wasn't well suited despite being the ArtificialAnalysis/SWE-bench tier leader. `doc-001` ("Making local agents/models effective at writing Zig") argues this bakeoff mis-measures the models: the real burn pipeline (`scripts/burn/driver.py`) gives the local builder model up to 150 turns with tools and a battery of deterministic gates, which is a fundamentally different regime than the one-shot bakeoff.

This task is to build the agentic A/B re-bench harness that doc-001 §5.3 identifies as the experiment that would actually settle model choice, replacing the misleading one-shot bakeoff with real, gates-passed evidence.

Full context and rationale: see backlog document doc-001, especially §2 (external benchmark landscape), §3 (llmfit's hardware-fit recommendation of Qwen3-Coder-Next on the 96GB `mf` box), and §5.3 (the harness design this task implements).

Candidates to compare:
- Qwen3.6-35B-A3B-MTP-GGUF (current delegated builder in `~/.hermes/config.yaml`)
- Qwen3-Coder-Next-GGUF (llmfit's top hardware-fit pick for coding on this box; agentic/tool-call-tuned, 256K context)
- Qwen3.6-27B-MTP-GGUF (ArtificialAnalysis/SWE-bench tier leader, current fallback)

The harness must run real backlog Zig-port tasks (e.g. from TASK-004's subtasks) through each candidate model with tools, compiler feedback, and multiple turns — mirroring how `scripts/burn/driver.py` actually drives a burn run — and rank candidates by gates passed rather than one-shot compile success.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Harness runs each candidate model (Qwen3.6-35B-A3B, Qwen3-Coder-Next, Qwen3.6-27B) against the same set of real backlog Zig-port tasks, with tool access, compiler feedback, and multiple turns available in each run (not one-shot chat completion)
- [ ] #2 Harness reuses or mirrors driver.py's existing gate sequence (prek, zig:build, zig:test, zig:difftest, zig:parity, zig:parity-replay, build) to score each run
- [ ] #3 Each candidate's result is scored by gates passed per task, not by a single pass/fail compile check
- [ ] #4 Harness supports running the same task across multiple candidates without one candidate's run polluting another's git worktree or build state
- [ ] #5 Harness produces a comparison report (per model: tasks attempted, gates passed per task, turns used, wall-clock time) suitable for deciding which model(s) to use as the burn pipeline's delegated builder
- [ ] #6 A documented invocation exists for running the full A/B across all three candidates in one command or script
- [ ] #7 Running the harness does not modify scripts/burn/driver.py's production gate list or the live feat/zig-port-burn branch unless a run's changes are explicitly promoted
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task zig:build compiles clean
- [ ] #2 Running the binary with zelda3.sfc loaded shows zero 'Memory compare failed' lines on stderr (RAM-compare oracle)
- [ ] #3 Replay of reference saves (saves/ref/Chapter*.sav) stays clean
- [ ] #4 The file's C-ABI symbols are unchanged so remaining .c files link without edits
- [ ] #5 zelda3.bak and the C taskfile.yml build remain untouched and working
- [ ] #6 Harness code and scripts are committed under version control (e.g. scripts/burn/ or a new ab-bench directory)
- [ ] #7 Harness runs end-to-end at least once against all three candidate models with results captured in the comparison report
- [ ] #8 Documentation explains how to invoke the harness and interpret its report
<!-- DOD:END -->
