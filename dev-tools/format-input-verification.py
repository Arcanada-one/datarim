#!/usr/bin/env python3
"""Render a saved input-verification result as bounded, deterministic text."""
from __future__ import annotations

import json
import sys
from decimal import Decimal, DecimalException
from typing import Any

INPUT_LIMIT = 2 * 1024 * 1024
OUTPUT_LIMIT = 64 * 1024
SCHEMA = "DatarimCliInputManifestVerification/v1"
REFUSAL = "INPUT_VERIFICATION_FORMAT_REFUSED"
INPUT_REFUSAL_CODE = "INPUT_MANIFEST_VERIFICATION_REFUSED"
CHANGED_CODE = "INPUT_MANIFEST_BYTES_CHANGED"
FIELDS = frozenset({
    "schema",
    "result",
    "exit_code",
    "diagnostic_codes",
    "file_count",
    "file_count_status",
    "changed_paths",
})


class InvalidReport(ValueError):
    """The saved report is malformed, inconsistent, or not renderable."""


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidReport
        result[key] = value
    return result


def reject_constant(_value: str) -> None:
    raise InvalidReport


def measured_count(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if type(value) is int:
        return 1 <= value <= 64
    if isinstance(value, Decimal):
        return value.is_finite() and value == value.to_integral_value() and 1 <= value <= 64
    return False


def canonical_relative_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        return False
    if value.startswith("/"):
        return False
    return not any(part in ("", ".", "..") for part in value.split("/"))


def validate(document: Any) -> tuple[str, int, int | None, list[str]]:
    if not isinstance(document, dict) or frozenset(document) != FIELDS:
        raise InvalidReport
    if document["schema"] != SCHEMA:
        raise InvalidReport

    result = document["result"]
    exit_code = document["exit_code"]
    codes = document["diagnostic_codes"]
    count = document["file_count"]
    status = document["file_count_status"]
    paths = document["changed_paths"]
    if type(exit_code) is not int or not isinstance(codes, list) or not isinstance(paths, list):
        raise InvalidReport

    if result == "MATCHED":
        if exit_code != 0 or codes != [] or status != "MEASURED" or not measured_count(count) or paths != []:
            raise InvalidReport
        return result, exit_code, int(count), []

    if result == "CHANGED":
        if (
            exit_code != 1
            or codes != [CHANGED_CODE]
            or status != "MEASURED"
            or not measured_count(count)
            or not 1 <= len(paths) <= int(count)
        ):
            raise InvalidReport
        if not all(canonical_relative_path(path) for path in paths):
            raise InvalidReport
        if paths != sorted(set(paths)):
            raise InvalidReport
        return result, exit_code, int(count), paths

    if result == "INPUT_REFUSED":
        if (
            exit_code != 2
            or codes != [INPUT_REFUSAL_CODE]
            or count is not None
            or status != "NOT_MEASURED"
            or paths != []
        ):
            raise InvalidReport
        return result, exit_code, None, []

    raise InvalidReport


def append_bounded(output: bytearray, line: str) -> None:
    encoded = (line + "\n").encode("ascii")
    if len(output) + len(encoded) > OUTPUT_LIMIT:
        raise InvalidReport
    output.extend(encoded)


def render(result: str, exit_code: int, count: int | None, paths: list[str]) -> bytes:
    output = bytearray()
    count_text = str(count) if count is not None else "NOT_MEASURED (unavailable)"
    append_bounded(output, "Input verification result: " + result)
    append_bounded(output, "Exit code: " + str(exit_code))
    append_bounded(output, "File count: " + count_text)
    append_bounded(output, "Changed paths:")
    if paths:
        for path in paths:
            # This is line-safe display syntax, not a model-trust boundary.
            append_bounded(output, "  " + json.dumps(path, ensure_ascii=True))
    else:
        append_bounded(output, "  (none)")
    return bytes(output)


def refuse() -> int:
    try:
        sys.stderr.write(REFUSAL + "\n")
    except OSError:
        pass
    return 2


def main() -> int:
    try:
        chunks: list[bytes] = []
        remaining = INPUT_LIMIT + 1
        while remaining:
            chunk = sys.stdin.buffer.read(remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        if len(raw) > INPUT_LIMIT:
            raise InvalidReport
        text = raw.decode("utf-8", errors="strict")
        document = json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_float=Decimal,
            parse_constant=reject_constant,
        )
        profile = validate(document)
        report = render(*profile)
    except (OSError, UnicodeError, json.JSONDecodeError, InvalidReport, ValueError, DecimalException, RecursionError):
        return refuse()

    try:
        written = sys.stdout.buffer.write(report)
        if written != len(report):
            return refuse()
    except OSError:
        return refuse()
    return profile[1]


if __name__ == "__main__":
    raise SystemExit(main())
