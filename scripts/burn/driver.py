#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# dependencies = [
#     "python-decouple>=3.8",
#     "burnkit @ git+https://github.com/pythoninthegrass/burnkit",
# ]
# ///

"""Overnight backlog-burn driver for the C -> Zig port: this repo's burnkit config.

burnkit owns the queue, the per-task git worktree lifecycle, the launch
backends, the finish-marker protocol, and the proof-of-done gates. Everything
here is what makes those specific to this port: the models, the seven Zig
gates, the local-only burn branch, the pre-port ROM the parity oracle needs,
and the hand-tuned prompt prose in the sibling prompt_header*.txt files.

Two behaviors that used to live in this file and now come from burnkit are
worth naming, because both were bugs:

  - Termination is scoped to the process group of a pid the launched shell
    recorded. The old code ran `pkill -9 -f "hermes chat"` and `pkill -9 -x`
    over zelda3/sway/wtype, machine-wide, and killed an unrelated session.
  - An attempt's commits land on a per-task branch that is fast-forwarded into
    the burn branch on success and retired otherwise, so the driver no longer
    needs this repo's own checkout to have that branch out.

Commands are unchanged: ./scripts/burn/driver.py {run,resume,status,kill}.
"""

import os
from burnkit import (
    ANY_PATH,
    BurnConfig,
    FastForwardBranch,
    MachineGate,
    copy_prepare,
    dsh_backend,
    hermes_backend,
    preflight_local_model,
    run_from_cli,
)
from decouple import config
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

BURN = Path(os.environ.get("BURN_DIR", Path.home() / "burn-zelda3"))
REPO = Path(config("BURN_REPO", default=str(Path.home() / "git/zelda3")))
# Work happens on this branch directly and it deliberately never leaves the
# machine: origin has only master. BASE_REMOTE stays empty so burnkit resolves
# the local branch rather than a remote-tracking ref that does not exist.
BRANCH = config("BURN_BRANCH", default="feat/zig-port-burn")
BASE_REMOTE = config("BURN_BASE_REMOTE", default="")
PUSH = config("BURN_PUSH", default=False, cast=bool)
SECRETS_ENV = Path(config("BURN_SECRETS_ENV", default=str(Path.home() / "git/linux_setup/.env")))
DSH_ENV_FILE = Path(config("BURN_DSH_ENV", default=str(Path.home() / "git/dsh_config/.env")))
ORCH_MODEL = config("BURN_ORCH_MODEL", default="accounts/fireworks/models/deepseek-v4-flash-0731")
ORCH_PROVIDER = config("BURN_ORCH_PROVIDER", default="fireworks")
BUILDER_MODEL = config("BURN_BUILDER_MODEL", default="qwen3.8-27b-fp8")
BUILDER_PROVIDER = config("BURN_BUILDER_PROVIDER", default="vllm")
FALLBACK_MODEL = config("BURN_FALLBACK_MODEL", default="qwen3.8-27b-fp8")
FALLBACK_PROVIDER = config("BURN_FALLBACK_PROVIDER", default="vllm")
HEALTH_CHECK_URL = config("BURN_HEALTH_URL", default="http://127.0.0.1:61519/v1/models")
TASK_TIMEOUT_S = config("BURN_TASK_TIMEOUT_S", default=4500, cast=int)
MAX_ATTEMPTS = config("BURN_MAX_ATTEMPTS", default=2, cast=int)
MAX_TURNS = config("BURN_MAX_TURNS", default=150, cast=int)
BURN_BACKEND = config("BURN_BACKEND", default="dsh")

# TASK-004.09 (sprite_main.c, 25.8kLOC) needs human subdivision into smaller
# subtasks before a burn worker can tackle it. The dependency chain is strictly
# linear, so this doesn't let the driver skip past it and keep going -- it just
# means the queue goes empty (not "stuck spinning") once this is the only
# remaining ready leaf, which is the intended behavior.
SKIP_LIST = frozenset({"TASK-004.09"})

TASKS_DIR = "backlog/tasks"

