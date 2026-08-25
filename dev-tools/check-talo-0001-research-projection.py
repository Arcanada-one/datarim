#!/usr/bin/env python3
"""Validate public TALO-0001 projections without claiming raw-evidence replay."""

import json
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "dev-tools/check-research-authority-audit.py"
MANIFEST = ROOT / "datarim/insights/TALO-0001-research-authority-audit.json"
INSIGHTS = ROOT / "datarim/insights/INSIGHTS-TALO-0001.md"
MAX_INPUT_BYTES = 16 * 1024 * 1024


def bounded_text(path: Path) -> str:
    with path.open("rb") as handle:
        content = handle.read(MAX_INPUT_BYTES + 1)
    if len(content) > MAX_INPUT_BYTES:
        raise ValueError(f"input_resource_limit:{path.name}")
    return content.decode("utf-8")


def main() -> int:
    if "--if-present" in sys.argv[1:] and not all(
        path.is_file() for path in (VALIDATOR, MANIFEST, INSIGHTS)
    ):
        print("research_authority_projection=SKIPPED reason=inputs_absent")
        print("raw_evidence_replay=NOT_CLAIMED")
        return 0
    try:
        namespace = runpy.run_path(str(VALIDATOR))
        manifest = json.loads(bounded_text(MANIFEST))
        insights = bounded_text(INSIGHTS)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        print("research_authority_projection=ERROR")
        return 2
    findings: list[str] = []
    if not isinstance(manifest, dict):
        findings.append("manifest_invalid")
    else:
        namespace["validate_closed_profile"](manifest, "TALO-0001", findings)
        namespace["validate_source_register_profile"](insights, "TALO-0001", findings)
        if manifest.get("schema_version") != "datarim.research-authority-audit/v1":
            findings.append("schema_version_invalid")
        if manifest.get("declared_language") != "en":
            findings.append("declared_language_invalid")
    if findings:
        print("research_authority_projection=NOT_MET")
        for finding in dict.fromkeys(findings):
            print(f"finding={finding}")
        return 1
    print("research_authority_projection=MET items=66 candidates=19 external_pins=8")
    print("raw_evidence_replay=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
