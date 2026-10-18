#!/usr/bin/env python3
"""Read-only validator for a QA charter and its immutable run evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


CHARTER_SCHEMA = "DatarimQaCharter/v1"
EVIDENCE_SCHEMA = "DatarimQaCharterEvidence/v1"
OUTCOMES = {"pass", "fail", "blocked", "not run", "inconclusive", "n.a."}
SURFACES = {"browser", "api", "cli", "worker", "webhook"}
RUN_NAME = re.compile(r"^run-(\d{8}T\d{6}Z)$")
REVISION = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class CoverageError(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code


class DuplicateKeyError(ValueError):
    pass


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(key)
        result[key] = value
    return result


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fail(code: str, detail: str) -> None:
    raise CoverageError(code, detail)


def is_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip()) and not re.fullmatch(
        r"\s*(?:<[^>]+>|TODO|TBD|REPLACE_ME)\s*", value, re.IGNORECASE
    )


def load_json(path: Path, code: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except DuplicateKeyError as exc:
        fail("duplicate_key", f"duplicate JSON object key: {exc}")
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(code, f"cannot read valid UTF-8 JSON: {exc}")


def within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def no_symlink_components(path: Path, root: Path) -> bool:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return False
    current = root
    if current.is_symlink():
        return False
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return False
    return True


def input_file(value: str, root: Path, label: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    if not candidate.exists() or not candidate.is_file():
        fail("missing_" + label, f"{label} is missing or not a file")
    resolved = candidate.resolve(strict=True)
    if not within(resolved, root) or not no_symlink_components(candidate.absolute(), root):
        code = "mutable_baseline_path" if label == "evidence" else "unsafe_" + label
        fail(code, f"{label} must be a non-symlink file inside --root")
    return resolved


def parse_charter(path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail("invalid_charter", f"cannot read charter: {exc}")
    blocks = re.findall(r"(?ms)^```qa-charter-json\s*\n(.*?)^```\s*$", text)
    if len(blocks) != 1:
        fail("invalid_charter", "charter must contain exactly one qa-charter-json block")
    try:
        charter = json.loads(blocks[0], object_pairs_hook=unique_object)
    except DuplicateKeyError as exc:
        fail("duplicate_key", f"duplicate JSON object key: {exc}")
    except json.JSONDecodeError as exc:
        fail("invalid_charter", f"charter JSON is invalid: {exc}")
    if not isinstance(charter, dict) or charter.get("schema") != CHARTER_SCHEMA:
        fail("invalid_charter", f"schema must be {CHARTER_SCHEMA}")
    if not is_text(charter.get("owner")):
        fail("invalid_charter", "charter owner is required")
    behaviours = charter.get("behaviours")
    if not isinstance(behaviours, list) or not behaviours:
        fail("invalid_charter", "behaviours must be a non-empty array")
    probes: dict[str, dict[str, Any]] = {}
    behaviour_ids: set[str] = set()
    behaviour_fields = (
        "contract", "risk", "entrypoint", "isolation", "exit_condition",
        "source", "commands", "inputs", "surfaces", "probes",
    )
    for behaviour in behaviours:
        if not isinstance(behaviour, dict) or not is_text(behaviour.get("id")):
            fail("invalid_charter", "each behaviour needs a non-empty id")
        behaviour_id = behaviour["id"]
        if behaviour_id in behaviour_ids:
            fail("invalid_charter", "behaviour ids must be unique")
        behaviour_ids.add(behaviour_id)
        for field in behaviour_fields:
            value = behaviour.get(field)
            if field in {"commands", "inputs", "surfaces", "probes"}:
                if not isinstance(value, list) or not value:
                    fail("invalid_charter", f"behaviour {behaviour_id}: {field} must be non-empty")
            elif not is_text(value):
                fail("invalid_charter", f"behaviour {behaviour_id}: {field} is required")
        surfaces = behaviour["surfaces"]
        if any(not isinstance(surface, str) or surface not in SURFACES for surface in surfaces):
            fail("invalid_charter", f"behaviour {behaviour_id}: unknown surface")
        if any(not is_text(item) for item in behaviour["commands"] + behaviour["inputs"]):
            fail("invalid_charter", f"behaviour {behaviour_id}: commands and inputs must be concrete")
        for probe in behaviour["probes"]:
            if not isinstance(probe, dict):
                fail("invalid_charter", f"behaviour {behaviour_id}: probe must be an object")
            probe_id = probe.get("id")
            surface = probe.get("surface")
            if not is_text(probe_id) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", probe_id):
                fail("invalid_charter", f"behaviour {behaviour_id}: probe id is invalid")
            if probe_id in probes:
                fail("invalid_charter", f"probe id is duplicated: {probe_id}")
            if surface not in surfaces:
                fail("invalid_charter", f"probe {probe_id}: surface must be listed by its behaviour")
            if not isinstance(probe.get("required"), bool) or not is_text(probe.get("description")):
                fail("invalid_charter", f"probe {probe_id}: required and description are required")
            probes[probe_id] = probe
    return charter, probes


def run_revision(root: Path) -> str:
    try:
        clean = subprocess.run(
            ["git", "-C", str(root), "diff", "--quiet", "HEAD", "--"],
            check=False, capture_output=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail("source_tree_unavailable", f"cannot check tracked source-tree drift: {exc}")
    if clean.returncode != 0:
        fail("dirty_source_tree", "tracked source tree differs from current HEAD")
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
            check=False, capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail("source_revision_unavailable", f"cannot read current git revision: {exc}")
    revision = result.stdout.strip()
    if result.returncode != 0 or not REVISION.fullmatch(revision):
        fail("source_revision_unavailable", "--root has no verifiable current HEAD")
    return revision


def evidence_run_directory(evidence_path: Path, root: Path, evidence: dict[str, Any]) -> Path:
    try:
        relative = evidence_path.relative_to(root)
    except ValueError:
        fail("mutable_baseline_path", "evidence must be inside --root")
    if len(relative.parts) < 4 or relative.parts[:2] != ("datarim", "qa"):
        fail("mutable_baseline_path", "evidence must be under datarim/qa/<task>/run-<UTC>/")
    run_dir = evidence_path.parent
    match = RUN_NAME.fullmatch(run_dir.name)
    if not match or evidence_path.name != "evidence.json":
        fail("mutable_baseline_path", "evidence must be evidence.json in a concrete run-<UTC> directory")
    if not no_symlink_components(run_dir, root) or evidence_path.is_symlink():
        fail("mutable_baseline_path", "mutable aliases and symlinked baseline paths are refused")
    if evidence.get("run_id") != run_dir.name:
        fail("mutable_baseline_path", "run_id must match its immutable run directory")
    try:
        timestamp = datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ")
        captured = datetime.strptime(evidence.get("captured_at", ""), "%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError):
        fail("invalid_evidence", "captured_at must be UTC and match run-<UTC>")
    if captured != timestamp:
        fail("mutable_baseline_path", "captured_at must exactly match the run directory timestamp")
    return run_dir


def verify_artifact(run_dir: Path, artifact: Any, root: Path, probe_id: str) -> None:
    if not isinstance(artifact, dict):
        fail("invalid_evidence", f"probe {probe_id}: artifact object is required")
    relative = artifact.get("path")
    expected_hash = artifact.get("sha256")
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        fail("unsafe_artifact", f"probe {probe_id}: artifact path must be relative to its run directory")
    if not SHA256.fullmatch(str(expected_hash or "")):
        fail("invalid_evidence", f"probe {probe_id}: artifact sha256 is invalid")
    artifact_path = run_dir / relative
    if ".." in Path(relative).parts or not artifact_path.exists() or not artifact_path.is_file():
        fail("missing_artifact", f"probe {probe_id}: artifact is missing or escapes the run directory")
    resolved = artifact_path.resolve(strict=True)
    if not within(resolved, run_dir) or not no_symlink_components(artifact_path.absolute(), root):
        fail("unsafe_artifact", f"probe {probe_id}: symlinked or escaping artifacts are refused")
    if digest(resolved.read_bytes()) != expected_hash:
        fail("artifact_digest_mismatch", f"probe {probe_id}: artifact bytes do not match sha256")


def validate(root: Path, charter_path: Path, evidence_path: Path) -> tuple[int, int, int, str]:
    charter, probes = parse_charter(charter_path)
    evidence = load_json(evidence_path, "invalid_evidence")
    if not isinstance(evidence, dict) or evidence.get("schema") != EVIDENCE_SCHEMA:
        fail("invalid_evidence", f"schema must be {EVIDENCE_SCHEMA}")
    if evidence.get("charter_sha256") != digest(charter_path.read_bytes()):
        fail("stale_charter", "evidence does not bind the exact charter bytes")
    revision = run_revision(root)
    if evidence.get("source_revision") != revision:
        fail("stale_source_revision", "evidence source_revision differs from current repository HEAD")
    run_dir = evidence_run_directory(evidence_path, root, evidence)
    if not isinstance(evidence.get("probes"), list):
        fail("invalid_evidence", "probes must be an array")

    seen: dict[str, dict[str, Any]] = {}
    for entry in evidence["probes"]:
        if not isinstance(entry, dict) or not is_text(entry.get("id")):
            fail("invalid_evidence", "each probe evidence entry needs an id")
        probe_id = entry["id"]
        if probe_id not in probes:
            fail("unknown_probe", f"evidence contains undeclared probe {probe_id}")
        if probe_id in seen:
            fail("duplicate_probe", f"probe evidence is duplicated: {probe_id}")
        outcome = entry.get("outcome")
        if outcome not in OUTCOMES:
            fail("invalid_outcome", f"probe {probe_id}: unsupported outcome")
        if not is_text(entry.get("observed")):
            fail("invalid_evidence", f"probe {probe_id}: observed result is required")
        if outcome in {"not run", "n.a."}:
            if not is_text(entry.get("reason")):
                fail("invalid_evidence", f"probe {probe_id}: reason is required for {outcome}")
        else:
            if not is_text(entry.get("command")):
                fail("invalid_evidence", f"probe {probe_id}: command is required")
            code = entry.get("exit_code")
            if type(code) is not int or not 0 <= code <= 255:
                fail("invalid_evidence", f"probe {probe_id}: exit_code must be an integer from 0 to 255")
            verify_artifact(run_dir, entry.get("artifact"), root, probe_id)
        if outcome == "n.a." and probes[probe_id]["required"]:
            fail("required_probe_not_pass", f"required probe {probe_id} cannot be n.a.")
        seen[probe_id] = entry

    required = [probe_id for probe_id, probe in probes.items() if probe["required"]]
    missing = [probe_id for probe_id in required if probe_id not in seen]
    if missing:
        fail("missing_required_probe", "required probe evidence missing: " + ",".join(missing))
    nonpass = [probe_id for probe_id in required if seen[probe_id]["outcome"] != "pass"]
    if nonpass:
        fail("required_probe_not_pass", "required probe outcome is not pass: " + ",".join(nonpass))
    return len(required), len(seen), len(probes) - len(seen), revision


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="task repository root")
    parser.add_argument("--charter", required=True, help="Markdown charter with one qa-charter-json block")
    parser.add_argument("--evidence", required=True, help="immutable run-<UTC>/evidence.json")
    args = parser.parse_args()
    try:
        root_candidate = Path(args.root).resolve(strict=True)
        root = Path(subprocess.check_output(
            ["git", "-C", str(root_candidate), "rev-parse", "--show-toplevel"],
            text=True, stderr=subprocess.DEVNULL, timeout=5,
        ).strip()).resolve(strict=True)
        if root != root_candidate or root_candidate.is_symlink():
            fail("invalid_root", "--root must be the non-symlink git repository root")
        charter = input_file(args.charter, root, "charter")
        evidence = input_file(args.evidence, root, "evidence")
        required, recorded, optional_missing, revision = validate(root, charter, evidence)
    except CoverageError as exc:
        print(f"CHARTER_COVERAGE FAIL reason={exc.code}: {exc}")
        return 1
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"CHARTER_COVERAGE FAIL reason=source_or_path_error: {exc}")
        return 1
    print(
        f"CHARTER_COVERAGE PASS required={required} recorded={recorded} "
        f"optional_unrecorded={optional_missing} source_revision={revision}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
