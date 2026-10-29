#!/usr/bin/env python3
"""Check structural consistency of security-finding labels in a compliance report."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


BEGIN = "<!-- security-finding-evidence:begin -->"
END = "<!-- security-finding-evidence:end -->"
MAX_REPORT_BYTES = 1_000_000
ROOT_KEYS = {"schema", "findings"}
FINDING_KEYS = {
    "id",
    "evidence_label",
    "reproduction_state",
    "assessment_scope",
    "scope",
    "mechanism",
    "evidence_refs",
    "origin",
    "witness",
    "custody_ref",
}
EVIDENCE_LABELS = {"supported", "hypothesis", "legacy_review"}
REPRODUCTION_STATES = {
    "not_attempted",
    "blocked",
    "inconclusive",
    "disproved",
    "reproduced",
}
ASSESSMENT_SCOPES = {"static", "qualified_runtime"}
ORIGINS = {"author_reported", "artifact_cited", "independent_witness"}
EMPTY_REFERENCES = {"n/a", "na", "none", "unknown", "tbd", "todo", "pending"}
SUMMARY_SCHEMA = "DatarimSecurityFindingLabelsValidationSummary/v1"


class ValidationError(ValueError):
    """A report has malformed or inconsistent label data."""


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError("duplicate JSON key")
        result[key] = value
    return result


def _nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _concrete_reference(value: Any) -> bool:
    return _nonempty_text(value) and value.strip().casefold() not in EMPTY_REFERENCES


def _valid_refs(value: Any) -> bool:
    return isinstance(value, list) and all(_concrete_reference(item) for item in value)


def _validate_finding(finding: Any, index: int) -> list[str]:
    prefix = f"finding[{index}]"
    errors: list[str] = []
    if not isinstance(finding, dict):
        return [f"{prefix}: expected an object"]

    unknown = set(finding) - FINDING_KEYS
    missing = FINDING_KEYS - set(finding)
    if unknown:
        errors.append(f"{prefix}: unsupported field")
    if missing:
        errors.append(f"{prefix}: required fields missing")

    evidence = finding.get("evidence_label")
    reproduction = finding.get("reproduction_state")
    assessment = finding.get("assessment_scope")
    origin = finding.get("origin")
    refs = finding.get("evidence_refs")
    if not _nonempty_text(finding.get("id")):
        errors.append(f"{prefix}: id must be non-empty text")
    if not isinstance(evidence, str) or evidence not in EVIDENCE_LABELS:
        errors.append(f"{prefix}: invalid evidence_label")
    if not isinstance(reproduction, str) or reproduction not in REPRODUCTION_STATES:
        errors.append(f"{prefix}: invalid reproduction_state")
    if not isinstance(assessment, str) or assessment not in ASSESSMENT_SCOPES:
        errors.append(f"{prefix}: invalid assessment_scope")
    if not isinstance(origin, str) or origin not in ORIGINS:
        errors.append(f"{prefix}: invalid origin")
    if not _nonempty_text(finding.get("scope")):
        errors.append(f"{prefix}: scope must be non-empty text")
    if not _nonempty_text(finding.get("mechanism")):
        errors.append(f"{prefix}: mechanism must be non-empty text")
    if not _valid_refs(refs):
        errors.append(f"{prefix}: evidence_refs must be an array of non-empty strings")

    if evidence == "supported" and isinstance(refs, list) and not refs:
        errors.append(f"{prefix}: supported findings require an evidence reference")
    if evidence == "legacy_review" and isinstance(refs, list) and not refs:
        errors.append(f"{prefix}: legacy_review requires its historical evidence reference")
    if evidence == "legacy_review" and assessment != "static":
        errors.append(f"{prefix}: legacy_review cannot claim qualified runtime assessment")

    witness = finding.get("witness")
    custody = finding.get("custody_ref")
    runtime_claim = assessment == "qualified_runtime" or (
        isinstance(reproduction, str) and reproduction in {"reproduced", "disproved"}
    )
    if runtime_claim:
        if assessment != "qualified_runtime":
            errors.append(f"{prefix}: reproduced or disproved claims require qualified_runtime assessment")
        if assessment == "qualified_runtime" and reproduction == "not_attempted":
            errors.append(f"{prefix}: qualified_runtime cannot be not_attempted")
        if origin != "independent_witness":
            errors.append(f"{prefix}: runtime assessment requires independent_witness origin")
        if not isinstance(witness, dict) or set(witness) != {"identity", "evidence_ref"}:
            errors.append(f"{prefix}: runtime assessment requires identified witness and evidence reference")
        elif not _concrete_reference(witness.get("identity")) or not _concrete_reference(witness.get("evidence_ref")):
            errors.append(f"{prefix}: witness identity and evidence reference must be non-empty")
        elif isinstance(refs, list) and witness["evidence_ref"] not in refs:
            errors.append(f"{prefix}: witness evidence reference must appear in evidence_refs")
        if not _concrete_reference(custody):
            errors.append(f"{prefix}: runtime assessment requires a custody reference")
        if isinstance(refs, list) and not refs:
            errors.append(f"{prefix}: runtime assessment requires evidence references")
        if evidence == "legacy_review":
            errors.append(f"{prefix}: legacy_review cannot be promoted to runtime evidence")
    elif origin == "independent_witness" or witness is not None or custody is not None:
        errors.append(f"{prefix}: witness and custody fields require a qualified runtime assessment")

    if origin == "author_reported" and isinstance(reproduction, str) and reproduction in {"reproduced", "disproved"}:
        errors.append(f"{prefix}: author-reported claims cannot be labelled reproduced or disproved")
    return errors


def validate_report(path: Path) -> list[str]:
    try:
        raw = path.read_bytes()
    except OSError:
        raise ValidationError("report could not be read") from None
    if len(raw) > MAX_REPORT_BYTES:
        raise ValidationError("report exceeds size limit")
    try:
        report = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise ValidationError("report is not UTF-8") from None

    pattern = re.compile(
        re.escape(BEGIN) + r"\s*```json\s*(.*?)\s*```\s*" + re.escape(END),
        re.DOTALL,
    )
    if report.count(BEGIN) != 1 or report.count(END) != 1:
        raise ValidationError("expected exactly one pair of block markers")
    blocks = pattern.findall(report)
    if len(blocks) != 1:
        raise ValidationError("expected exactly one marked JSON block")
    try:
        payload = json.loads(blocks[0], object_pairs_hook=_object_without_duplicate_keys)
    except (json.JSONDecodeError, ValidationError):
        raise ValidationError("label block contains invalid or duplicate-key JSON") from None
    if not isinstance(payload, dict):
        raise ValidationError("label block root must be an object")
    if set(payload) != ROOT_KEYS:
        raise ValidationError("label block has missing or unsupported root fields")
    if payload.get("schema") != "security-finding-evidence/v1":
        raise ValidationError("unsupported label schema")
    findings = payload.get("findings")
    if not isinstance(findings, list):
        raise ValidationError("findings must be an array")
    errors: list[str] = []
    for index, finding in enumerate(findings):
        errors.extend(_validate_finding(finding, index))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument(
        "--summary-json",
        action="store_true",
        help="emit a fixed, redacted validation summary as JSON",
    )
    args = parser.parse_args()
    try:
        errors = validate_report(args.report)
    except ValidationError as exc:
        if args.summary_json:
            _print_summary("INPUT_REFUSED", 2, ["REPORT_INPUT_REFUSED"], "NOT_MEASURED", None)
            return 2
        print(f"security finding labels: {exc}", file=sys.stderr)
        return 2
    if args.summary_json:
        if errors:
            _print_summary(
                "INVALID", 1, ["LABELS_INCONSISTENT"], "MEASURED", len(errors)
            )
            return 1
        _print_summary("VALID", 0, [], "MEASURED", 0)
        return 0
    if errors:
        for error in errors:
            print(f"security finding labels: {error}", file=sys.stderr)
        return 1
    print("security finding labels: structurally consistent")
    return 0


def _print_summary(
    result: str,
    exit_code: int,
    diagnostic_codes: list[str],
    count_status: str,
    error_count: int | None,
) -> None:
    print(
        json.dumps(
            {
                "schema": SUMMARY_SCHEMA,
                "result": result,
                "exit_code": exit_code,
                "diagnostic_codes": diagnostic_codes,
                "validation_error_count": error_count,
                "validation_error_count_status": count_status,
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
