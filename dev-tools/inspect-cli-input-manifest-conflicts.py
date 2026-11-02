#!/usr/bin/env python3
"""Inspect disagreements among saved CLI input-manifest declarations."""

from __future__ import annotations

from decimal import Decimal, DecimalException
import json
import re
import sys
from typing import Any

SCHEMA = "DatarimCliInputManifest/v1"
OUTPUT_SCHEMA = "DatarimCliInputManifestConflicts/v1"
INPUT_LIMIT = 2 * 1024 * 1024
MAX_MANIFESTS = 16
MAX_FILES = 64
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 16 * 1024 * 1024
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z", re.ASCII)
ROW_KEYS = {"relative_path", "sha256", "byte_count"}


class _JsonIntegerToken(Decimal):
    """Preserve integer-token identity and exact value until field checks finish."""


class InputRefused(Exception):
    """Input is outside the saved-manifest inspection contract."""


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InputRefused
        result[key] = value
    return result


def _parse_integer_token(token: str) -> _JsonIntegerToken:
    return _JsonIntegerToken(token)


def _reject_constant(_value: str) -> Any:
    raise InputRefused


def _core_integer(value: Any, *, expected: int, maximum: int) -> int:
    if type(value) is not _JsonIntegerToken:
        raise InputRefused
    try:
        if (
            not value.is_finite()
            or value < 0
            or value > maximum
            or value != value.to_integral_value()
        ):
            raise InputRefused
        number = int(value)
    except DecimalException as exc:
        raise InputRefused from exc
    if number != expected:
        raise InputRefused
    return number


def _bounded_integer(value: Any, *, maximum: int) -> int:
    if not isinstance(value, Decimal):
        raise InputRefused
    try:
        if (
            not value.is_finite()
            or value < 0
            or value > maximum
            or value != value.to_integral_value()
        ):
            raise InputRefused
        return int(value)
    except DecimalException as exc:
        raise InputRefused from exc


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


def _load_manifest(item: Any) -> list[tuple[str, str, int]]:
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

    seen: set[str] = set()
    declarations: list[tuple[str, str, int]] = []
    total = 0
    for row in rows:
        if not isinstance(row, dict) or set(row) != ROW_KEYS:
            raise InputRefused
        path = _relative_path(row["relative_path"])
        digest = row["sha256"]
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise InputRefused
        size = _bounded_integer(row["byte_count"], maximum=MAX_FILE_BYTES)
        if path in seen:
            raise InputRefused
        seen.add(path)
        total += size
        if total > MAX_TOTAL_BYTES:
            raise InputRefused
        declarations.append((path, digest, size))
    return declarations


def _inspect(raw: bytes) -> dict[str, Any]:
    if len(raw) > INPUT_LIMIT:
        raise InputRefused
    try:
        text = raw.decode("utf-8", "strict")
        manifests = json.loads(
            text,
            parse_int=_parse_integer_token,
            parse_float=Decimal,
            parse_constant=_reject_constant,
            object_pairs_hook=_object_without_duplicates,
        )
    except (UnicodeError, json.JSONDecodeError, DecimalException, RecursionError, ValueError) as exc:
        raise InputRefused from exc

    if not isinstance(manifests, list) or not 1 <= len(manifests) <= MAX_MANIFESTS:
        raise InputRefused

    observations: dict[str, list[dict[str, Any]]] = {}
    for manifest_index, item in enumerate(manifests):
        for path, digest, size in _load_manifest(item):
            observations.setdefault(path, []).append(
                {"manifest_index": manifest_index, "sha256": digest, "byte_count": size}
            )
    if len(observations) > MAX_FILES:
        raise InputRefused

    conflicts: list[dict[str, Any]] = []
    for path in sorted(observations):
        declarations = observations[path]
        variants = {(entry["sha256"], entry["byte_count"]) for entry in declarations}
        if len(variants) > 1:
            conflicts.append({"relative_path": path, "declarations": declarations})

    conflict_count = len(conflicts)
    result = "CONFLICTS" if conflict_count else "CONSISTENT"
    diagnostic_codes = ["INPUT_MANIFEST_CONFLICTS"] if conflict_count else []
    return {
        "schema": OUTPUT_SCHEMA,
        "result": result,
        "exit_code": 1 if conflict_count else 0,
        "diagnostic_codes": diagnostic_codes,
        "manifest_count": len(manifests),
        "manifest_count_status": "MEASURED",
        "conflict_count": conflict_count,
        "conflict_count_status": "MEASURED",
        "conflicts": conflicts,
    }


def _refusal() -> dict[str, Any]:
    return {
        "schema": OUTPUT_SCHEMA,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": ["INPUT_MANIFEST_CONFLICT_INSPECTION_REFUSED"],
        "manifest_count": None,
        "manifest_count_status": "NOT_MEASURED",
        "conflict_count": None,
        "conflict_count_status": "NOT_MEASURED",
        "conflicts": [],
    }


def _encode(value: dict[str, Any]) -> bytes:
    encoded = (json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n").encode("utf-8")
    if len(encoded) > INPUT_LIMIT:
        raise InputRefused
    return encoded


def _write_refusal() -> int:
    try:
        sys.stdout.buffer.write(_encode(_refusal()))
        sys.stdout.buffer.flush()
        sys.stderr.write("INPUT_MANIFEST_CONFLICT_INSPECTION_REFUSED\n")
        sys.stderr.flush()
    except OSError:
        return 2
    return 2


def main() -> int:
    if len(sys.argv) != 1:
        return _write_refusal()
    try:
        raw = sys.stdin.buffer.read(INPUT_LIMIT + 1)
        result = _inspect(raw)
        encoded = _encode(result)
    except (InputRefused, OSError, UnicodeError, DecimalException, RecursionError, ValueError, OverflowError):
        return _write_refusal()
    try:
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()
    except OSError:
        return 2
    return result["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
