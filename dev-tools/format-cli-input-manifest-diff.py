#!/usr/bin/env python3
"""Render one saved CLI input-manifest diff as bounded, escaped text."""
from __future__ import annotations

from decimal import Decimal, DecimalException
import json
import sys
from typing import Any

INPUT_LIMIT = 2 * 1024 * 1024
OUTPUT_LIMIT = 128 * 1024
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
DIFF_SCHEMA = "DatarimCliInputManifestDiff/v1"
CHANGED_CODE = "INPUT_MANIFEST_CHANGED"
INPUT_REFUSED_CODE = "INPUT_MANIFEST_DIFF_REFUSED"
FORMAT_REFUSAL_CODE = "INPUT_MANIFEST_DIFF_FORMAT_REFUSED"
TOP_FIELDS = frozenset({
    "schema",
    "result",
    "exit_code",
    "diagnostic_codes",
    "added_count",
    "removed_count",
    "modified_count",
    "counts_status",
    "changes",
})
ROW_FIELDS = frozenset({
    "relative_path",
    "change",
    "before_sha256",
    "after_sha256",
    "before_byte_count",
    "after_byte_count",
})
HEX = frozenset("0123456789abcdef")


class InvalidDiff(Exception):
    """A saved diff is malformed, inconsistent, or cannot be rendered."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidDiff
        result[key] = value
    return result


def _reject_constant(_value: str) -> None:
    raise InvalidDiff


def _bounded_integer(value: Any, maximum: int) -> int:
    # JSON numeric tokens are parsed as Decimal. Check exactness and bounds before
    # converting, so booleans and huge numeric values never become Python ints.
    if not isinstance(value, Decimal):
        raise InvalidDiff
    try:
        if not value.is_finite() or value < 0 or value > maximum:
            raise InvalidDiff
        if value != value.to_integral_value():
            raise InvalidDiff
        return int(value)
    except DecimalException as exc:
        raise InvalidDiff from exc


def _path(value: Any) -> str:
    if not isinstance(value, str) or not value or value.startswith("/") or "\x00" in value:
        raise InvalidDiff
    try:
        value.encode("utf-8", "strict")
    except UnicodeError as exc:
        raise InvalidDiff from exc
    if any(part in ("", ".", "..") for part in value.split("/")):
        raise InvalidDiff
    return value


def _digest(value: Any, *, nullable: bool) -> str | None:
    if nullable and value is None:
        return None
    if not isinstance(value, str) or len(value) != 64 or any(char not in HEX for char in value):
        raise InvalidDiff
    return value


def _size(value: Any, *, nullable: bool) -> int | None:
    if nullable and value is None:
        return None
    return _bounded_integer(value, MAX_FILE_BYTES)


def _validate(document: Any) -> tuple[str, int, int | None, int | None, int | None, list[dict[str, Any]]]:
    if not isinstance(document, dict) or frozenset(document) != TOP_FIELDS:
        raise InvalidDiff
    if document["schema"] != DIFF_SCHEMA:
        raise InvalidDiff

    result = document["result"]
    exit_code = _bounded_integer(document["exit_code"], 2)
    codes = document["diagnostic_codes"]
    counts_status = document["counts_status"]
    changes = document["changes"]
    if not isinstance(codes, list) or not isinstance(changes, list):
        raise InvalidDiff

    if result == "INPUT_REFUSED":
        counts = (document["added_count"], document["removed_count"], document["modified_count"])
        if (
            exit_code != 2
            or codes != [INPUT_REFUSED_CODE]
            or counts != (None, None, None)
            or counts_status != "NOT_MEASURED"
            or changes != []
        ):
            raise InvalidDiff
        return result, exit_code, None, None, None, []

    if counts_status != "MEASURED":
        raise InvalidDiff
    raw_counts = (document["added_count"], document["removed_count"], document["modified_count"])
    counts = tuple(_bounded_integer(value, MAX_FILES) for value in raw_counts)
    if result == "UNCHANGED":
        if exit_code != 0 or codes != [] or counts != (0, 0, 0) or changes != []:
            raise InvalidDiff
        return result, exit_code, 0, 0, 0, []
    if result != "CHANGED" or exit_code != 1 or codes != [CHANGED_CODE]:
        raise InvalidDiff
    if not 1 <= len(changes) <= 2 * MAX_FILES or sum(counts) != len(changes):
        raise InvalidDiff

    normalized: list[dict[str, Any]] = []
    kinds = {"ADDED": 0, "REMOVED": 0, "MODIFIED": 0}
    paths: list[str] = []
    before_count = after_count = 0
    before_total = after_total = 0
    for row in changes:
        if not isinstance(row, dict) or frozenset(row) != ROW_FIELDS:
            raise InvalidDiff
        path = _path(row["relative_path"])
        kind = row["change"]
        if not isinstance(kind, str) or kind not in kinds:
            raise InvalidDiff
        before_hash = _digest(row["before_sha256"], nullable=True)
        after_hash = _digest(row["after_sha256"], nullable=True)
        before_size = _size(row["before_byte_count"], nullable=True)
        after_size = _size(row["after_byte_count"], nullable=True)

        if kind == "ADDED":
            if before_hash is not None or before_size is not None or after_hash is None or after_size is None:
                raise InvalidDiff
        elif kind == "REMOVED":
            if after_hash is not None or after_size is not None or before_hash is None or before_size is None:
                raise InvalidDiff
        elif (
            before_hash is None or before_size is None or after_hash is None or after_size is None
            or (before_hash, before_size) == (after_hash, after_size)
        ):
            raise InvalidDiff

        if before_size is not None:
            before_count += 1
            before_total += before_size
        if after_size is not None:
            after_count += 1
            after_total += after_size
        kinds[kind] += 1
        paths.append(path)
        normalized.append({
            "relative_path": path,
            "change": kind,
            "before_sha256": before_hash,
            "after_sha256": after_hash,
            "before_byte_count": before_size,
            "after_byte_count": after_size,
        })

    if paths != sorted(set(paths)) or tuple(kinds[k] for k in ("ADDED", "REMOVED", "MODIFIED")) != counts:
        raise InvalidDiff
    if before_count > MAX_FILES or after_count > MAX_FILES or before_total > MAX_TOTAL_BYTES or after_total > MAX_TOTAL_BYTES:
        raise InvalidDiff
    return result, exit_code, counts[0], counts[1], counts[2], normalized


def _side(digest: str | None, size: int | None) -> str:
    if digest is None or size is None:
        return "sha256=NOT_MEASURED bytes=NOT_MEASURED"
    return f"sha256={digest} bytes={size}"


def _render(
    result: str,
    exit_code: int,
    added: int | None,
    removed: int | None,
    modified: int | None,
    changes: list[dict[str, Any]],
) -> bytes:
    lines = [f"Input manifest difference: {result}", f"Exit code: {exit_code}"]
    if added is None:
        lines.append("Counts: added=NOT_MEASURED removed=NOT_MEASURED modified=NOT_MEASURED")
    else:
        lines.append(f"Counts: added={added} removed={removed} modified={modified} (MEASURED)")
    lines.append("Changes:")
    if not changes:
        lines.append("  (none)")
    else:
        for row in changes:
            path_text = json.dumps(row["relative_path"], ensure_ascii=True, separators=(",", ":"))
            lines.append(
                f"  {row['change']} {path_text} | before: {_side(row['before_sha256'], row['before_byte_count'])}"
                f" | after: {_side(row['after_sha256'], row['after_byte_count'])}"
            )
    try:
        output = ("\n".join(lines) + "\n").encode("ascii", "strict")
    except UnicodeError as exc:
        raise InvalidDiff from exc
    if len(output) > OUTPUT_LIMIT:
        raise InvalidDiff
    return output


def _load_stdin() -> bytes:
    chunks: list[bytes] = []
    remaining = INPUT_LIMIT + 1
    while remaining:
        chunk = sys.stdin.buffer.read(min(64 * 1024, remaining))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    raw = b"".join(chunks)
    if len(raw) > INPUT_LIMIT:
        raise InvalidDiff
    return raw


def _refuse() -> int:
    try:
        sys.stderr.write(FORMAT_REFUSAL_CODE + "\n")
    except OSError:
        pass
    return 2


def main() -> int:
    if len(sys.argv) != 1:
        return _refuse()
    try:
        text = _load_stdin().decode("utf-8", "strict")
        document = json.loads(
            text,
            parse_int=Decimal,
            parse_float=Decimal,
            parse_constant=_reject_constant,
            object_pairs_hook=_unique_object,
        )
        profile = _validate(document)
        output = _render(*profile)
    except (OSError, UnicodeError, json.JSONDecodeError, InvalidDiff, ValueError, DecimalException, RecursionError):
        return _refuse()

    try:
        written = sys.stdout.buffer.write(output)
        if written != len(output):
            return 2
        sys.stdout.buffer.flush()
    except OSError:
        return 2
    return profile[1]


if __name__ == "__main__":
    raise SystemExit(main())
