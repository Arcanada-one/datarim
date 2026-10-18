#!/usr/bin/env python3
"""Validate one Markdown test-value card's required evidence fields."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

import yaml


FIELDS = ("protects", "fails_when", "why_new", "seam", "no_claim")
MAX_FIELD_BYTES = 160
PLACEHOLDER = re.compile(r"^(?:|<[^>]+>|tbd|todo|n/?a|none)$", re.IGNORECASE)
CAUSAL_TRIGGER = re.compile(
    r"\b(?:remov\w*|disabl\w*|omit\w*|inver\w*|bypass\w*|"
    r"corrupt\w*|mutat\w*|break\w*|missing|absent|wrong|invalid)\b",
    re.IGNORECASE,
)
FAILURE_RESULT = re.compile(r"\b(?:fail\w*|red|reject\w*|error|non-zero)\b", re.IGNORECASE)
TEST_EVIDENCE = re.compile(r"\b(?:test|assert\w*|fixture|case|command)\b", re.IGNORECASE)
NO_CAUSAL_FAILURE = re.compile(
    r"\b(?:no defect|no failure|nothing fails|unknown failure|not applicable)\b",
    re.IGNORECASE,
)
WHY_EXISTING_GAP = re.compile(
    r"\b(?:existing|current|coverage|covered|tests?|gates?)\b.*"
    r"\b(?:not|only|miss\w*|lack\w*|gap|elsewhere|another)\b|"
    r"\b(?:not|only|miss\w*|lack\w*|gap|elsewhere)\b.*"
    r"\b(?:existing|current|coverage|covered|tests?|gates?)\b",
    re.IGNORECASE,
)
TEST_ONLY_SEAM = re.compile(
    r"\b(?:test[- ]only|testing[- ]only|only for tests|no production caller)\b",
    re.IGNORECASE,
)
SEAM_JUSTIFICATION = re.compile(
    r"^[^;\n]+;\s*production caller:\s*[^;\n]+;\s*"
    r"needed because:?\s*[^;\n]+$",
    re.IGNORECASE,
)


def validate_text(text: str) -> list[str]:
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return ["card must begin with YAML frontmatter"]
    match = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", text, re.DOTALL)
    if match is None:
        return ["card has malformed YAML frontmatter"]
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        return [f"invalid YAML frontmatter: {error.__class__.__name__}"]
    if not isinstance(data, dict):
        return ["frontmatter must be a mapping"]

    errors: list[str] = []
    for field in FIELDS:
        value = data.get(field)
        if not isinstance(value, str):
            errors.append(f"{field} must be a string")
            continue
        if len(value.encode("utf-8")) > MAX_FIELD_BYTES:
            errors.append(f"{field} must be at most {MAX_FIELD_BYTES} UTF-8 bytes")
        if field == "seam" and value.strip().lower() == "none":
            continue
        if PLACEHOLDER.fullmatch(value.strip()):
            errors.append(f"{field} must contain a concrete value")

    fails_when = data.get("fails_when")
    if isinstance(fails_when, str) and not PLACEHOLDER.fullmatch(fails_when.strip()):
        if NO_CAUSAL_FAILURE.search(fails_when) or not (
            CAUSAL_TRIGGER.search(fails_when)
            and FAILURE_RESULT.search(fails_when)
            and TEST_EVIDENCE.search(fails_when)
        ):
            errors.append(
                "fails_when must name a causal trigger and the failing test, assertion, fixture, or command"
            )

    why_new = data.get("why_new")
    if isinstance(why_new, str) and not WHY_EXISTING_GAP.search(why_new):
        errors.append("why_new must identify a gap in existing coverage")

    seam = data.get("seam")
    if isinstance(seam, str) and seam.strip().lower() != "none":
        if TEST_ONLY_SEAM.search(seam) or not SEAM_JUSTIFICATION.fullmatch(seam.strip()):
            errors.append(
                "named seam must identify a production caller and why it is needed; test-only seams are forbidden"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card", required=True, type=Path, help="Markdown card to validate")
    args = parser.parse_args()
    try:
        text = args.card.read_text(encoding="utf-8")
    except OSError as error:
        print(f"cannot read card: {error.strerror or error.__class__.__name__}", file=sys.stderr)
        return 2
    errors = validate_text(text)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"test value card: PASS ({args.card})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
