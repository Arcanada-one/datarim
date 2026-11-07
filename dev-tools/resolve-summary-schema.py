#!/usr/bin/env python3
"""Resolve a declared summary schema using an explicitly saved catalog."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import stat
import sys
from pathlib import PurePosixPath
from typing import Any


CATALOG_SCHEMA = "DatarimSummarySchemaCatalog/v1"
RESULT_SCHEMA = "DatarimSummarySchemaResolution/v1"
MAX_QUERY_BYTES = 64 * 1024
MAX_CATALOG_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 256
MAX_METADATA_CHARS = 256
QUERY_ID = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,127}/v[1-9][0-9]{0,3}$", re.ASCII)
SHA256 = re.compile(r"^[0-9a-f]{64}$", re.ASCII)
CATALOG_FIELDS = {
    "schema",
    "result",
    "exit_code",
    "diagnostic_codes",
    "entry_count",
    "entry_count_status",
    "entries",
}
ENTRY_FIELDS = {"relative_path", "sha256", "title", "dialect", "summary_schema"}


class InputRefused(Exception):
    """Raised for any input that cannot be safely resolved."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("non-finite JSON number")
    return number


def _reject_constant(_value: str) -> None:
    raise ValueError("non-finite JSON constant")


def _decode_json(raw: bytes) -> Any:
    return json.loads(
        raw.decode("utf-8", errors="strict"),
        object_pairs_hook=_unique_object,
        parse_float=_finite_float,
        parse_constant=_reject_constant,
    )


def _read_limited_stream(stream: Any, limit: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while total <= limit:
        chunk = stream.read(min(65536, limit + 1 - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    if total > limit:
        raise InputRefused
    return b"".join(chunks)


def _read_catalog(path: str) -> bytes:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_NONBLOCK"):
        raise InputRefused
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        fd = os.open(path, flags)
    except (OSError, ValueError):
        raise InputRefused from None
    try:
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise InputRefused
            chunks: list[bytes] = []
            total = 0
            while total <= MAX_CATALOG_BYTES:
                chunk = os.read(fd, min(65536, MAX_CATALOG_BYTES + 1 - total))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
            if total > MAX_CATALOG_BYTES:
                raise InputRefused
            return b"".join(chunks)
        except OSError:
            raise InputRefused from None
    finally:
        os.close(fd)


def _canonical_schema_path(value: Any) -> bool:
    if not isinstance(value, str) or "\\" in value or "\x00" in value:
        return False
    path = PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value:
        return False
    parts = path.parts
    return (
        len(parts) == 4
        and parts[:3] == ("documentation", "reference", "schemas")
        and parts[3].endswith(".schema.json")
        and parts[3] not in (".schema.json",)
    )


def _metadata(value: Any) -> bool:
    return value is None or (isinstance(value, str) and len(value) <= MAX_METADATA_CHARS)


def _validate_catalog(catalog: Any) -> list[dict[str, Any]]:
    if not isinstance(catalog, dict) or set(catalog) != CATALOG_FIELDS:
        raise InputRefused
    if (
        catalog["schema"] != CATALOG_SCHEMA
        or catalog["result"] != "COMPLETE"
        or type(catalog["exit_code"]) is not int
        or catalog["exit_code"] != 0
        or catalog["diagnostic_codes"] != []
        or catalog["entry_count_status"] != "MEASURED"
    ):
        raise InputRefused
    count = catalog["entry_count"]
    entries = catalog["entries"]
    if type(count) is not int or not 0 <= count <= MAX_ENTRIES:
        raise InputRefused
    if not isinstance(entries, list) or len(entries) != count:
        raise InputRefused

    paths: set[str] = set()
    validated: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != ENTRY_FIELDS:
            raise InputRefused
        path = entry["relative_path"]
        digest = entry["sha256"]
        if not _canonical_schema_path(path) or path in paths:
            raise InputRefused
        if not isinstance(digest, str) or SHA256.fullmatch(digest) is None:
            raise InputRefused
        if not all(_metadata(entry[key]) for key in ("title", "dialect", "summary_schema")):
            raise InputRefused
        paths.add(path)
        validated.append(entry)
    return validated


def _query_schema_id(query: Any) -> str:
    if not isinstance(query, dict):
        raise InputRefused
    schema_id = query.get("schema")
    if not isinstance(schema_id, str) or QUERY_ID.fullmatch(schema_id) is None:
        raise InputRefused
    return schema_id


def _result(
    result: str,
    exit_code: int,
    diagnostic_codes: list[str],
    match_count: int | None,
    count_status: str,
    selection: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "schema": RESULT_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": diagnostic_codes,
        "match_count": match_count,
        "match_count_status": count_status,
        "selection": selection,
    }


def _resolve(catalog_path: str, query_raw: bytes) -> dict[str, Any]:
    query = _decode_json(query_raw)
    schema_id = _query_schema_id(query)
    catalog = _validate_catalog(_decode_json(_read_catalog(catalog_path)))
    matches = [entry for entry in catalog if entry["summary_schema"] == schema_id]
    if len(matches) == 1:
        return _result("MATCHED", 0, [], 1, "MEASURED", matches[0])
    if not matches:
        return _result("NOT_FOUND", 1, ["SUMMARY_SCHEMA_NOT_FOUND"], 0, "MEASURED", None)
    return _result(
        "AMBIGUOUS",
        1,
        ["SUMMARY_SCHEMA_AMBIGUOUS"],
        len(matches),
        "MEASURED",
        None,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Resolve a summary schema from an explicitly saved catalog.",
        allow_abbrev=False,
    )
    parser.add_argument("--catalog", required=True, metavar="FILE")
    args = parser.parse_args()

    try:
        query_raw = _read_limited_stream(sys.stdin.buffer, MAX_QUERY_BYTES)
        result = _resolve(args.catalog, query_raw)
    except (
        InputRefused,
        OSError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        RecursionError,
        ValueError,
        TypeError,
    ):
        result = _result(
            "INPUT_REFUSED",
            2,
            ["SUMMARY_SCHEMA_RESOLUTION_REFUSED"],
            None,
            "NOT_MEASURED",
            None,
        )
    print(json.dumps(result, ensure_ascii=True, allow_nan=False, separators=(",", ":")))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
