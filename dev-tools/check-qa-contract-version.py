#!/usr/bin/env python3
"""Bind a superseding acceptance contract to its current QA charter."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--charter", type=Path, required=True)
    args = parser.parse_args()
    try:
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        charter_text = args.charter.read_text(encoding="utf-8")
        blocks = re.findall(r"```qa-charter-json\s*\n(.*?)\n```", charter_text, re.DOTALL)
        if len(blocks) != 1:
            raise ValueError("charter requires exactly one qa-charter-json block")
        charter = json.loads(blocks[0])
        version = contract.get("contract_version")
        supersedes = contract.get("supersedes_version")
        if not isinstance(version, str) or not version.strip():
            raise ValueError("contract_version is required")
        if supersedes is not None and (not isinstance(supersedes, str) or not supersedes.strip()):
            raise ValueError("supersedes_version must name the prior version")
        if supersedes and charter.get("contract_version") != version:
            raise ValueError("superseding contract requires a charter at the same version")
    except (OSError, UnicodeError, ValueError, AttributeError) as exc:
        print(f"QA_CONTRACT_VERSION FAIL: {exc}")
        return 1
    print("QA_CONTRACT_VERSION PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
