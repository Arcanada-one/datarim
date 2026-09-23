"""Behavioral fixtures for the public evidence gate (no mocked checker)."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


GATE = Path(__file__).resolve().parents[1] / "dev-tools/check-live-evidence.sh"


class EvidenceLoop(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        (self.root / "product.txt").write_text("observable behavior\n")
        (self.root / "output.txt").write_text("named assertion passed\n")
        self.git("add", "product.txt")
        self.git("commit", "-qm", "fixture baseline")
        self.contract = {
            "version": 1, "task_id": "TEST-0001", "defined_at": "2026-01-01T00:00:00Z",
            "workflow": {"complexity": "L3", "task_type": "framework", "route": ["do", "qa", "compliance", "archive"]},
            "scope": ["product.txt", "planned.txt"],
            "criteria": [{"id": "AC-1", "expected": "observable result",
                          "evidence_type": "static", "environment": "test",
                          "cases": {"happy": {"expected": "named assertion passes",
                                              "expected_exit_code": 0, "required_stage": "do"}}}],
        }
        self.write_metadata()
        self.save_contract()
        preflight = self.call("preflight")
        self.assertEqual(preflight.returncode, 0, preflight.stderr)
        self.preflight = json.loads(preflight.stdout)
        self.bundle = {"task_id": "TEST-0001", "preflight": self.preflight,
                       "implementation_started_at": self.preflight["timestamp"],
                       "attempts": []}
        for stage in ["do", "qa", "compliance"]:
            self.bundle["attempts"].append(self.attempt(stage))
        self.save()

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def save_contract(self):
        (self.root / "contract.json").write_text(json.dumps(self.contract))

    def write_metadata(self):
        path = self.root / "datarim/tasks/TEST-0001-task-description.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        workflow = self.contract["workflow"]
        path.write_text(f"---\nid: TEST-0001\ncomplexity: {workflow['complexity']}\ntype: {workflow['task_type']}\n---\n")

    def use_route(self, complexity, task_type, route, first_stage=None):
        self.contract["workflow"] = {"complexity": complexity, "task_type": task_type, "route": route}
        self.contract["criteria"][0]["cases"]["happy"]["required_stage"] = first_stage or route[0]
        self.write_metadata()
        self.save_contract()
        result = self.call("preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.preflight = json.loads(result.stdout)
        self.bundle["preflight"] = self.preflight
        self.bundle["implementation_started_at"] = self.preflight["timestamp"]
        self.bundle["attempts"] = [self.attempt(s) for s in route if s != "archive"]
        self.save()

    def save(self):
        (self.root / "evidence.json").write_text(json.dumps(self.bundle))

    def call(self, stage):
        return subprocess.run(["bash", str(GATE), "--contract", str(self.root / "contract.json"),
                               "--evidence", str(self.root / "evidence.json"), "--root",
                               str(self.root), "--stage", stage], capture_output=True, text=True)

    def attempt(self, stage):
        return {"stage": stage, "actor": stage + "-agent", "timestamp": self.preflight["timestamp"],
                "revision": self.preflight["revision"],
                "contract_sha256": self.preflight["contract_sha256"],
                "scope_sha256": self.preflight["scope_sha256"],
                "cases": [{"criterion_id": "AC-1", "case_id": "happy",
                           "observed": "named assertion passed", "status": "pass",
                           "evidence_type": "static", "environment": "test", "source": "fixture",
                           "command": "assert named behavior", "exit_code": 0,
                           "artifact": {"relative_path": "output.txt",
                                        "sha256": hashlib.sha256((self.root / "output.txt").read_bytes()).hexdigest()}}]}

    def reject(self, stage="compliance"):
        self.save()
        result = self.call(stage)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("BLOCKED", result.stderr)

    def test_valid_static_full_flow(self):
        for stage in ["do", "qa", "compliance", "archive"]:
            with self.subTest(stage=stage):
                result = self.call(stage)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_contract_stage_requires_scalar_route_member(self):
        for value in [None, [], ["archive"], ["do", "qa"], {}, 0, True, "unknown", "", "preflight"]:
            with self.subTest(value=value):
                self.contract["criteria"][0]["cases"]["happy"]["required_stage"] = value
                self.save_contract()
                self.assertEqual(self.call("preflight").returncode, 1)

    def test_contract_scalar_fields_reject_other_json_types(self):
        original = copy.deepcopy(self.contract)
        paths = [("task_id",), ("defined_at",), ("workflow", "complexity"),
                 ("workflow", "task_type"), ("criteria", 0, "id"),
                 ("criteria", 0, "expected"), ("criteria", 0, "environment"),
                 ("criteria", 0, "evidence_type"),
                 ("criteria", 0, "cases", "happy", "expected"),
                 ("criteria", 0, "cases", "happy", "expected_exit_code")]
        for path in paths:
            for value in [None, [], {}, True, ""]:
                with self.subTest(path=path, value=value):
                    self.contract = copy.deepcopy(original)
                    target = self.contract
                    for part in path[:-1]:
                        target = target[part]
                    target[path[-1]] = value
                    self.save_contract()
                    self.assertEqual(self.call("preflight").returncode, 1)

    def test_attempt_stage_requires_scalar_route_member_even_when_unselected(self):
        original = copy.deepcopy(self.bundle)
        for value in [None, [], ["do"], ["archive"], {}, 0, True, "unknown", "", "preflight"]:
            with self.subTest(value=value):
                self.bundle = copy.deepcopy(original)
                attempt = self.attempt("do")
                attempt["stage"] = value
                attempt["cases"][0]["status"] = "fail"
                self.bundle["attempts"].append(attempt)
                self.reject("archive")

    def test_explicit_archive_latest_attempt_is_never_ignored(self):
        original = copy.deepcopy(self.bundle)
        for status in ["fail", "blocked", "WAITING_OPERATOR"]:
            with self.subTest(status=status):
                self.bundle = copy.deepcopy(original)
                self.bundle["attempts"].append(self.attempt("archive"))
                latest = self.attempt("archive")
                latest["cases"][0]["status"] = status
                self.bundle["attempts"].append(latest)
                self.reject("archive")
        self.bundle = copy.deepcopy(original)
        partial = self.attempt("archive")
        partial["cases"] = []
        self.bundle["attempts"].append(partial)
        self.reject("archive")
        self.bundle["attempts"].append(self.attempt("archive"))
        self.save()
        self.assertEqual(self.call("archive").returncode, 0)

    def test_selected_evidence_scalar_fields_reject_other_json_types(self):
        original = copy.deepcopy(self.bundle)
        for field in ["criterion_id", "case_id", "observed", "status", "evidence_type",
                      "environment", "source", "command", "exit_code"]:
            for value in [None, [], {}, True, 42]:
                with self.subTest(field=field, value=value):
                    self.bundle = copy.deepcopy(original)
                    self.bundle["attempts"][-1]["cases"][0][field] = value
                    self.reject()

    def test_historical_attempt_scalar_fields_are_validated(self):
        original = copy.deepcopy(self.bundle)
        for field in ["actor", "revision", "contract_sha256", "scope_sha256"]:
            for value in [None, [], {}, True, 42]:
                with self.subTest(field=field, value=value):
                    self.bundle = copy.deepcopy(original)
                    self.bundle["attempts"][0][field] = value
                    self.bundle["attempts"] += [self.attempt(s) for s in ["do", "qa", "compliance"]]
                    self.reject("archive")

    def test_historical_case_schema_is_checked_without_requiring_pass(self):
        original = copy.deepcopy(self.bundle)
        for field in ["criterion_id", "case_id", "observed", "status", "evidence_type",
                      "environment", "source", "command", "exit_code", "artifact"]:
            for value in [None, [], {}, True]:
                with self.subTest(field=field, value=value):
                    self.bundle = copy.deepcopy(original)
                    self.bundle["attempts"][0]["cases"][0][field] = value
                    self.bundle["attempts"] += [self.attempt(s) for s in ["do", "qa", "compliance"]]
                    self.reject("archive")
        for field in ["status", "evidence_type", "source"]:
            self.bundle = copy.deepcopy(original)
            self.bundle["attempts"][0]["cases"][0][field] = "unknown"
            self.bundle["attempts"] += [self.attempt(s) for s in ["do", "qa", "compliance"]]
            self.reject("archive")
        for status in ["fail", "blocked"]:
            self.bundle = copy.deepcopy(original)
            self.bundle["attempts"][0]["cases"][0]["status"] = status
            self.bundle["attempts"] += [self.attempt(s) for s in ["do", "qa", "compliance"]]
            self.save()
            self.assertEqual(self.call("archive").returncode, 0)

    def test_live_and_measurement(self):
        for kind in ["empirical", "measurement"]:
            self.contract["criteria"][0]["evidence_type"] = kind
            self.save_contract()
            self.preflight = json.loads(self.call("preflight").stdout)
            self.bundle["preflight"] = self.preflight
            self.bundle["implementation_started_at"] = self.preflight["timestamp"]
            self.bundle["attempts"] = [self.attempt(s) for s in ["do", "qa", "compliance"]]
            for attempt in self.bundle["attempts"]:
                attempt["cases"][0].update(evidence_type=kind, source="live")
            self.save()
            self.assertEqual(self.call("compliance").returncode, 0)
            self.bundle["attempts"][-1]["cases"][0]["source"] = "fixture"
            self.reject()

    def test_each_required_field_removal_fails(self):
        original = copy.deepcopy(self.bundle)
        for key in self.bundle["attempts"][-1]["cases"][0]:
            with self.subTest(field=key):
                self.bundle = copy.deepcopy(original)
                del self.bundle["attempts"][-1]["cases"][0][key]
                self.reject()

    def test_missing_case(self):
        self.bundle["attempts"][-1]["cases"] = []
        self.reject()

    def test_duplicate_case(self):
        self.bundle["attempts"][-1]["cases"] *= 2
        self.reject()

    def test_wrong_case(self):
        self.bundle["attempts"][-1]["cases"][0]["case_id"] = "unrelated"
        self.reject()

    def test_one_case_does_not_cover_two(self):
        self.contract["criteria"][0]["cases"]["negative"] = {"expected": "rejects invalid", "expected_exit_code": 1}
        self.save_contract()
        self.reject()

    def test_scope_dirty_or_new_file(self):
        (self.root / "planned.txt").write_text("new implementation")
        self.reject()

    def test_scope_executable_bit_changes(self):
        (self.root / "product.txt").chmod(0o755)
        self.reject()

    def test_negative_probe_requires_named_expected_failure(self):
        self.contract["criteria"][0]["cases"]["happy"]["expected_exit_code"] = 1
        self.save_contract()
        self.preflight = json.loads(self.call("preflight").stdout)
        self.bundle["preflight"] = self.preflight
        self.bundle["implementation_started_at"] = self.preflight["timestamp"]
        self.bundle["attempts"] = [self.attempt(s) for s in ["do", "qa", "compliance"]]
        for attempt in self.bundle["attempts"]:
            attempt["cases"][0]["exit_code"] = 1
        self.save()
        self.assertEqual(self.call("compliance").returncode, 0)
        self.bundle["attempts"][-1]["cases"][0]["exit_code"] = 127
        self.reject()

    def test_missing_contract_and_bundle_fail_closed(self):
        (self.root / "evidence.json").unlink()
        self.assertEqual(self.call("do").returncode, 1)
        (self.root / "contract.json").unlink()
        self.assertEqual(self.call("preflight").returncode, 1)

    def test_empty_duplicate_and_control_character_scope(self):
        for scope in [[], ["product.txt", "product.txt"], ["one\ntwo"]]:
            self.contract["scope"] = scope
            self.save_contract()
            self.assertEqual(self.call("preflight").returncode, 1)

    def test_malformed_json(self):
        (self.root / "evidence.json").write_text("{broken")
        self.assertEqual(self.call("do").returncode, 1)

    def test_contract_rejects_json_stream_before_or_after_valid(self):
        valid = json.dumps(self.contract)
        for documents in [["{}", valid], [valid, "{}"], [valid, valid]]:
            with self.subTest(documents=documents):
                (self.root / "contract.json").write_text("\n".join(documents))
                self.assertEqual(self.call("preflight").returncode, 1)

    def test_evidence_rejects_invalid_failed_or_duplicate_json_stream(self):
        valid = json.dumps(self.bundle)
        failed = copy.deepcopy(self.bundle)
        failed["attempts"][-1]["cases"][0]["status"] = "fail"
        for other in ["{}", json.dumps(failed), valid]:
            for documents in [[other, valid], [valid, other]]:
                with self.subTest(documents=documents):
                    (self.root / "evidence.json").write_text("\n".join(documents))
                    self.assertEqual(self.call("archive").returncode, 1)

    def test_impossible_calendar_dates_rejected_in_contract(self):
        for timestamp in ["2026-02-30T00:00:00Z", "2026-04-31T00:00:00Z", "2026-01-01T24:00:00Z"]:
            self.contract["defined_at"] = timestamp
            self.save_contract()
            self.assertEqual(self.call("preflight").returncode, 1)

    def test_impossible_calendar_dates_rejected_in_evidence(self):
        for timestamp in ["2026-02-30T00:00:00Z", "2026-04-31T00:00:00Z"]:
            self.bundle["preflight"]["timestamp"] = "2026-02-01T00:00:00Z"
            self.bundle["implementation_started_at"] = "2026-02-01T00:00:00Z"
            for attempt in self.bundle["attempts"]:
                attempt["timestamp"] = timestamp
            self.reject()

    def test_artifact_cannot_escape_or_be_symlink(self):
        (self.root / "link").symlink_to(self.root / "output.txt")
        for path in ["../outside", "/etc/passwd", "link", "output.txt\nother"]:
            self.bundle["attempts"][-1]["cases"][0]["artifact"]["relative_path"] = path
            self.reject()

    def test_changed_artifact(self):
        (self.root / "output.txt").write_text("different output")
        self.reject()

    def test_missing_artifact(self):
        (self.root / "output.txt").unlink()
        self.reject()

    def test_wrong_revision(self):
        self.git("commit", "--allow-empty", "-qm", "new revision")
        self.reject()

    def test_contract_drift(self):
        self.contract["criteria"][0]["expected"] = "weaker result"
        self.save_contract()
        self.reject()

    def test_failed_blocked_wrong_environment_and_exit(self):
        original = copy.deepcopy(self.bundle)
        for key, value in [("status", "fail"), ("status", "blocked"), ("status", "skipped"),
                           ("environment", "wrong"), ("exit_code", 2), ("source", "unknown")]:
            self.bundle = copy.deepcopy(original)
            self.bundle["attempts"][-1]["cases"][0][key] = value
            self.reject()

    def test_correction_invalidates_same_second_qa_then_retest(self):
        self.bundle["attempts"].append(self.attempt("do"))
        self.reject()
        self.bundle["attempts"].append(self.attempt("qa"))
        self.reject()
        self.bundle["attempts"].append(self.attempt("compliance"))
        self.save()
        self.assertEqual(self.call("compliance").returncode, 0)

    def test_missing_preflight(self):
        del self.bundle["preflight"]
        self.reject()

    def test_future_and_invalid_time(self):
        for timestamp in ["2999-01-01T00:00:00Z", "yesterday"]:
            self.bundle["attempts"][-1]["timestamp"] = timestamp
            self.reject()

    def test_review_is_independent(self):
        self.bundle["attempts"][-1]["actor"] = "do-agent"
        self.reject()

    def test_quick_has_same_evidence_floor(self):
        self.contract["workflow"] = {"complexity": "L1", "task_type": "framework", "route": ["quick"]}
        self.write_metadata()
        self.contract["criteria"][0]["cases"]["happy"]["required_stage"] = "quick"
        self.save_contract()
        self.preflight = json.loads(self.call("preflight").stdout)
        self.bundle["preflight"] = self.preflight
        self.bundle["implementation_started_at"] = self.preflight["timestamp"]
        self.bundle["attempts"] = [self.attempt("quick")]
        self.save()
        self.assertEqual(self.call("quick").returncode, 0)
        self.reject("archive")
        self.bundle["attempts"][0]["cases"][0]["status"] = "fail"
        self.reject("quick")

    def test_lightweight_routes_do_not_invent_skipped_receipts(self):
        for complexity, route in [("L1", ["do", "archive"]), ("L2", ["do", "archive"]),
                                  ("L2", ["do", "qa", "archive"])]:
            self.use_route(complexity, "framework", route)
            result = self.call("archive")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(self.bundle["attempts"]), len(route) - 1)
            self.reject("compliance")

    def test_l3_l4_cannot_skip_required_reviews(self):
        for complexity in ["L3", "L4"]:
            for route in [["do", "archive"], ["do", "qa", "archive"], ["quick"]]:
                self.contract["workflow"] = {"complexity": complexity, "task_type": "framework", "route": route}
                self.write_metadata()
                self.save_contract()
                self.assertEqual(self.call("preflight").returncode, 1)

    def test_canonical_task_binding_and_downgrade_fail(self):
        path = self.root / "datarim/tasks/TEST-0001-task-description.md"
        original = path.read_text()
        for changed in [original.replace("L3", "L1"), original.replace("framework", "content"),
                        original.replace("TEST-0001", "TEST-0002")]:
            path.write_text(changed)
            self.assertEqual(self.call("archive").returncode, 1)
        self.contract["workflow"] = {"complexity": "L1", "task_type": "framework", "route": ["do", "archive"]}
        self.write_metadata()
        self.save_contract()
        self.reject("archive")  # Cannot reuse the higher-complexity pre-work baseline.

    def test_content_routes_use_real_stages_and_full_case_coverage(self):
        for route in [["write", "edit", "publish", "archive"], ["edit", "archive"], ["publish", "archive"]]:
            self.use_route("L2", "content", route)
            self.assertEqual(self.call(route[0]).returncode, 0)
            self.assertEqual(self.call("archive").returncode, 0)
            self.assertNotIn("do", [a["stage"] for a in self.bundle["attempts"]])
            self.bundle["attempts"][-1]["cases"] = []
            self.reject("archive")

    def test_content_l3_retains_independent_compliance(self):
        self.use_route("L3", "content", ["write", "edit", "publish", "qa", "compliance", "archive"])
        self.assertEqual(self.call("archive").returncode, 0)
        self.bundle["attempts"][-1]["actor"] = "publish-agent"
        self.reject("archive")

    def test_content_edit_is_independent_of_author(self):
        self.use_route("L2", "content", ["write", "edit", "archive"])
        self.bundle["attempts"][-1]["actor"] = "write-agent"
        self.reject("edit")

    def test_case_cannot_be_assigned_to_skipped_stage(self):
        self.contract["workflow"] = {"complexity": "L1", "task_type": "framework", "route": ["do", "archive"]}
        self.contract["criteria"][0]["cases"]["happy"]["required_stage"] = "qa"
        self.write_metadata()
        self.save_contract()
        self.assertEqual(self.call("preflight").returncode, 1)

    def test_canonical_type_remains_freeform(self):
        self.use_route("L1", "technical documentation", ["do", "archive"])
        self.assertEqual(self.call("archive").returncode, 0)

    def test_task_id_must_follow_canonical_shape(self):
        self.contract["task_id"] = "TEST-1"
        self.save_contract()
        path = self.root / "datarim/tasks/TEST-1-task-description.md"
        path.write_text("---\nid: TEST-1\ncomplexity: L3\ntype: framework\n---\n")
        self.assertEqual(self.call("preflight").returncode, 1)

    def test_later_case_pending_until_due_and_final_aggregate(self):
        self.contract["criteria"][0]["cases"]["production"] = {
            "expected": "approved live behavior", "expected_exit_code": 0, "required_stage": "archive"}
        self.save_contract()
        self.preflight = json.loads(self.call("preflight").stdout)
        self.bundle["preflight"] = self.preflight
        self.bundle["implementation_started_at"] = self.preflight["timestamp"]
        self.bundle["attempts"] = [self.attempt(s) for s in ["do", "qa", "compliance"]]
        self.save()
        result = self.call("compliance")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["pending"][0]["case_id"], "production")
        self.reject("archive")
        archive = self.attempt("archive")
        archive["cases"].append(copy.deepcopy(archive["cases"][0]))
        archive["cases"][-1]["case_id"] = "production"
        archive["cases"][-1]["status"] = "WAITING_OPERATOR"
        self.bundle["attempts"].append(archive)
        self.reject("archive")
        archive["cases"][-1]["status"] = "pass"
        self.save()
        self.assertEqual(self.call("archive").returncode, 0)

    def test_ordinary_edit_does_not_rewrite_preflight(self):
        original = copy.deepcopy(self.preflight)
        (self.root / "product.txt").write_text("corrected observable behavior")
        current = json.loads(self.call("snapshot").stdout)
        for attempt in self.bundle["attempts"]:
            attempt["scope_sha256"] = current["scope_sha256"]
        self.save()
        self.assertEqual(self.call("compliance").returncode, 0)
        self.assertEqual(self.bundle["preflight"], original)
        self.bundle["preflight"] = current
        self.reject()

    def test_escape_and_symlink_rejected(self):
        for path in ["../outside", "/etc/passwd", "product.txt/../output.txt"]:
            self.contract["scope"] = [path]
            self.save_contract()
            self.assertEqual(self.call("preflight").returncode, 1)
        (self.root / "link").symlink_to(self.root / "product.txt")
        self.contract["scope"] = ["link"]
        self.save_contract()
        self.assertEqual(self.call("preflight").returncode, 1)

    def test_legacy_is_explicitly_uncertified(self):
        result = subprocess.run(["bash", str(GATE), "--expectations", "/nonexistent",
                                 "--qa-report", "/nonexistent"], capture_output=True, text=True)
        self.assertIn("UNCERTIFIED", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
