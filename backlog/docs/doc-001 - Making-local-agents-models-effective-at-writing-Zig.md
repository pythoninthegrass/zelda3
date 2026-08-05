---
id: doc-001
title: Making local agents/models effective at writing Zig
type: other
created_date: '2026-08-05 00:11'
---
# Making local agents/models effective at writing Zig

Companion to [`bakeoff.md`](../../docs/bakeoff.md). That doc ran a one-shot, no-tools chat-completion bakeoff
(`snes/dsp.c → dsp.zig`) and every candidate — including Qwen3.6-27B, the model expected to be best suited
for the hermes agent and agentic coding — failed to produce a compiling file. This reads, at first glance,
like "the model isn't suited." This doc argues that conclusion doesn't hold up: the bakeoff measured the
wrong thing, and the actual levers for making local models effective at Zig are harness changes, not a
model swap.

## Thesis

The local models' Zig failures are **harness and language-drift problems, not model-rank problems.**
Three local facts explain the bakeoff result without needing to indict the model:

1. **Qwen3.6-27B is already the top-ranked small open model** on ArtificialAnalysis (Intelligence Index
   37 — highest in the whole 4B–40B tier, and higher than every model in the 40B–150B tier too). "Pick a
   smarter model" is not an available lever here; it's already the smartest thing that fits the "small"
   category, and beats the "medium" category on general intelligence.
2. **The `zig-0.16` skill never reaches the burn worker.** `hermes chat` (what `scripts/burn/driver.py`
   invokes) doesn't load Claude Code skills — the worker's entire prompt is
   `scripts/burn/prompt_header.txt` concatenated with the task markdown (`driver.py:404`). The 25 KB
   pinned-0.16 skill sitting in `.claude/skills/zig-0.16/SKILL.md` currently does nothing for an
   autonomous burn run.
3. **The bakeoff was the worst possible way to measure this**: one-shot, no compiler feedback, no
   iteration. The burn driver's real pipeline gives hermes up to 150 turns *with* tools and a battery of
   deterministic gates (`prek`, `zig:build`, `zig:test`, `zig:difftest`, `zig:parity`,
   `zig:parity-replay`, `build` — `driver.py:302-310`). Every recurring bakeoff error class — a `var`
   never mutated, `@intCast`/`@truncate` signedness, `@memset` on a fixed array instead of a slice, `u3`
   bitfield overflow — is caught with a precise, actionable message the moment `zig build` runs. One-shot
   chat completion never gets to see that message, let alone act on it.

## 1. Why the one-shot bakeoff mis-ranks the models

