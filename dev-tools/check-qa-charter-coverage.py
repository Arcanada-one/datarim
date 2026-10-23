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
        linkage = behaviour.get("checkpoint_chain")
        if "checkpoint_chain" in behaviour and (
            not isinstance(linkage, dict)
            or set(linkage) != {"required"}
            or not isinstance(linkage.get("required"), bool)
        ):
            fail("invalid_charter", f"behaviour {behaviour_id}: checkpoint_chain must contain boolean required")
        if isinstance(linkage, dict) and linkage["required"] and len(behaviour["probes"]) < 2:
            fail("invalid_charter", f"behaviour {behaviour_id}: a required checkpoint chain needs at least two probes")
    return charter, probes


def validate_checkpoint_chains(
    charter: dict[str, Any], probes: dict[str, dict[str, Any]], evidence: dict[str, Any],
    seen: dict[str, dict[str, Any]], run_dir: Path,
) -> int | None:
    """Validate explicitly requested chains; None means legacy linkage is unmeasured."""
    behaviours = {item["id"]: item for item in charter["behaviours"]}
    required = {key for key, value in behaviours.items()
                if isinstance(value.get("checkpoint_chain"), dict)
                and value["checkpoint_chain"].get("required") is True}
    if "checkpoint_chains" not in evidence:
        if required:
            fail("missing_checkpoint_chain", "charter requires checkpoint linkage but evidence has no checkpoint_chains")
        return None
    chains = evidence["checkpoint_chains"]
    if not isinstance(chains, list):
        fail("invalid_checkpoint_chain", "checkpoint_chains must be an array")

    by_behaviour: dict[str, dict[str, Any]] = {}
    checkpoint_ids: set[str] = set()
    for chain in chains:
        if not isinstance(chain, dict) or set(chain) != {"behaviour_id", "checkpoints"}:
            fail("invalid_checkpoint_chain", "each chain needs exactly behaviour_id and checkpoints")
        behaviour_id = chain.get("behaviour_id")
        if not is_text(behaviour_id) or behaviour_id not in behaviours or behaviour_id in by_behaviour:
            fail("invalid_checkpoint_chain", "chain behaviour is undeclared or duplicated")
        checkpoints = chain.get("checkpoints")
        if not isinstance(checkpoints, list) or len(checkpoints) < 2:
            fail("invalid_checkpoint_chain", f"behaviour {behaviour_id}: chain needs at least two checkpoints")
        declared_probe_ids = {item["id"] for item in behaviours[behaviour_id]["probes"]}
        probe_sequence: list[str] = []
        for index, point in enumerate(checkpoints):
            if not isinstance(point, dict) or set(point) != {
                "id", "prior_checkpoint_id", "probe_id", "observation_sha256",
                "artifact_sha256", "hypothesis", "next_probe_id",
            }:
                fail("invalid_checkpoint_chain", "checkpoint fields do not match the declared contract")
            checkpoint_id = point.get("id")
            probe_id = point.get("probe_id")
            if (not is_text(checkpoint_id) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", checkpoint_id)
                    or checkpoint_id in checkpoint_ids):
                fail("duplicate_checkpoint", "checkpoint ids must be valid and globally unique")
            checkpoint_ids.add(checkpoint_id)
            if not is_text(probe_id) or probe_id not in declared_probe_ids or probe_id not in seen:
                fail("dangling_checkpoint_probe", f"checkpoint {checkpoint_id} does not bind an evidenced probe in its behaviour")
            entry = seen[probe_id]
            if entry.get("outcome") != "pass":
                fail("checkpoint_probe_not_pass", f"checkpoint {checkpoint_id} refers to a non-passing probe")
            if not SHA256.fullmatch(str(point.get("observation_sha256") or "")) or point["observation_sha256"] != digest(entry["observed"].encode("utf-8")):
                fail("stale_checkpoint_observation", f"checkpoint {checkpoint_id} does not bind the exact prior observation")
            artifact = entry.get("artifact")
            if not isinstance(artifact, dict) or point.get("artifact_sha256") != artifact.get("sha256"):
                fail("stale_checkpoint_artifact", f"checkpoint {checkpoint_id} does not bind the prior artifact digest")
            # The ordinary probe pass has already checked the artifact's path and bytes.
            if not is_text(point.get("hypothesis")):
                fail("invalid_checkpoint_hypothesis", f"checkpoint {checkpoint_id} needs a concrete hypothesis")
            next_probe = point.get("next_probe_id")
            if index < len(checkpoints) - 1:
                next_point = checkpoints[index + 1]
                if not isinstance(next_point, dict) or next_probe != next_point.get("probe_id"):
                    fail("out_of_order_checkpoint", f"checkpoint {checkpoint_id} must point to the next listed checkpoint probe")
                if point.get("prior_checkpoint_id") != (None if index == 0 else checkpoints[index - 1].get("id")):
                    fail("invalid_checkpoint_relation", f"checkpoint {checkpoint_id} has a dangling, cyclic, or out-of-order predecessor")
            else:
                if next_probe is not None or point.get("prior_checkpoint_id") != checkpoints[index - 1].get("id"):
                    fail("invalid_checkpoint_relation", f"checkpoint {checkpoint_id} must terminate the ordered chain")
            probe_sequence.append(probe_id)
        if len(set(probe_sequence)) != len(probe_sequence):
            fail("checkpoint_cycle", f"behaviour {behaviour_id}: a probe may appear only once in the chain")
        by_behaviour[behaviour_id] = chain
    missing = required - set(by_behaviour)
    if missing:
        fail("missing_checkpoint_chain", "required checkpoint chain missing: " + ",".join(sorted(missing)))
    if not by_behaviour:
        return None
    return sum(len(chain["checkpoints"]) - 1 for chain in by_behaviour.values())


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


def validate(root: Path, charter_path: Path, evidence_path: Path) -> tuple[int, int, int, str, int | None]:
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
        if not isinstance(outcome, str) or outcome not in OUTCOMES:
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
    linked = validate_checkpoint_chains(charter, probes, evidence, seen, run_dir)
    return len(required), len(seen), len(probes) - len(seen), revision, linked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="task repository root")
    parser.add_argument("--charter", required=True, help="Markdown charter with one qa-charter-json block")
    parser.add_argument("--evidence", required=True, help="immutable run-<UTC>/evidence.json")
    args = parser.parse_args()
    try:
        root_argument = Path(args.root)
        if root_argument.is_symlink():
            fail("invalid_root", "--root must be the non-symlink git repository root")
        root_candidate = root_argument.resolve(strict=True)
        root = Path(subprocess.check_output(
            ["git", "-C", str(root_candidate), "rev-parse", "--show-toplevel"],
            text=True, stderr=subprocess.DEVNULL, timeout=5,
        ).strip()).resolve(strict=True)
        if root != root_candidate:
            fail("invalid_root", "--root must be the non-symlink git repository root")
        charter = input_file(args.charter, root, "charter")
        evidence = input_file(args.evidence, root, "evidence")
        required, recorded, optional_missing, revision, linked = validate(root, charter, evidence)
    except CoverageError as exc:
        print(f"CHARTER_COVERAGE FAIL reason={exc.code}: {exc}")
        return 1
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"CHARTER_COVERAGE FAIL reason=source_or_path_error: {exc}")
        return 1
    print(
        f"CHARTER_COVERAGE PASS required={required} recorded={recorded} "
        f"optional_unrecorded={optional_missing} source_revision={revision} "
        f"checkpoint_linkage={'PASS transitions=' + str(linked) if linked is not None else 'NOT_MEASURED'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
