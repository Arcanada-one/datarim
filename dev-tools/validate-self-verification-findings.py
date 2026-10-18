#!/usr/bin/env python3
"""Validate and normalize findings consumed by the /dr-verify audit writer.

Input is a JSON array or an object with a ``findings`` array. Legacy records
without resolution metadata remain valid. New records carry both resolution
and round. This utility is deterministic and has no external dependencies.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


SEVERITIES = {"high", "medium", "low"}
CATEGORIES = {"correctness", "completeness", "consistency", "safety"}
DRIFT_SUBTYPES = {
    "scope_creep",
    "spec_decay",
    "execution_skew",
    "orphaned_requirements",
}
EVIDENCE_TYPES = {"file_quote", "test_output", "verified_absence", "absent"}
RESOLUTIONS = {"actionable", "advisory", "unresolved"}
DISCARD_REASONS = {"no_evidence_provided", "parse_error", "malformed_evidence"}
TRUNCATION_SUFFIX = "[truncated]"


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _validate_record(
    record: Any, index: int, current_round: int, max_iter: int, upgrade_legacy: bool
) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    if not isinstance(record, dict):
        return None, ["finding must be an object"]

    normalized = dict(record)
    for required in ("severity", "category", "evidence", "ac_criteria"):
        if required not in normalized:
            errors.append(f"missing required field: {required}")

    if "confidence" in normalized:
        errors.append("confidence is not a supported finding field")

    severity = normalized.get("severity")
    if not isinstance(severity, str) or severity not in SEVERITIES:
        errors.append("severity must be high, medium, or low")

    category = normalized.get("category")
    if not isinstance(category, str) or category not in CATEGORIES:
        errors.append("category must be correctness, completeness, consistency, or safety")
    has_subtype = "drift_subtype" in normalized
    if category != "consistency" and has_subtype:
        errors.append("drift_subtype must be absent unless category is consistency")
    if has_subtype and (
        not isinstance(normalized.get("drift_subtype"), str)
        or normalized["drift_subtype"] not in DRIFT_SUBTYPES
    ):
        errors.append("drift_subtype is not a supported consistency subtype")

    ac_criteria = normalized.get("ac_criteria")
    if not isinstance(ac_criteria, list):
        errors.append("ac_criteria must be an array")

    if "suggested_fix" in normalized:
        suggested_fix = normalized["suggested_fix"]
        if not isinstance(suggested_fix, str) or len(suggested_fix) > 500:
            errors.append("suggested_fix must be a string of at most 500 characters")

    evidence = normalized.get("evidence")
    if not isinstance(evidence, dict):
        errors.append("evidence must be an object")
        evidence = {}
    else:
        evidence = dict(evidence)
        normalized["evidence"] = evidence

    evidence_type = evidence.get("type")
    if not isinstance(evidence_type, str) or evidence_type not in EVIDENCE_TYPES:
        errors.append("evidence.type must be file_quote, test_output, verified_absence, or absent")
    elif evidence_type == "absent":
        if "source" in evidence or "excerpt" in evidence:
            errors.append("absent evidence must omit source and excerpt")
        # Preserve the established audit-writer behavior: absent evidence is
        # discarded before verdict calculation, regardless of any downgrade.
        normalized["discarded"] = True
        normalized["discard_reason"] = "no_evidence_provided"
    else:
        if not _nonempty_string(evidence.get("source")):
            errors.append("evidence.source is required for evidence-backed findings")
        excerpt = evidence.get("excerpt")
        if not _nonempty_string(excerpt):
            errors.append("evidence.excerpt is required for evidence-backed findings")
        elif len(excerpt) > 200:
            evidence["excerpt"] = excerpt[: 200 - len(TRUNCATION_SUFFIX)] + TRUNCATION_SUFFIX
        if evidence_type == "verified_absence" and normalized.get("discarded") is True:
            errors.append("verified_absence is evidence and must not be discarded")
        if evidence_type == "verified_absence":
            normalized["discarded"] = False
            normalized.pop("discard_reason", None)

    if "discarded" in normalized and not isinstance(normalized["discarded"], bool):
        errors.append("discarded must be boolean")
    if "discard_reason" in normalized and (
        not isinstance(normalized["discard_reason"], str)
        or normalized["discard_reason"] not in DISCARD_REASONS
    ):
        errors.append("discard_reason is not a supported value")

    has_resolution = "resolution" in normalized
    has_round = "round" in normalized
    if has_resolution != has_round:
        errors.append("resolution and round must be supplied together")
    elif not has_resolution and upgrade_legacy:
        # Live /dr-verify runs may still receive findings from legacy emitters.
        # Preserve them as open records; absence of the new fields is not proof
        # that a finding was resolved.
        normalized["resolution"] = "unresolved"
        normalized["round"] = current_round
    elif has_resolution:
        resolution = normalized.get("resolution")
        round_number = normalized.get("round")
        if not isinstance(resolution, str) or resolution not in RESOLUTIONS:
            errors.append("resolution must be actionable, advisory, or unresolved")
        if isinstance(round_number, bool) or not isinstance(round_number, int):
            errors.append("round must be an integer")
        elif round_number < 1 or round_number > max_iter:
            errors.append("round must be between 1 and max_iter")
        elif round_number != current_round:
            errors.append("round must match the current verification iteration")
        # At the cap unresolved remains unresolved. The validator never infers
        # or writes a fixed state; "fixed" is outside the resolution enum.
        if current_round == max_iter and resolution == "fixed":
            errors.append("iteration cap cannot convert an unresolved finding to fixed")

    return (normalized if not errors else None), errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--round", type=int, required=True, dest="current_round")
    parser.add_argument("--max-iter", type=int, required=True)
    parser.add_argument(
        "--upgrade-legacy",
        action="store_true",
        help="promote legacy records in a live run to unresolved at the current round",
    )
    args = parser.parse_args()
    if args.max_iter < 1 or args.current_round < 1 or args.current_round > args.max_iter:
        parser.error("require 1 <= --round <= --max-iter")

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(json.dumps({"ok": False, "findings": [], "malformed": [{"index": 0, "errors": [f"invalid JSON: {exc.msg}"]}]}))
        return 1

    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict) and isinstance(payload.get("findings"), list):
        records = payload["findings"]
    else:
        print(json.dumps({"ok": False, "findings": [], "malformed": [{"index": 0, "errors": ["input must be an array or an object with a findings array"]}]}))
        return 1

    valid: list[dict[str, Any]] = []
    malformed: list[dict[str, Any]] = []
    for index, record in enumerate(records):
        normalized, errors = _validate_record(
            record, index, args.current_round, args.max_iter, args.upgrade_legacy
        )
        if errors:
            malformed.append({"index": index, "errors": errors, "finding": record})
        else:
            assert normalized is not None
            valid.append(normalized)

    print(json.dumps({"ok": not malformed, "findings": valid, "malformed": malformed}, indent=2, ensure_ascii=False))
    return 1 if malformed else 0


if __name__ == "__main__":
    raise SystemExit(main())
