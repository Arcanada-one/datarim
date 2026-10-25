#!/usr/bin/env python3
"""Refuse unexplained FAIL lines in a QA run directory."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


def inside(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    if path == root or root not in path.parents or path.is_symlink():
        raise ValueError(f"unsafe run path: {value}")
    return path


def check(root: Path, manifest: Path) -> None:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("fail_lines"), list):
        raise ValueError("manifest requires fail_lines array")
    cases = data.get("cases", {})
    if not isinstance(cases, dict):
        raise ValueError("cases must be an object")
    observed = set()
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"symlink in run directory: {path.relative_to(root)}")
        if path.suffix not in (".log", ".txt", ".out") or not path.is_file():
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "FAIL" in line:
                observed.add((str(path.relative_to(root)), number))
    explained = set()
    for row in data["fail_lines"]:
        if not isinstance(row, dict):
            raise ValueError("fail_lines entries must be objects")
        key = (row.get("path"), row.get("line"))
        if key in explained or key not in observed:
            raise ValueError(f"duplicate or absent FAIL line: {key}")
        explained.add(key)
        disposition = row.get("disposition")
        if disposition == "failing_case":
            if cases.get(row.get("case_id")) != "fail":
                raise ValueError(f"FAIL line lacks a failing case: {key}")
        elif disposition == "harness_fixed":
            response = inside(root, row.get("response_path", ""))
            reevaluation = inside(root, row.get("reevaluation_path", ""))
            if not response.is_file() or not reevaluation.is_file():
                raise ValueError(f"missing replay evidence: {key}")
            replay = json.loads(reevaluation.read_text(encoding="utf-8"))
            digest = hashlib.sha256(response.read_bytes()).hexdigest()
            if replay.get("response_sha256") != digest or replay.get("result") != "pass":
                raise ValueError(f"replay did not pass the recorded response: {key}")
        else:
            raise ValueError(f"invalid FAIL disposition: {key}")
    if observed != explained:
        raise ValueError(f"orphan FAIL lines: {sorted(observed - explained)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    root = args.run_dir.resolve()
    if not root.is_dir() or not args.manifest.is_file():
        parser.error("run directory and manifest must exist")
    try:
        check(root, args.manifest)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as exc:
        print(f"QA_RUN_FAIL_LINES FAIL: {exc}")
        return 1
    print("QA_RUN_FAIL_LINES PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
