#!/usr/bin/env python3
"""Validate the structure of the Layer 3 plan-completion table in a QA report.

This checker validates recorded states and their required context. It does not
verify that cited evidence is authentic and never changes or promotes a status.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


STATUSES = {"DONE", "PARTIAL", "NOT DONE", "CHANGED", "UNVERIFIABLE"}
REASONS = {"scope cut", "context exhaustion", "misunderstood", "blocked", "forgotten"}
HEADERS = (
    "Step / deliverable",
    "Status",
    "Discrepancy reason",
    "Evidence",
    "Planned approach",
    "Actual replacement",
    "Missing evidence / exact check",
)
EMPTY = {"", "-", "—", "none", "n/a", "not provided", "tbd"}


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _is_separator(line: str) -> bool:
    cells = _cells(line)
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def _present(value: str) -> bool:
    return value.strip().casefold() not in EMPTY


def validate_report(text: str) -> list[str]:
    lines = text.splitlines()
    start = next(
        (i for i, line in enumerate(lines) if line.startswith("### Layer 3: Plan Completeness")),
        None,
    )
    if start is None:
        return ["missing '### Layer 3: Plan Completeness' section"]

    end = next(
        (i for i in range(start + 1, len(lines)) if re.match(r"^#{1,3} ", lines[i])),
        len(lines),
    )
    section = lines[start + 1 : end]
    header_index = next(
        (i for i, line in enumerate(section) if line.lstrip().startswith("|")),
        None,
    )
    if header_index is None:
        return ["missing Layer 3 status table"]
    if tuple(_cells(section[header_index])) != HEADERS:
        return ["Layer 3 table headers do not match the required record fields"]
    if header_index + 1 >= len(section) or not _is_separator(section[header_index + 1]):
        return ["Layer 3 status table is missing its Markdown separator row"]

    errors: list[str] = []
    row_count = 0
    for line_number, line in enumerate(section[header_index + 2 :], start=header_index + 3):
        if not line.strip().startswith("|"):
            continue
        cells = _cells(line)
        if len(cells) != len(HEADERS):
            errors.append(f"Layer 3 table row {line_number}: expected 7 fields, got {len(cells)}")
            continue
        row_count += 1
        step, status, reason, evidence, planned, replacement, gap = cells
        label = f"Layer 3 row {row_count} ({step or 'unnamed'})"
        if not _present(step):
            errors.append(f"{label}: deliverable name is required")
        if status not in STATUSES:
            errors.append(f"{label}: unsupported status {status!r}")
            continue
        if not _present(evidence):
            errors.append(f"{label}: evidence is required for every status")

        if status == "DONE":
            if _present(reason):
                errors.append(f"{label}: DONE must use '-' for discrepancy reason")
            if _present(gap):
                errors.append(f"{label}: DONE must use '-' for missing evidence / exact check")
        else:
            if reason not in REASONS:
                errors.append(f"{label}: a supported discrepancy reason is required")
            if status == "CHANGED" and (not _present(planned) or not _present(replacement)):
                errors.append(f"{label}: CHANGED requires both planned approach and actual replacement")
            if status == "UNVERIFIABLE" and not _present(gap):
                errors.append(f"{label}: UNVERIFIABLE requires the exact missing evidence or manual check")
            if status != "UNVERIFIABLE" and _present(gap):
                errors.append(f"{label}: missing evidence / exact check is only valid for UNVERIFIABLE")

    if row_count == 0:
        errors.append("Layer 3 status table must contain at least one deliverable row")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path, help="existing /dr-qa report to validate")
    args = parser.parse_args()
    try:
        report = args.report.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        print(f"plan-completion: cannot read report: {exc}", file=sys.stderr)
        return 2

    errors = validate_report(report)
    if errors:
        for error in errors:
            print(f"plan-completion: {error}", file=sys.stderr)
        return 1
    print("plan-completion structure valid; statuses unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