# Every task is gated as a code task, and no path is out of scope. A port task
# can be a pure build.zig or unit-test-list edit and still change what the
# parity oracle sees, so there is no prose-only task here; and no scope
# allow-list has ever been enforced, so guessing one would block legitimate
# overnight work rather than catch anything.
CODE_CHANGE_PREFIXES = ANY_PATH
CODE_TASK_ALLOWED_PREFIXES = ANY_PATH

# Run unconditionally and in this order: the DoD is that the branch only ever
# advances green. Timeouts are per-gate because they differ by an order of
# magnitude -- parity-replay is 13 chapters at ~12s each.
MACHINE_GATES = (
    MachineGate("prek", ("task", "prek"), timeout_s=180),  # lint + correctness hooks over the whole tree
    MachineGate("zig:build", ("task", "zig:build"), timeout_s=300),
    MachineGate("zig:test", ("task", "zig:test"), timeout_s=120),
    MachineGate("zig:difftest", ("task", "zig:difftest"), timeout_s=120),
    MachineGate("zig:parity", ("task", "zig:parity"), timeout_s=60),
    MachineGate("zig:parity-replay", ("task", "zig:parity-replay"), timeout_s=600),
    MachineGate("build", ("task", "build"), timeout_s=300),  # the C reference build must still link (zelda3.bak stays working)
)

CONTEXT7_LINE = (
    "Context7 is available for zig/taskfile/backlog.md documentation — use it rather than guessing at Zig 0.16 API shapes."
)

# The parity oracle diffs against the original machine code, which needs the ROM
# in the worktree. It is gitignored, so a fresh worktree has none and every
# parity gate would fail for a reason unrelated to the port. Copied rather than
# linked because a gate may write alongside it.
ROM_RELS = ("zelda3.sfc",)
prepare_rom = copy_prepare(REPO, ROM_RELS)


def health_check(backend: str) -> bool:
    """vLLM/llama-swap serves hermes' delegated builders; dsh's model is fully
    local and doesn't touch it, so only hermes needs this preflight."""
    return backend != "hermes" or preflight_local_model(HEALTH_CHECK_URL)


CONFIG = BurnConfig(
    project="zelda3",
    burn_dir=BURN,
    repo=REPO,
    base_branch=BRANCH,
    base_remote=BASE_REMOTE,
    author="pythoninthegrass",
    task_id_prefix="TASK",
    example_task_id="TASK-002.01",
    tasks_dir=TASKS_DIR,
    skip_list=SKIP_LIST,
    model=ORCH_MODEL,
    provider=ORCH_PROVIDER,
    builder_model=BUILDER_MODEL,
    builder_provider=BUILDER_PROVIDER,
    fallback_model=FALLBACK_MODEL,
    fallback_provider=FALLBACK_PROVIDER,
    health_check_url=HEALTH_CHECK_URL,
    secrets_env=SECRETS_ENV,
    dsh_env_file=DSH_ENV_FILE,
    default_backend=BURN_BACKEND,
    launch_secrets={"FIREWORKS_API_KEY": "", "LOCAL_API_KEY": "lemonade"},
    health_check=health_check,
    task_timeout_s=TASK_TIMEOUT_S,
    max_attempts=MAX_ATTEMPTS,
    max_turns=MAX_TURNS,
    code_change_prefixes=CODE_CHANGE_PREFIXES,
    code_task_allowed_prefixes=CODE_TASK_ALLOWED_PREFIXES,
    machine_gates=MACHINE_GATES,
    # Nothing here opens a pull request for a human to close a phase parent on,
    # so the last Done leaf under TASK-002/003/004 sweeps its parent up.
    close_out_phase_parents=True,
    prompt_project_fragment=SCRIPT_DIR / "prompt_header.txt",
    extra_bail_conditions=("an ABI or API-shape decision only a human should make",),
    context7_line=CONTEXT7_LINE,
)

BACKENDS = {
    "hermes": hermes_backend(CONFIG, prepare_worktree=prepare_rom),
    "dsh": dsh_backend(CONFIG, prepare_worktree=prepare_rom),
}

INTEGRATION = FastForwardBranch(CONFIG, branch=BRANCH, push=PUSH)

if __name__ == "__main__":
    run_from_cli(CONFIG, INTEGRATION, BACKENDS)
