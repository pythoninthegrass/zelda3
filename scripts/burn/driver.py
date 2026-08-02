#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.12"
# dependencies = ["python-decouple>=3.8", "pyyaml>=6.0"]
# ///

# pyright: reportMissingImports=false

"""
Overnight backlog-burn driver for the zelda3 C -> Zig port, on the mf GPU box.

Adapted from ~/git/llmao's scripts/burn/driver.py (feat/backlog-burn-20260728).
Differences from that driver, all deliberate:
  - The task queue is the LIVE backlog (backlog/tasks/*.md frontmatter), not a
    static manifest file, so the driver survives this actively-developed repo
    changing shape between runs. "Ready" = status "To Do", every dependency
    Done, not in SKIP_LIST, and a dotted id (a leaf task, not a phase parent).
  - Single machine, single branch: work happens on feat/zig-port-burn directly.
    Commits stay LOCAL (no push/pull) unless --push / BURN_PUSH is set.
  - verify() runs the project's OWN existing + newly-added gates (task
    zig:build/zig:test/zig:difftest/zig:parity/zig:parity-replay/build) rather
    than a project-specific test runner.
  - After a leaf task goes Done, if every sibling leaf under the same phase
    parent (TASK-002/003/004) is now Done, the parent is marked Done too.

Sequentially works the live queue: for each ready task it cuts a detached git
worktree off the branch tip, launches one `hermes chat` run (Fireworks
orchestrator, builders delegated to local Qwen via lemonade per
~/.hermes/config.yaml) inside a herdr agent pane, gates the result (TASK:DONE
marker + new commits + all gates green), then fast-forwards the branch.
Failed work is discarded; the branch only ever advances green.

Usage:
    ./scripts/burn/driver.py run [--once] [--push]
    ./scripts/burn/driver.py status
    ./scripts/burn/driver.py kill      # emergency: SIGKILL everything now
    ./scripts/burn/driver.py resume    # clear kill state and continue
"""

import argparse
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
import yaml
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decouple import Config, RepositoryEnv, config
from pathlib import Path

BURN = Path(os.environ.get("BURN_DIR", Path.home() / "burn-zelda3"))
KILL_FILE = BURN / "KILL"
ORCH_OVERRIDE = BURN / "ORCH_OVERRIDE"
HEARTBEAT = BURN / "status" / "state.log"
REPO = Path(config("BURN_REPO", default=str(Path.home() / "git/zelda3")))
BRANCH = config("BURN_BRANCH", default="feat/zig-port-burn")
SECRETS_ENV = Path(config("BURN_SECRETS_ENV", default=str(Path.home() / "git/linux_setup/.env")))
ORCH_MODEL = config("BURN_ORCH_MODEL", default="accounts/fireworks/models/kimi-k3")
ORCH_PROVIDER = config("BURN_ORCH_PROVIDER", default="fireworks")
FALLBACK_MODEL = config("BURN_FALLBACK_MODEL", default="Qwen3.6-27B-MTP-GGUF")
FALLBACK_PROVIDER = config("BURN_FALLBACK_PROVIDER", default="lemonade")
LEMONADE_URL = config("BURN_LEMONADE_URL", default="http://127.0.0.1:13305/api/v1/models")
TASK_TIMEOUT_S = config("BURN_TASK_TIMEOUT_S", default=4500, cast=int)
MAX_ATTEMPTS = config("BURN_MAX_ATTEMPTS", default=2, cast=int)
MAX_TURNS = config("BURN_MAX_TURNS", default=150, cast=int)
FAST_FAIL_S = 90  # a hermes run dying faster than this suggests provider trouble, not task trouble
POLL_S = 15

# TASK-004.09 (sprite_main.c, 25.8kLOC) needs human/Claude subdivision into
# smaller subtasks before a burn worker can tackle it. The dependency chain is
# strictly linear, so this doesn't let the driver skip past it and keep
# going -- it just means the queue goes empty (not "stuck spinning") once
# this is the only remaining ready leaf, which is the intended behavior.
SKIP_LIST = {"TASK-004.09"}

TASKS_DIR = "backlog/tasks"
EXIT_MARKER = "=== HERMES_EXIT:"
ATTEMPTS: dict[str, int] = {}  # in-memory attempt counter, keyed by task id (no manifest file to persist it)


