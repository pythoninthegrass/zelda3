#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.12"
# dependencies = ["python-decouple>=3.8", "pyyaml>=6.0", "jinja2>=3.1"]
# ///

# pyright: reportMissingImports=false

"""
Agentic A/B benchmark harness: re-bench local builder models on a completed
Zig port, giving each candidate the same tool access / compiler feedback /
multi-turn regime scripts/burn/driver.py gives a real burn worker, and
scoring by gates passed (partial credit) rather than one-shot compile
success. See docs/bakeoff.md's one-shot bakeoff for the measurement this is
meant to correct.

Reuses scripts/burn/driver.py read-only (GATES, load_secrets,
preflight_lemonade, git/sh helpers, kill_task_processes) -- never imports its
main() and never mutates driver.GATES or the feat/zig-port-burn branch. Each
candidate runs solo (delegation off) against an isolated per-model
$HOME/.hermes so multiple models' session stores/state never collide, inside
a throwaway --detach git worktree cut from a completed port's pre-port base
SHA, with a fixed guardrail bundle (zig-0.16 skill + pre-commit hooks
including zig ast-check) overlaid so every candidate is measured with the
same guardrails.

Usage:
    ./scripts/burn/benchmark.py run [--models a,b,c] [--task TASK-003.01]
    ./scripts/burn/benchmark.py tasks
    ./scripts/burn/benchmark.py report <results.json>
    ./scripts/burn/benchmark.py status
    ./scripts/burn/benchmark.py kill
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from dataclasses import asdict, dataclass, field
from decouple import config
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import driver  # noqa: E402  read-only reuse: GATES, load_secrets, preflight_lemonade, git/sh, kill_task_processes

import jinja2  # noqa: E402
import yaml  # noqa: E402

REPO = driver.REPO
TEMPLATE_DIR = Path(__file__).resolve().parent / "templates"
BAKEOFF_MD = REPO / "docs" / "bakeoff.md"
AB_BEGIN = "<!-- AB:BEGIN -->"
AB_END = "<!-- AB:END -->"

LEMONADE_BASE_URL = config("LEMONADE_BASE_URL", default="http://127.0.0.1:13305/api/v1")
LEMONADE_KEY_ENV = config("LEMONADE_KEY_ENV", default="LEMONADE_API_KEY")
DEFAULT_MODELS = [
    m.strip()
    for m in config("MODELS", default="Qwen3.6-35B-A3B-MTP-GGUF,Qwen3-Coder-Next-GGUF,Qwen3.6-27B-MTP-GGUF").split(",")
    if m.strip()
]
DEFAULT_MAX_TURNS = config("MAX_TURNS", default=150, cast=int)
# Must match lemonade's llama-server --ctx-size so hermes's compression
# threshold is computed against the real runtime ceiling, not each model's
# much larger registered max_context_window.
LLM_CONTEXT_SIZE = config("LLM_CONTEXT_SIZE", default=131072, cast=int)
DEFAULT_TASK_TIMEOUT_S = config("TASK_TIMEOUT", default=1200, cast=int)
DEFAULT_OUT_DIR = Path(config("OUT_DIR", default=str(driver.BURN / "ab"))).expanduser()
DEFAULT_TASK = "TASK-003.01"
PROVIDER = "lemonade"

# Fixed, answer-neutral guardrail bundle overlaid into every worktree (plan
# Section 8). Never includes build.zig or any *.zig -- those are the answer
# the model must produce. These paths are read from the live REPO working
# tree (not git show HEAD) since the pre-commit/taskfile guardrail additions
# ship uncommitted alongside this harness.
GUARDRAIL_FILES = [".pre-commit-config.yaml", "taskfiles/zig.yml", "scripts/zig-ast-check.sh"]
# Splice-in only, never a whole-file copy: root taskfile.yml's `build` task
# grows new compile-zig-* deps as later ports land, so overlaying today's full
# file onto an old base SHA makes `task build` require .zig files (e.g.
# snes/apu.zig, snes/cart.zig) that don't exist yet at that replay point. Only
# `prek` (added after every base SHA this harness replays) needs injecting.
GUARDRAIL_TASKS = ["prek"]
SKILL_REAL_DIR = ".agents/skills/zig-0.16"
SKILL_SYMLINK = ".claude/skills/zig-0.16"

PORT_COMMIT_RE = re.compile(r"^feat\(zig\): port (\S+) to (\S+)")


def slugify(model: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", model)


# ---------------------------------------------------------------------------
# Completed-port discovery (drives `tasks` and the default replay target)
# ---------------------------------------------------------------------------


@dataclass
class PortTask:
    task_id: str
    c_path: str
    zig_path: str
    commit_sha: str
    base_sha: str
    c_lines: int
    zig_lines: int


def discover_port_tasks(repo: Path = REPO) -> list[PortTask]:
    log = driver.git("log", "--all", "--format=%H %s", "--grep=^feat(zig): port", cwd=repo)
    titles = {}
    for f in (repo / driver.TASKS_DIR).glob("*.md"):
        fm = driver.read_frontmatter(f)
        titles[(fm.get("title") or "").strip()] = fm["id"]

    out = []
    for line in log.stdout.splitlines():
        sha, _, subject = line.partition(" ")
        m = PORT_COMMIT_RE.match(subject)
        if not m:
            continue
        c_path, zig_name = m.group(1), m.group(2)
        zig_dir, _, _ = c_path.rpartition("/")
        zig_path = f"{zig_dir}/{zig_name}" if zig_dir else zig_name
        task_id = titles.get(f"Port {c_path} to {zig_name}")
        if task_id is None:
            continue  # title format didn't match this commit (e.g. multi-file ports); skip rather than guess
        base_sha = driver.git("rev-parse", f"{sha}^", cwd=repo).stdout.strip()
        zig_lines = len(driver.sh("git", "show", f"{sha}:{zig_path}", cwd=repo).stdout.splitlines())
        try:
            c_lines = len(driver.sh("git", "show", f"{base_sha}:{c_path}", cwd=repo).stdout.splitlines())
        except subprocess.CalledProcessError:
            c_lines = 0
        out.append(PortTask(task_id, c_path, zig_path, sha, base_sha, c_lines, zig_lines))
    out.sort(key=lambda t: t.zig_lines)
    return out


def find_port_task(task_id: str, base_override: str | None) -> PortTask:
    for t in discover_port_tasks():
        if t.task_id == task_id:
            if base_override:
                t.base_sha = driver.git("rev-parse", base_override, cwd=REPO).stdout.strip()
            return t
    if base_override:
        return PortTask(task_id, "", "", "", driver.git("rev-parse", base_override, cwd=REPO).stdout.strip(), 0, 0)
    raise SystemExit(f"{task_id} is not a discoverable completed single-file zig port; pass --base to override.")


# ---------------------------------------------------------------------------
# Worktree isolation + guardrail overlay (never touches feat/zig-port-burn)
# ---------------------------------------------------------------------------


def cut_worktree(root: Path, model: str, task_id: str, base_sha: str) -> Path:
    wt = root / "wt" / slugify(model) / task_id
    subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
    shutil.rmtree(wt, ignore_errors=True)
    wt.parent.mkdir(parents=True, exist_ok=True)
    driver.git("worktree", "add", "--detach", str(wt), base_sha)
    rom = REPO / "zelda3.sfc"
    if rom.is_file():
        shutil.copy2(rom, wt / "zelda3.sfc")
    return wt


def inject_guardrail_tasks(wt: Path, task_names: list[str]) -> None:
    root_text = (REPO / "taskfile.yml").read_text()
    wt_taskfile = wt / "taskfile.yml"
    wt_text = wt_taskfile.read_text()
    additions = []
    for name in task_names:
        if re.search(rf"(?m)^  {re.escape(name)}:\s*$", wt_text):
            continue  # this base SHA's own taskfile.yml already has it
        m = re.search(rf"(?m)^  {re.escape(name)}:\n(?:(?:[ \t]{{4,}}.*)?\n)*", root_text)
        if not m:
            raise RuntimeError(f"guardrail task {name!r} not found in {REPO}/taskfile.yml")
        additions.append(m.group(0).rstrip("\n"))
    if additions:
        wt_taskfile.write_text(wt_text.rstrip("\n") + "\n\n" + "\n\n".join(additions) + "\n")


def overlay_guardrails(wt: Path, guardrails: bool, skills: bool) -> None:
    if not guardrails:
        return
    for rel in GUARDRAIL_FILES:
        src = REPO / rel
        dst = wt / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    inject_guardrail_tasks(wt, GUARDRAIL_TASKS)
    if not skills:
        return
    skill_dst = wt / SKILL_REAL_DIR
    shutil.rmtree(skill_dst, ignore_errors=True)
    shutil.copytree(REPO / SKILL_REAL_DIR, skill_dst)
    link_dst = wt / SKILL_SYMLINK
    link_dst.parent.mkdir(parents=True, exist_ok=True)
    if link_dst.exists() or link_dst.is_symlink():
        link_dst.unlink()
    link_dst.symlink_to(Path("../../.agents/skills/zig-0.16"))


AST_CHECK_MUTATED_RE = re.compile(r"^[^\n:]+:(?P<line>\d+):\d+: error: local variable is never mutated$", re.MULTILINE)


def fix_never_mutated_vars(wt: Path, max_rounds: int = 5) -> None:
    """Mechanically swap `var` -> `const` for zig-ast-check's "never mutated"
    findings, same drift-from-an-old-base-SHA rationale as the fmt fix but for
    a hook (zig-ast-check) that didn't exist at all when these base SHAs were
    committed. Bounded rounds since ast-check only reports the first error per
    file, so a file with N such vars needs N passes to fully clear.
    """
    zig_files = list(wt.rglob("*.zig"))
    for _ in range(max_rounds):
        hit = False
        for f in zig_files:
            r = subprocess.run(["zig", "ast-check", str(f)], cwd=wt, capture_output=True, text=True)
            if r.returncode == 0:
                continue
            m = AST_CHECK_MUTATED_RE.search(r.stderr)
            if not m:
                continue
            hit = True
            lineno = int(m.group("line"))
            lines = f.read_text().splitlines(keepends=True)
            lines[lineno - 1] = re.sub(r"\bvar\b", "const", lines[lineno - 1], count=1)
            f.write_text("".join(lines))
        if not hit:
            return


def run_prek_until_clean(wt: Path, max_rounds: int = 6) -> None:
    """Run prek's auto-fixers to convergence.

    A single pass under-fixes: e.g. ruff-check --fix only applies non-
    overlapping safe fixes per file per invocation, so a file needing several
    independent fixes takes several rounds (verified empirically: this repo's
    base-SHA drift needed 4 rounds to reach a clean exit, not the 2 a naive
    "run it twice" guess would assume).
    """
    for _ in range(max_rounds):
        r = subprocess.run(["prek", "run", "--all-files"], cwd=wt, check=False, capture_output=True)
        if r.returncode == 0:
            return


def normalize_worktree_fmt(wt: Path) -> str:
    """Apply every prek auto-fixer (zig-fmt, ruff-format/check --fix,
    end-of-file-fixer, mixed-line-ending, ...) plus a mechanical fix for
    zig-ast-check's "never mutated" findings (the one prek hook that only
    checks, never fixes), then commit the result before the model starts.

    Base SHAs predate today's tool versions and some hooks entirely (verified:
    zig-fmt drift also exists on live master, unrelated to any candidate's
    work; ruff/EOF drift is base-SHA-only, already clean on master), so
    without this every candidate's prek gate fails on issues it didn't
    introduce. Returns the resulting HEAD SHA so downstream commit
    counts/gate scoring measure only what the model itself does from here.
    """
    run_prek_until_clean(wt)
    fix_never_mutated_vars(wt)
    run_prek_until_clean(wt)
    if not subprocess.run(["git", "status", "--porcelain"], cwd=wt, capture_output=True, text=True).stdout.strip():
        return driver.git("rev-parse", "HEAD", cwd=wt).stdout.strip()
    driver.git("add", "-A", cwd=wt)
    driver.git("commit", "-m", "chore: normalize prek hooks before agentic bench run", cwd=wt)
    return driver.git("rev-parse", "HEAD", cwd=wt).stdout.strip()


def remove_worktree(wt: Path) -> None:
    subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO, check=False, capture_output=True)
    shutil.rmtree(wt, ignore_errors=True)


# ---------------------------------------------------------------------------
# Isolated hermes config (solo agent, delegation off) via jinja2
# ---------------------------------------------------------------------------


def render_hermes_config(model: str, max_turns: int, skills_dir: str | None, delegate_to_self: bool) -> str:
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(str(TEMPLATE_DIR)), trim_blocks=True, lstrip_blocks=True)
    tmpl = env.get_template("hermes_config.yaml.j2")
    rendered = tmpl.render(
        model=model,
        provider=PROVIDER,
        lemonade_base_url=LEMONADE_BASE_URL,
        lemonade_key_env=LEMONADE_KEY_ENV,
        llm_context_size=LLM_CONTEXT_SIZE,
        max_turns=max_turns,
        skills_dirs=[skills_dir] if skills_dir else [],
        delegation_enabled=delegate_to_self,
    )
    yaml.safe_load(rendered)  # fail fast on template bugs before any hermes launch
    return rendered


def prepare_isolated_home(root: Path, model: str) -> Path:
    home = root / "home" / slugify(model)
    shutil.rmtree(home, ignore_errors=True)
    (home / ".hermes").mkdir(parents=True)
    return home


def write_run_config(home: Path, model: str, wt: Path, max_turns: int, skills: bool, delegate_to_self: bool) -> None:
    skills_dir = str(wt / ".claude" / "skills") if skills else None
    cfg = render_hermes_config(model, max_turns, skills_dir, delegate_to_self)
    (home / ".hermes" / "config.yaml").write_text(cfg)


# ---------------------------------------------------------------------------
# hermes launch (mirrors driver.py's HERMES_CMD shape, plus --source tagging
# for per-run turn/tool-call lookup in the isolated session store)
# ---------------------------------------------------------------------------

AB_HERMES_CMD = (
    'set -o pipefail; hermes chat -q "$(cat "$BURN_PROMPT")" --model "$BURN_MODEL" --provider "$BURN_PROVIDER" '
    '--yolo -Q --max-turns "$BURN_MAX_TURNS" --accept-hooks --source "$BURN_SOURCE" $BURN_SKILLS_FLAG '
    '2>&1 | tee "$BURN_LOG"; echo "=== HERMES_EXIT:$? ===" >> "$BURN_LOG"'
)


def launch_hermes(
    wt: Path, home: Path, prompt_file: Path, log: Path, model: str, max_turns: int, source_tag: str, skills: bool, base_env: dict
) -> subprocess.Popen:
    task_env = {
        "HOME": str(home),
        "BURN_PROMPT": str(prompt_file),
        "BURN_LOG": str(log),
        "BURN_MODEL": model,
        "BURN_PROVIDER": PROVIDER,
        "BURN_MAX_TURNS": str(max_turns),
        "BURN_SOURCE": source_tag,
        "BURN_SKILLS_FLAG": "--skills zig-0.16" if skills else "",
    }
    return subprocess.Popen(["bash", "-c", AB_HERMES_CMD], cwd=wt, env={**base_env, **task_env}, start_new_session=True)


def wait_for_exit(log: Path, timeout_s: int) -> tuple[bool, float]:
    start = time.time()
    while time.time() - start < timeout_s:
        if log.exists() and driver.EXIT_MARKER in log.read_text(errors="replace")[-2000:]:
            return True, time.time() - start
        time.sleep(5)
    return False, time.time() - start


def parse_hermes_exit(log: Path) -> int | None:
    if not log.exists():
        return None
    m = re.search(r"=== HERMES_EXIT:(\d+) ===", log.read_text(errors="replace"))
    return int(m.group(1)) if m else None


def read_session_stats(home: Path, source_tag: str) -> tuple[int | None, int | None, str, str | None]:
    """Primary turn/tool-call source: the isolated hermes session store.

    hermes -Q suppresses tool-call banners from stdout entirely, so there is
    no reliable log-text fallback -- confirmed empirically against a real
    tool-using run. If the session store lookup fails for any reason, report
    turns as unknown rather than guessing from the log.
    """
    try:
        r = subprocess.run(
            ["hermes", "sessions", "export", "--format", "jsonl", "--source", source_tag, "-"],
            env={**os.environ, "HOME": str(home)},
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, None, "unknown", None
    lines = [line for line in r.stdout.splitlines() if line.strip()]
    if r.returncode != 0 or not lines:
        return None, None, "unknown", None
    obj = json.loads(lines[-1])
    return obj.get("api_call_count"), obj.get("tool_call_count"), "session-store", obj.get("id")


# ---------------------------------------------------------------------------
# Partial-credit gate scoring (driver.GATES imported, driver.run_gates NOT
# used -- it short-circuits on first failure, which loses the "how far did
# it get" signal this harness exists to measure)
# ---------------------------------------------------------------------------


@dataclass
class GateResult:
    name: str
    passed: bool
    seconds: float
    tail: str = ""


def score_gates(wt: Path, env: dict) -> list[GateResult]:
    results = []
    for gate, timeout_s in driver.GATES:
        start = time.time()
        try:
            r = subprocess.run(["task", gate], cwd=wt, env=env, capture_output=True, text=True, timeout=timeout_s)
            passed = r.returncode == 0
            tail = "" if passed else (r.stdout[-800:] + r.stderr[-800:]).strip()[-300:]
        except subprocess.TimeoutExpired:
            passed = False
            tail = f"timed out after {timeout_s}s"
        results.append(GateResult(gate, passed, time.time() - start, tail))
    return results


# ---------------------------------------------------------------------------
# Result capture
# ---------------------------------------------------------------------------


@dataclass
class RunResult:
    model: str
    task: str
    base_sha: str
    ground_truth_sha: str
    done_marker: bool
    bail_reason: str | None
    gates: list[dict] = field(default_factory=list)
    gates_passed: int = 0
    gates_total: int = len(driver.GATES)
    turns_used: int | None = None
    turns_source: str = "unknown"
    tool_calls: int | None = None
    wall_clock_s: float = 0.0
    hermes_exit: int | None = None
    timed_out: bool = False
    commits: int = 0
    log_path: str = ""
    session_id: str | None = None


def detect_marker(log_text: str, task_id: str) -> tuple[bool, str | None]:
    if f"=== TASK:BAIL {task_id}" in log_text:
        m = re.search(rf"=== TASK:BAIL {re.escape(task_id)} reason=(.*?) ===", log_text)
        return False, m.group(1) if m else "unknown"
    return f"=== TASK:DONE {task_id} ===" in log_text, None


def append_result(out_dir: Path, result: RunResult) -> None:
    results_file = out_dir / "results.json"
    existing = json.loads(results_file.read_text()) if results_file.exists() else []
    existing.append(asdict(result))
    results_file.write_text(json.dumps(existing, indent=2) + "\n")


# ---------------------------------------------------------------------------
# CLI: run
# ---------------------------------------------------------------------------


def run_one(
    model: str,
    task: PortTask,
    out_dir: Path,
    max_turns: int,
    task_timeout_s: int,
    guardrails: bool,
    skills: bool,
    delegate_to_self: bool,
    env: dict,
    dry_run: bool,
    keep_worktrees: bool,
) -> RunResult | None:
    wt = cut_worktree(out_dir, model, task.task_id, task.base_sha)
    try:
        overlay_guardrails(wt, guardrails, skills)
        norm_sha = normalize_worktree_fmt(wt) if guardrails else task.base_sha
        home = prepare_isolated_home(out_dir, model)
        write_run_config(home, model, wt, max_turns, skills, delegate_to_self)
        if dry_run:
            cfg = yaml.safe_load((home / ".hermes" / "config.yaml").read_text())
            assert cfg["delegation"]["orchestrator_enabled"] == delegate_to_self
            assert cfg["model"]["default"] == model
            assert cfg["providers"]["lemonade"]["base_url"]
            if skills:
                assert cfg["skills"]["external_dirs"]
            print(
                f"--dry-run OK: {model} / {task.task_id} (base {task.base_sha[:8]}) -- worktree, guardrails, config all check out"
            )
            return None

        md = driver.task_md(wt, task.task_id)
        header = (REPO / "scripts/burn/prompt_header.txt").read_text()
        prompts_dir = out_dir / "prompts"
        prompts_dir.mkdir(parents=True, exist_ok=True)
        prompt_file = prompts_dir / f"{slugify(model)}.{task.task_id}.txt"
        prompt_file.write_text(header + "\n\n=== TASK FILE ===\n" + md.read_text())

        logs_dir = out_dir / "logs"
        logs_dir.mkdir(parents=True, exist_ok=True)
        log = logs_dir / f"{slugify(model)}.{task.task_id}.log"
        log.unlink(missing_ok=True)
        source_tag = f"ab-bench:{slugify(model)}:{task.task_id}"

        start = time.time()
        launch_hermes(wt, home, prompt_file, log, model, max_turns, source_tag, skills, env)
        finished, _elapsed = wait_for_exit(log, task_timeout_s)
        wall_clock_s = time.time() - start
        if not finished:
            driver.kill_task_processes(f"ab-{slugify(model)}-{task.task_id}")

        log_text = log.read_text(errors="replace") if log.exists() else ""
        done, bail_reason = detect_marker(log_text, task.task_id)
        commits = int(driver.git("rev-list", "--count", f"{norm_sha}..HEAD", cwd=wt).stdout.strip())
        gates = score_gates(wt, env)
        turns_used, tool_calls, turns_source, session_id = read_session_stats(home, source_tag)

        result = RunResult(
            model=model,
            task=task.task_id,
            base_sha=task.base_sha,
            ground_truth_sha=task.commit_sha,
            done_marker=done,
            bail_reason=bail_reason,
            gates=[asdict(g) for g in gates],
            gates_passed=sum(1 for g in gates if g.passed),
            turns_used=turns_used,
            turns_source=turns_source,
            tool_calls=tool_calls,
            wall_clock_s=wall_clock_s,
            hermes_exit=parse_hermes_exit(log),
            timed_out=not finished,
            commits=commits,
            log_path=str(log),
            session_id=session_id,
        )
        append_result(out_dir, result)
        print(
            f"{model} / {task.task_id}: {result.gates_passed}/{result.gates_total} gates, "
            f"{'DONE' if done else f'BAIL({bail_reason})' if bail_reason else 'no marker'}, "
            f"{turns_used if turns_used is not None else '?'} turns, {wall_clock_s:.0f}s"
        )
        return result
    finally:
        driver.kill_task_processes(f"ab-{slugify(model)}-{task.task_id}")
        if not keep_worktrees:
            remove_worktree(wt)


def lemonade_models() -> set[str]:
    try:
        with urllib.request.urlopen(driver.LEMONADE_URL, timeout=10) as r:
            return {m["id"] for m in json.loads(r.read()).get("data", [])}
    except (OSError, json.JSONDecodeError):
        return set()


def cmd_run(args: argparse.Namespace) -> int:
    out_dir = Path(args.out).expanduser() if args.out else DEFAULT_OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    models = args.models.split(",") if args.models else DEFAULT_MODELS
    task = find_port_task(args.task, args.base)
    guardrails = not args.no_guardrails
    skills = guardrails and not args.no_skills
    env = driver.load_secrets()

    if not driver.preflight_lemonade():
        print("lemonade preflight failed", file=sys.stderr)
        return 3
    missing = [m for m in models if m not in lemonade_models()]
    if missing:
        print(f"models not registered in lemonade: {missing}", file=sys.stderr)
        return 3

    results = []
    for model in models:
        result = run_one(
            model,
            task,
            out_dir,
            args.max_turns,
            args.task_timeout,
            guardrails,
            skills,
            args.delegate_to_self,
            env,
            args.dry_run,
            args.keep_worktrees,
        )
        if result is not None:
            results.append(asdict(result))

    if not args.dry_run:
        write_report(results, task)
        print(f"report appended to {BAKEOFF_MD}")
    return 0


# ---------------------------------------------------------------------------
# CLI: tasks
# ---------------------------------------------------------------------------


def cmd_tasks(_args: argparse.Namespace) -> int:
    for t in discover_port_tasks():
        print(
            f"{t.task_id:14s} {t.c_path:24s} -> {t.zig_path:24s} {t.c_lines:5d}C -> {t.zig_lines:5d}Z  commit={t.commit_sha[:8]} base={t.base_sha[:8]}"
        )
    return 0


# ---------------------------------------------------------------------------
# CLI: report (idempotent append between AB:BEGIN/END markers)
# ---------------------------------------------------------------------------


def render_report_body(results: list[dict], task: PortTask) -> str:
    lines = [
        "## Agentic re-bench (tools + gates)",
        "",
        f"Re-benches the same candidate models on **{task.task_id}** (`{task.c_path}` -> `{task.zig_path}`), "
        f"but this time with the real burn regime: tool access, compiler feedback, and up to N turns per "
        f"`scripts/burn/driver.py`'s gate sequence -- scored by gates passed, not one-shot compile success. "
        f"Ground truth is the merged commit `{task.commit_sha[:8]}` (parity-verified 7/7), replayed from its "
        f"pre-port base `{task.base_sha[:8]}`, so 7/7 is known-achievable.",
        "",
        "How to read: `gates` = X/7 of `driver.GATES` (prek, zig:build, zig:test, zig:difftest, zig:parity, "
        "zig:parity-replay, build), run non-short-circuiting so a partial score reflects how far the attempt got. "
        "How to run: `./scripts/burn/benchmark.py run` (bare invocation replays TASK-003.01 across all 3 default "
        "candidates). `results.json` in the output dir is the machine-readable artifact.",
        "",
        "| Model | Task | Gates | Turns | Tool calls | Wall-clock | Status |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        turns = r["turns_used"] if r["turns_used"] is not None else "?"
        tool_calls = r["tool_calls"] if r["tool_calls"] is not None else "?"
        status = "DONE" if r["done_marker"] else (f"BAIL: {r['bail_reason']}" if r["bail_reason"] else "no marker")
        if r["timed_out"]:
            status += " (timed out)"
        lines.append(
            f"| {r['model']} | {r['task']} | {r['gates_passed']}/{r['gates_total']} | {turns} | {tool_calls} | "
            f"{r['wall_clock_s']:.0f}s | {status} |"
        )
    lines.append("")
    lines.append("Per-gate detail:")
    lines.append("")
    lines.append("| Model | Task | " + " | ".join(g for g, _ in driver.GATES) + " |")
    lines.append("|---|---|" + "---|" * len(driver.GATES))
    for r in results:
        by_name = {g["name"]: g["passed"] for g in r["gates"]}
        cells = ["y" if by_name.get(g) else "n" for g, _ in driver.GATES]
        lines.append(f"| {r['model']} | {r['task']} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def write_report(results: list[dict], task: PortTask) -> None:
    body = render_report_body(results, task)
    block = f"{AB_BEGIN}\n{body}{AB_END}\n"
    text = BAKEOFF_MD.read_text() if BAKEOFF_MD.exists() else "# dsp.c -> dsp.zig port bakeoff\n\n"
    if AB_BEGIN in text and AB_END in text:
        pre, _, rest = text.partition(AB_BEGIN)
        _, _, post = rest.partition(AB_END)
        text = pre + block + post.lstrip("\n")
    else:
        text = text.rstrip("\n") + "\n\n" + block
    BAKEOFF_MD.write_text(text)


def cmd_report(args: argparse.Namespace) -> int:
    results_file = Path(args.results_json)
    results = json.loads(results_file.read_text())
    if not results:
        print("no results in " + str(results_file), file=sys.stderr)
        return 1
    task = find_port_task(results[0]["task"], None)
    write_report(results, task)
    print(f"report regenerated in {BAKEOFF_MD}")
    return 0


# ---------------------------------------------------------------------------
# CLI: status / kill
# ---------------------------------------------------------------------------


def cmd_status(_args: argparse.Namespace) -> int:
    print("lemonade:", "up" if driver.preflight_lemonade() else "DOWN")
    wts = subprocess.run(["git", "worktree", "list"], cwd=REPO, capture_output=True, text=True).stdout
    ab_wts = [line for line in wts.splitlines() if "/ab/wt/" in line]
    print(f"active A/B worktrees: {len(ab_wts)}")
    for line in ab_wts:
        print(" ", line)
    return 0


def cmd_kill(_args: argparse.Namespace) -> int:
    for name in ("hermes chat",):
        subprocess.run(["pkill", "-9", "-f", name], check=False)
    for name in ("zelda3", "sway", "wtype"):
        subprocess.run(["pkill", "-9", "-x", name], check=False)
    print("killed hermes/zelda3/sway/wtype")
    return 0


# ---------------------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    runp = sub.add_parser("run", help="run the A/B benchmark across candidate models")
    runp.add_argument("--models", help=f"comma-separated model list (default: {','.join(DEFAULT_MODELS)})")
    runp.add_argument("--task", default=DEFAULT_TASK, help=f"completed port task id to replay (default: {DEFAULT_TASK})")
    runp.add_argument("--base", help="override the pinned base SHA for --task")
    runp.add_argument("--out", help=f"output dir (default: {DEFAULT_OUT_DIR})")
    runp.add_argument("--max-turns", type=int, default=DEFAULT_MAX_TURNS)
    runp.add_argument("--task-timeout", type=int, default=DEFAULT_TASK_TIMEOUT_S, dest="task_timeout")
    runp.add_argument("--no-skills", action="store_true", help="disable the zig-0.16 skill only")
    runp.add_argument("--no-guardrails", action="store_true", help="disable the whole guardrail bundle (skill + ast-check hook)")
    runp.add_argument(
        "--delegate-to-self",
        action="store_true",
        help="leave delegation on, pointed at the same candidate (fallback if a model always tries to delegate)",
    )
    runp.add_argument("--keep-worktrees", action="store_true", help="do not remove worktrees after each run (for post-mortem)")
    runp.add_argument("--dry-run", action="store_true", help="cut worktree + render config + assert invariants, no hermes launch")

    sub.add_parser("tasks", help="list completed single-file zig ports available to replay")

    reportp = sub.add_parser("report", help="regenerate the docs/bakeoff.md section from an existing results.json")
    reportp.add_argument("results_json")

    sub.add_parser("status", help="lemonade health + active A/B worktrees")
    sub.add_parser("kill", help="SIGKILL hermes/zelda3/sway/wtype")

    args = p.parse_args()
    match args.cmd:
        case "run":
            return cmd_run(args)
        case "tasks":
            return cmd_tasks(args)
        case "report":
            return cmd_report(args)
        case "status":
            return cmd_status(args)
        case "kill":
            return cmd_kill(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
