#!/usr/bin/env python3
"""List public summary-schema files and a small set of literal metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any


SCHEMA_ID = "DatarimSummarySchemaCatalog/v1"
MAX_FILES = 256
MAX_FILE_BYTES = 1024 * 1024
MAX_METADATA_CHARS = 256
SCHEMA_SUFFIX = ".schema.json"


class CatalogError(Exception):
    def __init__(self, code: str) -> None:
        self.code = code


def _directory_flags() -> int:
    return os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)


def _open_directory(name: str, parent_fd: int) -> int:
    fd = os.open(name, _directory_flags(), dir_fd=parent_fd)
    if not stat.S_ISDIR(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError("not a directory")
    return fd


def _open_schema_directory(root: Path) -> int:
    root_fd = os.open(root, _directory_flags())
    try:
        documentation_fd = _open_directory("documentation", root_fd)
    finally:
        os.close(root_fd)
    try:
        reference_fd = _open_directory("reference", documentation_fd)
    finally:
        os.close(documentation_fd)
    try:
        return _open_directory("schemas", reference_fd)
    finally:
        os.close(reference_fd)


def _read_regular_file(name: str, directory_fd: int) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(name, flags, dir_fd=directory_fd)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError("not a regular file")
        chunks: list[bytes] = []
        total = 0
        while total <= MAX_FILE_BYTES:
            chunk = os.read(fd, min(65536, MAX_FILE_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
        if total > MAX_FILE_BYTES:
            raise CatalogError("SCHEMA_CATALOG_LIMIT")
        return b"".join(chunks)
    finally:
        os.close(fd)


def _metadata_string(value: Any) -> str | None:
    if isinstance(value, str) and len(value) <= MAX_METADATA_CHARS:
        return value
    return None


def _literal_summary_schema(document: Any) -> str | None:
    if not isinstance(document, dict):
        return None
    properties = document.get("properties")
    if not isinstance(properties, dict):
        return None
    schema_property = properties.get("schema")
    if not isinstance(schema_property, dict):
        return None
    return _metadata_string(schema_property.get("const"))


def _reject_non_json_constant(value: str) -> None:
    raise ValueError(value)


def _catalog(root: Path) -> dict[str, Any]:
    try:
        schemas_fd = _open_schema_directory(root)
    except (OSError, ValueError):
        raise CatalogError("SCHEMA_DIRECTORY_UNAVAILABLE") from None

    try:
        try:
            with os.scandir(schemas_fd) as entries:
                names = sorted(
                    entry.name for entry in entries if entry.name.endswith(SCHEMA_SUFFIX)
                )
        except OSError:
            raise CatalogError("SCHEMA_DIRECTORY_UNAVAILABLE") from None

        if len(names) > MAX_FILES:
            raise CatalogError("SCHEMA_CATALOG_LIMIT")

        catalog_entries = []
        for name in names:
            try:
                raw = _read_regular_file(name, schemas_fd)
                document = json.loads(
                    raw.decode("utf-8"), parse_constant=_reject_non_json_constant
                )
                if not isinstance(document, (dict, bool)):
                    raise CatalogError("SCHEMA_INPUT_REFUSED")
            except CatalogError:
                raise
            except (
                OSError,
                UnicodeDecodeError,
                json.JSONDecodeError,
                RecursionError,
                ValueError,
            ):
                raise CatalogError("SCHEMA_INPUT_REFUSED") from None

            title = _metadata_string(document.get("title")) if isinstance(document, dict) else None
            dialect = _metadata_string(document.get("$schema")) if isinstance(document, dict) else None
            catalog_entries.append(
                {
                    "relative_path": f"documentation/reference/schemas/{name}",
                    "sha256": hashlib.sha256(raw).hexdigest(),
                    "title": title,
                    "dialect": dialect,
                    "summary_schema": _literal_summary_schema(document),
                }
            )

        return {
            "schema": SCHEMA_ID,
            "result": "COMPLETE",
            "exit_code": 0,
            "diagnostic_codes": [],
            "entry_count": len(catalog_entries),
            "entry_count_status": "MEASURED",
            "entries": catalog_entries,
        }
    finally:
        os.close(schemas_fd)


def _refusal(code: str) -> dict[str, Any]:
    return {
        "schema": SCHEMA_ID,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": [code],
        "entry_count": None,
        "entry_count_status": "NOT_MEASURED",
        "entries": [],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List installed public summary-schema artifacts as JSON."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (default: the parent of this script's directory)",
    )
    args = parser.parse_args()

    try:
        result = _catalog(args.root)
    except CatalogError as error:
        result = _refusal(error.code)
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
