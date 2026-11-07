#!/usr/bin/env python3
"""Select declarations from one saved CLI input manifest."""

from __future__ import annotations

import argparse
from decimal import Decimal, DecimalException
import json
import re
import sys
from typing import Any


SCHEMA = "DatarimCliInputManifest/v1"
MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
SHA256_RE = re.compile(r"[0-9a-f]{64}", re.ASCII)


class InputRefused(Exception):
    """The saved manifest or requested subset is outside the fixed contract."""


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InputRefused
        result[key] = value
    return result


def _reject_constant(_value: str) -> Any:
    raise InputRefused


def _relative_path(value: Any) -> str:
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


def _integer_value(value: Any, *, maximum: int) -> int:
    if type(value) is int:
        number = value
    elif isinstance(value, Decimal):
        try:
            if not value.is_finite() or value < 0 or value > maximum:
                raise InputRefused
            if value != value.to_integral_value():
                raise InputRefused
            number = int(value)
        except DecimalException as exc:
            raise InputRefused from exc
    else:
        raise InputRefused

    if number < 0 or number > maximum:
        raise InputRefused
    return number


def _load_manifest(raw: bytes) -> dict[str, Any]:
    if len(raw) > MAX_INPUT_BYTES:
        raise InputRefused
    try:
        text = raw.decode("utf-8", "strict")
        value = json.loads(
            text,
            parse_int=int,
            parse_float=Decimal,
            parse_constant=_reject_constant,
            object_pairs_hook=_object_without_duplicates,
        )
    except (UnicodeError, json.JSONDecodeError, DecimalException, RecursionError, ValueError) as exc:
        raise InputRefused from exc

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


def _requested_paths(values: list[str]) -> list[str]:
    if not 1 <= len(values) <= MAX_FILES:
        raise InputRefused
    paths = [_relative_path(value) for value in values]
    if len(set(paths)) != len(paths):
        raise InputRefused
    return paths


def _summary(files: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "result": "COMPLETE",
        "exit_code": 0,
        "diagnostic_codes": [],
        "file_count": len(files),
        "file_count_status": "MEASURED",
        "files": files,
    }


def _refusal() -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": ["INPUT_MANIFEST_REFUSED"],
        "file_count": None,
        "file_count_status": "NOT_MEASURED",
        "files": [],
    }


def _write_summary(value: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", action="append", required=True, help="exact canonical relative POSIX path; repeatable")
    args = parser.parse_args()

    try:
        raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        inventory = _load_manifest(raw)
        requested = _requested_paths(args.file)
        if any(path not in inventory for path in requested):
            raise InputRefused
        selected = [
            {
                "relative_path": path,
                "sha256": inventory[path][0],
                "byte_count": inventory[path][1],
            }
            for path in sorted(requested)
        ]
        result = _summary(selected)
    except (InputRefused, OSError, UnicodeError, ValueError, DecimalException, RecursionError):
        _write_summary(_refusal())
        sys.stderr.write("INPUT_MANIFEST_SELECTION_REFUSED\n")
        return 2

    _write_summary(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
