#!/usr/bin/env python3
"""Deterministic normalization, rotation, and ranking for resolver history."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any


ACTION_PATTERN = re.compile(r"/dr-[a-z0-9][a-z0-9-]*\Z")
FORBIDDEN_INTENT_CHARS = set("/\\;&|<>$`\"'()[]{}*?!~")


def normalize_intent(value: str) -> str:
    """Return the canonical exact-match intent or raise ValueError."""
    if any(
        (ord(char) <= 0x1F and char != "\t")
        or 0x7F <= ord(char) <= 0x9F
        for char in value
    ):
        raise ValueError("intent contains a control character")
    normalized = re.sub(r"[ \t]+", " ", value.strip(" \t"))
    size = len(normalized.encode("utf-8"))
    if not 1 <= size <= 256:
        raise ValueError("intent must contain 1 through 256 UTF-8 bytes")
    if normalized.startswith("-") or normalized in {".", ".."}:
        raise ValueError("intent resembles an option or path component")
    if any(char in FORBIDDEN_INTENT_CHARS for char in normalized):
        raise ValueError("intent contains a path or shell metacharacter")
    return normalized


def canonical_record(raw: Any) -> dict[str, Any] | None:
    """Validate and canonicalize one decoded history object."""
    if not isinstance(raw, dict):
        return None
    intent = raw.get("intent")
    try:
        normalized = normalize_intent(intent) if isinstance(intent, str) else None
    except (UnicodeError, ValueError):
        return None
    action = raw.get("action")
    exit_code = raw.get("exit_code")
    timestamp = raw.get("timestamp")
    if normalized is None or normalized != intent:
        return None
    if not isinstance(action, str) or ACTION_PATTERN.fullmatch(action) is None:
        return None
    if isinstance(exit_code, bool) or not isinstance(exit_code, int):
        return None
    if not 0 <= exit_code <= 255:
        return None
    if isinstance(timestamp, bool) or not isinstance(timestamp, int) or timestamp < 0:
        return None
    return {
        "intent": normalized,
        "action": action,
        "exit_code": exit_code,
        "timestamp": timestamp,
    }


def load_valid_records(path: Path) -> tuple[list[dict[str, Any]], int]:
    """Load structurally valid records and count ignored corrupt lines."""
    records: list[dict[str, Any]] = []
    corrupt = 0
    if not path.exists():
        return records, corrupt
    with path.open("rb") as stream:
        for line in stream:
            try:
                parsed = json.loads(line.decode("utf-8", "strict"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                corrupt += 1
                continue
            record = canonical_record(parsed)
            if record is None:
                corrupt += 1
            else:
                records.append(record)
    return records, corrupt


def encode_record(record: dict[str, Any]) -> bytes:
    return (
        json.dumps(record, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )


def bounded_suffix(
    records: list[dict[str, Any]], max_records: int, max_bytes: int
) -> list[bytes]:
    """Return the newest contiguous suffix within both retention bounds."""
    kept_reversed: list[bytes] = []
    used = 0
    for record in reversed(records[-max_records:]):
        encoded = encode_record(record)
        if used + len(encoded) > max_bytes:
            break
        kept_reversed.append(encoded)
        used += len(encoded)
    return list(reversed(kept_reversed))


def rotate(arguments: list[str]) -> int:
    if len(arguments) != 5:
        return 2
    source = Path(arguments[0])
    destination = Path(arguments[1])
    max_records = int(arguments[2])
    max_bytes = int(arguments[3])
    new_record = arguments[4]
    records, corrupt = load_valid_records(source)
    if new_record:
        try:
            appended = canonical_record(json.loads(new_record))
        except json.JSONDecodeError:
            appended = None
        if appended is None:
            return 2
        records.append(appended)
    with destination.open("wb") as stream:
        for encoded in bounded_suffix(records, max_records, max_bytes):
            stream.write(encoded)
        stream.flush()
        os.fsync(stream.fileno())
    print(corrupt)
    return 0


def suggest(arguments: list[str]) -> int:
    if len(arguments) != 3:
        return 2
    history = Path(arguments[0])
    intent = normalize_intent(arguments[1])
    trusted_raw = json.loads(arguments[2])
    trusted = {
        action
        for action in trusted_raw
        if isinstance(action, str) and ACTION_PATTERN.fullmatch(action) is not None
    }
    records, _ = load_valid_records(history)
    counts: dict[str, dict[str, int]] = {}
    for record in records:
        if record["intent"] != intent or record["action"] not in trusted:
            continue
        stats = counts.setdefault(
            record["action"], {"success": 0, "failure": 0, "latest_success": -1}
        )
        if record["exit_code"] == 0:
            stats["success"] += 1
            stats["latest_success"] = max(stats["latest_success"], record["timestamp"])
        else:
            stats["failure"] += 1
    if counts:
        print(
            min(
                counts,
                key=lambda action: (
                    -counts[action]["success"],
                    counts[action]["failure"],
                    -counts[action]["latest_success"],
                    action,
                ),
            )
        )
    return 0


def normalize(arguments: list[str]) -> int:
    if len(arguments) != 1:
        return 2
    raw = os.fsencode(arguments[0])
    try:
        decoded = raw.decode("utf-8", "strict")
        normalized = normalize_intent(decoded)
    except (UnicodeDecodeError, UnicodeError, ValueError):
        return 2
    sys.stdout.buffer.write(normalized.encode("utf-8"))
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    command, arguments = sys.argv[1], sys.argv[2:]
    try:
        if command == "normalize":
            return normalize(arguments)
        if command == "rotate":
            return rotate(arguments)
        if command == "suggest":
            return suggest(arguments)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
