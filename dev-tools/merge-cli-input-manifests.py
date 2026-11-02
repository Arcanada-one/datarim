#!/usr/bin/env python3
"""Merge saved Datarim CLI input-manifest declarations without reading listed paths."""

from __future__ import annotations

from decimal import Decimal, DecimalException
import json
import re
import sys
from typing import Any

SCHEMA = "DatarimCliInputManifest/v1"
INPUT_LIMIT = 2 * 1024 * 1024
MAX_MANIFESTS = 16
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z", re.ASCII)
ROW_KEYS = {"relative_path", "sha256", "byte_count"}


class InputRefused(Exception):
    """Input is outside the saved-manifest merge contract."""


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


def _core_integer(value: Any, *, expected: int, maximum: int) -> int:
    # Producer core counters/status use JSON integer tokens, never bool or Decimal.
    if type(value) is not int or value != expected or value > maximum:
        raise InputRefused
    return value


def _load_manifest(item: Any) -> dict[str, tuple[str, int]]:
    if not isinstance(item, dict):
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
    if not required.issubset(item):
        raise InputRefused
    if item["schema"] != SCHEMA or item["result"] != "COMPLETE":
        raise InputRefused
    _core_integer(item["exit_code"], expected=0, maximum=0)
    if item["diagnostic_codes"] != [] or item["file_count_status"] != "MEASURED":
        raise InputRefused

    rows = item["files"]
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_FILES:
        raise InputRefused
    _core_integer(item["file_count"], expected=len(rows), maximum=MAX_FILES)

    inventory: dict[str, tuple[str, int]] = {}
    total = 0
    for row in rows:
        if not isinstance(row, dict) or set(row) != ROW_KEYS:
            raise InputRefused
        path = _relative_path(row["relative_path"])
        digest = row["sha256"]
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise InputRefused
        size = _integer_value(row["byte_count"], maximum=MAX_FILE_BYTES)
        if path in inventory:
            raise InputRefused
        total += size
        if total > MAX_TOTAL_BYTES:
            raise InputRefused
        inventory[path] = (digest, size)
    return inventory


def _merge(raw: bytes) -> dict[str, Any]:
    if len(raw) > INPUT_LIMIT:
        raise InputRefused
    try:
        text = raw.decode("utf-8", "strict")
        manifests = json.loads(
            text,
            parse_int=int,
            parse_float=Decimal,
            parse_constant=_reject_constant,
            object_pairs_hook=_object_without_duplicates,
        )
    except (UnicodeError, json.JSONDecodeError, DecimalException, RecursionError, ValueError) as exc:
        raise InputRefused from exc

    if not isinstance(manifests, list) or not 1 <= len(manifests) <= MAX_MANIFESTS:
        raise InputRefused

    merged: dict[str, tuple[str, int]] = {}
    total = 0
    for item in manifests:
        inventory = _load_manifest(item)
        for path, declaration in inventory.items():
            prior = merged.get(path)
            if prior is not None:
                if prior != declaration:
                    raise InputRefused
                continue
            if len(merged) >= MAX_FILES:
                raise InputRefused
            total += declaration[1]
            if total > MAX_TOTAL_BYTES:
                raise InputRefused
            merged[path] = declaration

    rows = [
        {"relative_path": path, "sha256": merged[path][0], "byte_count": merged[path][1]}
        for path in sorted(merged)
    ]
    result = {
        "schema": SCHEMA,
        "result": "COMPLETE",
        "exit_code": 0,
        "diagnostic_codes": [],
        "file_count": len(rows),
        "file_count_status": "MEASURED",
        "files": rows,
    }
    return result


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


def _encode(value: dict[str, Any]) -> bytes:
    encoded = (json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n").encode("utf-8")
    if len(encoded) > INPUT_LIMIT:
        raise InputRefused
    return encoded


def _write_refusal() -> int:
    try:
        raw = _encode(_refusal())
        sys.stdout.buffer.write(raw)
        sys.stdout.buffer.flush()
        sys.stderr.write("INPUT_MANIFEST_MERGE_REFUSED\n")
        sys.stderr.flush()
    except OSError:
        return 2
    return 2


def main() -> int:
    if len(sys.argv) != 1:
        return _write_refusal()
    try:
        raw = sys.stdin.buffer.read(INPUT_LIMIT + 1)
        result = _merge(raw)
        encoded = _encode(result)
    except (InputRefused, OSError, UnicodeError, DecimalException, RecursionError, ValueError, OverflowError):
        return _write_refusal()
    try:
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()
    except OSError:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
