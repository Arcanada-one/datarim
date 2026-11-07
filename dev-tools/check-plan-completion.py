#!/usr/bin/env python3
"""Validate the structure of the Layer 3 plan-completion table in a QA report.

This checker validates recorded states and their required context. It does not
verify that cited evidence is authentic and never changes or promotes a status.
"""

from __future__ import annotations

import argparse
import json
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
SUMMARY_SCHEMA = "DatarimPlanCompletionValidationSummary/v1"
SUMMARY_FALLBACK_CODE = "E_VALIDATION_FAILED"
SUMMARY_READ_FAILURE_CODE = "REPORT_UNREADABLE"
SUMMARY_DIAGNOSTIC_CODES = frozenset(
    {
        "E_SECTION_MISSING",
        "E_STATUS_TABLE_MISSING",
        "E_TABLE_HEADERS_INVALID",
        "E_TABLE_SEPARATOR_MISSING",
        "E_TABLE_ROW_SHAPE_INVALID",
        "E_DELIVERABLE_REQUIRED",
        "E_STATUS_UNSUPPORTED",
        "E_EVIDENCE_REQUIRED",
        "E_DONE_REASON_FORBIDDEN",
        "E_DONE_GAP_FORBIDDEN",
        "E_DISCREPANCY_REASON_UNSUPPORTED",
        "E_CHANGED_FIELDS_REQUIRED",
        "E_UNVERIFIABLE_GAP_REQUIRED",
        "E_GAP_ONLY_UNVERIFIABLE",
        "E_STATUS_TABLE_EMPTY",
        SUMMARY_FALLBACK_CODE,
        SUMMARY_READ_FAILURE_CODE,
    }
)


def _cells(line: str) -> list[str]:
    row = line.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        slash_count = len(row) - len(row.rstrip("\\"))
        if slash_count % 2 == 0:
            row = row[:-1]

    cells: list[str] = []
    current: list[str] = []
    index = 0
    while index < len(row):
        if row[index] == "\\":
            end = index
            while end < len(row) and row[end] == "\\":
                end += 1
            slash_count = end - index
            current.extend("\\" * (slash_count // 2))
            if end < len(row) and row[end] == "|":
                if slash_count % 2:
                    current.append("|")
                    index = end + 1
                    continue
                cells.append("".join(current).strip())
                current = []
                index = end + 1
                continue
            if slash_count % 2:
                current.append("\\")
            index = end
            continue
        if row[index] == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(row[index])
        index += 1
    cells.append("".join(current).strip())
    return cells


def _is_separator(line: str, expected_count: int) -> bool:
    cells = _cells(line)
    return len(cells) == expected_count and all(
        re.fullmatch(r":?-{3,}:?", cell) for cell in cells
    )


def _present(value: str) -> bool:
    return value.strip().casefold() not in EMPTY


def _record_error(
    errors: list[str], diagnostic_codes: list[str] | None, code: str, message: str
) -> None:
    errors.append(message)
    if diagnostic_codes is not None:
        diagnostic_codes.append(code)


def _single_error(message: str, diagnostic_codes: list[str] | None, code: str) -> list[str]:
    if diagnostic_codes is not None:
        diagnostic_codes.append(code)
    return [message]


def validate_report(
    text: str, *, diagnostic_codes: list[str] | None = None
) -> list[str]:
    """Return the existing human diagnostics, optionally collecting fixed codes."""
    lines = text.splitlines()
    start = next(
        (i for i, line in enumerate(lines) if line.startswith("### Layer 3: Plan Completeness")),
        None,
    )
    if start is None:
        return _single_error(
            "missing '### Layer 3: Plan Completeness' section",
            diagnostic_codes,
            "E_SECTION_MISSING",
        )

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
        return _single_error("missing Layer 3 status table", diagnostic_codes, "E_STATUS_TABLE_MISSING")
    if tuple(_cells(section[header_index])) != HEADERS:
        return _single_error(
            "Layer 3 table headers do not match the required record fields",
            diagnostic_codes,
            "E_TABLE_HEADERS_INVALID",
        )
    if header_index + 1 >= len(section) or not _is_separator(
        section[header_index + 1], len(HEADERS)
    ):
        return _single_error(
            "Layer 3 status table is missing its Markdown separator row",
            diagnostic_codes,
            "E_TABLE_SEPARATOR_MISSING",
        )

    errors: list[str] = []
    row_count = 0
    for line_number, line in enumerate(section[header_index + 2 :], start=header_index + 3):
        if not line.strip().startswith("|"):
            continue
        cells = _cells(line)
        if len(cells) != len(HEADERS):
            _record_error(
                errors,
                diagnostic_codes,
                "E_TABLE_ROW_SHAPE_INVALID",
                f"Layer 3 table row {line_number}: expected 7 fields, got {len(cells)}",
            )
            continue
        row_count += 1
        step, status, reason, evidence, planned, replacement, gap = cells
        label = f"Layer 3 row {row_count} ({step or 'unnamed'})"
        if not _present(step):
            _record_error(
                errors,
                diagnostic_codes,
                "E_DELIVERABLE_REQUIRED",
                f"{label}: deliverable name is required",
            )
        if status not in STATUSES:
            _record_error(
                errors,
                diagnostic_codes,
                "E_STATUS_UNSUPPORTED",
                f"{label}: unsupported status {status!r}",
            )
            continue
        if not _present(evidence):
            _record_error(
                errors,
                diagnostic_codes,
                "E_EVIDENCE_REQUIRED",
                f"{label}: evidence is required for every status",
            )

        if status == "DONE":
            if _present(reason):
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_DONE_REASON_FORBIDDEN",
                    f"{label}: DONE must use '-' for discrepancy reason",
                )
            if _present(gap):
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_DONE_GAP_FORBIDDEN",
                    f"{label}: DONE must use '-' for missing evidence / exact check",
                )
        else:
            if reason not in REASONS:
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_DISCREPANCY_REASON_UNSUPPORTED",
                    f"{label}: a supported discrepancy reason is required",
                )
            if status == "CHANGED" and (not _present(planned) or not _present(replacement)):
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_CHANGED_FIELDS_REQUIRED",
                    f"{label}: CHANGED requires both planned approach and actual replacement",
                )
            if status == "UNVERIFIABLE" and not _present(gap):
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_UNVERIFIABLE_GAP_REQUIRED",
                    f"{label}: UNVERIFIABLE requires the exact missing evidence or manual check",
                )
            if status != "UNVERIFIABLE" and _present(gap):
                _record_error(
                    errors,
                    diagnostic_codes,
                    "E_GAP_ONLY_UNVERIFIABLE",
                    f"{label}: missing evidence / exact check is only valid for UNVERIFIABLE",
                )

    if row_count == 0:
        _record_error(
            errors,
            diagnostic_codes,
            "E_STATUS_TABLE_EMPTY",
            "Layer 3 status table must contain at least one deliverable row",
        )
    return errors


