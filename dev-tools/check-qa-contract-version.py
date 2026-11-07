#!/usr/bin/env python3
"""Bind a superseding acceptance contract to its current QA charter."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

SUMMARY_SCHEMA = "DatarimQaContractVersionSummary/v1"


def emit_summary(result: str, exit_code: int, version_binding: str, diagnostic_codes: list[str]) -> None:
    print(
        json.dumps(
            {
                "schema": SUMMARY_SCHEMA,
                "result": result,
                "exit_code": exit_code,
                "version_binding": version_binding,
                "diagnostic_codes": diagnostic_codes,
            },
            separators=(",", ":"),
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--charter", type=Path, required=True)
    parser.add_argument(
        "--summary-json",
        action="store_true",
        help="emit a fixed private JSON result for the existing version-binding check",
    )
    args = parser.parse_args()
    phase = "contract_read"
    diagnostic_code = "VALIDATION_REFUSED"
    try:
        contract_text = args.contract.read_text(encoding="utf-8")
        phase = "contract_json"
        contract = json.loads(contract_text)
        phase = "charter_read"
        charter_text = args.charter.read_text(encoding="utf-8")
        blocks = re.findall(r"```qa-charter-json\s*\n(.*?)\n```", charter_text, re.DOTALL)
        if len(blocks) != 1:
            diagnostic_code = "CHARTER_BLOCK_COUNT_INVALID"
            raise ValueError("charter requires exactly one qa-charter-json block")
        phase = "charter_json"
        charter = json.loads(blocks[0])
        phase = "contract_structure"
        version = contract.get("contract_version")
        supersedes = contract.get("supersedes_version")
        if not isinstance(version, str) or not version.strip():
            diagnostic_code = "CONTRACT_VERSION_INVALID"
            raise ValueError("contract_version is required")
        if supersedes is not None and (not isinstance(supersedes, str) or not supersedes.strip()):
            diagnostic_code = "SUPERSEDES_VERSION_INVALID"
            raise ValueError("supersedes_version must name the prior version")
        if supersedes:
            phase = "charter_structure"
            if charter.get("contract_version") != version:
                diagnostic_code = "CHARTER_VERSION_MISMATCH"
                raise ValueError("superseding contract requires a charter at the same version")
    except (OSError, UnicodeError, ValueError, AttributeError) as exc:
        if args.summary_json:
            if isinstance(exc, OSError):
                code = "CONTRACT_READ_FAILED" if phase == "contract_read" else "CHARTER_READ_FAILED"
            elif isinstance(exc, UnicodeError):
                code = "INPUT_ENCODING_INVALID"
            elif isinstance(exc, ValueError):
                code = diagnostic_code
                if phase == "contract_read":
                    code = "CONTRACT_READ_FAILED"
                elif phase == "contract_json":
                    code = "CONTRACT_JSON_INVALID"
                elif phase == "charter_read":
                    code = "CHARTER_READ_FAILED"
                elif phase == "charter_json":
                    code = "CHARTER_JSON_INVALID"
            else:
                code = "STRUCTURE_INVALID"
            emit_summary("FAIL", 1, "NOT_MEASURED", [code])
            return 1
        print(f"QA_CONTRACT_VERSION FAIL: {exc}")
        return 1
    if args.summary_json:
        emit_summary("PASS", 0, "MATCHED" if supersedes else "NOT_REQUIRED", [])
        return 0
    print("QA_CONTRACT_VERSION PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
