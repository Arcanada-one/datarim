#!/usr/bin/env bash
# Verify the committed required-check contract against branch protection (optional)
# and against workflow job names that must keep reporting for PR events.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${ROOT}/tests/required-check-contexts.json"
BATS_WF="${ROOT}/.github/workflows/bats.yml"
MODE="${1:-local}"

[ -f "$CONTRACT" ] || { echo "ERROR: missing $CONTRACT" >&2; exit 2; }

python3 - "$CONTRACT" "$BATS_WF" "$MODE" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

contract_path, bats_wf, mode = sys.argv[1:4]
contract = json.loads(Path(contract_path).read_text(encoding="utf-8"))
contexts = contract["contexts"]
if len(contexts) != 19:
    print(f"ERROR: contract must list exactly 19 contexts, found {len(contexts)}", file=sys.stderr)
    sys.exit(1)
if len(contexts) != len(set(contexts)):
    print("ERROR: duplicate contexts in contract", file=sys.stderr)
    sys.exit(1)

text = Path(bats_wf).read_text(encoding="utf-8")
# Discovery shards must keep the required names shard N/8.
if "shard: [1, 2, 3, 4, 5, 6, 7, 8]" not in text and "name: shard ${{ matrix.shard }}/8" not in text:
    print("ERROR: bats.yml must keep required shard N/8 job names", file=sys.stderr)
    sys.exit(1)
if "fetch-depth: 0" not in text:
    print("ERROR: bats.yml must keep full history (fetch-depth: 0) where ancestry is checked", file=sys.stderr)
    sys.exit(1)
# Skipped jobs must not hide missing required results: fail-fast false on shard + CD matrices.
if text.count("fail-fast: false") < 2:
    print("ERROR: bats.yml must keep fail-fast: false on sharded matrices", file=sys.stderr)
    sys.exit(1)

if mode == "remote":
    raw = subprocess.check_output(
        [
            "gh",
            "api",
            "repos/Arcanada-one/datarim/branches/main/protection/required_status_checks",
        ],
        text=True,
    )
    remote = json.loads(raw).get("contexts") or []
    if remote != contexts:
        print("ERROR: remote required contexts drifted from contract", file=sys.stderr)
        print("contract:", contexts, file=sys.stderr)
        print("remote:", remote, file=sys.stderr)
        sys.exit(1)
    print(f"required_check_contexts=ok remote_match=true count={len(contexts)}")
else:
    print(f"required_check_contexts=ok local_contract=true count={len(contexts)}")
sys.exit(0)
PY
