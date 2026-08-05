# dsp.c → dsp.zig port bakeoff

One-shot chat-completion bakeoff of several local models against the same
"port `snes/dsp.c` to `snes/dsp.zig`" task, run against the actual completed
port (`d180e4e feat(zig): port snes/spc.c to spc.zig`'s sibling task) as
ground truth. All models ran via `lemonade-server` on `mf` against the
llama.cpp CUDA backend. No tool access, no agentic loop, no iteration — each
run is a single blind chat-completion call given the task description,
acceptance criteria, `dsp_regs.h`/`dsp.h`/`dsp.c`, and the already-completed
`dma.zig` port as a style precedent. None of the candidates produced a file
that compiles.

## Models tested

| Model | Quant | Draft/speculative | Result |
|---|---|---|---|
| MiniMax-M2.7 | Q2_K_XL | none | compiles fails (syntax error) |
| Laguna-S-2.1 | Q2_K_XL | none | never converged (deleted after) |
| Qwen3.6-27B | Q8_K_XL | DFlash | 3 runs, 7/13/14 build errors |

## MiniMax-M2.7-UD-Q2_K_XL

Needed a retry (`max_tokens` 8192 → 15400) to reach `finish_reason: stop`.
Produced 586 lines. **Fails to compile**: mismatched parentheses in the echo
buffer address calculation (`dsp.zig:237`) — the sibling `adr+3` expression is
correctly parenthesized but the `adr+2` one is missing a wrapping paren.

## Laguna-S-2.1-UD-Q2_K_XL

Never produced usable output across two attempts. First attempt hit the
32768-token context ceiling mid-reasoning. Reloaded with `ctx=65536` and
retried at `max_tokens=40000` — burned the entire budget (~145k chars of
reasoning) without concluding (`finish_reason: length`, `content` empty).
Total spend across both attempts: ~58,900 tokens with zero usable output.
Model was subsequently deregistered from lemonade and its 37GB checkpoint
deleted from disk (`rm -rf .../Laguna-S-2.1-GGUF`).

## Qwen3.6-27B-UD-Q8_K_XL + DFlash draft (`z-lab/Qwen3.6-27B-DFlash`)

Registered in lemonade as a single `main`+`draft` checkpoint pair
(`qwen3.6-27b-q8-dflash`), since draft models can only be wired at
registration time, not via `--llamacpp-args --model-draft` (lemonade rejects
that flag as reserved). Three runs against this same registration:

### Run 1 — naive prompt

Same plain task prompt as the other two models. Needed a retry
(`max_tokens` 15400 → 44000) to reach `stop` (27,037 completion tokens).
**7 build errors**: one `@intCast` missing an explicit result type (line
259), five `@truncate`/`@intCast` signedness mismatches (lines 124, 167,
314, 331, 513), one `var` that should be `const` (line 556).

### Run 2 — AGENTS.md + explicit prek/self-check instructions

Same task, but the prompt prepended this repo's full `AGENTS.md` and added
explicit instructions to mentally run `prek run zig-fmt` and audit every
`@intCast`/`@truncate` call for signedness before finalizing. Reached `stop`
on the first try (29,778 completion tokens, larger prompt due to AGENTS.md).
**Fails `zig fmt`**, and **13 build errors**: 9 `var`→`const`, 2
`@memset`-on-fixed-array (needs a slice, not an array value — lines 120,
490), 2 signedness mismatches (lines 252, 271).

### Run 3 — naive prompt repeated (variance check)

Identical prompt to run 1, rerun to check whether run 2's higher error count
was a real regression from the added instructions or just sampling noise.
Reached `stop` on the first try (30,608 completion tokens). **Fails `zig
fmt`**, and **14 build errors**: 9 `var`→`const`, 3 signedness mismatches, one
`@intFromFloat` missing a result type (line 532), and two new `u3` bitfield
overflow errors not seen in the other two runs (`type 'u3' cannot represent
integer value '8'`, lines 338 and 462).

**Conclusion**: run 3's error count (14) lands closer to run 2's (13) than to
run 1's (7), with no error class that the AGENTS.md/prek instructions
targeted actually going away. This is sampling variance in the model's
output, not a regression caused by the extra prompt content — the added
instructions didn't measurably help or hurt.

### Throughput

Consistent across all three successful Qwen generations: ~37-38 tokens/sec
(708s for 27,037 tokens; 792s for 29,778 tokens), measured from request/
response JSON file mtimes on `mf` (no other timing instrumentation exists).

## Recurring failure signature

Across every Qwen sample, and independent of prompt variant, two Zig 0.16
strictness rules account for most errors:

1. A `var` that's never subsequently mutated is a hard compile error, not a
   lint warning — every run had several locals declared `var` that should
   have been `const`.
2. `@truncate`/`@intCast` require the operand to already be the correct
   signedness; casting a signed value directly is rejected, and `@intCast`
   sometimes additionally needs an explicit `@as(T, ...)` when the
   destination type isn't inferable from context.

MiniMax's single failure was a plain syntax error (unbalanced parens) rather
than a Zig-semantics issue — a different failure mode from all three Qwen
runs.

## Byproduct: pre-commit gate hardening

Running these prompts through `zig build`/`prek` surfaced that the repo's
`zig-fmt` pre-commit hook alone doesn't catch semantic compile errors like
the ones above. Added a `zig-build` hook to `.pre-commit-config.yaml`
(`805d308`, pushed to `master`) so `zig build` runs as part of the standard
gate. `scripts/burn/driver.py`'s own gate list was separately updated by
Lance (`67d4435`) to require a `prek` pass alongside the existing
`zig:build`/`zig:test`/`zig:difftest`/`zig:parity` gates.

<!-- AB:BEGIN -->
## Agentic re-bench (tools + gates)

Re-benches the same candidate models on **TASK-003.01** (`snes/input.c` -> `snes/input.zig`), but this time with the real burn regime: tool access, compiler feedback, and up to N turns per `scripts/burn/driver.py`'s gate sequence -- scored by gates passed, not one-shot compile success. Ground truth is the merged commit `27870780` (parity-verified 7/7), replayed from its pre-port base `8605e2c0`, so 7/7 is known-achievable.

How to read: `gates` = X/7 of `driver.GATES` (prek, zig:build, zig:test, zig:difftest, zig:parity, zig:parity-replay, build), run non-short-circuiting so a partial score reflects how far the attempt got. How to run: `./scripts/burn/benchmark.py run` (bare invocation replays TASK-003.01 across all 3 default candidates). `results.json` in the output dir is the machine-readable artifact.

| Model | Task | Gates | Turns | Tool calls | Wall-clock | Status |
|---|---|---|---|---|---|---|
| Qwen3.6-35B-A3B-MTP-GGUF | TASK-003.01 | 6/7 | ? | ? | 1200s | no marker (timed out) |
| Qwen3-Coder-Next-GGUF | TASK-003.01 | 3/7 | ? | ? | 625s | no marker |
| Qwen3.6-27B-MTP-GGUF | TASK-003.01 | 6/7 | ? | ? | 1200s | no marker (timed out) |

Per-gate detail:

| Model | Task | prek | zig:build | zig:test | zig:difftest | zig:parity | zig:parity-replay | build |
|---|---|---|---|---|---|---|---|---|
| Qwen3.6-35B-A3B-MTP-GGUF | TASK-003.01 | y | y | n | y | y | y | y |
| Qwen3-Coder-Next-GGUF | TASK-003.01 | n | n | y | y | n | n | y |
| Qwen3.6-27B-MTP-GGUF | TASK-003.01 | y | y | n | y | y | y | y |

Note: a `KeyboardInterrupt` inside `zig:parity`/`zig:parity-replay` tails means the model's build
genuinely failed to compile -- Task runs the `build` and `:assets` deps concurrently, and
cancels the sibling `:assets` step via SIGINT once `build` fails. The parity gate's fail verdict
is correct; the traceback is just Task's cancellation mechanism, not an infra bug.
<!-- AB:END -->
