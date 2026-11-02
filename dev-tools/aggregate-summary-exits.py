#!/usr/bin/env python3
"""Aggregate declared exit codes from a bounded array of saved summaries."""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, DecimalException
from typing import Any, BinaryIO, NoReturn

MAX_INPUT_BYTES = 64 * 1024
READ_CHUNK_BYTES = 8192
MAX_SUMMARIES = 256
MAX_SCHEMA_CHARS = 128
SCHEMA_ID_RE = re.compile(r"Datarim[A-Za-z0-9]+/v[1-9][0-9]*", re.ASCII)

OUTPUT_SCHEMA = "DatarimSummaryExitRollup/v1"
REFUSAL_DIAGNOSTIC = "SUMMARY_EXIT_ROLLUP_REFUSED"


class InvalidInput(ValueError):
    """Raised when the bounded input is not an accepted summary array."""


def reject_constant(token: str) -> NoReturn:
    del token
    raise InvalidInput


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidInput
        result[key] = value
    return result


def read_bounded(stream: BinaryIO) -> bytes:
    """Read stdin once, keeping at most the limit and one detection byte."""
    chunks: list[bytes] = []
    total = 0
    while total <= MAX_INPUT_BYTES:
        chunk = stream.read(min(READ_CHUNK_BYTES, MAX_INPUT_BYTES + 1 - total))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > MAX_INPUT_BYTES:
            raise InvalidInput
    raise InvalidInput


def parse_summary_array(raw: bytes) -> list[dict[str, Any]]:
    try:
        text = raw.decode("utf-8", errors="strict")
        value = json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_float=Decimal,
            parse_constant=reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, InvalidInput, ValueError, DecimalException, RecursionError) as exc:
        raise InvalidInput from exc

    if type(value) is not list or len(value) > MAX_SUMMARIES:
        raise InvalidInput
    if any(type(item) is not dict for item in value):
        raise InvalidInput
    return value


def valid_schema_id(value: Any) -> bool:
    return (
        type(value) is str
        and len(value) <= MAX_SCHEMA_CHARS
        and SCHEMA_ID_RE.fullmatch(value) is not None
    )


def declared_exit_code(summary: dict[str, Any]) -> int:
    schema = summary.get("schema")
    if not valid_schema_id(schema):
        raise InvalidInput

    value = summary.get("exit_code")
    if type(value) is int and value in (0, 1, 2):
        return value
    if isinstance(value, Decimal) and value in (Decimal(0), Decimal(1), Decimal(2)):
        return int(value)
    raise InvalidInput


def rollup(summaries: list[dict[str, Any]]) -> tuple[dict[str, Any], int]:
    counts = {"0": 0, "1": 0, "2": 0}
    for summary in summaries:
        counts[str(declared_exit_code(summary))] += 1

    if counts["2"]:
        result = "ERROR"
        exit_code = 2
        diagnostic_codes = ["SUMMARY_ERROR_PRESENT"]
    elif counts["1"]:
        result = "FINDINGS"
        exit_code = 1
        diagnostic_codes = ["SUMMARY_FINDINGS_PRESENT"]
    else:
        result = "CLEAN"
        exit_code = 0
        diagnostic_codes = []

    output = {
        "schema": OUTPUT_SCHEMA,
        "result": result,
        "exit_code": exit_code,
        "diagnostic_codes": diagnostic_codes,
        "summary_count": len(summaries),
        "summary_count_status": "MEASURED",
        "exit_counts": counts,
    }
    return output, exit_code


def refusal_output() -> dict[str, Any]:
    return {
        "schema": OUTPUT_SCHEMA,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": [REFUSAL_DIAGNOSTIC],
        "summary_count": None,
        "summary_count_status": "NOT_MEASURED",
        "exit_counts": None,
    }


def emit(output: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(output, separators=(",", ":"), ensure_ascii=True) + "\n")


def build_parser() -> argparse.ArgumentParser:
    return argparse.ArgumentParser(
        prog="aggregate-summary-exits",
        description="Aggregate declared exit codes from a bounded JSON array on stdin.",
        allow_abbrev=False,
    )


def main(argv: list[str] | None = None, stdin: BinaryIO | None = None) -> int:
    build_parser().parse_args(argv)
    source = sys.stdin.buffer if stdin is None else stdin
    try:
        summaries = parse_summary_array(read_bounded(source))
        output, exit_code = rollup(summaries)
    except (OSError, InvalidInput, ValueError, DecimalException, RecursionError):
        output = refusal_output()
        exit_code = 2
    emit(output)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