def now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def heartbeat(task: str, attempt: int, phase: str, status: str) -> None:
    HEARTBEAT.parent.mkdir(parents=True, exist_ok=True)
    with HEARTBEAT.open("a") as f:
        f.write(f"{now()} task={task} attempt={attempt} phase={phase} status={status}\n")


def sh(*args: str, cwd: Path | None = None, check: bool = True, timeout: int = 300, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, check=check, timeout=timeout, env=env, capture_output=True, text=True)


def git(*args: str, cwd: Path = REPO, check: bool = True) -> subprocess.CompletedProcess:
    return sh("git", *args, cwd=cwd, check=check)


def backlog(*args: str, cwd: Path = REPO, check: bool = True) -> subprocess.CompletedProcess:
    return sh("backlog", *args, cwd=cwd, check=check)


# ---------------------------------------------------------------------------
# Live backlog queue (replaces llmao's manifest.txt)
# ---------------------------------------------------------------------------

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


@dataclass
class Task:
    id: str
    status: str
    dependencies: list[str] = field(default_factory=list)
    parent_task_id: str | None = None
    ordinal: int = 0
    file: Path = None


def read_frontmatter(md: Path) -> dict:
    m = FRONTMATTER_RE.match(md.read_text())
    if not m:
        raise ValueError(f"no frontmatter in {md}")
    return yaml.safe_load(m.group(1)) or {}


def load_tasks(repo: Path = REPO) -> dict[str, Task]:
    tasks = {}
    for f in sorted((repo / TASKS_DIR).glob("*.md")):
        fm = read_frontmatter(f)
        tid = fm["id"]
        tasks[tid] = Task(
            id=tid,
            status=fm.get("status", ""),
            dependencies=fm.get("dependencies") or [],
            parent_task_id=fm.get("parent_task_id"),
            ordinal=fm.get("ordinal") or 0,
            file=f,
        )
    return tasks


def next_ready(repo: Path = REPO) -> str | None:
    tasks = load_tasks(repo)
    ready = [
        t
        for t in tasks.values()
        if "." in t.id  # leaf task, not a phase parent (TASK-002 vs TASK-002.01)
        and t.id not in SKIP_LIST
        and t.status == "To Do"
        and all(tasks.get(d, Task("", "")).status == "Done" for d in t.dependencies)
    ]
    if not ready:
        return None
    ready.sort(key=lambda t: (t.ordinal, t.id))
    return ready[0].id


def task_md(wt: Path, task: str) -> Path:
    matches = sorted((wt / TASKS_DIR).glob(f"{task.lower()} - *.md"))
    if not matches:
        raise FileNotFoundError(f"no task file for {task}")
    return matches[0]


def close_out_completed_phase_parent(task: str, repo: Path = REPO) -> None:
    """After `task` (a leaf) goes Done, mark its phase parent Done too if every sibling leaf is Done."""
    tasks = load_tasks(repo)
    t = tasks.get(task)
    if t is None or t.parent_task_id is None:
        return
    parent = tasks.get(t.parent_task_id)
    if parent is None or parent.status == "Done":
        return
    siblings = [x for x in tasks.values() if x.parent_task_id == t.parent_task_id]
    if siblings and all(s.status == "Done" for s in siblings):
        backlog("task", "edit", parent.id, "-s", "Done", cwd=repo, check=False)
        git("add", TASKS_DIR, cwd=repo, check=False)
        git("commit", "-m", f"chore(backlog): close out {parent.id} ({len(siblings)} leaves Done)", cwd=repo, check=False)


# ---------------------------------------------------------------------------
# Secrets / orchestrator selection (verbatim shape from llmao)
# ---------------------------------------------------------------------------


def load_secrets() -> dict:
    env = dict(os.environ)
    # mise shims so zig/task/uv/backlog resolve inside herdr panes and non-login shells
    env["PATH"] = f"{Path.home()}/.local/share/mise/shims:{Path.home()}/.local/bin:" + env.get("PATH", "")
    if SECRETS_ENV.exists():
        secrets = Config(RepositoryEnv(str(SECRETS_ENV)))
        env["FIREWORKS_API_KEY"] = secrets("FIREWORKS_API_KEY", default="")
        env["LEMONADE_API_KEY"] = secrets("LEMONADE_API_KEY", default="lemonade")
    return env


