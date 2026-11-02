#!/usr/bin/env python3
"""Relay the declared exit status in a previously validated summary."""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, DecimalException
from typing import Any, BinaryIO, NoReturn

MAX_INPUT_BYTES = 64 * 1024
READ_CHUNK_BYTES = 8192
MAX_SCHEMA_ID_CHARS = 128
SCHEMA_ID_RE = re.compile(
    r"(?:D|d)atarim(?:[A-Za-z0-9]+|[._-][A-Za-z0-9]+)(?:[._-][A-Za-z0-9]+)*/v[1-9][0-9]*",
    re.ASCII,
)

USAGE_ERROR = "ERROR: USAGE_ERROR"
INVALID_EXPECTED_SCHEMA = "ERROR: INVALID_EXPECTED_SCHEMA"
INVALID_SUMMARY = "ERROR: INVALID_SUMMARY"


class UsageError(Exception):
    """Raised for malformed command-line arguments without echoing them."""


class InvalidSummary(ValueError):
    """Raised when input is not one acceptable core summary envelope."""


class FixedArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        del message
        raise UsageError


def parse_finite_decimal(token: str) -> Decimal:
    try:
        number = Decimal(token)
    except DecimalException as exc:
        raise InvalidSummary from exc
    if not number.is_finite():
        raise InvalidSummary
    return number


def reject_constant(token: str) -> NoReturn:
    del token
    raise InvalidSummary


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidSummary
        result[key] = value
    return result


def read_bounded(stream: BinaryIO) -> bytes:
    """Consume stdin once, retaining no more than the limit plus one byte."""
    chunks: list[bytes] = []
    total = 0
    while total <= MAX_INPUT_BYTES:
        chunk = stream.read(min(READ_CHUNK_BYTES, MAX_INPUT_BYTES + 1 - total))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > MAX_INPUT_BYTES:
            raise InvalidSummary
    raise InvalidSummary


def expected_schema_is_valid(value: str) -> bool:
    return len(value) <= MAX_SCHEMA_ID_CHARS and SCHEMA_ID_RE.fullmatch(value) is not None


def declared_status(summary: Any, expected_schema: str) -> int:
    if type(summary) is not dict:
        raise InvalidSummary
    if summary.get("schema") != expected_schema:
        raise InvalidSummary

    status = summary.get("exit_code")
    if type(status) is int and status in (0, 1, 2):
        return status
    if isinstance(status, Decimal) and status in (Decimal(0), Decimal(1), Decimal(2)):
        return int(status)
    raise InvalidSummary


def emit_error(label: str) -> None:
    sys.stderr.write(label + "\n")


def build_parser() -> FixedArgumentParser:
    parser = FixedArgumentParser(
        prog="relay-summary-exit",
        description="Relay exit_code from one independently validated summary object.",
        allow_abbrev=False,
    )
    parser.add_argument(
        "--expected-schema",
        required=True,
        help="exact versioned Datarim schema identifier expected in stdin",
    )
    return parser


def main(argv: list[str] | None = None, stdin: BinaryIO | None = None) -> int:
    try:
        args = build_parser().parse_args(argv)
    except UsageError:
        emit_error(USAGE_ERROR)
        return 2

    if not expected_schema_is_valid(args.expected_schema):
        emit_error(INVALID_EXPECTED_SCHEMA)
        return 2

    source = sys.stdin.buffer if stdin is None else stdin
    try:
        raw = read_bounded(source)
        text = raw.decode("utf-8", errors="strict")
        summary = json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_float=parse_finite_decimal,
            parse_constant=reject_constant,
        )
        return declared_status(summary, args.expected_schema)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, InvalidSummary, ValueError, RecursionError):
        emit_error(INVALID_SUMMARY)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
