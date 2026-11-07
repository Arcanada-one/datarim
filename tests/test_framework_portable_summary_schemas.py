#!/usr/bin/env python3
"""Portable structural-consumer contract checks for Datarim summary schemas.

Discovered by the accepted ``test_framework_*.py`` unittest pattern. It uses
fresh synthetic producer operands only. Set
``PORTABLE_SUMMARY_EVIDENCE_DIR`` to a new direct child path named
``tests/.portable-summary-evidence-*`` to retain per-process receipts and
mode-0600 raw streams for a bounded evidence run. The test creates it privately
inside this clone. Without it, receipts live only in a private run directory
inside this clone and are removed by guarded cleanup.

No fixture paths, payloads, diagnostics, or raw producer output are printed.
"""

from __future__ import annotations

import copy
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

from jsonschema import Draft202012Validator


REPO = Path(__file__).resolve().parents[1]
TESTS_DIR = REPO / "tests"
PROSE_SCHEMA_PATH = REPO / "documentation/reference/schemas/prose-banlist-summary.v1.schema.json"
TEMPLATE_SCHEMA_PATH = REPO / "documentation/reference/schemas/template-path-summary.v1.schema.json"
PROSE_CHECKER = REPO / "dev-tools/check-banlist-on-prose.sh"
TEMPLATE_CHECKER = REPO / "dev-tools/check-template-path-convention.sh"
SOURCE_PATHS = [
    PROSE_SCHEMA_PATH,
    TEMPLATE_SCHEMA_PATH,
    REPO / "documentation/reference/prose-banlist-summary-schema.md",
    REPO / "documentation/reference/template-path-summary-schema.md",
    PROSE_CHECKER,
    TEMPLATE_CHECKER,
    REPO / "documentation/reference/prose-banlist-summary.md",
    REPO / "documentation/reference/template-path-summary.md",
    REPO / "tests/prose-banlist-summary.bats",
    REPO / "tests/template-path-summary.bats",
]
TEST_PATH = Path(__file__).resolve()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(paths: list[Path]) -> dict[str, str]:
    """Hash explicit sources/specimens; mark intentionally absent operands."""
    result = {}
    for path in paths:
        if not path.exists():
            result[str(path)] = "ABSENT"
            continue
        candidates = sorted(path.rglob("*")) if path.is_dir() else [path]
        for candidate in candidates:
            if candidate.is_file():
                result[str(candidate)] = digest(candidate)
    return result


def explicit_operands(argv: list[str]) -> list[Path]:
    result = []
    for index, arg in enumerate(argv[:-1]):
        if arg in ("--file", "--banlist", "--whitelist", "--root"):
            result.append(Path(argv[index + 1]))
    return result