Zig is, for LLMs, a **low-resource and fast-drifting** language: sparse training data plus a language
that keeps breaking its own APIs release to release. One author's write-up of using ChatGPT for Zig
([eriklangille.com](https://eriklangille.com/blog/llms_zig.html)) is blunt about the shape of the
failure: the same model that produces working Python/S3 code on the first try hallucinates
non-existent Zig annotations and functions "that don't work like this" — the author eventually gave up
on LLM-assisted Zig entirely and went back to reading docs and trial-and-error against the compiler.
That's the diagnosis: **data scarcity, not incapability.**

The bakeoff's own recurring-failure signature is exactly this class of error, and it is Zig-0.16-specific
version drift rather than generic incompetence:

- A `var` that's never subsequently mutated is a **hard compile error** in 0.16, not a lint warning —
  every Qwen run had several.
- `@truncate`/`@intCast` require the operand to already be the correct signedness, and `@intCast`
  sometimes needs an explicit `@as(T, ...)` when the destination isn't inferable from context (confirmed
  against the version-pinned Zig 0.16.0 docs via context7 — see §4).
- `@memset` needs a mutable slice, not a fixed array value.
- `u3` bitfield overflow (writing `8` into a 3-bit field).

None of this is exotic reasoning failure — it's the compiler enforcing rules the model's training data
(mostly pre-0.16) doesn't reflect. And it is **deterministically catchable**: `zig build`/`zig ast-check`
report the exact line and the exact rule violated. Judging a model on whether it avoids these errors
zero-shot, with no chance to read the compiler's own error message, discards the single most
informative signal available for this exact failure class.

## 2. External model landscape (compare/contrast)

**ArtificialAnalysis — [small open-source models (4B–40B)](https://artificialanalysis.ai/models/open-source/small):**

| Model | Params | Intelligence Index |
|---|---|---|
| Qwen3.6 27B (Reasoning) | 27.8B | **37 (highest)** |
| Qwen3.6 35B A3B (Reasoning) | 36B (3B active) | 32 |
| G9v3-39A5B | 39B (5B active) | 31 |
| Qwen3.6 27B (Non-reasoning) | 27.8B | 30 |
| Gemma 4 31B (Reasoning) | 30.7B | 29 |

**ArtificialAnalysis — [medium open-source models (40B–150B)](https://artificialanalysis.ai/models/open-source/medium):**

| Model | Params | Intelligence Index |
|---|---|---|
| Qwen3.5 122B A10B (Reasoning) | 125B | 32 |
| Mistral Medium 3.5 | 128B | 30 |
| Qwen3.5 122B A10B (Non-reasoning) | 125B | 28 |
| NVIDIA Nemotron 3 Super 120B | 120.6B | 25 |
| gpt-oss-120b (high) | 117B | 24 |
| **Qwen3-Coder-Next** | 79.7B | 21 (flagged "best for coding") |

Note the shape: Qwen3.6-27B's **37** beats every model in the medium tier's general intelligence score.
Bigger isn't automatically smarter here, and the coding-tuned model (Qwen3-Coder-Next) scores *lower*
on general intelligence than several non-coding-branded peers — its edge is elsewhere (tool-use tuning,
agentic harness fit, context length), which matters for a different reason (see §3, §5.3).

**SWE-bench Verified** (web search, current as of this writing): Qwen3.6-27B 77.2% (highest of any model
that runs on consumer hardware), Devstral Small 2 68.0%, GLM-4.7-Flash 59.2%, Qwen3-Coder-30B-A3B 50.3%.
Again: the model already in the burn pipeline is the class leader by this measure too.

**The decisive datapoint — [AkitaOnRails' Zig coding-agent challenge](https://akitaonrails.com/en/2026/01/11/ai-agents-comparing-top-llms-on-the-zig-challenge/):**
this is the closest external analogue to what the burn driver actually does — an *agentic*, tool-using,
iterative Zig task, not one-shot chat completion. Results:

- Claude Opus solved it in two prompts, ~30 minutes, ~$8. GPT-5.1 Codex, GPT-5.2, and Gemini 3 Pro Preview
  also eventually solved it.
- **Every open-source model tested failed** — Qwen3-Coder (30B), GPT-OSS (20B), DeepSeek V2 Lite, GLM-4.7,
  MiniMax v2.1. None "solved" the challenge, hitting build-system/ArrayList API drift (Zig 0.15.x era) and
  getting stuck.
- The specific open-model failure mode: they'd "recognize the problem, even generate a plan to fix it,"
  then **repeat the identical reasoning without making progress** — a stall/loop, not a wrong turn.

This is direct, agentic-setting evidence that (a) the gap between commercial frontier models and today's
open models on Zig specifically is real and not just a training-data artifact fixable by better prompting,
and (b) the actual open-model failure mode worth designing around is **looping**, not "picks the wrong
model." That reframes what an Opus/Sonnet judge should be for (§5.4).

## 3. llmfit vs. this bakeoff

`llmfit` (`/usr/local/bin/llmfit`, upstream `AlexsJones/llmfit`) is a hardware-aware model selector —
"right-size LLM models to your system's hardware." Its `recommend` subcommand ranks models by a fit
score against detected/declared VRAM, context length, and use case. It answers a different question than
the bakeoff: *what fits and runs well here*, not *does this model write correct Zig*.

On `mf` (RTX PRO 6000 Blackwell, **96 GB VRAM** — documented in `linux_setup/docs/egpu-setup.md` and
`model-comparison.md`), the documented invocation

```
llmfit --memory=96G --max-context 131072 recommend --use-case coding --limit 10
```

returns a top-10 list that's **entirely Qwen3-Coder-Next variants**, with #1 being **Q6_K, 40.8 GB,
score 99.1/100, ~42 tok/s** (`linux_setup/docs/model-comparison.md`).

The mismatch: **the bakeoff only tested models ≤27B**, leaving roughly 55 GB of the box's 96 GB VRAM
unused, and never tested the model llmfit's own coding-use-case ranking already recommends for this
exact hardware. This isn't a contradiction between the two tools — they measure orthogonal things
(capacity/throughput fit vs. one-shot correctness) — but it does mean the bakeoff's implicit model
verdict was reached without testing the model the hardware is best suited to run for coding.

Current hermes wiring (`~/.hermes/config.yaml`): orchestrator is Fireworks `deepseek-v4-flash-0731`
(driver.py default) or local Qwen3.6-27B-MTP (config default/fallback); delegated builder is
**Qwen3.6-35B-A3B-MTP-GGUF** via lemonade, `max_turns: 150`. Qwen3-Coder-Next has not been wired in or
tested agentically at all.

## 4. The Zig-specific playbook

**[ZigNet](https://fulgidus.github.io/posts/zignet/)** — an MCP server purpose-built for LLM-assisted Zig
— converges on the same conclusion from a different angle. Its architecture is explicitly **50%
deterministic / 50% stochastic**: the deterministic half runs the *real* `zig ast-check`/`zig fmt` for
validation (100% accurate, and "when Zig 0.16 drops, it just works" — zero maintenance, because it
shells out to the actual compiler rather than re-implementing Zig semantics); the stochastic half is a
small QLoRA-fine-tuned Qwen2.5-Coder-7B for suggestions/doc lookup. The compiler-output parse (error
type, line/column, involved types) feeds back into the next suggestion. This is independent confirmation
that **compiler-in-the-loop is the dominant lever for LLM-assisted Zig**, not model selection.

**context7 has a version-pinned Zig 0.16.0 source** (`/websites/ziglang_0_16_0`) that directly answers
the exact failure classes seen in the bakeoff — queried live for this doc:

- `@truncate(int)` — "return type is the inferred result type... always truncates significant bits."
- `@intCast(int)` — "Safety checks are performed for out-of-range values, resulting in a panic."
- `@memset(dest, elem)` — "`dest` must be a mutable slice or a mutable pointer to an array" (confirms
  the bakeoff's "`@memset` on a fixed array" failure was passing the wrong pointer kind).

This is a way to hand the worker *current, version-pinned* ground truth instead of relying on the
model's stale pre-0.16 training data — the same principle ZigNet applies via the live compiler, applied
to documentation instead.

**The repo already has the ideal few-shot precedent**, confirmed by reading the files directly:
`snes/dma.zig` and `snes/spc.zig` demonstrate every idiom the bakeoff models got wrong, consistently:
strict `const`-unless-mutated discipline (`const ch = &dma.channel[i];`, `const off_idx = ch.offIndex;`,
with only genuinely-mutated locals as `var`), correct `@truncate`/`@intCast` usage
(`@truncate(dma.channel[c].aAdr & 0xff)`, `@as(u16, val) << 8`, `@as(u8, 1) << @intCast(i)`), wrapping
arithmetic where the hardware wraps (`+%=`, `-%=`), `extern struct` mirroring C layout field-for-field,
and `pub export fn ... callconv(.c)` preserving the C ABI exactly. This precedent was already given to
the bakeoff models as context — the gap is real model-vs-idiom mismatch, not a missing example.

## 5. Recommendations

1. **Get 0.16 knowledge to the worker, not just the skill file.** The skill is currently inert for burn
   runs since hermes never loads it. Distill the highest-signal parts (the const/var rule, the
   intCast/truncate signedness rule, the memset-needs-a-slice rule, plus a pointer to query context7's
   `/websites/ziglang_0_16_0` and to read `snes/dma.zig`/`snes/spc.zig` as precedent) into
   `prompt_header.txt` itself, where the worker will actually see it. Note that the bakeoff's run 2
   already tried dumping the *entire* `AGENTS.md` in one-shot and saw no measurable improvement (13 vs 14
   errors, chalked up to sampling noise) — that's a different intervention from a focused cheat-sheet
   inside a tool-driven, iterative loop, so it doesn't preempt this.
2. **Tighten the compiler-in-the-loop.** This is the highest-leverage single change, and it's exactly
   what ZigNet's architecture and the AkitaOnRails agentic result both point at. Have the worker run
   `zig ast-check <file>` (fast) after each edit and `task zig:build` before considering a file done,
   rather than writing an entire port and hitting the gate once at the end.
3. **Re-bench agentically, not one-shot — this replaces the bakeoff's model conclusion.** Design a
   harness that runs real backlog port tasks *with* tools, compiler feedback, and multiple turns (mirroring
   what `driver.py` actually does), ranked by gates-passed rather than blind compile success. A/B across:
   Qwen3.6-35B-A3B (current delegated builder), Qwen3-Coder-Next (llmfit's coding pick for this hardware,
   agentic/tool-call-tuned, 256K context, uses the currently-idle VRAM headroom), and Qwen3.6-27B (the
   ArtificialAnalysis/SWE-bench tier leader, already in the config as a fallback). This is the experiment
   that would actually settle model choice — the one-shot bakeoff wasn't it.
4. **Use a strong model (Opus/Sonnet) as a loop-breaker, not a correctness judge.** The project's
   `zig:parity`/`zig:parity-replay` gates are a byte-exact RAM-compare oracle against the original 65816
   machine code — already a stronger correctness signal than any LLM judge could offer for game logic, and
   asking a strong model to judge correctness on top of that gate would mostly duplicate it. The failure
   mode actually worth targeting is the one AkitaOnRails documented: an open model stalls, generates a
   plan, and then loops on identical reasoning without progress. The high-value role for Opus/Sonnet is
   detecting that stall (repeated identical compiler error, or no new commit across N turns) and injecting
   a single targeted fix hint back into the local worker's loop — cheap, occasional escalation rather than
   reviewing every turn.
5. **Don't read the one-shot result as a verdict on Qwen3.6-27B.** It's the small-tier leader on both
   ArtificialAnalysis and SWE-bench, and its 27B reasoning variant's Intelligence Index (37) beats every
   model in the 40B-150B medium tier. The bakeoff's failures track directly to the "one-shot, no
   compiler feedback, skill not wired in" setup described in §1, not to a capability gap relative to its
   peers. Whether a bigger or coding-tuned model still wins once the loop is fixed is exactly what item 3
   is for — that's an empirical question, not something to assume either way.

## Conclusion

The bakeoff's implicit reading — "Qwen3.6-27B q8 isn't well suited for this after all" — doesn't survive
scrutiny. It's the strongest small open model by two independent published benchmarks, and the
experiment that produced the doubt (one-shot, no tools, no compiler feedback, skill added after the
fact) is not the setup the burn pipeline actually uses. The AkitaOnRails result shows there is a real,
current gap between frontier commercial models and today's open models specifically on agentic Zig
work — but the shape of that gap (stalling/looping, not "picks worse code") points at harness fixes
(compiler-in-the-loop tightening, a stall-triggered strong-model escalation) rather than a model swap.
The agentic A/B re-bench in §5.3 is the follow-up that would replace this doc's inherited assumption with
real data.