def _safe_diagnostic_codes(codes: list[str], error_count: int) -> list[str]:
    safe_codes: list[str] = []
    for code in codes:
        safe_code = code if code in SUMMARY_DIAGNOSTIC_CODES else SUMMARY_FALLBACK_CODE
        if safe_code not in safe_codes:
            safe_codes.append(safe_code)
    if error_count and not safe_codes:
        safe_codes.append(SUMMARY_FALLBACK_CODE)
    return safe_codes


def _summary_payload(
    result: str, exit_code: int, codes: list[str], error_count: int | None
) -> dict[str, object]:
    if result == "UNREADABLE":
        diagnostic_codes = [SUMMARY_READ_FAILURE_CODE]
        count_status = "NOT_MEASURED"
        measured_count = None
    else:
        diagnostic_codes = _safe_diagnostic_codes(codes, error_count or 0)
        count_status = "MEASURED"
        measured_count = error_count
    return {
        "schema": SUMMARY_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": diagnostic_codes,
        "validation_error_count": measured_count,
        "validation_error_count_status": count_status,
    }


def _write_summary(payload: dict[str, object]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path, help="existing /dr-qa report to validate")
    parser.add_argument(
        "--summary-json",
        action="store_true",
        help=(
            "emit a redacted machine-readable validation summary "
            "(see documentation/reference/plan-completion-summary.md)"
        ),
    )
    args = parser.parse_args()
    try:
        report = args.report.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        if args.summary_json:
            _write_summary(_summary_payload("UNREADABLE", 2, [], None))
            return 2
        print(f"plan-completion: cannot read report: {exc}", file=sys.stderr)
        return 2

    diagnostic_codes: list[str] | None = [] if args.summary_json else None
    if diagnostic_codes is not None:
        errors = validate_report(report, diagnostic_codes=diagnostic_codes)
    else:
        errors = validate_report(report)
    if args.summary_json:
        result = "INVALID" if errors else "VALID"
        exit_code = 1 if errors else 0
        _write_summary(_summary_payload(result, exit_code, diagnostic_codes or [], len(errors)))
        return exit_code

    if errors:
        for error in errors:
            print(f"plan-completion: {error}", file=sys.stderr)
        return 1
    print("plan-completion structure valid; statuses unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