def write_private(path: Path, data: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def create_private_run_root() -> tuple[Path, bool]:
    """Create one owned private root under this clone; never probe outside it."""
    configured = os.environ.get("PORTABLE_SUMMARY_EVIDENCE_DIR")
    if configured:
        requested_root = Path(configured)
        if not requested_root.is_absolute():
            raise AssertionError("retained evidence root must be an absolute path")
        root = Path(os.path.abspath(requested_root))
        if root.parent != TESTS_DIR or not root.name.startswith(".portable-summary-evidence-"):
            raise AssertionError("retained evidence root must be a new direct child of this clone tests directory")
        os.mkdir(root, 0o700)
        retained = True
    else:
        root = Path(tempfile.mkdtemp(prefix=".portable-summary-run-", dir=TESTS_DIR))
        retained = False
    os.chmod(root, 0o700)
    ensure_private_owned_dir(root, TESTS_DIR)
    return root, retained


def ensure_private_owned_dir(path: Path, parent: Path) -> None:
    if path.parent != parent:
        raise AssertionError("private directory escaped its authorized parent")
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise AssertionError("private directory is not an owned mode-0700 directory")


def cleanup_private_run_root(root: Path) -> None:
    if root.parent != TESTS_DIR or not root.name.startswith(".portable-summary-run-"):
        raise AssertionError("refusing cleanup outside the exact private run-root pattern")
    ensure_private_owned_dir(root, TESTS_DIR)
    shutil.rmtree(root)


def process_receipt(argv: list[str], cwd: Path, raw_dir: Path, scratch_dir: Path, label: str,
                    schema_path: Path, specimen_paths: list[Path], timeout_seconds: float = 30) -> tuple[int, dict]:
    ensure_private_owned_dir(raw_dir, raw_dir.parent)
    ensure_private_owned_dir(scratch_dir, scratch_dir.parent)
    watched = [*SOURCE_PATHS, schema_path, TEST_PATH, scratch_dir, *specimen_paths]
    before = inventory(watched)
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        env={"PATH": "/usr/bin:/bin", "TMPDIR": str(scratch_dir), "LANG": "C", "LC_ALL": "C"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        close_fds=True,
        start_new_session=True,
    )
    selector = selectors.DefaultSelector()
    streams = {proc.stdout: bytearray(), proc.stderr: bytearray()}
    for pipe in streams:
        selector.register(pipe, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout_seconds
    capture_limit = 65536
    timed_out = False
    oversized = False
    terminated = False
    try:
        while selector.get_map():
            if time.monotonic() >= deadline and not terminated:
                timed_out = True
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                terminated = True
            for key, _ in selector.select(timeout=0.2):
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                stored = sum(len(value) for value in streams.values())
                room = max(0, capture_limit - stored)
                streams[key.fileobj].extend(chunk[:room])
                if len(chunk) > room and not terminated:
                    oversized = True
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    terminated = True
    except BaseException:
        # This Popen owns a new session, so cleanup is limited to its process
        # group. Never enumerate or signal unrelated host processes.
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        raise
    finally:
        selector.close()
        for pipe in streams:
            if not pipe.closed:
                pipe.close()
    # EOF on both pipes is not proof that the child exited. Bound the final
    # wait too, and clean/reap this owned process group on that timeout path.
    try:
        proc.wait(timeout=max(0.0, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
    finished = dt.datetime.now(dt.timezone.utc).isoformat()
    stdout_bytes = bytes(streams[proc.stdout])
    stderr_bytes = bytes(streams[proc.stderr])
    # Preserve the primary process result and both raw streams before applying
    # any contract assertions or cleanup.
    stdout_path = raw_dir / (label + ".stdout.raw")
    stderr_path = raw_dir / (label + ".stderr.raw")
    write_private(stdout_path, stdout_bytes)
    write_private(stderr_path, stderr_bytes)
    after = inventory(watched)
    record = {
        "label": label,
        "pid": proc.pid,
        "utc_started": started,
        "utc_finished": finished,
        "argv": argv,
        "cwd": str(cwd),
        "exit_code": proc.returncode,
        "stdout_raw": stdout_path.name,
        "stdout_sha256": hashlib.sha256(stdout_bytes).hexdigest(),
        "stderr_raw": stderr_path.name,
        "stderr_sha256": hashlib.sha256(stderr_bytes).hexdigest(),
        "timed_out": timed_out,
        "capture_limit_exceeded": oversized,
        "inventory_before": before,
        "inventory_after": after,
        "inventory_equal": before == after,
    }
    receipt = raw_dir / (label + ".receipt.json")
    write_private(receipt, (json.dumps(record, sort_keys=True) + "\n").encode("utf-8"))
    if not proc.pid or not started or before != after or timed_out or oversized:
        raise AssertionError("producer process custody or source/specimen stability failed")
    try:
        summary = json.loads(stdout_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError("synthetic producer did not emit one JSON object") from exc
    return proc.returncode, summary


def schema_mutations(validator: Draft202012Validator, base: dict, family: str,
                     receipt_path: Path, record: dict) -> dict:
    vectors: list[tuple[str, dict, bool]] = []

    def changed(label: str, key: str, value, expected_valid: bool = False) -> None:
        specimen = copy.deepcopy(base)
        specimen[key] = value
        vectors.append((label, specimen, expected_valid))

    extra = copy.deepcopy(base)
    extra["extra"] = True
    vectors.append(("additional-property", extra, False))
    missing = copy.deepcopy(base)
    del missing["schema"]
    vectors.append(("required-field", missing, False))
    changed("schema-discriminator", "schema", "OtherSummary/v1")
    changed("unsupported-result", "result", "UNKNOWN")
    changed("exit-type", "exit_code", "0")
    changed("unsupported-exit", "exit_code", 2)
    changed("diagnostic-type", "diagnostic_codes", "none")
    changed("diagnostic-code", "diagnostic_codes", ["UNDECLARED"])
    changed("diagnostic-cardinality", "diagnostic_codes", ["A", "B"])

    if family == "prose":
        changed("negative-count", "offence_count", -1)
        changed("boolean-count", "offence_count", True)
        changed("count-status-correlation", "offence_count_status", "NOT_MEASURED")
        changed("result-exit-correlation", "exit_code", 1)
        changed("result-diagnostic-correlation", "diagnostic_codes", ["LANGUAGE_NOT_APPLICABLE"])
        changed("result-count-correlation", "offence_count", None)
        float_profile = {
            "schema": "DatarimProseBanlistSummary/v1",
            "result": "OFFENCES",
            "exit_code": 1.0,
            "diagnostic_codes": ["PROSE_BANLIST_MATCH"],
            "offence_count": 1.0,
            "offence_count_status": "MEASURED",
        }
        vectors.append(("integer-valued-number-semantics", float_profile, True))
    else:
        changed("boolean-status", "offences_present_status", "NOT_MEASURED")
        changed("boolean-versus-integer", "offences_present", 1)
        changed("result-exit-correlation", "exit_code", 1)
        changed("result-diagnostic-correlation", "diagnostic_codes", ["TEMPLATE_PATH_CONVENTION_INVALID"])
        changed("result-boolean-correlation", "offences_present", True)
        changed("wrong-status-type", "offences_present_status", True)
        float_profile = {
            "schema": "DatarimTemplatePathConventionSummary/v1",
            "result": "FAIL",
            "exit_code": 1.0,
            "diagnostic_codes": ["TEMPLATE_PATH_CONVENTION_INVALID"],
            "offences_present": True,
            "offences_present_status": "MEASURED",
        }
        vectors.append(("integer-valued-number-semantics", float_profile, True))

    rejected = 0
    outcomes = []
    family_result = {"total_vectors": len(vectors), "rejected_invalid_vectors": 0, "outcomes": outcomes}
    record["mutations"][family] = family_result
    for label, specimen, expected_valid in vectors:
        actual_valid = validator.is_valid(specimen)
        outcomes.append({"label": label, "valid": actual_valid})
        if not expected_valid and not actual_valid:
            rejected += 1
        family_result["rejected_invalid_vectors"] = rejected
        write_private_update(receipt_path, record)
        if actual_valid != expected_valid:
            raise AssertionError("constructed schema vector had an unexpected outcome: " + label)
    if rejected < 12:
        raise AssertionError("fewer than twelve invalid vectors were rejected")
    return family_result


def write_private_update(path: Path, record: dict) -> None:
    if not stat.S_ISREG(path.lstat().st_mode) or stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise AssertionError("mutation receipt is not a private regular file")
    path.write_text(json.dumps(record, sort_keys=True) + "\n", encoding="utf-8")


class FrameworkPortableSummarySchemaTests(unittest.TestCase):
    maxDiff = None

    def test_portable_schema_contracts_and_producer_profiles(self):
        run_root, retained = create_private_run_root()
        fixture_root = run_root / "fixtures"
        scratch_dir = run_root / "child-tmp"
        raw_dir = run_root / "receipts"
        os.mkdir(fixture_root, 0o700)
        os.mkdir(scratch_dir, 0o700)
        os.mkdir(raw_dir, 0o700)
        for private_dir in (fixture_root, scratch_dir, raw_dir):
            ensure_private_owned_dir(private_dir, run_root)
        mutation_receipt = raw_dir / "schema-mutation-receipt.json"
        mutation_record = {
            "state": "started",
            "draft_2020_12_metaschema": {"prose": "NOT_MEASURED", "template": "NOT_MEASURED"},
            "constructed_profiles": {"evidence_kind": "constructed vectors, not producer output", "outcomes": []},
            "schema_sha256": {"prose": digest(PROSE_SCHEMA_PATH), "template": digest(TEMPLATE_SCHEMA_PATH)},
            "test_sha256": digest(TEST_PATH),
            "mutations": {},
        }
        write_private(mutation_receipt, (json.dumps(mutation_record, sort_keys=True) + "\n").encode("utf-8"))
        try:
            prose_schema = json.loads(PROSE_SCHEMA_PATH.read_text(encoding="utf-8"))
            template_schema = json.loads(TEMPLATE_SCHEMA_PATH.read_text(encoding="utf-8"))
            Draft202012Validator.check_schema(prose_schema)
            mutation_record["draft_2020_12_metaschema"]["prose"] = "PASS"
            write_private_update(mutation_receipt, mutation_record)
            Draft202012Validator.check_schema(template_schema)
            mutation_record["draft_2020_12_metaschema"]["template"] = "PASS"
            write_private_update(mutation_receipt, mutation_record)
            prose = Draft202012Validator(prose_schema)
            template = Draft202012Validator(template_schema)

            constructed_prose = [
                {"schema": "DatarimProseBanlistSummary/v1", "result": "CLEAN", "exit_code": 0, "diagnostic_codes": [], "offence_count": 0, "offence_count_status": "MEASURED"},
                {"schema": "DatarimProseBanlistSummary/v1", "result": "OFFENCES", "exit_code": 1, "diagnostic_codes": ["PROSE_BANLIST_MATCH"], "offence_count": 2, "offence_count_status": "MEASURED"},
                {"schema": "DatarimProseBanlistSummary/v1", "result": "NOT_APPLICABLE", "exit_code": 0, "diagnostic_codes": ["LANGUAGE_NOT_APPLICABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"},
                {"schema": "DatarimProseBanlistSummary/v1", "result": "INPUT_UNAVAILABLE", "exit_code": 1, "diagnostic_codes": ["PROSE_BANLIST_UNAVAILABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"},
                {"schema": "DatarimProseBanlistSummary/v1", "result": "INPUT_UNAVAILABLE", "exit_code": 1, "diagnostic_codes": ["PROSE_WHITELIST_UNAVAILABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"},
            ]
            constructed_template = [
                {"schema": "DatarimTemplatePathConventionSummary/v1", "result": "PASS", "exit_code": 0, "diagnostic_codes": [], "offences_present": False, "offences_present_status": "MEASURED"},
                {"schema": "DatarimTemplatePathConventionSummary/v1", "result": "FAIL", "exit_code": 1, "diagnostic_codes": ["TEMPLATE_PATH_CONVENTION_INVALID"], "offences_present": True, "offences_present_status": "MEASURED"},
            ]
            for index, specimen in enumerate(constructed_prose):
                outcome = prose.is_valid(specimen)
                mutation_record["constructed_profiles"]["outcomes"].append({"family": "prose", "index": index, "valid": outcome})
                write_private_update(mutation_receipt, mutation_record)
                if not outcome:
                    raise AssertionError("a constructed prose profile failed schema validation")
            for index, specimen in enumerate(constructed_template):
                outcome = template.is_valid(specimen)
                mutation_record["constructed_profiles"]["outcomes"].append({"family": "template", "index": index, "valid": outcome})
                write_private_update(mutation_receipt, mutation_record)
                if not outcome:
                    raise AssertionError("a constructed template profile failed schema validation")

            prose_mutations = schema_mutations(prose, constructed_prose[0], "prose", mutation_receipt, mutation_record)
            template_mutations = schema_mutations(template, constructed_template[0], "template", mutation_receipt, mutation_record)
            if prose_mutations["rejected_invalid_vectors"] < 12 or template_mutations["rejected_invalid_vectors"] < 12:
                raise AssertionError("mutation coverage minimum was not met")
            mutation_record["state"] = "complete-before-producer-runs"
            write_private_update(mutation_receipt, mutation_record)
            self._check_producers(fixture_root, scratch_dir, raw_dir, prose, template)
        finally:
            if not retained:
                cleanup_private_run_root(run_root)

    def test_process_receipt_kills_owned_child_after_pipe_eof(self):
        run_root = Path(tempfile.mkdtemp(prefix=".portable-summary-run-", dir=TESTS_DIR))
        os.chmod(run_root, 0o700)
        ensure_private_owned_dir(run_root, TESTS_DIR)
        scratch_dir = run_root / "child-tmp"
        raw_dir = run_root / "receipts"
        os.mkdir(scratch_dir, 0o700)
        os.mkdir(raw_dir, 0o700)
        ensure_private_owned_dir(scratch_dir, run_root)
        ensure_private_owned_dir(raw_dir, run_root)
        try:
            # Child closes inherited stdout/stderr, then remains alive beyond
            # the short test-only deadline. No shell or external process is used.
            child = "import os,time; os.close(1); os.close(2); time.sleep(30)"
            with self.assertRaisesRegex(AssertionError, "process custody"):
                process_receipt(
                    [sys.executable, "-c", child], run_root, raw_dir, scratch_dir,
                    "closed-pipes-live-child", PROSE_SCHEMA_PATH, [], timeout_seconds=0.25,
                )
            receipt_path = raw_dir / "closed-pipes-live-child.receipt.json"
            self.assertTrue(receipt_path.exists(), "primary receipt must be saved before timeout assertion")
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            self.assertTrue(receipt["timed_out"])
            self.assertIsInstance(receipt["exit_code"], int)
            self.assertEqual(receipt["cwd"], str(run_root))
        finally:
            cleanup_private_run_root(run_root)

    def _check_producers(self, root: Path, scratch_dir: Path, raw_dir: Path,
                         prose: Draft202012Validator, template: Draft202012Validator) -> None:
        ensure_private_owned_dir(root, root.parent)
        ensure_private_owned_dir(scratch_dir, root.parent)
        ensure_private_owned_dir(raw_dir, root.parent)
        lists = root / "lists"
        os.mkdir(lists, 0o700)
        ban = lists / "ban.txt"
        white = lists / "white.txt"
        doc = root / "input.md"
        ban.write_text("blockedword\n", encoding="utf-8")
        white.write_text("allowedword\n", encoding="utf-8")
        doc.write_text("ordinary synthetic text\n", encoding="utf-8")

        prose_cases = [
            ("prose-clean", ["bash", str(PROSE_CHECKER), "--summary-json", "--file", str(doc), "--banlist", str(ban), "--whitelist", str(white), "--language", "ru"], 0, {"schema": "DatarimProseBanlistSummary/v1", "result": "CLEAN", "exit_code": 0, "diagnostic_codes": [], "offence_count": 0, "offence_count_status": "MEASURED"}),
            ("prose-offences", ["bash", str(PROSE_CHECKER), "--summary-json", "--file", str(doc), "--banlist", str(ban), "--whitelist", str(white), "--language", "ru"], 1, {"schema": "DatarimProseBanlistSummary/v1", "result": "OFFENCES", "exit_code": 1, "diagnostic_codes": ["PROSE_BANLIST_MATCH"], "offence_count": 1, "offence_count_status": "MEASURED"}),
            ("prose-not-applicable", ["bash", str(PROSE_CHECKER), "--summary-json", "--file", str(doc), "--language", "en"], 0, {"schema": "DatarimProseBanlistSummary/v1", "result": "NOT_APPLICABLE", "exit_code": 0, "diagnostic_codes": ["LANGUAGE_NOT_APPLICABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"}),
            ("prose-banlist-unavailable", ["bash", str(PROSE_CHECKER), "--summary-json", "--file", str(doc), "--banlist", str(root / "missing-ban"), "--whitelist", str(white), "--language", "ru"], 1, {"schema": "DatarimProseBanlistSummary/v1", "result": "INPUT_UNAVAILABLE", "exit_code": 1, "diagnostic_codes": ["PROSE_BANLIST_UNAVAILABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"}),
            ("prose-whitelist-unavailable", ["bash", str(PROSE_CHECKER), "--summary-json", "--file", str(doc), "--banlist", str(ban), "--whitelist", str(root / "missing-white"), "--language", "ru"], 1, {"schema": "DatarimProseBanlistSummary/v1", "result": "INPUT_UNAVAILABLE", "exit_code": 1, "diagnostic_codes": ["PROSE_WHITELIST_UNAVAILABLE"], "offence_count": None, "offence_count_status": "NOT_MEASURED"}),
        ]
        for label, argv, expected_exit, expected_summary in prose_cases:
            if label == "prose-offences":
                doc.write_text("blockedword\n", encoding="utf-8")
            specimen_paths = explicit_operands(argv)
            code, summary = process_receipt(argv, root, raw_dir, scratch_dir, label, PROSE_SCHEMA_PATH, specimen_paths)
            if code != expected_exit or summary != expected_summary or not prose.is_valid(summary):
                raise AssertionError("a fresh synthetic prose producer profile mismatched its exact source-derived summary")
            if label == "prose-offences":
                doc.write_text("ordinary synthetic text\n", encoding="utf-8")

        clean = root / "template-clean"
        bad = root / "template-offence"
        (clean / "commands").mkdir(parents=True)
        (bad / "commands").mkdir(parents=True)
        (clean / "commands/one.md").write_text("$HOME/.claude/templates/example.md\n", encoding="utf-8")
        (bad / "commands/one.md").write_text("templates/example.md\n", encoding="utf-8")
        template_cases = (
            ("template-pass", clean, 0, {"schema": "DatarimTemplatePathConventionSummary/v1", "result": "PASS", "exit_code": 0, "diagnostic_codes": [], "offences_present": False, "offences_present_status": "MEASURED"}),
            ("template-fail", bad, 1, {"schema": "DatarimTemplatePathConventionSummary/v1", "result": "FAIL", "exit_code": 1, "diagnostic_codes": ["TEMPLATE_PATH_CONVENTION_INVALID"], "offences_present": True, "offences_present_status": "MEASURED"}),
        )
        for label, fixture, expected_exit, expected_summary in template_cases:
            argv = ["bash", str(TEMPLATE_CHECKER), "--summary-json", "--root", str(fixture)]
            specimen_paths = explicit_operands(argv)
            code, summary = process_receipt(argv, root, raw_dir, scratch_dir, label, TEMPLATE_SCHEMA_PATH, specimen_paths)
            if code != expected_exit or summary != expected_summary or not template.is_valid(summary):
                raise AssertionError("a fresh synthetic template producer profile mismatched its exact source-derived summary")


if __name__ == "__main__":
    unittest.main(verbosity=2)
