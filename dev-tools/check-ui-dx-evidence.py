#!/usr/bin/env python3
"""Read-only structural validator for task-scoped UI and DX review evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SCHEMA = "DatarimUiDxEvidence/v1"
REVISION = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
RUN_NAME = re.compile(r"^run-\d{8}T\d{6}Z$")
EVIDENCE_TYPES = {"observed", "reported", "estimated"}
UI_STATES = ("loading", "empty", "error", "success", "partial")
JOURNEY_STAGES = ("install", "configure", "first-accepted-result", "recover")
DX_PASSES = (
    "getting-started", "api-cli-sdk", "errors", "documentation", "upgrade",
    "development-environment", "community", "measurement",
)
FORBIDDEN_INPUTS = {"adoption-statistic", "designer-binary"}
SUMMARY_SCHEMA = "UIDXEvidenceValidationSummary/v1"
SUMMARY_DIAGNOSTIC_CODES = frozenset({
    "dirty_source_tree", "duplicate_key", "evidence_digest_mismatch",
    "incomplete_journey", "incomplete_persona", "incomplete_review_passes",
    "incomplete_storyboard", "incomplete_ui_state", "incomplete_ui_state_matrix",
    "input_unavailable", "invalid_applicability", "invalid_attribution",
    "invalid_evidence_digest", "invalid_evidence_type", "invalid_feature_id",
    "invalid_input_kind", "invalid_journey_status", "invalid_json",
    "invalid_plan_specification", "invalid_review_mode", "invalid_review_pass_status",
    "invalid_schema", "invalid_shape", "invalid_source_revision",
    "invalid_ui_state_score", "invalid_ui_state_status", "missing_acceptance_signal",
    "missing_attribution_notice", "missing_design_gap", "missing_design_reference",
    "missing_evidence", "missing_evidence_artifact", "missing_feature_name",
    "missing_field", "missing_input_reference", "missing_journey_gap",
    "missing_not_applicable_reason", "missing_recovery_action", "missing_storyboard",
    "missing_ui_features", "missing_ui_state_reason", "no_applicable_ui_states",
    "prohibited_input", "source_revision_unavailable", "stale_source_revision",
    "ui_rubric_below_floor", "unattributed_retained_material",
    "unexpected_applicability_reason", "unexpected_ui_features", "unknown_field",
    "unreadable_evidence_artifact", "unsafe_attribution_notice", "unsafe_evidence_path",
    "unsafe_evidence_reference", "validation_error",
}) | frozenset(f"missing_ui_state_{state}" for state in UI_STATES) | frozenset(
    f"missing_journey_stage_{stage}" for stage in JOURNEY_STAGES
)


class EvidenceError(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code


class DuplicateKeyError(ValueError):
    pass


class ValidationProgress:
    """Values established before a validation refusal, for summary availability."""

    def __init__(self) -> None:
        self.source_revision: str | None = None
        self.evidence_sha256: str | None = None
        self.lowest_rubric_score: int | None = None
        self.notes_count: int | None = None


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(key)
        result[key] = value
    return result


def fail(code: str, detail: str) -> None:
    raise EvidenceError(code, detail)


def text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip()) and not re.fullmatch(
        r"\s*(?:<[^>]+>|TODO|TBD|REPLACE_ME)\s*", value, re.IGNORECASE
    )


def object_with(value: Any, required: set[str], optional: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail("invalid_shape", f"{label} must be an object")
    missing = required - value.keys()
    extra = value.keys() - required - optional
    if missing:
        fail("missing_field", f"{label} is missing {sorted(missing)[0]}")
    if extra:
        fail("unknown_field", f"{label} has unsupported field {sorted(extra)[0]}")
    return value


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except DuplicateKeyError as exc:
        fail("duplicate_key", f"duplicate JSON object key: {exc}")
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail("invalid_json", f"cannot read valid UTF-8 JSON: {exc}")


def inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def no_symlink_components(path: Path, root: Path) -> bool:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        return False
    current = root
    if current.is_symlink():
        return False
    for part in parts:
        current /= part
        if current.is_symlink():
            return False
    return True


def evidence_path(value: str, root: Path) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    absolute = candidate.absolute()
    relative = absolute.relative_to(root)
    if len(relative.parts) < 4 or relative.parts[:2] != ("datarim", "qa"):
        fail("unsafe_evidence_path", "evidence must be under datarim/qa/<task>/")
    if candidate.name != "ui-dx-evidence.json" or not candidate.is_file():
        fail("missing_evidence", "evidence must be a regular ui-dx-evidence.json file")
    if not no_symlink_components(absolute, root):
        fail("unsafe_evidence_path", "symlinked evidence paths are refused")
    resolved = candidate.resolve(strict=True)
    if not inside(resolved, root):
        fail("unsafe_evidence_path", "evidence resolves outside --root")
    return resolved


def current_revision(root: Path) -> str:
    try:
        dirty = subprocess.run(
            ["git", "-C", str(root), "diff", "--quiet", "HEAD", "--"],
            capture_output=True, timeout=5, check=False,
        )
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail("source_revision_unavailable", f"cannot inspect source revision: {exc}")
    revision = result.stdout.strip()
    if dirty.returncode != 0:
        fail("dirty_source_tree", "tracked source differs from HEAD")
    if result.returncode != 0 or not REVISION.fullmatch(revision):
        fail("source_revision_unavailable", "--root has no verifiable Git HEAD")
    return revision


def validate_evidence_ref(value: Any, label: str, root: Path, report_path: Path) -> None:
    item = object_with(value, {"type", "path", "sha256"}, set(), label)
    if item["type"] not in EVIDENCE_TYPES:
        fail("invalid_evidence_type", f"{label} type must be observed, reported, or estimated")
    relative = item["path"]
    if not text(relative) or Path(relative).is_absolute() or ".." in Path(relative).parts:
        fail("unsafe_evidence_reference", f"{label} path must be a safe repository-relative artifact")
    parts = Path(relative).parts
    if (
        len(parts) < 5
        or parts[:2] != ("datarim", "qa")
        or parts[2] != report_path.parent.name
        or not RUN_NAME.fullmatch(parts[3])
    ):
        fail("unsafe_evidence_reference", f"{label} must reference an artifact in this task's immutable QA run")
    if not SHA256.fullmatch(str(item["sha256"])):
        fail("invalid_evidence_digest", f"{label} sha256 must be 64 lowercase hexadecimal characters")
    artifact = root.joinpath(*parts)
    if not artifact.is_file() or not no_symlink_components(artifact.absolute(), root):
        fail("missing_evidence_artifact", f"{label} artifact is missing or uses a symlink")
    try:
        actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
    except OSError:
        fail("unreadable_evidence_artifact", f"{label} artifact cannot be read")
    if actual != item["sha256"]:
        fail("evidence_digest_mismatch", f"{label} artifact bytes do not match the supplied sha256")


def validate_applicability(value: Any, label: str) -> tuple[str, str | None]:
    item = object_with(value, {"status"}, {"reason"}, label)
    status = item["status"]
    reason = item.get("reason")
    if status not in {"applicable", "not_applicable"}:
        fail("invalid_applicability", f"{label} status must be applicable or not_applicable")
    if status == "not_applicable" and not text(reason):
        fail("missing_not_applicable_reason", f"{label} requires a reason")
    if status == "applicable" and "reason" in item:
        fail("unexpected_applicability_reason", f"{label} reason is only valid for not_applicable")
    return status, reason


def validate_ui(ui_value: Any, root: Path, report_path: Path) -> tuple[str, int | None, list[str]]:
    ui = object_with(ui_value, {"applicability", "features"}, set(), "ui")
    status, _ = validate_applicability(ui["applicability"], "ui.applicability")
    features = ui["features"]
    if not isinstance(features, list):
        fail("invalid_shape", "ui.features must be an array")
    if status == "not_applicable":
        if features:
            fail("unexpected_ui_features", "not-applicable UI must have no feature rows")
        return status, None, []
    if not features:
        fail("missing_ui_features", "applicable UI needs at least one feature")

    feature_ids: set[str] = set()
    ratings: list[int] = []
    notes: list[str] = []
    for index, raw_feature in enumerate(features):
        feature = object_with(raw_feature, {"id", "name", "states", "storyboard"}, set(), f"ui.features[{index}]")
        feature_id = feature["id"]
        if not text(feature_id) or feature_id in feature_ids:
            fail("invalid_feature_id", "feature ids must be non-empty and unique")
        feature_ids.add(feature_id)
        if not text(feature["name"]):
            fail("missing_feature_name", f"feature {feature_id} needs a name")
        states = feature["states"]
        if not isinstance(states, dict) or set(states) != set(UI_STATES):
            fail("incomplete_ui_state_matrix", f"feature {feature_id} must include exactly the five required states")
        applicable_states = 0
        for state_name in UI_STATES:
            state = states[state_name]
            label = f"feature {feature_id} state {state_name}"
            if not isinstance(state, dict):
                fail("invalid_shape", f"{label} must be an object")
            state_status = state.get("status")
            if state_status == "not_applicable":
                object_with(state, {"status", "reason"}, set(), label)
                if not text(state["reason"]):
                    fail("missing_not_applicable_reason", f"{label} requires a reason")
                continue
            applicable_states += 1
            if state_status == "missing":
                object_with(state, {"status", "reason", "evidence", "score"}, set(), label)
                if not text(state["reason"]):
                    fail("missing_ui_state_reason", f"{label} needs a gap description")
                validate_evidence_ref(state["evidence"], label, root, report_path)
                if state["score"] != 0:
                    fail("invalid_ui_state_score", f"missing {label} must score zero")
                fail(f"missing_ui_state_{state_name}", f"{label} is missing")
            if state_status != "present":
                fail("invalid_ui_state_status", f"{label} status must be present, missing, or not_applicable")
            object_with(state, {"status", "trigger", "feedback", "action", "evidence", "score"}, set(), label)
            for field in ("trigger", "feedback", "action"):
                if not text(state[field]):
                    fail("incomplete_ui_state", f"{label} needs {field}")
            validate_evidence_ref(state["evidence"], label, root, report_path)
            if state["score"] not in {1, 2}:
                fail("invalid_ui_state_score", f"present {label} must score one or two")
            if state["score"] != 2:
                fail("ui_rubric_below_floor", f"{label} is not yet specific and testable")
            ratings.append(state["score"])

        if applicable_states == 0:
            fail("no_applicable_ui_states", f"feature {feature_id} cannot be applicable with all five states excluded")

        storyboard = feature["storyboard"]
        if not isinstance(storyboard, list) or not storyboard:
            fail("missing_storyboard", f"feature {feature_id} needs at least one journey step")
        for step_index, raw_step in enumerate(storyboard):
            step = object_with(
                raw_step,
                {"step", "does", "feels", "plan_specifies", "evidence"},
                {"design_reference", "gap"},
                f"feature {feature_id} storyboard[{step_index}]",
            )
            for field in ("step", "does", "feels"):
                if not text(step[field]):
                    fail("incomplete_storyboard", f"feature {feature_id} storyboard needs {field}")
            if not isinstance(step["plan_specifies"], bool):
                fail("invalid_plan_specification", "plan_specifies must be true or false")
            if step["plan_specifies"] and not text(step.get("design_reference")):
                fail("missing_design_reference", "a specified storyboard step needs its design reference")
            if not step["plan_specifies"]:
                if not text(step.get("gap")):
                    fail("missing_design_gap", "an unspecified storyboard step needs a gap note")
                notes.append(f"plan-unspecified:{feature_id}:{step_index}")
            validate_evidence_ref(step["evidence"], f"feature {feature_id} storyboard[{step_index}]", root, report_path)
    lowest = min(ratings) if ratings else None
    return status, lowest, notes


def validate_dx(dx_value: Any, root: Path, report_path: Path) -> tuple[str, list[str]]:
    if not isinstance(dx_value, dict):
        fail("invalid_shape", "dx must be an object")
    status, _ = validate_applicability(dx_value.get("applicability"), "dx.applicability")
    if status == "not_applicable":
        object_with(dx_value, {"applicability"}, set(), "dx")
        return status, []
    dx = object_with(dx_value, {"applicability", "mode", "persona", "stages", "passes"}, set(), "dx")
    if dx["mode"] not in {"expansion", "polish", "triage"}:
        fail("invalid_review_mode", "dx.mode must be expansion, polish, or triage")
    persona = object_with(dx["persona"], {"role", "goal", "starting_point", "constraints"}, set(), "dx.persona")
    if any(not text(persona[field]) for field in ("role", "goal", "starting_point", "constraints")):
        fail("incomplete_persona", "dx.persona fields must contain concrete descriptions")

    stages = dx["stages"]
    if not isinstance(stages, list) or [item.get("stage") if isinstance(item, dict) else None for item in stages] != list(JOURNEY_STAGES):
        fail("incomplete_journey", "dx.stages must list install, configure, first-accepted-result, and recover in order")
    for stage in stages:
        label = f"journey stage {stage['stage']}"
        status_value = stage.get("status")
        if status_value == "missing":
            object_with(stage, {"stage", "status", "reason", "evidence"}, set(), label)
            if not text(stage["reason"]):
                fail("missing_journey_gap", f"{label} needs a gap description")
            validate_evidence_ref(stage["evidence"], label, root, report_path)
            fail(f"missing_journey_stage_{stage['stage']}", f"{label} has no supported path")
        if status_value != "present":
            fail("invalid_journey_status", f"{label} status must be present or missing")
        required = {"stage", "status", "does", "evidence"}
        optional = {"recovery_action", "acceptance_signal"}
        object_with(stage, required, optional, label)
        if not text(stage["does"]):
            fail("incomplete_journey", f"{label} needs an observable action or outcome")
        validate_evidence_ref(stage["evidence"], label, root, report_path)
        if stage["stage"] == "recover" and not text(stage.get("recovery_action")):
            fail("missing_recovery_action", "the recovery stage must name a concrete recovery action")
        if stage["stage"] == "first-accepted-result" and not text(stage.get("acceptance_signal")):
            fail("missing_acceptance_signal", "the first accepted result must name its acceptance signal")

    passes = dx["passes"]
    if not isinstance(passes, list) or [item.get("name") if isinstance(item, dict) else None for item in passes] != list(DX_PASSES):
        fail("incomplete_review_passes", "dx.passes must list all eight review passes in order")
    for item in passes:
        label = f"DX pass {item['name']}"
        if item.get("status") == "not_applicable":
            object_with(item, {"name", "status", "reason"}, set(), label)
            if not text(item["reason"]):
                fail("missing_not_applicable_reason", f"{label} needs a reason")
        elif item.get("status") == "reviewed":
            object_with(item, {"name", "status", "evidence"}, set(), label)
            validate_evidence_ref(item["evidence"], label, root, report_path)
        else:
            fail("invalid_review_pass_status", f"{label} status must be reviewed or not_applicable")
    return status, []


def validate_inputs(value: Any) -> None:
    if not isinstance(value, list):
        fail("invalid_shape", "inputs must be an array")
    for index, raw in enumerate(value):
        item = object_with(raw, {"kind", "reference"}, set(), f"inputs[{index}]")
        kind = item["kind"]
        if kind in FORBIDDEN_INPUTS:
            fail("prohibited_input", f"input kind {kind} is not permitted")
        if kind not in {"design-source", "observed-run", "reported-source", "estimate-basis"}:
            fail("invalid_input_kind", f"inputs[{index}] has unsupported kind")
        if not text(item["reference"]):
            fail("missing_input_reference", f"inputs[{index}] needs a reference")


def validate_retained_material(value: Any, root: Path) -> None:
    if not isinstance(value, list):
        fail("invalid_shape", "retained_material must be an array")
    for index, raw in enumerate(value):
        item = object_with(
            raw, {"section", "source", "license", "notice", "modified"}, set(),
            f"retained_material[{index}]",
        )
        for field in ("section", "source", "license", "notice"):
            if not text(item[field]):
                fail("unattributed_retained_material", f"retained material {index} lacks {field}")
        if not isinstance(item["modified"], bool):
            fail("invalid_attribution", f"retained material {index} modified must be boolean")
        notice = Path(item["notice"])
        if notice.is_absolute() or ".." in notice.parts:
            fail("unsafe_attribution_notice", f"retained material {index} notice must be repository-relative")
        notice_path = root.joinpath(*notice.parts)
        if not notice_path.is_file() or not no_symlink_components(notice_path.absolute(), root):
            fail("missing_attribution_notice", f"retained material {index} notice is missing or uses a symlink")


def validate(
    root: Path,
    evidence_value: str,
    progress: ValidationProgress | None = None,
) -> tuple[str, str, int | None, list[str], str]:
    evidence_path_value = evidence_path(evidence_value, root)
    evidence = load_json(evidence_path_value)
    top = object_with(
        evidence,
        {"schema", "source_revision", "ui", "dx", "inputs", "retained_material"},
        set(),
        "evidence",
    )
    if top["schema"] != SCHEMA:
        fail("invalid_schema", f"schema must be {SCHEMA}")
    if not isinstance(top["source_revision"], str) or not REVISION.fullmatch(top["source_revision"]):
        fail("invalid_source_revision", "source_revision must be a full Git object ID")
    current = current_revision(root)
    if progress is not None:
        progress.source_revision = current
    if top["source_revision"] != current:
        fail("stale_source_revision", "evidence source_revision differs from current HEAD")
    ui_status, lowest, ui_notes = validate_ui(top["ui"], root, evidence_path_value)
    if progress is not None:
        progress.lowest_rubric_score = lowest
    dx_status, dx_notes = validate_dx(top["dx"], root, evidence_path_value)
    validate_inputs(top["inputs"])
    validate_retained_material(top["retained_material"], root)
    notes = ui_notes + dx_notes
    report_sha = hashlib.sha256(evidence_path_value.read_bytes()).hexdigest()
    if progress is not None:
        progress.evidence_sha256 = report_sha
        progress.notes_count = len(notes)
    if ui_status == dx_status == "not_applicable":
        return "NOT_APPLICABLE", current, lowest, notes, report_sha
    return "PASS", current, lowest, notes, report_sha


def summary_value(value: Any, available: bool) -> dict[str, Any]:
    return {
        "availability": "MEASURED" if available else "NOT_MEASURED",
        "value": value if available else None,
    }


def emit_summary(
    result: str,
    exit_code: int,
    diagnostic_codes: list[str],
    revision: str | None = None,
    report_sha: str | None = None,
    lowest: int | None = None,
    notes_count: int | None = None,
) -> None:
    summary = {
        "schema": SUMMARY_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": diagnostic_codes,
        "source_revision": summary_value(revision, revision is not None),
        "evidence_sha256": summary_value(report_sha, report_sha is not None),
        "lowest_rubric_score": summary_value(lowest, lowest is not None),
        "notes_count": summary_value(notes_count, notes_count is not None),
    }
    encoded = json.dumps(
        summary, sort_keys=True, separators=(",", ":"), allow_nan=False,
    )
    sys.stdout.write(encoded + "\n")


def emit_refusal(code: str, progress: ValidationProgress) -> None:
    safe_code = code if code in SUMMARY_DIAGNOSTIC_CODES else "validation_error"
    emit_summary(
        "FAIL", 1, [safe_code], progress.source_revision,
        progress.evidence_sha256, progress.lowest_rubric_score,
        progress.notes_count,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--evidence", required=True)
    parser.add_argument(
        "--summary-json", action="store_true",
        help="emit one versioned JSON summary instead of the default text report",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    progress = ValidationProgress()
    try:
        root = args.root.resolve()
    except Exception:
        if args.summary_json:
            emit_refusal("input_unavailable", progress)
            return 1
        raise
    try:
        status, revision, lowest, notes, report_sha = validate(
            root, args.evidence, progress if args.summary_json else None,
        )
    except EvidenceError as exc:
        if args.summary_json:
            emit_refusal(exc.code, progress)
            return 1
        print(f"UI_DX_REVIEW FAIL code={exc.code}: {exc}", file=sys.stderr)
        return 1
    except (AttributeError, TypeError, ValueError) as exc:
        if args.summary_json:
            emit_refusal("invalid_shape", progress)
            return 1
        print(f"UI_DX_REVIEW FAIL code=invalid_shape: {exc}", file=sys.stderr)
        return 1
    except OSError:
        if args.summary_json:
            emit_refusal("input_unavailable", progress)
            return 1
        raise
    except Exception:
        if args.summary_json:
            emit_refusal("validation_error", progress)
            return 1
        raise
    if args.summary_json:
        emit_summary(
            status, 0, [], revision, report_sha, lowest, len(notes),
        )
        return 0
    score = "none" if lowest is None else str(lowest)
    print(f"UI_DX_REVIEW {status} source_revision={revision} evidence_sha256={report_sha} lowest_rubric_score={score}")
    for note in notes:
        print(f"NOTE {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
