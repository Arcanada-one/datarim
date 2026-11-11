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
    # R-REQUIRED-CHECKS: required contexts come from branch protection AND from
    # rulesets. A 404 or empty protection answer does not mean "no required
    # checks". CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR (protection.json, rules.json)
    # replaces the live reads so the comparison itself is testable offline.
    import os

    repo = contract.get("repository", "Arcanada-one/datarim")
    branch = contract.get("branch", "main")
    fixture = os.environ.get("CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR")

    def read(name, api_path):
        if fixture:
            return json.loads((Path(fixture) / name).read_text(encoding="utf-8"))
        try:
            return json.loads(subprocess.check_output(["gh", "api", api_path], text=True, stderr=subprocess.PIPE))
        except subprocess.CalledProcessError as exc:
            print(f"ERROR: cannot read {api_path}: {exc.stderr.strip()[:200]}", file=sys.stderr)
            sys.exit(2)

    protection = read("protection.json", f"repos/{repo}/branches/{branch}/protection/required_status_checks")
    rules = read("rules.json", f"repos/{repo}/rules/branches/{branch}")
    sources = {}
    for ctx in protection.get("contexts") or []:
        sources.setdefault(ctx, set()).add("branch_protection")
    for rule in rules:
        if rule.get("type") != "required_status_checks":
            continue
        for item in (rule.get("parameters") or {}).get("required_status_checks") or []:
            sources.setdefault(item["context"], set()).add("ruleset")
    remote = set(sources)
    want = set(contexts)
    missing = sorted(want - remote)
    extra = sorted(remote - want)
    if missing or extra:
        print("ERROR: remote required contexts drifted from contract", file=sys.stderr)
        print("missing_on_remote:", missing, file=sys.stderr)
        print("extra_on_remote:", [(c, sorted(sources[c])) for c in extra], file=sys.stderr)
        sys.exit(1)
    by_source = {}
    for ctx in sources.values():
        key = "+".join(sorted(ctx))
        by_source[key] = by_source.get(key, 0) + 1
    print(
        "required_check_contexts=ok remote_match=true count=%d sources=%s"
        % (len(contexts), json.dumps(by_source, sort_keys=True))
    )
else:
    print(f"required_check_contexts=ok local_contract=true count={len(contexts)}")
sys.exit(0)
PY
