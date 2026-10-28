"""Focused CLI contract tests for the explicit, read-only test audit report."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "dev-tools/build-test-audit-report.py"
CARD = {
    "protects": "A selected test remains bound to its source bytes.",
    "fails_when": "Removing source binding makes this fixture assertion fail.",
    "why_new": "Existing tests cover cards, not explicit audit selections.",
    "seam": "none",
    "no_claim": "This structural report does not establish test value.",
}


class TestAuditReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project"
        (self.root / "tests").mkdir(parents=True)
        (self.root / "audit").mkdir()
        (self.root / "tests/test_one.py").write_bytes(b"assert True\n")
        (self.root / "tests/test_two.py").write_bytes(b"assert False\n")
        self.selection_path = "audit/selection.json"

    def entry(self, path: str = "tests/test_one.py", **updates: object) -> dict:
        value = {
            "test_path": path,
            "card": dict(CARD),
            "proposed_action": "retain",
            "rationale": "Keep the selected regression visible for review.",
            "limits": "Reassess this proposal with current evidence.",
            "overlap_with": [],
            "evidence_refs": [],
        }
        value.update(updates)
        return value

    def selection(self, entries: list[dict] | None = None) -> dict:
        return {"schema_version": 1, "tests": entries if entries is not None else [self.entry()]}

    def write_selection(self, value: object, path: str | None = None) -> None:
        target = self.root / (path or self.selection_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, bytes):
            target.write_bytes(value)
        elif isinstance(value, str):
            target.write_text(value, encoding="utf-8")
        else:
            target.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")

    def invoke(self, selection_path: str | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(BUILDER), "--root", str(self.root), "--selection",
             selection_path or self.selection_path],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_error(self, code: str, value: object, path: str | None = None) -> subprocess.CompletedProcess:
        self.write_selection(value, path)
        result = self.invoke(path)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, f"ERROR {code}\n")
        return result

    def test_report_contains_only_explicit_selection_and_byte_bindings(self) -> None:
        source = (self.root / "tests/test_one.py").read_bytes()
        other = (self.root / "tests/test_two.py").read_bytes()
        selection_bytes = json.dumps(self.selection(), ensure_ascii=False).encode()
        (self.root / self.selection_path).write_bytes(selection_bytes)
        before = {
            path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in self.root.rglob("*") if path.is_file()
        }

        result = self.invoke()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        report = json.loads(result.stdout)
        self.assertEqual(report["schema"], "datarim.test-audit-report/v1")
        self.assertEqual(report["selection"]["sha256"], hashlib.sha256(selection_bytes).hexdigest())
        self.assertEqual([item["test_path"] for item in report["tests"]], ["tests/test_one.py"])
        self.assertEqual(report["tests"][0]["source_sha256"], hashlib.sha256(source).hexdigest())
        self.assertEqual(report["tests"][0]["proposed_action"], "retain")
        self.assertEqual(report["tests"][0]["costs"]["wall_time_ms"]["status"], "NOT_MEASURED")
        self.assertEqual(report["tests"][0]["costs"]["flaky_attempts"]["value"], None)
        self.assertNotIn(str(self.root), result.stdout)
        self.assertNotEqual(hashlib.sha256(other).hexdigest(), report["tests"][0]["source_sha256"])
        after = {
            path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in self.root.rglob("*") if path.is_file()
        }
        self.assertEqual(before, after)

    def test_cited_costs_are_resolved_by_exact_json_pointer_and_raw_receipt_is_not_copied(self) -> None:
        receipt = {"runs": [{"wall_time_ms": 12.5, "flaky_attempts": 0, "private_note": "raw receipt text"}]}
        receipt_path = self.root / "audit/run.json"
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        entry = self.entry(evidence_refs=[{
            "path": "audit/run.json",
            "sha256": digest,
            "cost_pointers": {"wall_time_ms": "/runs/0/wall_time_ms", "flaky_attempts": "/runs/0/flaky_attempts"},
        }])
        self.write_selection(self.selection([entry]))

        result = self.invoke()

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        costs = report["tests"][0]["costs"]
        self.assertEqual(costs["wall_time_ms"]["value"], 12.5)
        self.assertEqual(costs["wall_time_ms"]["evidence"]["json_pointer"], "/runs/0/wall_time_ms")
        self.assertEqual(costs["wall_time_ms"]["evidence"]["sha256"], digest)
        self.assertEqual(costs["flaky_attempts"]["value"], 0)
        self.assertNotIn("raw receipt text", result.stdout)

    def test_valid_overlap_target_is_in_the_same_explicit_selection(self) -> None:
        first = self.entry(overlap_with=["tests/test_two.py"])
        second = self.entry("tests/test_two.py", proposed_action="merge")
        self.write_selection(self.selection([first, second]))
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual([row["test_path"] for row in report["tests"]], ["tests/test_one.py", "tests/test_two.py"])
        self.assertEqual(report["tests"][0]["overlap_with"], ["tests/test_two.py"])

    def test_empty_duplicate_and_over_limit_selections_refuse(self) -> None:
        self.assert_error("SELECTION_COUNT_INVALID", self.selection([]))
        self.assert_error("SELECTION_DUPLICATE_TEST", self.selection([self.entry(), self.entry()]))
        self.assert_error("SELECTION_COUNT_INVALID", self.selection([self.entry() for _ in range(21)]))

    def test_oversized_and_malformed_selection_refuse_with_fixed_diagnostics(self) -> None:
        self.assert_error("SELECTION_TOO_LARGE", b" " * 65537)
        self.assert_error("SELECTION_INVALID", b"{")
        self.assert_error("SELECTION_INVALID", b'{"schema_version":1,"schema_version":1,"tests":[]}')
        self.assert_error("SELECTION_INVALID", b'{"schema_version":NaN,"tests":[]}')

    def test_selection_path_must_be_relative_contained_and_not_a_glob(self) -> None:
        self.assert_error("TEST_PATH_INVALID", self.selection([self.entry("../outside.py")]))
        self.assert_error("TEST_PATH_INVALID", self.selection([self.entry("/etc/passwd")]))
        self.assert_error("TEST_PATH_INVALID", self.selection([self.entry("tests/*.py")]))
        self.assert_error("TEST_PATH_INVALID", self.selection([self.entry("config/credentials/token.json")]))

    def test_symlink_and_non_regular_test_inputs_are_refused(self) -> None:
        external = Path(self.temporary.name) / "outside.py"
        external.write_text("pass\n", encoding="utf-8")
        (self.root / "tests/link.py").symlink_to(external)
        self.assert_error("INPUT_SYMLINK", self.selection([self.entry("tests/link.py")]))
        self.assert_error("INPUT_NOT_REGULAR", self.selection([self.entry("tests")]))

    def test_unreadable_test_source_is_refused_even_when_runner_can_read_mode_zero(self) -> None:
        source = self.root / "tests/test_one.py"
        source.chmod(0)
        self.addCleanup(source.chmod, 0o644)
        self.assert_error("INPUT_UNREADABLE", self.selection())

    def test_unknown_actions_and_unselected_or_self_overlap_refuse(self) -> None:
        self.assert_error("ACTION_UNKNOWN", self.selection([self.entry(proposed_action="delete")]))
        self.assert_error("OVERLAP_NOT_SELECTED", self.selection([self.entry(overlap_with=["tests/test_two.py"])]))
        self.assert_error("OVERLAP_NOT_SELECTED", self.selection([self.entry(overlap_with=["tests/test_one.py"])]))

    def test_cli_has_no_output_file_option(self) -> None:
        self.write_selection(self.selection())
        result = subprocess.run(
            [sys.executable, str(BUILDER), "--root", str(self.root), "--selection", self.selection_path, "--output", "report.json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "ERROR CLI_USAGE\n")

    def test_missing_evidence_is_not_measured_but_missing_or_invalid_cited_evidence_refuses(self) -> None:
        self.write_selection(self.selection())
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        cost = json.loads(result.stdout)["tests"][0]["costs"]["wall_time_ms"]
        self.assertEqual(cost, {"status": "NOT_MEASURED", "value": None, "reason": "NO_CITED_OBSERVATION"})

        missing = self.entry(evidence_refs=[{"path": "audit/missing.json", "sha256": "0" * 64, "cost_pointers": {}}])
        self.assert_error("EVIDENCE_READ_FAILED", self.selection([missing]))
        bad_hash = self.entry(evidence_refs=[{"path": "audit/run.json", "sha256": "z" * 64, "cost_pointers": {}}])
        self.assert_error("EVIDENCE_DIGEST_INVALID", self.selection([bad_hash]))

    def test_receipt_size_hash_json_pointer_and_numeric_value_are_validated(self) -> None:
        receipt_path = self.root / "audit/run.json"
        receipt_path.write_text('{"cost": "four"}', encoding="utf-8")
        actual = hashlib.sha256(receipt_path.read_bytes()).hexdigest()

        def entry_for(pointer: str, digest: str = actual) -> dict:
            return self.entry(evidence_refs=[{
                "path": "audit/run.json", "sha256": digest,
                "cost_pointers": {"wall_time_ms": pointer},
            }])

        self.assert_error("EVIDENCE_POINTER_INVALID", self.selection([entry_for("/missing")]))
        self.assert_error("EVIDENCE_VALUE_INVALID", self.selection([entry_for("/cost")]))
        self.assert_error("EVIDENCE_DIGEST_MISMATCH", self.selection([entry_for("/cost", "0" * 64)]))

        receipt_path.write_text(json.dumps({"cost": -1}), encoding="utf-8")
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        self.assert_error("EVIDENCE_VALUE_INVALID", self.selection([entry_for("/cost", digest)]))
        receipt_path.write_text('{"cost": true}', encoding="utf-8")
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        self.assert_error("EVIDENCE_VALUE_INVALID", self.selection([entry_for("/cost", digest)]))
        receipt_path.write_text('{"cost": 1,}', encoding="utf-8")
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        self.assert_error("EVIDENCE_JSON_INVALID", self.selection([entry_for("/cost", digest)]))
        receipt_path.write_bytes(b" " * 65537)
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        self.assert_error("EVIDENCE_TOO_LARGE", self.selection([entry_for("/cost", digest)]))

    def test_cost_subnormal_values_do_not_lose_sign_or_become_zero(self) -> None:
        receipt_path = self.root / "audit/run.json"
        for raw_number in ("-1e-9999", "1e-9999"):
            with self.subTest(raw_number=raw_number):
                receipt_path.write_text('{"cost":' + raw_number + '}', encoding="utf-8")
                digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
                entry = self.entry(evidence_refs=[{
                    "path": "audit/run.json", "sha256": digest,
                    "cost_pointers": {"wall_time_ms": "/cost"},
                }])
                self.assert_error("EVIDENCE_VALUE_INVALID", self.selection([entry]))

    def test_extreme_json_decimal_exponent_returns_fixed_refusal(self) -> None:
        receipt_path = self.root / "audit/run.json"
        receipt_path.write_text('{"cost":1e' + ("9" * 40) + '}', encoding="utf-8")
        digest = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        entry = self.entry(evidence_refs=[{
            "path": "audit/run.json", "sha256": digest,
            "cost_pointers": {"wall_time_ms": "/cost"},
        }])
        self.assert_error("EVIDENCE_JSON_INVALID", self.selection([entry]))

    def test_more_than_twenty_distinct_evidence_files_refuse(self) -> None:
        references = []
        for index in range(21):
            path = self.root / f"audit/r{index}.json"
            path.write_text("{}", encoding="utf-8")
            references.append({"path": f"audit/r{index}.json", "sha256": hashlib.sha256(b"{}").hexdigest(), "cost_pointers": {}})
        self.assert_error("EVIDENCE_COUNT_LIMIT", self.selection([self.entry(evidence_refs=references)]))

    def test_aggregate_read_budget_is_enforced_before_reading_past_limit(self) -> None:
        entries = []
        for index in range(9):
            relative = f"tests/large_{index}.py"
            (self.root / relative).write_bytes(b"x" * 262144)
            entries.append(self.entry(relative))
        self.assert_error("AGGREGATE_READ_LIMIT", self.selection(entries))

    def test_unicode_is_preserved_but_adversarial_text_is_never_executed_or_leaked_as_paths(self) -> None:
        marker = self.root / "audit/should-not-exist"
        rationale = "Unicode 東京 café; literal $(touch audit/should-not-exist)."
        entry = self.entry(rationale=rationale, limits="Synthetic only; no runtime claim.")
        self.write_selection(self.selection([entry]))
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(rationale, result.stdout)
        self.assertFalse(marker.exists())
        self.assertNotIn(str(self.root), result.stdout)

    def test_absolute_path_secret_like_and_oversized_declarative_text_refuse(self) -> None:
        self.assert_error("TEXT_INVALID", self.selection([self.entry(rationale="See /home/maintainer/private/report.json")]))
        self.assert_error("TEXT_INVALID", self.selection([self.entry(limits="Bearer abcdefghijklmnopqrstuvwxyz0123456789")]))
        self.assert_error("TEXT_INVALID", self.selection([self.entry(limits="é" * 257)]))


if __name__ == "__main__":
    unittest.main()
