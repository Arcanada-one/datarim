#!/usr/bin/env python3
"""Deterministic reference analysis for the supplied synthetic fixtures only."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def rejected(reason: str) -> dict[str, Any]:
    return {"status": "rejected", "reason": reason}


def analyze_bundle(payload: dict[str, Any], raw_bytes: bytes | None,
                   protocol_bytes: bytes | None) -> dict[str, Any]:
    """Resolve exact bytes, calculate raw counts, then apply the frozen decision rule."""
    if not payload.get("synthetic"):
        return rejected("only explicitly synthetic fixtures are accepted")
    refs = payload.get("raw_observation_refs")
    if not isinstance(refs, list) or not refs:
        return rejected("no raw observation references")
    if raw_bytes is None or protocol_bytes is None:
        return rejected("raw observations or frozen protocol bytes are unavailable")

    protocol = payload.get("protocol")
    if not isinstance(protocol, dict):
        return rejected("protocol reference is missing")
    if (protocol.get("status") != "protocol_frozen"
            or protocol.get("digest") != "sha256:" + hashlib.sha256(protocol_bytes).hexdigest()):
        return rejected("frozen protocol digest or status does not match supplied bytes")
    try:
        protocol_doc = json.loads(protocol_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return rejected("frozen protocol is not valid JSON")
    if any(protocol.get(key) != protocol_doc.get(key) for key in ("id", "revision", "status")):
        return rejected("protocol identity does not match supplied bytes")

    lines = raw_bytes.splitlines(keepends=True)
    if not lines or any(not line.endswith(b"\n") for line in lines):
        return rejected("raw observation lines must end in LF")
    try:
        rows = [json.loads(line) for line in lines]
    except (UnicodeDecodeError, json.JSONDecodeError):
        return rejected("raw observations are not valid JSONL")
    if rows != payload.get("observations"):
        return rejected("raw observation bytes do not match the supplied rows")
    if any(line != json.dumps(row, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"
           for row, line in zip(rows, lines)):
        return rejected("raw observation lines are not canonical compact key-sorted JSONL")
    if len({row.get("id") for row in rows if isinstance(row, dict)}) != len(rows):
        return rejected("raw observation ids are not unique")

    refs_by_id: dict[str, dict[str, Any]] = {}
    for ref in refs:
        if (not isinstance(ref, dict) or set(ref) != {"id", "revision", "digest"}
                or type(ref.get("revision")) is not int or ref.get("revision") < 1
                or not isinstance(ref.get("id"), str) or not ref["id"].startswith("raw:")
                or ref["id"] in refs_by_id):
            return rejected("raw observation reference is invalid or duplicated")
        refs_by_id[ref["id"]] = ref
    if len(rows) != len(refs_by_id):
        return rejected("raw observation reference count does not match supplied rows")

    expected_refs: set[str] = set()
    for row, line in zip(rows, lines):
        if (not isinstance(row, dict) or set(row) != {"id", "variant", "outcome", "critical_error"}
                or row.get("variant") not in {"A", "B"}
                or type(row.get("outcome")) is not int or row["outcome"] not in {0, 1}
                or type(row.get("critical_error")) is not bool):
            return rejected("raw observation row has an invalid shape")
        ref_id = "raw:" + row["id"]
        expected_refs.add(ref_id)
        ref = refs_by_id.get(ref_id)
        if ref is None or ref.get("digest") != "sha256:" + hashlib.sha256(line).hexdigest():
            return rejected("raw observation digest does not match its exact line")
    if set(refs_by_id) != expected_refs:
        return rejected("raw observation references do not match row ids")

    sample = payload.get("sample_rule") or {}
    decision = payload.get("decision_rule") or {}
    expected_per_variant = sample.get("expected_per_variant")
    if type(expected_per_variant) is not int or expected_per_variant < 1:
        return rejected("frozen sample rule is invalid")
    counts = {}
    for variant in ("A", "B"):
        arm = [row for row in rows if row["variant"] == variant]
        successes = sum(row["outcome"] for row in arm)
        counts[variant] = {
            "successes": successes,
            "failures": len(arm) - successes,
            "missing": max(0, expected_per_variant - len(arm)),
            "observed": len(arm),
            "expected": expected_per_variant,
        }
    expected_total = 2 * expected_per_variant
    received_total = len(rows)
    missing_total = sum(counts[variant]["missing"] for variant in counts)
    if received_total > expected_total or any(counts[v]["observed"] > expected_per_variant for v in counts):
        return rejected("received observations exceed the frozen sample rule")

    complete = missing_total == 0 and received_total == expected_total
    supported = (complete
                 and counts["B"]["successes"] >= decision.get("b_min_successes", expected_total + 1)
                 and counts["A"]["successes"] <= decision.get("a_max_successes", -1)
                 and sum(row["critical_error"] for row in rows)
                     <= decision.get("max_new_critical_errors", -1))
    return {
        "counts": counts,
        "expected_total": expected_total,
        "received_total": received_total,
        "missing_total": missing_total,
        "status": "supported" if supported else "inconclusive",
        "limits": "fixed synthetic guide scenarios only",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--raw")
    parser.add_argument("--protocol")
    args = parser.parse_args()
    try:
        payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
        raw_bytes = Path(args.raw).read_bytes() if args.raw else None
        protocol_bytes = Path(args.protocol).read_bytes() if args.protocol else None
        result = analyze_bundle(payload, raw_bytes, protocol_bytes)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        result = rejected(f"input could not be read: {exc}")
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
