#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# dependencies = [
#     "python-decouple>=3.8",
#     "burnkit",
# ]
#
# [tool.uv.sources]
# burnkit = { path = "../../../burnkit", editable = true }
# ///

"""Unit tests for this repo's burnkit configuration in driver.py.

Only the project-specific half is tested here -- the queue, worktree lifecycle,
marker protocol, and gate mechanics are burnkit's and are tested in
~/git/burnkit/tests. What's left is what this repo asserts about its own
configuration: the model choices, the local-only burn branch, the seven
unconditional Zig gates, and the pre-port ROM the parity oracle needs.

One test here is not about configuration at all: KillScopeTests. The unscoped
`pkill` this driver used to run is the regression that motivated extracting
burnkit in the first place, so it is asserted mechanically rather than left to
a review habit.

Hermetic: no git, no hermes, no lemonade, no Fireworks. The full overnight run
is exercised live on the mf box."""

import ast
import burnkit.proc
import sys
import tempfile
import unittest
from burnkit import ANY_PATH, base_ref, copy_prepare
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import driver  # noqa: E402


def executable_strings(path: Path) -> str:
    """Every string literal in `path` that isn't a docstring, joined.

    Scoped this way so the scripts can keep explaining the machine-wide `pkill`
    they used to run -- that history is the reason burnkit exists and is worth
    documenting -- while still failing if one of them ever calls it again.
    Comments are absent from the AST, so they are excluded for free.
    """
    tree = ast.parse(path.read_text())
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            first = node.body[0] if node.body else None
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                docstrings.add(id(first.value))
    return "\n".join(
        n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docstrings
    )


class ModelConfigTests(unittest.TestCase):
    def test_planner_defaults_to_fireworks_deepseek(self):
        self.assertEqual(driver.ORCH_MODEL, "accounts/fireworks/models/deepseek-v4-flash-0731")
        self.assertEqual(driver.ORCH_PROVIDER, "fireworks")

    def test_fallback_planner_is_the_local_model(self):
        # Repeated fast failures mean the remote provider is sick, so the
        # demotion target has to be something that cannot share its outage.
        self.assertEqual(driver.CONFIG.fallback_model, "Qwen3.6-27B-MTP-GGUF")
        self.assertEqual(driver.CONFIG.fallback_provider, "lemonade")

    def test_config_carries_the_model_selection_into_burnkit(self):
        self.assertEqual(driver.CONFIG.model, driver.ORCH_MODEL)
        self.assertEqual(driver.CONFIG.provider, driver.ORCH_PROVIDER)


class LocalBranchTests(unittest.TestCase):
    """Work happens on a branch that deliberately never leaves the machine:
    origin has only master. Declaring a remote for it would make burnkit fetch
    a ref that does not exist and fail every task before it started."""

    def test_the_burn_branch_has_no_remote(self):
        self.assertEqual(driver.CONFIG.base_remote, "")
        self.assertEqual(driver.CONFIG.base_branch, "feat/zig-port-burn")

    def test_the_base_ref_is_the_local_branch_itself(self):
        self.assertEqual(base_ref(driver.CONFIG), "feat/zig-port-burn")

    def test_publication_fast_forwards_that_same_branch(self):
        self.assertEqual(driver.INTEGRATION.branch, driver.CONFIG.base_branch)


class GateTests(unittest.TestCase):
    def test_every_gate_runs_unconditionally(self):
        # The DoD is that the branch only ever advances green, so no gate is
        # selected out by what the diff happened to touch.
        self.assertTrue(all(g.applies is None for g in driver.CONFIG.machine_gates))

    def test_the_full_zig_sequence_is_registered_in_order(self):
        names = [g.name for g in driver.CONFIG.machine_gates]
        self.assertEqual(names, ["prek", "zig:build", "zig:test", "zig:difftest", "zig:parity", "zig:parity-replay", "build"])

    def test_each_gate_shells_out_to_its_task_target(self):
        self.assertEqual([g.argv for g in driver.CONFIG.machine_gates][:2], [("task", "prek"), ("task", "zig:build")])

    def test_the_replay_gate_gets_room_to_finish(self):
        # 13 chapters at ~12s each; the default ceiling would kill it mid-run.
        gates = {g.name: g for g in driver.CONFIG.machine_gates}
        self.assertEqual(gates["zig:parity-replay"].timeout_s, 600)
        self.assertEqual(gates["prek"].timeout_s, 180)

    def test_every_task_is_gated_as_a_code_task(self):
        # A port task can be a pure build.zig or test-list edit and still change
        # what the parity oracle sees, so nothing here is prose-only.
        self.assertEqual(driver.CONFIG.code_change_prefixes, ANY_PATH)

    def test_nothing_is_out_of_scope(self):
        # No scope allow-list has ever been enforced here; guessing one would
        # block legitimate overnight work rather than catch anything.
        self.assertEqual(driver.CONFIG.code_task_allowed_prefixes, ANY_PATH)


class RomPreparationTests(unittest.TestCase):
    """The parity gates diff against the original machine code, which needs the
    ROM present in the worktree -- it is gitignored, so a fresh worktree has
    none and every parity gate would fail for a reason unrelated to the port.

    What is project-specific is which file, from where; copy-vs-symlink and the
    missing-source case are copy_prepare's contract and are tested in burnkit."""

    def test_the_rom_is_what_gets_prepared(self):
        self.assertEqual(driver.ROM_RELS, ("zelda3.sfc",))

    def test_both_backends_prepare_it(self):
        # The parity gates run identically whichever model planned the work.
        for name, backend in driver.BACKENDS.items():
            with self.subTest(backend=name):
                self.assertIs(backend.prepare_worktree, driver.prepare_rom)

    def test_it_is_copied_from_this_repo(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, wt = Path(tmp) / "repo", Path(tmp) / "wt"
            repo.mkdir()
            wt.mkdir()
            (repo / "zelda3.sfc").write_bytes(b"\x00\x01")
            copy_prepare(repo, driver.ROM_RELS)("TASK-002.01", wt)
            self.assertEqual((wt / "zelda3.sfc").read_bytes(), b"\x00\x01")


class PhaseParentTests(unittest.TestCase):
    def test_phase_parents_are_closed_out_automatically(self):
        # A shared-branch consumer has no pull request for a human to close the
        # parent on, so the last Done leaf has to sweep it up.
        self.assertTrue(driver.CONFIG.close_out_phase_parents)


class KillScopeTests(unittest.TestCase):
    """The regression that motivated burnkit: this driver used to run `pkill -9
    -f "hermes chat"` and `pkill -9 -x` over zelda3/sway/wtype, machine-wide,
    which killed an unrelated session. Termination is now scoped to the process
    group of the pid burnkit itself recorded."""

    def test_no_burn_script_here_pattern_matches_a_process(self):
        # This file is excluded because it is the one asserting the rule, so it
        # necessarily names what it forbids.
        here = Path(__file__).resolve()
        offenders = [p.name for p in here.parent.glob("*.py") if p != here and "pkill" in executable_strings(p)]
        self.assertEqual(offenders, [])

    def test_burnkit_kills_by_process_group_not_by_name(self):
        source = Path(burnkit.proc.__file__).read_text()
        self.assertNotIn("pkill", source)
        self.assertIn("killpg", source)
        self.assertIn("getpgid", source)

    def test_the_launched_agent_records_a_pid_to_kill(self):
        # killpg needs a pgid, so the launch has to write the pid down; without
        # it there is nothing to scope a kill to and only a name search is left.
        self.assertIn("$$", driver.BACKENDS["hermes"].shell_cmd)


if __name__ == "__main__":
    unittest.main()