def preflight_lemonade() -> bool:
    for attempt in range(2):
        try:
            with urllib.request.urlopen(LEMONADE_URL, timeout=10) as r:
                if r.status == 200:
                    return True
        except OSError:
            pass
        if attempt == 0:
            subprocess.run(["docker", "restart", "lemonade-server"], check=False, timeout=120)
            time.sleep(90)
    return False


def orch() -> tuple[str, str]:
    if ORCH_OVERRIDE.exists():
        model, provider = ORCH_OVERRIDE.read_text().strip().split("|")
        return model, provider
    return ORCH_MODEL, ORCH_PROVIDER


def herdr_available() -> bool:
    try:
        return subprocess.run(["herdr", "agent", "list"], capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


HERMES_CMD = (
    'set -o pipefail; hermes chat -q "$(cat "$BURN_PROMPT")" --model "$BURN_MODEL" --provider "$BURN_PROVIDER" '
    '--yolo -Q --max-turns "$BURN_MAX_TURNS" --accept-hooks 2>&1 | tee "$BURN_LOG"; '
    'echo "=== HERMES_EXIT:$? ===" >> "$BURN_LOG"'
)


def launch_hermes(task: str, wt: Path, prompt_file: Path, log: Path, env: dict) -> None:
    model, provider = orch()
    task_env = {
        "BURN_PROMPT": str(prompt_file), "BURN_LOG": str(log),
        "BURN_MODEL": model, "BURN_PROVIDER": provider, "BURN_MAX_TURNS": str(MAX_TURNS),
    }
    if herdr_available():
        cmd = ["herdr", "agent", "start", task, "--cwd", str(wt), "--no-focus"]
        for k, v in {**task_env, "FIREWORKS_API_KEY": env.get("FIREWORKS_API_KEY", ""), "LEMONADE_API_KEY": env.get("LEMONADE_API_KEY", ""), "PATH": env["PATH"]}.items():
            cmd += ["--env", f"{k}={v}"]
        cmd += ["--", "bash", "-c", HERMES_CMD]
        if subprocess.run(cmd, check=False, timeout=60).returncode == 0:
            return
    # fallback: run hermes as a direct child in its own process group
    proc = subprocess.Popen(["bash", "-c", HERMES_CMD], cwd=wt, env={**env, **task_env}, start_new_session=True)
    (BURN / "pids" / task).write_text(str(proc.pid))


def kill_task_processes(task: str) -> None:
    subprocess.run(["herdr", "pane", "close", task], check=False, capture_output=True, timeout=15)
    pidfile = BURN / "pids" / task
    if pidfile.exists():
        try:
            os.killpg(int(pidfile.read_text().strip()), signal.SIGKILL)
        except (ProcessLookupError, ValueError, PermissionError):
            pass
        pidfile.unlink(missing_ok=True)
    subprocess.run(["pkill", "-9", "-f", "hermes chat"], check=False)
    # the parity-replay gate leaves headless sway/zelda3/wtype behind on a hard kill
    for name in ("zelda3", "sway", "wtype"):
        subprocess.run(["pkill", "-9", "-x", name], check=False)


def wait_for_exit(log: Path) -> tuple[bool, float]:
    start = time.time()
    while time.time() - start < TASK_TIMEOUT_S:
        if KILL_FILE.exists():
            return False, time.time() - start
        if log.exists() and EXIT_MARKER in log.read_text(errors="replace")[-2000:]:
            return True, time.time() - start
        time.sleep(POLL_S)
    return False, time.time() - start


# ---------------------------------------------------------------------------
# Verification: reuse the project's own gates, no project-specific test runner
# ---------------------------------------------------------------------------


@dataclass
class Verdict:
    ok: bool
    reason: str


GATES = [
    ("zig:build", 300),
    ("zig:test", 120),
    ("zig:difftest", 120),
    ("zig:parity", 60),
    ("zig:parity-replay", 600),
    ("build", 300),  # the C reference build must still link (DoD: zelda3.bak stays working)
]


def run_gates(wt: Path, env: dict) -> Verdict:
    for gate, timeout_s in GATES:
        r = subprocess.run(["task", gate], cwd=wt, env=env, capture_output=True, text=True, timeout=timeout_s)
        if r.returncode != 0:
            tail = (r.stdout[-800:] + r.stderr[-800:]).strip()
            return Verdict(False, f"gate {gate} failed: {tail[-300:]}")
    return Verdict(True, "all gates green")


def verify(task: str, wt: Path, log: Path, env: dict) -> Verdict:
    text = log.read_text(errors="replace") if log.exists() else ""
    if f"=== TASK:BAIL {task}" in text:
        m = re.search(rf"=== TASK:BAIL {task} reason=(.*?) ===", text)
        return Verdict(False, f"bail: {m.group(1) if m else 'unknown'}")
    if f"=== TASK:DONE {task} ===" not in text:
        return Verdict(False, "no DONE marker")
    commits = int(git("rev-list", "--count", f"{BRANCH}..HEAD", cwd=wt).stdout.strip())
    if commits < 1:
        return Verdict(False, "no new commits")
    gate_verdict = run_gates(wt, env)
    if not gate_verdict.ok:
        return gate_verdict
    ensure_backlog_done(task, wt)
    return Verdict(True, f"{commits} commits, {gate_verdict.reason}")


def ensure_backlog_done(task: str, wt: Path) -> None:
    """Force the task's backlog status to Done in the worktree before merge.

    A worker that hits --max-turns mid-run gets forced into a final summary
    turn: it can print the TASK:DONE marker and describe having run
    `backlog task edit ... -s Done` without that tool call actually executing.
    Gates already passed and code is already committed at this point, so the
    work is real -- but next_ready() reads task status from disk, and a task
    left "To Do" gets handed straight back out for a redundant re-run. Belt
    and braces: check status and fix it here rather than trust self-report.
    """
    tasks = load_tasks(wt)
    if tasks.get(task, Task("", "")).status == "Done":
        return
    backlog("task", "edit", task, "-s", "Done", cwd=wt, check=False)
    git("add", TASKS_DIR, cwd=wt, check=False)
    git(
        "commit", "-m",
        f"chore(backlog): force-mark {task} done (gates green, worker turn-capped before its own bookkeeping ran)",
        cwd=wt, check=False,
    )


def merge_local(wt: Path, push: bool) -> bool:
    sha = git("rev-parse", "HEAD", cwd=wt).stdout.strip()
    if git("merge", "--ff-only", sha, check=False).returncode != 0:
        return False
    if push:
        git("push", "origin", BRANCH, check=False)
    return True


# ---------------------------------------------------------------------------
# Main loop (shape verbatim from llmao; queue + verify + no-push swapped in)
# ---------------------------------------------------------------------------


def cmd_run(once: bool, push: bool) -> int:
    for d in ("logs", "pids", "prompts", "status", "wt"):
        (BURN / d).mkdir(parents=True, exist_ok=True)
    (BURN / "pids/driver").write_text(str(os.getpid()))
    env = load_secrets()
    header = (REPO / "scripts/burn/prompt_header.txt").read_text()
    fast_fails = 0

    if git("branch", "--show-current", cwd=REPO).stdout.strip() != BRANCH:
        git("checkout", BRANCH, cwd=REPO)

    while (task := next_ready()) is not None:
        if KILL_FILE.exists():
            print("KILL sentinel present; stopping.")
            return 1
        if not preflight_lemonade():
            heartbeat(task, 0, "preflight", "LEMONADE_DOWN")
            return 3
        wt = BURN / "wt" / task
        subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
        git("worktree", "add", "--detach", str(wt), BRANCH)
        md = task_md(wt, task)
        prompt_file = BURN / "prompts" / f"{task}.txt"
        prompt_file.write_text(header + "\n\n=== TASK FILE ===\n" + md.read_text())
        attempt = ATTEMPTS[task] = ATTEMPTS.get(task, 0) + 1
        log = BURN / "logs" / f"{task}.a{attempt}.log"
        (BURN / "logs/current").unlink(missing_ok=True)
        (BURN / "logs/current").symlink_to(log)
        heartbeat(task, attempt, "start", f"model={orch()[0]}")
        launch_hermes(task, wt, prompt_file, log, env)
        finished, elapsed = wait_for_exit(log)
        if not finished:
            kill_task_processes(task)
        verdict = verify(task, wt, log, env)
        if verdict.ok and merge_local(wt, push):
            close_out_completed_phase_parent(task)
            heartbeat(task, attempt, "end", "DONE")
            fast_fails = 0
        elif verdict.ok:
            heartbeat(task, attempt, "end", "MERGEFAIL")
            return 2  # branch tip moved out from under us; a human reconciles and restarts
        else:
            blocked = attempt >= MAX_ATTEMPTS
            heartbeat(task, attempt, "end", f"{'BLOCKED' if blocked else 'FAILED'} {verdict.reason[:120]}")
            if elapsed < FAST_FAIL_S:
                fast_fails += 1
                if fast_fails >= 3 and not ORCH_OVERRIDE.exists():
                    ORCH_OVERRIDE.write_text(f"{FALLBACK_MODEL}|{FALLBACK_PROVIDER}\n")
                    heartbeat(task, attempt, "fallback", f"orchestrator -> {FALLBACK_MODEL}")
                    fast_fails = 0
            else:
                fast_fails = 0
            if blocked:
                subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
                kill_task_processes(task)
                # a BLOCKED task never becomes ready again (attempts exhausted, status
                # still "To Do"); next_ready() would just hand it right back, so stop
                # rather than spin. The worktree for the failed attempt is removed
                # above; logs under BURN/logs/{task}.a*.log survive for post-mortem.
                print(f"{task} BLOCKED after {attempt} attempts; stopping for triage.")
                return 4
        subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
        kill_task_processes(task)  # belt-and-braces: nothing survives a task boundary
        if once:
            break
    heartbeat("-", 0, "exit", "QUEUE_DRAINED" if next_ready() is None else "ONCE")
    return 0


def cmd_kill() -> int:
    BURN.mkdir(parents=True, exist_ok=True)
    KILL_FILE.write_text(now() + "\n")  # sentinel first so a racing driver cannot start the next task
    pids_dir = BURN / "pids"
    if pids_dir.exists():
        for pidfile in pids_dir.iterdir():
            try:
                os.killpg(int(pidfile.read_text().strip()), signal.SIGKILL)
            except (ProcessLookupError, ValueError, PermissionError):
                pass
    subprocess.run(["pkill", "-9", "-f", "hermes chat"], check=False)
    subprocess.run(["pkill", "-9", "-f", "driver.py run"], check=False)
    for name in ("zelda3", "sway", "wtype"):
        subprocess.run(["pkill", "-9", "-x", name], check=False)
    subprocess.run(["herdr", "pane", "close", "driver"], check=False, capture_output=True, timeout=15)
    heartbeat("-", 0, "kill", "KILLED")
    print("killed. worktrees left intact for post-mortem; `driver.py resume` to continue.")
    return 0


def cmd_resume(push: bool) -> int:
    KILL_FILE.unlink(missing_ok=True)
    subprocess.run(["git", "worktree", "prune"], cwd=REPO, check=False)
    for wt in (BURN / "wt").glob("TASK-*"):
        subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
    return cmd_run(once=False, push=push)


def cmd_status() -> int:
    tasks = load_tasks()
    counts: dict[str, int] = {}
    for t in tasks.values():
        if "." not in t.id:
            continue  # phase parents don't count toward leaf progress
        counts[t.status] = counts.get(t.status, 0) + 1
    print("backlog:", " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    nxt = next_ready()
    print("next ready:", nxt or "none (queue drained or stalled on SKIP_LIST)")
    print("kill sentinel:", "PRESENT" if KILL_FILE.exists() else "absent")
    if ORCH_OVERRIDE.exists():
        print("orchestrator override:", ORCH_OVERRIDE.read_text().strip())
    if HEARTBEAT.exists():
        print("last heartbeats:")
        for line in HEARTBEAT.read_text().splitlines()[-5:]:
            print(" ", line)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    runp = sub.add_parser("run", help="work the live backlog queue")
    runp.add_argument("--once", action="store_true", help="process a single task then exit")
    runp.add_argument("--push", action="store_true", help="also push the branch to origin after each merge")
    resp = sub.add_parser("resume", help="clear kill state, requeue stale state, continue")
    resp.add_argument("--push", action="store_true")
    sub.add_parser("status", help="print backlog progress + heartbeats")
    sub.add_parser("kill", help="emergency stop: SIGKILL driver + all hermes trees + playtest processes")
    args = p.parse_args()
    match args.cmd:
        case "run":
            return cmd_run(args.once, args.push)
        case "status":
            return cmd_status()
        case "kill":
            return cmd_kill()
        case "resume":
            return cmd_resume(args.push)
    return 1


if __name__ == "__main__":
    sys.exit(main())
