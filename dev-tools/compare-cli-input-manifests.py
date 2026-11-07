#!/usr/bin/env python3
"""Compare two saved declarations of explicitly inventoried CLI inputs."""

from __future__ import annotations

import argparse
from decimal import Decimal, DecimalException
import hashlib
import json
import os
import re
import stat
import sys


SCHEMA = "DatarimCliInputManifest/v1"
DIFF_SCHEMA = "DatarimCliInputManifestDiff/v1"
MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
READ_CHUNK_BYTES = 64 * 1024
SHA256_RE = re.compile(r"[0-9a-f]{64}", re.ASCII)


class InputRefused(Exception):
    """An input cannot be compared under the declared contract."""


def _stable_stat(value: os.stat_result) -> tuple[int, int, int, int, int]:
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def _read_once(path: str) -> bytes:
    if not hasattr(os, "O_NONBLOCK"):
        raise InputRefused
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | os.O_NONBLOCK
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_INPUT_BYTES:
            raise InputRefused

        chunks: list[bytes] = []
        remaining = MAX_INPUT_BYTES + 1
        while remaining:
            chunk = os.read(fd, min(READ_CHUNK_BYTES, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        after = os.fstat(fd)
        if len(data) > MAX_INPUT_BYTES or len(data) != before.st_size:
            raise InputRefused
        if _stable_stat(before) != _stable_stat(after):
            raise InputRefused
        return data
    finally:
        os.close(fd)


def _object_without_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InputRefused
        result[key] = value
    return result


def _reject_constant(_value: str) -> object:
    raise InputRefused


def _load_json(path: str) -> object:
    raw = _read_once(path)
    try:
        text = raw.decode("utf-8", "strict")
        return json.loads(
            text,
            parse_int=int,
            parse_float=Decimal,
            parse_constant=_reject_constant,
            object_pairs_hook=_object_without_duplicates,
        )
    except (UnicodeError, json.JSONDecodeError, DecimalException, RecursionError, ValueError) as exc:
        raise InputRefused from exc


def _integer_value(value: object, *, maximum: int) -> int:
    if type(value) is int:
        number = value
    elif isinstance(value, Decimal):
        try:
            if not value.is_finite() or value != value.to_integral_value():
                raise InputRefused
            if value < 0 or value > maximum:
                raise InputRefused
            number = int(value)
        except DecimalException as exc:
            raise InputRefused from exc
    else:
        raise InputRefused

    if number < 0 or number > maximum:
        raise InputRefused
    return number


def _relative_path(value: object) -> str:
    if not isinstance(value, str):
        raise InputRefused
    try:
        value.encode("utf-8", "strict")
    except UnicodeError as exc:
        raise InputRefused from exc
    if not value or value.startswith("/") or "\x00" in value:
        raise InputRefused
    if any(part in ("", ".", "..") for part in value.split("/")):
        raise InputRefused
    return value


def _validate_inventory(value: object) -> dict[str, tuple[str, int]]:
    if not isinstance(value, dict):
        raise InputRefused
    required = {
        "schema",
        "result",
        "exit_code",
        "diagnostic_codes",
        "file_count",
        "file_count_status",
        "files",
    }
    if not required.issubset(value):
        raise InputRefused
    if value["schema"] != SCHEMA or value["result"] != "COMPLETE":
        raise InputRefused
    if type(value["exit_code"]) is not int or value["exit_code"] != 0:
        raise InputRefused
    if value["diagnostic_codes"] != [] or value["file_count_status"] != "MEASURED":
        raise InputRefused

    files = value["files"]
    if not isinstance(files, list) or not 1 <= len(files) <= MAX_FILES:
        raise InputRefused
    if type(value["file_count"]) is not int or value["file_count"] != len(files):
        raise InputRefused

    inventory: dict[str, tuple[str, int]] = {}
    total = 0
    for item in files:
        if not isinstance(item, dict) or set(item) != {"relative_path", "sha256", "byte_count"}:
            raise InputRefused
        path = _relative_path(item["relative_path"])
        digest = item["sha256"]
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise InputRefused
        size = _integer_value(item["byte_count"], maximum=MAX_FILE_BYTES)
        if path in inventory:
            raise InputRefused
        total += size
        if total > MAX_TOTAL_BYTES:
            raise InputRefused
        inventory[path] = (digest, size)
    return inventory


def _summary(
    result: str,
    exit_code: int,
    diagnostic_codes: list[str],
    added: int | None,
    removed: int | None,
    modified: int | None,
    counts_status: str,
    changes: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "schema": DIFF_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": diagnostic_codes,
        "added_count": added,
        "removed_count": removed,
        "modified_count": modified,
        "counts_status": counts_status,
        "changes": changes,
    }


def _compare(before: dict[str, tuple[str, int]], after: dict[str, tuple[str, int]]) -> dict[str, object]:
    changes: list[dict[str, object]] = []
    added = removed = modified = 0
    for path in sorted(before.keys() | after.keys()):
        old = before.get(path)
        new = after.get(path)
        if old is None:
            change = "ADDED"
            added += 1
        elif new is None:
            change = "REMOVED"
            removed += 1
        elif old != new:
            change = "MODIFIED"
            modified += 1
        else:
            continue
        changes.append(
            {
                "relative_path": path,
                "change": change,
                "before_sha256": old[0] if old is not None else None,
                "after_sha256": new[0] if new is not None else None,
                "before_byte_count": old[1] if old is not None else None,
                "after_byte_count": new[1] if new is not None else None,
            }
        )

    if not changes:
        return _summary("UNCHANGED", 0, [], 0, 0, 0, "MEASURED", [])
    return _summary("CHANGED", 1, ["INPUT_MANIFEST_CHANGED"], added, removed, modified, "MEASURED", changes)


def _write(value: dict[str, object]) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, help="saved complete input inventory JSON")
    parser.add_argument("--after", required=True, help="saved complete input inventory JSON")
    args = parser.parse_args()

    try:
        before = _validate_inventory(_load_json(args.before))
        after = _validate_inventory(_load_json(args.after))
        summary = _compare(before, after)
    except (InputRefused, OSError, UnicodeError, ValueError, DecimalException):
        _write(_summary("INPUT_REFUSED", 2, ["INPUT_MANIFEST_DIFF_REFUSED"], None, None, None, "NOT_MEASURED", []))
        sys.stderr.write("INPUT_MANIFEST_DIFF_REFUSED\n")
        return 2

    _write(summary)
    return int(summary["exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())
