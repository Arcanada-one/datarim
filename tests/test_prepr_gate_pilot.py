"""Real local-git pilot with positive and refusal controls; no remote access."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "dev-tools" / "prepr-gate-pilot.py"
spec = importlib.util.spec_from_file_location("prepr_gate", SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


class PrePRPilot(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.top = Path(self.tmp.name)
        self.repo = self.top / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        (self.repo / "src").mkdir()
        (self.repo / "src/api.py").write_text("def inc(x):\n    return x\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "baseline")
        base = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "checkout", "-qb", "feature")
        (self.repo / "src/api.py").write_text("def inc(x):\n    return x + 1\n")
        (self.repo / "tests").mkdir()
        (self.repo / "tests/test_api.py").write_text(
            "import runpy\nimport unittest\n"
            "class APITests(unittest.TestCase):\n"
            "    def test_inc(self):\n"
            '        self.assertEqual(runpy.run_path("src/api.py")["inc"](2), 3)\n'
        )
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "feature change")
        head = git(self.repo, "rev-parse", "HEAD")
        tree = git(self.repo, "rev-parse", "HEAD^{tree}")
        run = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests"],
                             cwd=self.repo, text=True, capture_output=True,
                             env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        self.assertEqual(run.returncode, 0, run.stderr)
        self.actual_test_log = run.stdout + run.stderr
        self.plan = {
            "schema": "DatarimPrePRPlan/v1", "task_id": "EXAMPLE",
            "goal": {"owner": "engineer", "metric": "example_latency", "unit": "ms",
                     "baseline": {"value": 500, "source": "fixture measurement"},
                     "target": {"value": 300, "deadline_utc": "2027-01-01T00:00:00Z"},
                     "direction": "decrease"},
            "source": {"base_ref": "main", "base": base, "head": head, "tree": tree},
            "nodes": [{"id": "change", "kind": "change", "op": "M", "path": "src/api.py"},
                      {"id": "test-file", "kind": "change", "op": "A", "path": "tests/test_api.py"},
                      {"id": "test", "kind": "test", "path": "tests/test_api.py"}],
            "edges": [{"from": "test", "to": "change", "kind": "verifies"},
                      {"from": "test", "to": "test-file", "kind": "verifies"}],
            "implementation": {"provider": "vendor-one"},
            "plan_review": {"provider": "vendor-two", "decision": "accepted",
                            "plan_sha256": ""}}
        self.bind()
        self.evidence = {"schema": "DatarimPrePREvidence/v1", "task_id": "EXAMPLE",
                         "runs": [{"test_id": "test", "status": "passed",
                                   "head": head, "tree": tree,
                                   "command": "python -m unittest discover -s tests",
                                   "sandbox": "isolated-no-secrets",
                                   "log_sha256": hashlib.sha256(self.actual_test_log.encode()).hexdigest()}]}

    def commit(self, message):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", message)
        head = git(self.repo, "rev-parse", "HEAD")
        tree = git(self.repo, "rev-parse", "HEAD^{tree}")
        self.plan["source"].update(head=head, tree=tree)
        for run in self.evidence["runs"]:
            run.update(head=head, tree=tree)
        return head

    def rebase_plan_on_feature(self):
        """Make the current feature commit the new base: a follow-up change on an existing test."""
        git(self.repo, "branch", "-f", "main", "HEAD")
        self.plan["source"]["base"] = git(self.repo, "rev-parse", "HEAD")

    def bind(self):
        self.plan["plan_review"]["plan_sha256"] = gate.plan_digest(self.plan)

    def assert_blocked(self, code):
        with self.assertRaises(gate.Refusal) as x:
            gate.check(self.repo, self.plan, self.evidence)
        self.assertEqual(x.exception.code, code)

    def test_real_local_test_passes_but_execution_not_attested(self):
        out = gate.check(self.repo, self.plan, self.evidence)
        self.assertEqual(out["status"], "STRUCTURALLY_READY")
        self.assertEqual(out["tests_claimed_passed"], 1)
        self.assertEqual(out["trusted_execution"], "NOT_VERIFIED")
        self.assertFalse(out["release_eligible"])

    def test_missing_test_cannot_appear_green(self):
        self.evidence["runs"] = []
        self.assert_blocked("TEST_EVIDENCE_INCOMPLETE")

    def test_failed_or_skipped_test_is_blocked(self):
        self.evidence["runs"][0]["status"] = "skipped"
        self.assert_blocked("TEST_EVIDENCE_NOT_PASSING")

    def test_changed_file_unmapped_is_blocked(self):
        self.plan["nodes"] = [n for n in self.plan["nodes"] if n["id"] != "test-file"]
        self.plan["edges"] = [e for e in self.plan["edges"] if e["to"] != "test-file"]
        self.bind()
        self.assert_blocked("CHANGED_FILE_GRAPH_MISMATCH")

    # D136-B: an unchanged existing test may verify a source-only change.
    def test_source_only_change_with_unchanged_test_passes(self):
        self.rebase_plan_on_feature()
        (self.repo / "src/api.py").write_text("def inc(x):\n    return 1 + x\n")
        self.commit("source-only change")
        self.plan["nodes"] = [{"id": "change", "kind": "change", "op": "M", "path": "src/api.py"},
                              {"id": "test", "kind": "test", "path": "tests/test_api.py"}]
        self.plan["edges"] = [{"from": "test", "to": "change", "kind": "verifies"}]
        self.bind()
        out = gate.check(self.repo, self.plan, self.evidence)
        self.assertEqual(out["status"], "STRUCTURALLY_READY")
        self.assertEqual(out["changed_operations"]["M"], 1)
        self.assertFalse(out["release_eligible"])

    def test_selected_test_must_exist_at_head(self):
        self.plan["nodes"][2]["path"] = "tests/test_missing.py"
        self.bind()
        self.assert_blocked("TEST_PATH_MISSING")

    # D136-A: a rename is exactly a deletion of the old path plus an addition of the new one.
    def test_rename_hides_no_source_deletion(self):
        self.rebase_plan_on_feature()
        (self.repo / "lib").mkdir()
        git(self.repo, "mv", "src/api.py", "lib/api.py")
        test = self.repo / "tests/test_api.py"
        test.write_text(test.read_text().replace("src/api.py", "lib/api.py"))
        self.commit("rename")
        self.plan["nodes"] = [{"id": "new", "kind": "change", "op": "A", "path": "lib/api.py"},
                              {"id": "test-file", "kind": "change", "op": "M", "path": "tests/test_api.py"},
                              {"id": "test", "kind": "test", "path": "tests/test_api.py"}]
        self.plan["edges"] = [{"from": "test", "to": "new", "kind": "verifies"},
                              {"from": "test", "to": "test-file", "kind": "verifies"}]
        self.bind()
        self.assert_blocked("CHANGED_FILE_GRAPH_MISMATCH")
        self.plan["nodes"].append({"id": "old", "kind": "change", "op": "D", "path": "src/api.py"})
        self.plan["edges"].append({"from": "test", "to": "old", "kind": "verifies"})
        self.bind()
        out = gate.check(self.repo, self.plan, self.evidence)
        self.assertEqual(out["changed_operations"], {"A": 1, "D": 1, "M": 1, "T": 0})

    def test_wrong_operation_is_blocked(self):
        self.plan["nodes"][0]["op"] = "A"
        self.bind()
        self.assert_blocked("CHANGE_OP_MISMATCH")

    def test_deleted_path_with_unmapped_consumer_is_blocked(self):
        self.rebase_plan_on_feature()
        (self.repo / "src/util.py").write_text("X = 1\n")
        (self.repo / "src/use.py").write_text('import runpy\nX = runpy.run_path("src/util.py")["X"]\n')
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "add util and consumer")
        self.rebase_plan_on_feature()
        (self.repo / "src/util.py").unlink()
        self.commit("delete util, consumer left behind")
        self.plan["nodes"] = [{"id": "gone", "kind": "change", "op": "D", "path": "src/util.py"},
                              {"id": "test", "kind": "test", "path": "tests/test_api.py"}]
        self.plan["edges"] = [{"from": "test", "to": "gone", "kind": "verifies"}]
        self.bind()
        self.assert_blocked("DELETED_PATH_UNMAPPED_CONSUMER")
        self.plan["nodes"].append({"id": "use", "kind": "consumer", "path": "src/use.py"})
        self.plan["edges"] += [{"from": "use", "to": "gone", "kind": "depends_on"},
                               {"from": "test", "to": "use", "kind": "verifies"}]
        self.bind()
        self.assertEqual(gate.check(self.repo, self.plan, self.evidence)["status"], "STRUCTURALLY_READY")

    def test_newline_path_is_refused_not_split(self):
        self.rebase_plan_on_feature()
        (self.repo / "src/a\nb.py").write_text("Y = 2\n")
        self.commit("control character path")
        self.plan["nodes"] = [{"id": "change", "kind": "change", "op": "A", "path": "src/a"},
                              {"id": "test", "kind": "test", "path": "tests/test_api.py"}]
        self.plan["edges"] = [{"from": "test", "to": "change", "kind": "verifies"}]
        self.bind()
        self.assert_blocked("CHANGED_PATH_UNSAFE")

    def _ops_from(self, stream: bytes):
        saved = gate.git_bytes
        gate.git_bytes = lambda *_a, **_k: stream
        try:
            return gate.changed_operations(self.repo, "a" * 40, "b" * 40)
        finally:
            gate.git_bytes = saved

    def test_truncated_even_field_diff_stream_is_refused(self):
        # "M\0path" has an even field count but no terminating NUL: a cut stream.
        with self.assertRaises(gate.Refusal) as e:
            self._ops_from(b"M\0truncated-path")
        self.assertEqual(str(e.exception), "DIFF_UNPARSEABLE")
        with self.assertRaises(gate.Refusal) as e:
            self._ops_from(b"M\0src/a.py\0D\0src/b")
        self.assertEqual(str(e.exception), "DIFF_UNPARSEABLE")
        # Well-terminated and empty streams keep their meaning.
        self.assertEqual(self._ops_from(b"M\0src/a.py\0D\0src/b.py\0"),
                         {"src/a.py": "M", "src/b.py": "D"})
        self.assertEqual(self._ops_from(b""), {})

    def test_wrong_tree_is_blocked(self):
        self.plan["source"]["tree"] = "b" * 40
        self.assert_blocked("SOURCE_DRIFT")

    def test_forged_run_for_other_head_is_blocked(self):
        self.evidence["runs"][0]["head"] = "c" * 40
        self.assert_blocked("TEST_EVIDENCE_NOT_PASSING")

    def test_lockfile_drift_outside_graph_is_blocked(self):
        self.rebase_plan_on_feature()
        (self.repo / "src/api.py").write_text("def inc(x):\n    return 1 + x\n")
        (self.repo / "pnpm-lock.yaml").write_text("lockfileVersion: '9.0'\n")
        self.commit("source plus lock drift")
        self.plan["nodes"] = [{"id": "change", "kind": "change", "op": "M", "path": "src/api.py"},
                              {"id": "test", "kind": "test", "path": "tests/test_api.py"}]
        self.plan["edges"] = [{"from": "test", "to": "change", "kind": "verifies"}]
        self.bind()
        self.assert_blocked("CHANGED_FILE_GRAPH_MISMATCH")

    def test_merge_from_moved_base_is_blocked(self):
        git(self.repo, "checkout", "-q", "main")
        (self.repo / "README").write_text("moved\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "main moves")
        git(self.repo, "checkout", "-q", "feature")
        git(self.repo, "merge", "-q", "--no-edit", "main")
        self.plan["source"].update(head=git(self.repo, "rev-parse", "HEAD"),
                                   tree=git(self.repo, "rev-parse", "HEAD^{tree}"))
        self.assert_blocked("BASE_DRIFT")

    def test_dependency_cycle_is_blocked(self):
        self.plan["edges"] += [{"from": "change", "to": "test", "kind": "depends_on"},
                               {"from": "test", "to": "change", "kind": "depends_on"}]
        self.assert_blocked("DEPENDENCY_CYCLE")

    def test_change_without_verifying_test_is_blocked(self):
        self.plan["edges"] = []
        self.assert_blocked("CHANGE_WITHOUT_TEST")

    def test_plan_review_staleness_is_blocked(self):
        self.plan["goal"]["target"]["value"] = 200
        self.assert_blocked("PLAN_REVIEW_STALE")

    def test_same_vendor_review_is_blocked(self):
        self.plan["plan_review"]["provider"] = "vendor-one"
        self.assert_blocked("PLAN_REVIEW_NOT_INDEPENDENT")

    def test_base_drift_is_blocked(self):
        self.plan["source"]["base"] = "a" * 40
        self.assert_blocked("BASE_DRIFT")

    def test_head_drift_is_blocked(self):
        self.plan["source"]["head"] = "a" * 40
        self.assert_blocked("SOURCE_DRIFT")

    def test_dirty_tree_is_blocked(self):
        (self.repo / "untracked.txt").write_text("changed")
        self.assert_blocked("DIRTY_TREE")

    def test_goal_requires_actual_improvement(self):
        self.plan["goal"]["target"]["value"] = 900
        self.assert_blocked("GOAL_NOT_IMPROVING")

    def test_duplicates_and_nan_are_rejected(self):
        f = self.top / "unsafe.json"
        f.write_text('{"x": 1, "x": 2}')
        with self.assertRaises(gate.Refusal) as e:
            gate.read_json(f)
        self.assertEqual(e.exception.code, "DUPLICATE_JSON_KEY")
        f.write_text('{"x": NaN}')
        with self.assertRaises(gate.Refusal) as e:
            gate.read_json(f)
        self.assertEqual(e.exception.code, "NONFINITE_JSON")

    def test_check_does_not_write_the_input_repository(self):
        index = self.repo / ".git" / "index"
        src = self.repo / "src/api.py"
        st = src.stat()
        os.utime(src, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))
        before_bytes, before_ns = index.read_bytes(), index.stat().st_mtime_ns
        before_files = sorted(str(f.relative_to(self.repo)) for f in self.repo.rglob("*"))
        out = gate.check(self.repo, self.plan, self.evidence)
        self.assertEqual(out["status"], "STRUCTURALLY_READY")
        self.assertEqual(index.read_bytes(), before_bytes)
        self.assertEqual(index.stat().st_mtime_ns, before_ns)
        self.assertEqual(sorted(str(f.relative_to(self.repo)) for f in self.repo.rglob("*")),
                         before_files)

    def test_cli_result_does_not_approve_release(self):
        p, e = self.top / "plan.json", self.top / "evidence.json"
        p.write_text(json.dumps(self.plan))
        e.write_text(json.dumps(self.evidence))
        run = subprocess.run([sys.executable, str(SCRIPT), "--repo", str(self.repo),
                              "--plan", str(p), "--evidence", str(e)],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)
        self.assertFalse(json.loads(run.stdout)["release_eligible"])


if __name__ == "__main__":
    unittest.main()
