#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    CHECKER="$ROOT/dev-tools/check-talo-0001-workflow-contract.py"
    FIXTURE="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FIXTURE/dev-tools/systemd" "$FIXTURE/.github/workflows"
    cp "$CHECKER" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/preflight-talo-0001-workflow-run.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/publish-talo-0001-check.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/check-talo-0001-trusted-authority.py" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/systemd/talo-0001-trusted-runner.service" \
        "$FIXTURE/dev-tools/systemd/"
    cp "$ROOT/.github/workflows/dev-tools-lint.yml" \
        "$FIXTURE/.github/workflows/"
    cp "$ROOT/.github/workflows/talo-0001-trusted-replay.yml" \
        "$FIXTURE/.github/workflows/"
}

run_check() {
    run python3 "$FIXTURE/dev-tools/check-talo-0001-workflow-contract.py"
}

@test "trusted and projection workflow contract is MET" {
    run_check
    [ "$status" -eq 0 ] && [[ "$output" == *'talo_0001_workflow_contract=MET'* ]]
}

@test "projection no-op mutation is rejected" {
    sed -i 's|python3 dev-tools/check-talo-0001-research-projection.py --if-present|true|' \
        "$FIXTURE/.github/workflows/dev-tools-lint.yml"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:projection-job'* ]]
}

@test "trusted controller no-op and PR trigger mutations are rejected" {
    sed -i 's#trusted/dev-tools/trusted-talo-0001-replay.sh#true#; s/workflow_run:/pull_request_target:/' \
        "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:trusted-trigger'* ]] \
        && [[ "$output" == *'mismatch:trusted-job'* ]]
}

