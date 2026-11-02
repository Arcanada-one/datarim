#!/usr/bin/env python3
"""Verify a captured CLI input manifest against the selected file bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from decimal import Decimal
from typing import Any


INPUT_LIMIT = 2 * 1024 * 1024
FILE_LIMIT = 1024 * 1024
TOTAL_LIMIT = 16 * 1024 * 1024
MAX_FILES = 64
MANIFEST_SCHEMA = "DatarimCliInputManifest/v1"
OUTPUT_SCHEMA = "DatarimCliInputManifestVerification/v1"
ENTRY_KEYS = {"relative_path", "sha256", "byte_count"}
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


class Refused(Exception):
    """A fixed, non-sensitive refusal condition."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise Refused
        result[key] = value
    return result


def _reject_constant(_value: str) -> None:
    raise Refused


def _parse_manifest(raw: bytes) -> list[tuple[str, str, int]]:
    try:
        text = raw.decode("utf-8", errors="strict")
        document = json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_float=Decimal,
            parse_int=int,
            parse_constant=_reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, Refused, ValueError, RecursionError):
        raise Refused from None

    if not isinstance(document, dict):
        raise Refused
    if document.get("schema") != MANIFEST_SCHEMA:
        raise Refused
    if document.get("result") != "COMPLETE":
        raise Refused
    if type(document.get("exit_code")) is not int or document["exit_code"] != 0:
        raise Refused
    if document.get("diagnostic_codes") != []:
        raise Refused
    if document.get("file_count_status") != "MEASURED":
        raise Refused

    entries = document.get("files")
    count = document.get("file_count")
    if type(count) is not int or not 1 <= count <= MAX_FILES:
        raise Refused
    if not isinstance(entries, list) or len(entries) != count:
        raise Refused

    selected: list[tuple[str, str, int]] = []
    seen: set[str] = set()
    declared_total = 0
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != ENTRY_KEYS:
            raise Refused
        path = entry.get("relative_path")
        digest = entry.get("sha256")
        byte_count = entry.get("byte_count")
        if not isinstance(path, str) or not path or "\x00" in path or "\\" in path:
            raise Refused
        if path.startswith("/"):
            raise Refused
        components = path.split("/")
        if any(component in ("", ".", "..") for component in components):
            raise Refused
        if path in seen:
            raise Refused
        seen.add(path)
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise Refused
        if isinstance(byte_count, bool) or not isinstance(byte_count, (int, Decimal)):
            raise Refused
        if isinstance(byte_count, Decimal):
            if not byte_count.is_finite() or byte_count != byte_count.to_integral_value():
                raise Refused
            if byte_count < 0 or byte_count > FILE_LIMIT:
                raise Refused
            byte_count = int(byte_count)
        if not 0 <= byte_count <= FILE_LIMIT:
            raise Refused
        declared_total += byte_count
        if declared_total > TOTAL_LIMIT:
            raise Refused
        selected.append((path, digest, byte_count))
    return selected


def _required_posix_primitives() -> None:
    required_flags = ("O_DIRECTORY", "O_NOFOLLOW", "O_NONBLOCK")
    if os.name != "posix" or not all(hasattr(os, name) for name in required_flags):
        raise Refused
    if os.open not in os.supports_dir_fd or os.stat not in os.supports_dir_fd:
        raise Refused
    if os.stat not in os.supports_follow_symlinks:
        raise Refused


def _open_directory(parent_fd: int, name: str) -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError:
        raise Refused from None
    try:
        if not stat.S_ISDIR(os.fstat(fd).st_mode):
            raise Refused
        return fd
    except BaseException:
        os.close(fd)
        raise


def _open_root(root: str) -> int:
    if not root:
        raise Refused
    absolute = os.path.isabs(root)
    current = os.open("/" if absolute else ".", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        for component in root.split(os.sep):
            if component in ("", "."):
                continue
            if component == "..":
                raise Refused
            next_fd = _open_directory(current, component)
            os.close(current)
            current = next_fd
        return current
    except BaseException:
        os.close(current)
        raise


def _read_selected(root_fd: int, path: str, remaining_total: int) -> bytes:
    if remaining_total < 0:
        raise Refused
    read_limit = min(FILE_LIMIT, remaining_total)
    components = path.split("/")
    current = os.dup(root_fd)
    try:
        for component in components[:-1]:
            next_fd = _open_directory(current, component)
            os.close(current)
            current = next_fd

        leaf = components[-1]
        try:
            before = os.stat(leaf, dir_fd=current, follow_symlinks=False)
        except OSError:
            raise Refused from None
        if not stat.S_ISREG(before.st_mode):
            raise Refused
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        try:
            fd = os.open(leaf, flags, dir_fd=current)
        except OSError:
            raise Refused from None
        try:
            opened = os.fstat(fd)
            if (
                not stat.S_ISREG(opened.st_mode)
                or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino)
                or opened.st_size > FILE_LIMIT
                or opened.st_size > remaining_total
            ):
                raise Refused
            chunks: list[bytes] = []
            remaining = read_limit
            while remaining:
                chunk = os.read(fd, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            data = b"".join(chunks)
            return data
        except OSError:
            raise Refused from None
        finally:
            os.close(fd)
    finally:
        os.close(current)


def _result(result: str, exit_code: int, codes: list[str], count: int | None, status: str, changed: list[str]) -> dict[str, Any]:
    return {
        "schema": OUTPUT_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": codes,
        "file_count": count,
        "file_count_status": status,
        "changed_paths": changed,
    }


def _verify(root: str, raw: bytes) -> tuple[dict[str, Any], int]:
    try:
        _required_posix_primitives()
        selected = _parse_manifest(raw)
        root_fd = _open_root(root)
        try:
            changed: list[str] = []
            actual_total = 0
            for path, expected_digest, expected_size in selected:
                data = _read_selected(root_fd, path, TOTAL_LIMIT - actual_total)
                actual_total += len(data)
                if actual_total > TOTAL_LIMIT:
                    raise Refused
                if len(data) != expected_size or hashlib.sha256(data).hexdigest() != expected_digest:
                    changed.append(path)
        finally:
            os.close(root_fd)
    except (Refused, OSError, OverflowError, ValueError, RecursionError):
        return _result("INPUT_REFUSED", 2, ["INPUT_MANIFEST_VERIFICATION_REFUSED"], None, "NOT_MEASURED", []), 2

    changed.sort()
    if changed:
        return _result("CHANGED", 1, ["INPUT_MANIFEST_BYTES_CHANGED"], len(selected), "MEASURED", changed), 1
    return _result("MATCHED", 0, [], len(selected), "MEASURED", []), 0


def _read_stdin() -> bytes:
    raw = sys.stdin.buffer.read(INPUT_LIMIT + 1)
    if len(raw) > INPUT_LIMIT:
        raise Refused
    return raw


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, metavar="DIRECTORY")
    args = parser.parse_args()
    try:
        raw = _read_stdin()
    except (OSError, Refused):
        outcome, code = _result("INPUT_REFUSED", 2, ["INPUT_MANIFEST_VERIFICATION_REFUSED"], None, "NOT_MEASURED", []), 2
    else:
        outcome, code = _verify(args.root, raw)
    sys.stdout.write(json.dumps(outcome, ensure_ascii=True, separators=(",", ":")) + "\n")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
