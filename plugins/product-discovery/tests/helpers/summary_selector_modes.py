#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[4]
checker = repo / "dev-tools" / "check-product-artifact.py"
fixtures = Path(__file__).resolve().parents[1] / "fixtures"
complete = fixtures / "positive" / "complete"
decision_v2 = fixtures / "decision-record-v2"


def run_cmd(args):
    proc = subprocess.run(
        ["python3", str(checker), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc


artifact_summary = run_cmd(
    ["--root", str(complete), "--artifact", "opportunity.md", "--summary-json"]
)
summary_json = json.loads(artifact_summary.stdout.splitlines()[-1])
if summary_json["selection_mode"] != "artifact":
    raise SystemExit("artifact summary selection_mode mismatch")
if summary_json["exit_code"] not in (0, 1):
    raise SystemExit("artifact summary exit_code out of range")

artifact_plain = run_cmd(["--root", str(complete), "--artifact", "opportunity.md"])
if artifact_plain.returncode != artifact_summary.returncode:
    raise SystemExit("artifact summary-json exit diverges from validation exit")

files_summary = run_cmd(
    ["--root", str(decision_v2), "--files", "decision.md", "ledger.md", "--summary-json"]
)
if files_summary.returncode != 0:
    raise SystemExit(files_summary.stderr or "files summary run failed")
files_json = json.loads(files_summary.stdout.splitlines()[-1])
if files_json["selection_mode"] != "files" or files_json["result"] != "PASS":
    raise SystemExit("files summary payload mismatch")
