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

    def test_contract_replaced_after_strict_parser_is_refused(self):
        import os
        import shutil
        import shlex
        wrapper = self.root / "bin"
        wrapper.mkdir()
        real_python = shutil.which("python3")
        script = wrapper / "python3"
        target = self.root / "contract.json"
        replacement = self.root / "replacement.json"
        replacement.write_text(target.read_text().replace('"version": 1', '"version": 0, "version": 1'))
        script.write_text("#!/bin/bash\n" + shlex.quote(real_python) + ' "$@"\nstatus=$?\n'
                          + 'if [[ "$2" == ' + shlex.quote(str(target)) + ' && "$status" == 0 ]]; then\n'
                          + 'cp ' + shlex.quote(str(replacement)) + ' ' + shlex.quote(str(target)) + '\nfi\nexit "$status"\n')
        script.chmod(0o700)
        environment = dict(os.environ, PATH=str(wrapper) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", str(GATE), "--contract", str(target),
                                 "--evidence", str(self.root / "evidence.json"), "--root",
                                 str(self.root), "--stage", "preflight"], env=environment,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("contract changed during verification", result.stderr)

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

    def bind_inputs(self, inputs):
        self.contract["inputs"] = inputs
        self.save_contract()
        result = self.call("preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.preflight = json.loads(result.stdout)
        self.bundle = {"task_id": "TEST-0001", "preflight": self.preflight,
                       "implementation_started_at": self.preflight["timestamp"],
                       "attempts": [self.attempt(stage) for stage in ["do", "qa", "compliance"]]}
        self.save()

    def call(self, stage):
        return subprocess.run(["bash", str(GATE), "--contract", str(self.root / "contract.json"),
                               "--evidence", str(self.root / "evidence.json"), "--root",
                               str(self.root), "--stage", stage], capture_output=True, text=True)

    def summary_args(self, stage):
        return ["--summary-json", "--contract", str(self.root / "contract.json"),
                "--evidence", str(self.root / "evidence.json"), "--root",
                str(self.root), "--stage", stage]

    def call_summary(self, stage, env=None):
        return subprocess.run([str(GATE), *self.summary_args(stage)], env=env,
                              capture_output=True)

    def call_summary_args(self, args, env=None):
        return subprocess.run([str(GATE), *args], env=env, capture_output=True)

    def parse_summary(self, result):
        self.assertEqual(result.stderr, b"")
        self.assertTrue(result.stdout.endswith(b"\n"), result.stdout)
        self.assertEqual(result.stdout.count(b"\n"), 1, result.stdout)

        def unique_object(pairs):
            value = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError("duplicate summary key")
                value[key] = item
            return value

        def reject_constant(value):
            raise ValueError(f"invalid JSON constant: {value}")

        summary = json.loads(result.stdout.decode("utf-8"),
                             object_pairs_hook=unique_object,
                             parse_constant=reject_constant)
        self.assertIsInstance(summary, dict)
        self.assertEqual(set(summary), {"schema", "verdict", "reason_code", "exit_code", "stage",
                                        "identity", "counts"})
        self.assertEqual(set(summary["identity"]),
                         {"task_binding", "source_revision", "input_binding"})
        self.assertEqual(set(summary["identity"]["source_revision"]), {"availability", "value"})
        self.assertEqual(set(summary["counts"]), {"criteria_defined", "cases_defined", "cases_due",
                                                   "cases_validated", "cases_pending"})
        for count in summary["counts"].values():
            self.assertEqual(set(count), {"availability", "value"})
        self.assertNotIn("TEST-0001", result.stdout.decode("utf-8"))
        self.assertNotIn(str(self.root), result.stdout.decode("utf-8"))
        self.assertNotIn("contract.json", result.stdout.decode("utf-8"))
        self.assertNotIn("evidence.json", result.stdout.decode("utf-8"))
        self.assertNotIn("UNCERTIFIED", result.stdout.decode("utf-8"))
        return summary

    @staticmethod
    def count_value(value=None):
        if value is None:
            return {"availability": "NOT_MEASURED", "value": None}
        return {"availability": "AVAILABLE", "value": value}

    def expected_summary(self, verdict, reason, exit_code, stage, *, task_binding="NOT_MEASURED",
                         revision=None, input_binding="NOT_MEASURED", criteria=None, cases=None,
                         due=None, validated=None, pending=None):
        source_revision = ({"availability": "NOT_MEASURED", "value": None} if revision is None
                           else {"availability": "AVAILABLE", "value": revision})
        return {
            "schema": "datarim.live-evidence-summary/v1",
            "verdict": verdict,
            "reason_code": reason,
            "exit_code": exit_code,
            "stage": stage,
            "identity": {"task_binding": task_binding, "source_revision": source_revision,
                         "input_binding": input_binding},
            "counts": {"criteria_defined": self.count_value(criteria),
                       "cases_defined": self.count_value(cases),
                       "cases_due": self.count_value(due),
                       "cases_validated": self.count_value(validated),
                       "cases_pending": self.count_value(pending)},
        }

    def attempt(self, stage):
        attempt = {"stage": stage, "actor": stage + "-agent", "timestamp": self.preflight["timestamp"],
                   "revision": self.preflight["revision"],
                   "contract_sha256": self.preflight["contract_sha256"],
                   "scope_sha256": self.preflight["scope_sha256"],
                   "cases": [{"criterion_id": "AC-1", "case_id": "happy",
                           "observed": "named assertion passed", "status": "pass",
                           "evidence_type": "static", "environment": "test", "source": "fixture",
                           "command": "assert named behavior", "exit_code": 0,
                           "artifact": {"relative_path": "output.txt",
                                        "sha256": hashlib.sha256((self.root / "output.txt").read_bytes()).hexdigest()}}]}
        if "inputs_sha256" in self.preflight:
            attempt["inputs_sha256"] = self.preflight["inputs_sha256"]
        return attempt

    def test_legacy_contract_without_inputs_keeps_scope_only_compatibility(self):
        self.assertNotIn("inputs_sha256", self.preflight)
        self.assertIn("Legacy contract omits inputs[]", self.preflight["compatibility_note"])
        result = self.call("compliance")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_empty_inputs_are_bound_separately_from_legacy(self):
        self.bind_inputs([])
        self.assertEqual(self.preflight["inputs_sha256"], hashlib.sha256(b"").hexdigest())
        self.assertNotIn("compatibility_note", self.preflight)
        result = self.call("compliance")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unchanged_input_manifest_reuses_green_attempts(self):
        (self.root / "fixture.json").write_text('{"fixture":true}\n')
        (self.root / "schema.json").write_text('{"type":"object"}\n')
        (self.root / "untracked.data").write_text("synthetic untracked input\n")
        for path in ["fixture.json", "schema.json", "untracked.data"]:
            self.assertNotIn(path, self.git("ls-files").splitlines())
        self.bind_inputs([
            {"kind": "file", "path": "fixture.json"},
            {"kind": "file", "path": "schema.json"},
            {"kind": "file", "path": "untracked.data"},
            {"kind": "argv", "name": "check", "sha256": "a" * 64},
            {"kind": "env", "name": "synthetic-fixture-env", "sha256": "b" * 64,
             "synthetic": True},
        ])
        self.assertIn("inputs_sha256", self.preflight)
        self.assertTrue(all(a["inputs_sha256"] == self.preflight["inputs_sha256"]
                            for a in self.bundle["attempts"]))
        result = self.call("compliance")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_superseded_input_attempts_keep_history_without_blocking_return_to_baseline(self):
        fixture = self.root / "fixture.json"
        fixture.write_text('{"input":"A"}\n')
        self.bind_inputs([{"kind": "file", "path": "fixture.json"}])
        baseline_preflight = copy.deepcopy(self.bundle["preflight"])
        baseline_digest = baseline_preflight["inputs_sha256"]
        baseline_head = self.git("rev-parse", "HEAD")
        do_a, qa_a, compliance_a = copy.deepcopy(self.bundle["attempts"])

        fixture.write_text('{"input":"B"}\n')
        digest_b = json.loads(self.call("snapshot").stdout)["inputs_sha256"]
        self.assertNotEqual(digest_b, baseline_digest)
        qa_b = copy.deepcopy(qa_a)
        qa_b["inputs_sha256"] = digest_b
        fixture.write_text('{"input":"A"}\n')

        archive_a = self.attempt("archive")
        self.bundle["attempts"] = [do_a, qa_b, qa_a, compliance_a, archive_a]
        result = self.call("archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["verdict"], "STAGE_PASS")
        self.assertEqual(self.bundle["preflight"], baseline_preflight)
        self.assertEqual(self.git("rev-parse", "HEAD"), baseline_head)

        archive_b = copy.deepcopy(archive_a)
        archive_b["inputs_sha256"] = digest_b
        self.bundle["attempts"] = [do_a, qa_a, compliance_a, archive_b]
        self.reject("archive")

        malformed_superseded = copy.deepcopy(qa_b)
        malformed_superseded["inputs_sha256"] = "not-a-digest"
        self.bundle["attempts"] = [do_a, malformed_superseded, qa_a, compliance_a, archive_a]
        self.reject("archive")
        self.assertEqual(self.bundle["preflight"], baseline_preflight)
        self.assertEqual(self.git("rev-parse", "HEAD"), baseline_head)

    def test_changed_fixture_schema_or_untracked_input_blocks_same_head(self):
        paths = ["fixture.json", "schema.json", "untracked.data"]
        for path in paths:
            (self.root / path).write_text("initial synthetic input\n")
        inputs = [{"kind": "file", "path": path} for path in paths]
        self.bind_inputs(inputs)
        original_head = self.git("rev-parse", "HEAD")
        for index, path in enumerate(paths):
            if index:
                self.bind_inputs(inputs)
            (self.root / path).write_text(f"changed input {index}\n")
            self.reject("compliance")
            if path == "untracked.data":
                # The changed input makes the retained preflight/attempt digest
                # stale before final rechecks, so the existing validator's
                # fixed boundary is evidence_validation_failed.
                summary_result = self.call_summary("compliance")
                self.assertEqual(summary_result.returncode, 1,
                                 summary_result.stdout + summary_result.stderr)
                summary = self.parse_summary(summary_result)
                self.assertEqual(summary, self.expected_summary(
                    "BLOCKED", "evidence_validation_failed", 1, "compliance",
                    task_binding="VERIFIED", revision=original_head, input_binding="BOUND",
                    criteria=1, cases=1))
            self.assertEqual(self.git("rev-parse", "HEAD"), original_head)

    def test_missing_planned_input_uses_missing_marker_then_presence_blocks(self):
        planned = self.root / "planned-schema.json"
        self.assertFalse(planned.exists())
        self.bind_inputs([{"kind": "file", "path": "planned-schema.json"}])
        missing_digest = self.preflight["inputs_sha256"]
        self.assertEqual(self.call("compliance").returncode, 0)
        planned.write_text('{"type":"object"}\n')
        self.assertNotEqual(json.loads(self.call("snapshot").stdout)["inputs_sha256"], missing_digest)
        self.reject("compliance")

    def test_changed_command_or_synthetic_env_digest_invalidates_input_binding(self):
        for kind in ["argv", "env"]:
            with self.subTest(kind=kind):
                if kind == "argv":
                    inputs = [{"kind": "argv", "name": "synthetic-check", "sha256": "c" * 64}]
                else:
                    inputs = [{"kind": "env", "name": "synthetic-config", "sha256": "d" * 64,
                               "synthetic": True}]
                self.bind_inputs(inputs)
                stale_input_hash = self.preflight["inputs_sha256"]
                inputs[0]["sha256"] = "e" * 64
                self.save_contract()
                new_contract_hash = hashlib.sha256((self.root / "contract.json").read_bytes()).hexdigest()
                self.bundle["preflight"]["contract_sha256"] = new_contract_hash
                for attempt in self.bundle["attempts"]:
                    attempt["contract_sha256"] = new_contract_hash
                self.save()
                self.assertEqual(self.bundle["preflight"]["inputs_sha256"], stale_input_hash)
                self.reject("compliance")

    def test_malformed_duplicate_and_unsafe_input_manifests_fail_closed(self):
        malformed = [
            [{"kind": "file", "path": "fixture.json"}, {"kind": "file", "path": "fixture.json"}],
            [{"kind": "argv", "name": "check", "sha256": "not-a-digest"}],
            [{"kind": "argv", "name": "check", "sha256": "a" * 64},
             {"kind": "argv", "name": "check", "sha256": "b" * 64}],
            [{"kind": "env", "name": "live-env", "sha256": "a" * 64, "synthetic": False}],
            [{"kind": "file", "path": "../outside"}],
            [{"kind": "file", "path": "/etc/passwd"}],
        ]
        for inputs in malformed:
            with self.subTest(inputs=inputs):
                self.contract["inputs"] = inputs
                self.save_contract()
                result = self.call("preflight")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        (self.root / "linked-input").symlink_to(self.root / "product.txt")
        self.contract["inputs"] = [{"kind": "file", "path": "linked-input"}]
        self.save_contract()
        result = self.call("preflight")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def reject(self, stage="compliance"):
        self.save()
        result = self.call(stage)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("BLOCKED", result.stderr)

    def test_duplicate_literal_case_key_is_not_silently_replaced(self):
        path = self.root / "contract.json"
        raw = path.read_text().replace(
            '"cases": {"happy":',
            '"cases": {"happy": {"expected": "conflicting first definition", '
            '"expected_exit_code": 1, "required_stage": "do"}, "happy":', 1)
        path.write_text(raw)
        result = self.call("preflight")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ambiguous or invalid contract JSON", result.stderr)

    def test_duplicate_status_cannot_replace_failure_with_pass(self):
        path = self.root / "evidence.json"
        path.write_text(path.read_text().replace(
            '"status": "pass"', '"status": "fail", "status": "pass"', 1))
        result = self.call("compliance")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ambiguous or invalid evidence JSON", result.stderr)

    def test_duplicate_nested_object_with_disjoint_children_is_refused(self):
        path = self.root / "contract.json"
        raw = path.read_text().replace('"cases": {', '"cases": {"ignored": {}}, "cases": {', 1)
        path.write_text(raw)
        self.assertEqual(self.call("preflight").returncode, 1)

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
        summary_result = self.call_summary("compliance")
        self.assertEqual(summary_result.returncode, 0, summary_result.stdout + summary_result.stderr)
        summary = self.parse_summary(summary_result)
        self.assertEqual(summary["verdict"], "STAGE_PASS")
        self.assertEqual(summary["counts"], {
            "criteria_defined": self.count_value(1), "cases_defined": self.count_value(2),
            "cases_due": self.count_value(1), "cases_validated": self.count_value(1),
            "cases_pending": self.count_value(1),
        })
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

    def test_summary_json_preflight_stage_and_default_output_parity(self):
        revision = self.git("rev-parse", "HEAD")
        preflight_result = self.call_summary("preflight")
        self.assertEqual(preflight_result.returncode, 0, preflight_result.stdout + preflight_result.stderr)
        preflight = self.parse_summary(preflight_result)
        self.assertEqual(preflight, self.expected_summary(
            "PREFLIGHT_RECEIPT", "preflight_receipt_created", 0, "preflight",
            task_binding="VERIFIED", revision=revision, input_binding="LEGACY_OMITTED",
            criteria=1, cases=1))

        snapshot_result = self.call_summary("snapshot")
        self.assertEqual(snapshot_result.returncode, 0, snapshot_result.stdout + snapshot_result.stderr)
        snapshot = self.parse_summary(snapshot_result)
        self.assertEqual(snapshot, self.expected_summary(
            "SNAPSHOT_RECEIPT", "snapshot_receipt_created", 0, "snapshot",
            task_binding="VERIFIED", revision=revision, input_binding="LEGACY_OMITTED",
            criteria=1, cases=1))

        self.bundle["attempts"][-1]["cases"][0]["observed"] = "https://fixture.invalid/private /tmp/private-output"
        self.bundle["attempts"][-1]["cases"][0]["command"] = "echo private fixture diagnostic"
        self.save()

        pass_result = self.call_summary("compliance")
        self.assertEqual(pass_result.returncode, 0, pass_result.stdout + pass_result.stderr)
        passed = self.parse_summary(pass_result)
        self.assertEqual(passed, self.expected_summary(
            "STAGE_PASS", "evidence_stage_validated", 0, "compliance",
            task_binding="VERIFIED", revision=revision, input_binding="LEGACY_OMITTED",
            criteria=1, cases=1, due=1, validated=1, pending=0))
        for private_value in ("https://fixture.invalid/private", "/tmp/private-output",
                              "private fixture diagnostic"):
            self.assertNotIn(private_value, pass_result.stdout.decode("utf-8"))

        default_result = self.call("compliance")
        self.assertEqual(default_result.returncode, 0, default_result.stderr)
        default = json.loads(default_result.stdout)
        self.assertEqual(default["verdict"], "STAGE_PASS")
        self.assertEqual(default["task_id"], "TEST-0001")
        self.assertNotIn("schema", default)

    def test_summary_json_fixed_refusal_reasons_and_unknown_counts(self):
        revision = self.git("rev-parse", "HEAD")
        contract_path = self.root / "contract.json"
        contract_path.write_text('{"version":1,"version":1}\n')
        result = self.call_summary("preflight")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = self.parse_summary(result)
        self.assertEqual(summary, self.expected_summary(
            "BLOCKED", "contract_json_invalid", 1, "preflight", revision=revision))

        self.save_contract()
        evidence_path = self.root / "evidence.json"
        evidence_path.write_text('{"task_id":"TEST-0001","task_id":"TEST-0001"}\n')
        result = self.call_summary("compliance")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = self.parse_summary(result)
        self.assertEqual(summary, self.expected_summary(
            "BLOCKED", "evidence_json_invalid", 1, "compliance", task_binding="VERIFIED",
            revision=revision, input_binding="LEGACY_OMITTED", criteria=1, cases=1))

        self.save()
        self.bundle["attempts"][-1]["cases"][0]["status"] = "fail"
        self.save()
        result = self.call_summary("compliance")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = self.parse_summary(result)
        self.assertEqual(summary, self.expected_summary(
            "BLOCKED", "evidence_validation_failed", 1, "compliance",
            task_binding="VERIFIED", revision=revision, input_binding="LEGACY_OMITTED",
            criteria=1, cases=1))

        self.bundle["attempts"][-1]["cases"][0]["status"] = "pass"
        self.save()
        self.contract["version"] = 2
        self.save_contract()
        result = self.call_summary("preflight")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = self.parse_summary(result)
        self.assertEqual(summary["reason_code"], "contract_schema_invalid")
        self.assertEqual(summary["counts"]["criteria_defined"], self.count_value())
        self.assertEqual(summary["counts"]["cases_defined"], self.count_value())

    def test_summary_json_invocation_and_root_errors_are_fixed(self):
        valid = self.summary_args("qa")
        cases = [
            ("flag alone", ["--summary-json"], "invalid_arguments", None),
            ("duplicate summary flag", ["--summary-json", *valid], "invalid_arguments", None),
            ("missing value", ["--summary-json", "--contract"], "invalid_arguments", None),
            ("empty first contract before valid duplicate",
             ["--summary-json", "--contract", "", "--contract", str(self.root / "contract.json"),
              "--evidence", str(self.root / "evidence.json"), "--root", str(self.root),
              "--stage", "qa"], "invalid_arguments", None),
            ("empty first evidence before valid duplicate",
             ["--summary-json", "--contract", str(self.root / "contract.json"),
              "--evidence", "", "--evidence", str(self.root / "evidence.json"),
              "--root", str(self.root), "--stage", "qa"], "invalid_arguments", None),
            ("empty first root before valid duplicate",
             ["--summary-json", "--contract", str(self.root / "contract.json"),
              "--evidence", str(self.root / "evidence.json"), "--root", "", "--root",
              str(self.root), "--stage", "qa"], "invalid_arguments", None),
            ("empty first stage before valid duplicate",
             ["--summary-json", "--contract", str(self.root / "contract.json"),
              "--evidence", str(self.root / "evidence.json"), "--root", str(self.root),
              "--stage", "", "--stage", "qa"], "invalid_arguments", None),
            ("missing required evidence", ["--summary-json", "--contract",
                                             str(self.root / "contract.json"), "--root",
                                             str(self.root), "--stage", "qa"],
             "invalid_arguments", "qa"),
            ("missing stage", ["--summary-json", "--contract", str(self.root / "contract.json"),
                               "--evidence", str(self.root / "evidence.json"), "--root",
                               str(self.root)], "invalid_stage", None),
            ("flag cannot be a value", ["--summary-json", "--contract", "--summary-json",
                                         "--evidence", str(self.root / "evidence.json"),
                                         "--root", str(self.root), "--stage", "qa"],
             "invalid_arguments", None),
            ("invalid stage", self.summary_args("not-a-stage"), "invalid_stage", None),
            ("unknown option", [*valid, "--unknown"], "invalid_arguments", "qa"),
            ("legacy flags are refused", ["--summary-json", "--expectations", "synthetic"],
             "legacy_mode_unsupported", None),
        ]
        for label, args, reason, stage in cases:
            with self.subTest(label=label):
                result = self.call_summary_args(args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                summary = self.parse_summary(result)
                self.assertEqual(summary, self.expected_summary(
                    "USAGE_ERROR", reason, 2, stage))

        invalid_root = list(valid)
        invalid_root[6] = str(self.root / "missing-root")
        result = self.call_summary_args(invalid_root)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        summary = self.parse_summary(result)
        self.assertEqual(summary, self.expected_summary(
            "USAGE_ERROR", "repository_root_invalid", 2, "qa"))

    def test_summary_json_missing_jq_uses_hermetic_real_entrypoint(self):
        import shutil

        with tempfile.TemporaryDirectory() as tool_dir:
            tool_path = Path(tool_dir)
            for name in ("bash", "dirname", "python3", "git", "sha256sum", "cut"):
                target = shutil.which(name)
                self.assertIsNotNone(target, f"required fixture command unavailable: {name}")
                (tool_path / name).symlink_to(target)
            isolated_path = str(tool_path)
            self.assertIsNone(shutil.which("jq", path=isolated_path))
            for name in ("bash", "dirname", "python3", "git", "sha256sum", "cut"):
                self.assertEqual(shutil.which(name, path=isolated_path), str(tool_path / name))
            result = self.call_summary("qa", env={"PATH": isolated_path, "LC_ALL": "C", "TZ": "UTC"})
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        expected = self.expected_summary("USAGE_ERROR", "dependency_unavailable", 2, "qa")
        self.assertEqual(self.parse_summary(result), expected)
        self.assertNotIn(b"jq", result.stdout + result.stderr)

    def test_summary_json_reports_hash_tools_unavailable_separately(self):
        import shutil

        with tempfile.TemporaryDirectory() as tool_dir:
            tool_path = Path(tool_dir)
            for name in ("bash", "dirname", "python3", "git", "jq"):
                target = shutil.which(name)
                self.assertIsNotNone(target, f"required fixture command unavailable: {name}")
                (tool_path / name).symlink_to(target)
            isolated_path = str(tool_path)
            self.assertIsNone(shutil.which("sha256sum", path=isolated_path))
            self.assertIsNone(shutil.which("shasum", path=isolated_path))
            result = self.call_summary("qa", env={"PATH": isolated_path, "LC_ALL": "C", "TZ": "UTC"})
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(self.parse_summary(result), self.expected_summary(
            "USAGE_ERROR", "hash_utility_unavailable", 2, "qa"))

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