@test "each trusted pre-secret identity guard is load-bearing" {
    local controller="$FIXTURE/dev-tools/preflight-talo-0001-workflow-run.sh"
    local original="$BATS_TEST_TMPDIR/controller.original"
    cp "$controller" "$original"
    while IFS='|' read -r needle label; do
        cp "$original" "$controller"
        python3 - "$controller" "$needle" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
assert sys.argv[2] in text
path.write_text(text.replace(sys.argv[2], "REMOVED", 1), encoding="utf-8")
PY
        run_check
        [ "$status" -eq 1 ] \
            && [[ "$output" == *'digest_mismatch:preflight'* ]]
    done <<'GUARDS'
conclusion=$(jq -er|guard-conclusion
event=$(jq -er|guard-event
head_repository=$(jq -er|guard-head-repository
repository=$(jq -er|guard-repository
workflow_id=$(jq -er|guard-workflow-id
workflow_name=$(jq -er|guard-workflow-name
workflow_path=$(jq -er|guard-workflow-path
pr_head_sha=$(jq -er|guard-pr-head-sha
pr_number=$(jq -er|guard-pr-number
pr_head_ref=$(jq -er|guard-pr-head-ref
pr_head_repository=$(jq -er|guard-pr-head-repository
pr_base_ref=$(jq -er|guard-pr-base-ref
pr_base_repository=$(jq -er|guard-pr-base-repository
pr_count=$(jq -er|guard-pr-count
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]]|guard-head-sha
[ "$conclusion" != success ]|guard-success
[ "$event" != pull_request ]|guard-pull-request-event
[ "$head_repository" != Arcanada-one/datarim ]|guard-same-repository
[ "$repository" != Arcanada-one/datarim ]|guard-workflow-repository
[ "$workflow_id" -ne 270931528 ]|guard-workflow-id-value
[ "$workflow_name" != dev-tools-lint ]|guard-workflow-name-value
[ "$workflow_path" != .github/workflows/dev-tools-lint.yml ]|guard-workflow-path-value
[ "$head_sha" != "$pr_head_sha" ]|guard-workflow-pr-head-match
[ "$pr_number" -ne 394 ]|guard-pr-number-value
[ "$pr_head_ref" != research/TALO-0001-frontend-design ]|guard-pr-head-ref-value
[ "$pr_head_repository" != Arcanada-one/datarim ]|guard-pr-head-repository-value
[ "$pr_base_ref" != main ]|guard-pr-base-main
[ "$pr_base_repository" != Arcanada-one/datarim ]|guard-pr-base-repository-value
[ "$pr_count" -ne 1 ]|guard-single-pr
GUARDS
}

@test "workflow YAML is strict and command comments cannot satisfy the contract" {
    local trusted="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    python3 - "$trusted" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("checks: write", "checks: write\n  contents: write", 1)
text = text.replace(
    "trusted/dev-tools/trusted-talo-0001-replay.sh",
    "true # trusted/dev-tools/trusted-talo-0001-replay.sh",
    1,
)
text += "\npermissions:\n  contents: read\n"
path.write_text(text, encoding="utf-8")
PY
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'invalid_yaml:trusted:duplicate key'* ]]
}

@test "all TALO trust files are load-bearing projection paths" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    local original="$BATS_TEST_TMPDIR/dev-tools-lint.original"
    cp "$workflow" "$original"
    while IFS= read -r path; do
        cp "$original" "$workflow"
        python3 - "$workflow" "$path" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1])
needle = f"      - '{sys.argv[2]}'\n"
text = workflow.read_text(encoding="utf-8")
assert needle in text
workflow.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY
        run_check
        [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:projection-paths'* ]]
    done <<'PATHS'
datarim/insights/INSIGHTS-TALO-0001.md
datarim/insights/TALO-0001-research-authority-audit.json
dev-tools/**
.github/workflows/dev-tools-lint.yml
.github/workflows/talo-0001-trusted-replay.yml
PATHS
}

@test "candidate evaluator substitution and authority digest weakening are rejected" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i \
        's#/trusted/dev-tools/check-talo-0001-trusted-authority.py#/candidate/dev-tools/check-research-authority-audit.py#' \
        "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:trusted-evaluator-command'* ]]

    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$controller"
    sed -i '/TRUSTED_EVALUATOR_SHA256=/d' "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:trusted-evaluator-digest'* ]]
}

@test "dedicated runner identity, fixed paths, and hardening are load-bearing" {
    local unit="$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service"
    sed -i \
        -e 's/User=talo-replay/User=ci-isolated/' \
        -e '/NoNewPrivileges=true/d' \
        -e '/ReadOnlyPaths=\/srv\/talo-0001-trusted\/knowledge/d' \
        "$unit"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'digest_mismatch:runner-unit'* ]]
}

@test "preflight accepts only the exact upstream workflow and PR tuple" {
    local preflight="$ROOT/dev-tools/preflight-talo-0001-workflow-run.sh"
    local event="$BATS_TEST_TMPDIR/event.json"
    python3 - "$event" <<'PY'
import json
from pathlib import Path
import sys

head = "d1fa4f7ada7fc782b6055f4cacc41092848d1400"
payload = {"workflow_run": {
    "workflow_id": 270931528,
    "name": "dev-tools-lint",
    "path": ".github/workflows/dev-tools-lint.yml",
    "event": "pull_request",
    "conclusion": "success",
    "head_sha": head,
    "head_repository": {"full_name": "Arcanada-one/datarim"},
    "repository": {"full_name": "Arcanada-one/datarim"},
    "pull_requests": [{
        "number": 394,
        "head": {"sha": head, "ref": "research/TALO-0001-frontend-design", "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
        "base": {"ref": "main", "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
    }],
}}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
    run "$preflight" "$event"
    [ "$status" -eq 0 ]

    while IFS='|' read -r expression value; do
        python3 - "$event" "$expression" "$value" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
target = data
parts = sys.argv[2].split(".")
for part in parts[:-1]:
    target = target[int(part)] if part.isdigit() else target[part]
target[parts[-1]] = json.loads(sys.argv[3])
path.write_text(json.dumps(data), encoding="utf-8")
PY
        run "$preflight" "$event"
        [ "$status" -ne 0 ]
        python3 - "$event" "$expression" <<'PY'
import json
from pathlib import Path
import sys

# Restore from the code-owned baseline by reversing the single hostile value.
defaults = {
    "workflow_run.workflow_id": 270931528,
    "workflow_run.name": "dev-tools-lint",
    "workflow_run.path": ".github/workflows/dev-tools-lint.yml",
    "workflow_run.event": "pull_request",
    "workflow_run.conclusion": "success",
    "workflow_run.head_repository.full_name": "Arcanada-one/datarim",
    "workflow_run.repository.full_name": "Arcanada-one/datarim",
    "workflow_run.pull_requests.0.head.sha": "d1fa4f7ada7fc782b6055f4cacc41092848d1400",
    "workflow_run.pull_requests.0.number": 394,
    "workflow_run.pull_requests.0.head.ref": "research/TALO-0001-frontend-design",
    "workflow_run.pull_requests.0.head.repo.url": "https://api.github.com/repos/Arcanada-one/datarim",
    "workflow_run.pull_requests.0.base.ref": "main",
    "workflow_run.pull_requests.0.base.repo.url": "https://api.github.com/repos/Arcanada-one/datarim",
}
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
target = data
parts = sys.argv[2].split(".")
for part in parts[:-1]:
    target = target[int(part)] if part.isdigit() else target[part]
target[parts[-1]] = defaults[sys.argv[2]]
path.write_text(json.dumps(data), encoding="utf-8")
PY
    done <<'MUTANTS'
workflow_run.workflow_id|999
workflow_run.name|"other"
workflow_run.path|".github/workflows/other.yml"
workflow_run.event|"push"
workflow_run.conclusion|"failure"
workflow_run.head_repository.full_name|"attacker/fork"
workflow_run.repository.full_name|"attacker/fork"
workflow_run.pull_requests.0.head.sha|"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
workflow_run.pull_requests.0.number|999
workflow_run.pull_requests.0.head.ref|"attacker-branch"
workflow_run.pull_requests.0.head.repo.url|"https://api.github.com/repos/attacker/fork"
workflow_run.pull_requests.0.base.ref|"feature"
workflow_run.pull_requests.0.base.repo.url|"https://api.github.com/repos/attacker/fork"
MUTANTS
}
