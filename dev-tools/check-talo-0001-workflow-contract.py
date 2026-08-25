#!/usr/bin/env python3
"""Validate the closed TALO-0001 trusted-replay workflow contract."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path
from typing import Any

import yaml
from yaml.nodes import MappingNode, Node, SequenceNode

ROOT = Path(__file__).resolve().parent.parent
PROJECTION = ROOT / ".github/workflows/dev-tools-lint.yml"
TRUSTED = ROOT / ".github/workflows/talo-0001-trusted-replay.yml"
CONTROLLER = ROOT / "dev-tools/trusted-talo-0001-replay.sh"
PREFLIGHT = ROOT / "dev-tools/preflight-talo-0001-workflow-run.sh"
PUBLISHER = ROOT / "dev-tools/publish-talo-0001-check.sh"
EVALUATOR = ROOT / "dev-tools/check-talo-0001-trusted-authority.py"
RUNNER_UNIT = ROOT / "dev-tools/systemd/talo-0001-trusted-runner.service"
PROVISIONER = ROOT / "dev-tools/provision-talo-0001-trusted-runner.sh"
ACTIONLINT = ROOT / ".github/actionlint.yaml"

CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
EXPECTED_DIGESTS = {
    "preflight": "a18daf69186058ede3916e74423139dea2a7fdee5dd017b1e703160fef4c9784",
    "controller": "a307331a13f738cf34f78f2a3b8de73351263fb8245f4a08220e638832c9c005",
    "publisher": "7313aaa06977fdd274e1f97fc7edf3ba7e9a8f4199e881ab63f70ce05ea69fe3",
    "evaluator": "a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a",
    "runner-unit": "d9b25e4ea33ed2bddad9e5d1fd5a47acedfed852749f0771fb24838f70edc131",
    "provisioner": "95dd8ab3c2d9de0f7e2de56a6bc839b68e6efe8a6aa1fed0143075d69e3c8d13",
}
EXPECTED_PATHS = [
    "commands/**",
    "skills/**",
    "agents/**",
    "documentation/**",
    "CLAUDE.md",
    "README.md",
    "dev-tools/**",
    "datarim/insights/INSIGHTS-TALO-0001.md",
    "datarim/insights/TALO-0001-research-authority-audit.json",
    ".github/workflows/dev-tools-lint.yml",
    ".github/workflows/talo-0001-trusted-replay.yml",
    ".github/actionlint.yaml",
]
EXPECTED_JOB_IF = (
    "github.event.workflow_run.workflow_id == 270931528 && "
    "github.event.workflow_run.name == 'dev-tools-lint' && "
    "github.event.workflow_run.path == '.github/workflows/dev-tools-lint.yml' && "
    "github.event.workflow_run.repository.full_name == 'Arcanada-one/datarim' && "
    "github.event.workflow_run.head_repository.full_name == 'Arcanada-one/datarim' && "
    "github.event.workflow_run.event == 'pull_request' && "
    "github.event.workflow_run.conclusion == 'success' && "
    "github.event.workflow_run.pull_requests[0].head.sha == "
    "github.event.workflow_run.head_sha && "
    "github.event.workflow_run.pull_requests[0].number == 394 && "
    "github.event.workflow_run.pull_requests[0].head.ref == "
    "'research/TALO-0001-frontend-design' && "
    "github.event.workflow_run.pull_requests[0].head.repo.url == "
    "'https://api.github.com/repos/Arcanada-one/datarim' && "
    "github.event.workflow_run.pull_requests[0].base.ref == 'main' && "
    "github.event.workflow_run.pull_requests[0].base.repo.url == "
    "'https://api.github.com/repos/Arcanada-one/datarim' && "
    "github.event.workflow_run.pull_requests[1] == null"
)


def duplicate_keys(node: Node, path: str = "$") -> list[str]:
    findings: list[str] = []
    if isinstance(node, MappingNode):
        seen: set[str] = set()
        for key_node, value_node in node.value:
            key = str(key_node.value)
            if key in seen:
                findings.append(f"duplicate key {path}.{key}")
            seen.add(key)
            findings.extend(duplicate_keys(value_node, f"{path}.{key}"))
    elif isinstance(node, SequenceNode):
        for index, value_node in enumerate(node.value):
            findings.extend(duplicate_keys(value_node, f"{path}[{index}]"))
    return findings


def load_workflow(path: Path, label: str, findings: list[str]) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
        node = yaml.compose(raw, Loader=yaml.SafeLoader)
        if node is None:
            raise ValueError("empty")
        duplicates = duplicate_keys(node)
        if duplicates:
            findings.extend(f"invalid_yaml:{label}:{item}" for item in duplicates)
            return {}
        value = yaml.safe_load(raw)
    except (OSError, UnicodeError, ValueError, yaml.YAMLError) as error:
        findings.append(f"invalid_yaml:{label}:{type(error).__name__}")
        return {}
    if not isinstance(value, dict):
        findings.append(f"invalid_yaml:{label}:root")
        return {}
    return value


def exact(actual: Any, expected: Any, label: str, findings: list[str]) -> None:
    if actual != expected:
        findings.append(f"mismatch:{label}")


def validate_projection(workflow: dict[str, Any], findings: list[str]) -> None:
    exact(
        set(workflow),
        {"name", "on", "permissions", "concurrency", "jobs"},
        "projection-roots",
        findings,
    )
    exact(workflow.get("name"), "dev-tools-lint", "projection-name", findings)
    exact(
        workflow.get("permissions"),
        {"contents": "read"},
        "projection-permissions",
        findings,
    )
    trigger = workflow.get("on")
    exact(
        set(trigger) if isinstance(trigger, dict) else None,
        {"pull_request"},
        "projection-trigger",
        findings,
    )
    pull_request = trigger.get("pull_request") if isinstance(trigger, dict) else None
    exact(
        set(pull_request) if isinstance(pull_request, dict) else None,
        {"paths"},
        "projection-pull-request",
        findings,
    )
    paths = (
        pull_request.get("paths")
        if isinstance(pull_request, dict)
        else None
    )
    exact(
        paths,
        EXPECTED_PATHS,
        "projection-paths",
        findings,
    )
    exact(
        workflow.get("concurrency"),
        {
            "group": "dev-tools-lint-${{ github.ref }}",
            "cancel-in-progress": True,
        },
        "projection-concurrency",
        findings,
    )
    jobs = workflow.get("jobs")
    job = jobs.get("talo-0001-projection") if isinstance(jobs, dict) else None
    expected_job = {
        "name": "talo-0001-projection-contract",
        "runs-on": "ubuntu-latest",
        "timeout-minutes": 2,
        "steps": [
            {"uses": CHECKOUT, "with": {"persist-credentials": False}},
            {
                "name": "Validate public projection only (no raw-evidence claim)",
                "run": "python3 dev-tools/check-talo-0001-research-projection.py --if-present",
            },
        ],
    }
    exact(job, expected_job, "projection-job", findings)


def validate_trusted(workflow: dict[str, Any], findings: list[str]) -> None:
    exact(
        set(workflow),
        {"name", "on", "permissions", "jobs"},
        "trusted-roots",
        findings,
    )
    exact(
        workflow.get("name"),
        "TALO-0001 trusted replay",
        "trusted-name",
        findings,
    )
    exact(
        workflow.get("on"),
        {"workflow_run": {"workflows": ["dev-tools-lint"], "types": ["completed"]}},
        "trusted-trigger",
        findings,
    )
    exact(
        workflow.get("permissions"),
        {},
        "trusted-permissions",
        findings,
    )
    jobs = workflow.get("jobs")
    if isinstance(jobs, dict) and set(jobs) == {"initialize", "replay"}:
        initialize = jobs.get("initialize")
        replay = jobs.get("replay")
    else:
        initialize = None
        replay = None
    expected_steps = [
        {
            "name": "Initialize checkout-independent current-run verdict",
            "id": "initialize-verdict",
            "env": {
                "GH_TOKEN": "${{ github.token }}",
                "HEAD_SHA": "${{ github.event.workflow_run.head_sha }}",
                "BASE_SHA": "${{ github.event.workflow_run.pull_requests[0].base.sha }}",
                "TRUSTED_RUN_ID": "${{ github.run_id }}",
                "TRUSTED_RUN_ATTEMPT": "${{ github.run_attempt }}",
                "TRUSTED_WORKFLOW_SHA": "${{ github.workflow_sha }}",
                "SOURCE_RUN_ID": "${{ github.event.workflow_run.id }}",
                "SOURCE_RUN_ATTEMPT": "${{ github.event.workflow_run.run_attempt }}",
            },
            "run": (
                "set -euo pipefail\n"
                '[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]\n'
                '[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]]\n'
                '[[ "$TRUSTED_WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]]\n'
                '[[ "$TRUSTED_RUN_ID" =~ ^[1-9][0-9]*$ ]]\n'
                '[[ "$TRUSTED_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]]\n'
                '[[ "$SOURCE_RUN_ID" =~ ^[1-9][0-9]*$ ]]\n'
                '[[ "$SOURCE_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]]\n'
                "expected_nonce=$(\n"
                "  printf 'trusted_run_id=%s\\ntrusted_run_attempt=%s\\nworkflow_sha=%s\\nsource_run_id=%s\\nsource_run_attempt=%s\\nhead_sha=%s\\nbase_sha=%s\\n' \\\n"
                '    "$TRUSTED_RUN_ID" "$TRUSTED_RUN_ATTEMPT" "$TRUSTED_WORKFLOW_SHA" \\\n'
                '    "$SOURCE_RUN_ID" "$SOURCE_RUN_ATTEMPT" "$HEAD_SHA" "$BASE_SHA" \\\n'
                "    | sha256sum | cut -d' ' -f1\n"
                ")\n"
                'if [ "$BASE_SHA" != "$TRUSTED_WORKFLOW_SHA" ]; then\n'
                "  response=$(gh api --method POST repos/Arcanada-one/datarim/check-runs \\\n"
                '    -f name=talo-0001-privileged-replay -f head_sha="$HEAD_SHA" \\\n'
                "    -f status=completed -f conclusion=failure \\\n"
                '    -f external_id="$expected_nonce" \\\n'
                "    -f 'output[title]=TALO-0001 trusted replay' \\\n"
                "    -f 'output[summary]=Source run base is not current trusted main.')\n"
                '  jq -e --arg head "$HEAD_SHA" --arg nonce "$expected_nonce" \\\n'
                "    'select(.name == \"talo-0001-privileged-replay\" and .head_sha == $head and .external_id == $nonce and .status == \"completed\" and .conclusion == \"failure\") | .id | select(type == \"number\" and . > 0 and floor == .)' \\\n"
                '    <<<"$response" >/dev/null\n'
                "  check_id=$(jq -er '.id | select(type == \"number\" and . > 0 and floor == .)' \\\n"
                '    <<<"$response")\n'
                "  printf 'check_id=%s\\nexecution_nonce=%s\\ncurrent_base=false\\n' \\\n"
                '    "$check_id" "$expected_nonce" >>"$GITHUB_OUTPUT"\n'
                "  exit 1\n"
                "fi\n"
                "response=$(gh api --method POST repos/Arcanada-one/datarim/check-runs \\\n"
                '  -f name=talo-0001-privileged-replay -f head_sha="$HEAD_SHA" \\\n'
                '  -f status=in_progress -f external_id="$expected_nonce" \\\n'
                "  -f 'output[title]=TALO-0001 trusted replay' \\\n"
                "  -f 'output[summary]=Current trusted replay is pending.')\n"
                'check_id=$(jq -er --arg head "$HEAD_SHA" --arg nonce "$expected_nonce" \\\n'
                "  'select(.name == \"talo-0001-privileged-replay\" and .head_sha == $head and .external_id == $nonce and .status == \"in_progress\") | .id | select(type == \"number\" and . > 0 and floor == .)' \\\n"
                '  <<<"$response")\n'
                "printf 'check_id=%s\\nexecution_nonce=%s\\ncurrent_base=true\\n' \\\n"
                '  "$check_id" "$expected_nonce" >>"$GITHUB_OUTPUT"\n'
                "printf 'head_sha=%s\\nbase_sha=%s\\ntrusted_run_id=%s\\ntrusted_run_attempt=%s\\n' \\\n"
                '  "$HEAD_SHA" "$BASE_SHA" "$TRUSTED_RUN_ID" \\\n'
                '  "$TRUSTED_RUN_ATTEMPT" >>"$GITHUB_OUTPUT"\n'
                "printf 'workflow_sha=%s\\nsource_run_id=%s\\nsource_run_attempt=%s\\n' \\\n"
                '  "$TRUSTED_WORKFLOW_SHA" "$SOURCE_RUN_ID" \\\n'
                '  "$SOURCE_RUN_ATTEMPT" >>"$GITHUB_OUTPUT"\n'
            ),
        },
        {
            "name": "Check out trusted default-main controller",
            "id": "trusted-checkout",
            "uses": CHECKOUT,
            "with": {
                "ref": "${{ needs.initialize.outputs.workflow_sha }}",
                "path": "trusted",
                "persist-credentials": False,
            },
        },
        {
            "name": "Validate workflow-run identity before secret materialization",
            "env": {
                "TALO_TRUSTED_WORKFLOW_SHA": "${{ needs.initialize.outputs.workflow_sha }}",
            },
            "run": 'trusted/dev-tools/preflight-talo-0001-workflow-run.sh "$GITHUB_EVENT_PATH"',
        },
        {
            "name": "Run trusted collection and sandboxed exact-head replay",
            "env": {
                "GH_TOKEN": "${{ github.token }}",
                "TALO_TRUSTED_RUN_ID": "${{ needs.initialize.outputs.trusted_run_id }}",
                "TALO_TRUSTED_RUN_ATTEMPT": "${{ needs.initialize.outputs.trusted_run_attempt }}",
                "TALO_TRUSTED_WORKFLOW_SHA": "${{ needs.initialize.outputs.workflow_sha }}",
                "TALO_SOURCE_RUN_ID": "${{ needs.initialize.outputs.source_run_id }}",
                "TALO_SOURCE_RUN_ATTEMPT": "${{ needs.initialize.outputs.source_run_attempt }}",
                "TALO_BASE_SHA": "${{ needs.initialize.outputs.base_sha }}",
                "TALO_EXECUTION_NONCE": "${{ needs.initialize.outputs.execution_nonce }}",
            },
            "run": (
                "trusted/dev-tools/trusted-talo-0001-replay.sh \\\n"
                '  --event "$GITHUB_EVENT_PATH" \\\n'
                '  --candidate "$RUNNER_TEMP/candidate" \\\n'
                '  --output "$RUNNER_TEMP/talo-0001-attestation.json"\n'
            ),
        },
        {
            "name": "Publish fixed candidate-head verdict",
            "if": "always()",
            "env": {
                "GH_TOKEN": "${{ github.token }}",
                "HEAD_SHA": "${{ needs.initialize.outputs.head_sha }}",
                "BASE_SHA": "${{ needs.initialize.outputs.base_sha }}",
                "TRUSTED_RUN_ID": "${{ needs.initialize.outputs.trusted_run_id }}",
                "TRUSTED_RUN_ATTEMPT": "${{ needs.initialize.outputs.trusted_run_attempt }}",
                "TRUSTED_WORKFLOW_SHA": "${{ needs.initialize.outputs.workflow_sha }}",
                "SOURCE_RUN_ID": "${{ needs.initialize.outputs.source_run_id }}",
                "SOURCE_RUN_ATTEMPT": "${{ needs.initialize.outputs.source_run_attempt }}",
                "CHECK_RUN_ID": "${{ needs.initialize.outputs.check_id }}",
                "EXPECTED_EXECUTION_NONCE": "${{ needs.initialize.outputs.execution_nonce }}",
                "TRUSTED_CHECKOUT_OUTCOME": "${{ steps.trusted-checkout.outcome }}",
                "ATTESTATION": "${{ runner.temp }}/talo-0001-attestation.json",
            },
            "run": (
                "set -euo pipefail\n"
                "publisher=trusted/dev-tools/publish-talo-0001-check.sh\n"
                'if [ "$TRUSTED_CHECKOUT_OUTCOME" = success ] \\\n'
                '  && [ -f "$publisher" ] && [ ! -L "$publisher" ]; then\n'
                '  exec "$publisher"\n'
                "fi\n"
                "expected_nonce=$(\n"
                "  printf 'trusted_run_id=%s\\ntrusted_run_attempt=%s\\nworkflow_sha=%s\\nsource_run_id=%s\\nsource_run_attempt=%s\\nhead_sha=%s\\nbase_sha=%s\\n' \\\n"
                '    "$TRUSTED_RUN_ID" "$TRUSTED_RUN_ATTEMPT" "$TRUSTED_WORKFLOW_SHA" \\\n'
                '    "$SOURCE_RUN_ID" "$SOURCE_RUN_ATTEMPT" "$HEAD_SHA" "$BASE_SHA" \\\n'
                "    | sha256sum | cut -d' ' -f1\n"
                ")\n"
                '[ "$expected_nonce" = "$EXPECTED_EXECUTION_NONCE" ]\n'
                '[[ "$CHECK_RUN_ID" =~ ^[1-9][0-9]*$ ]]\n'
                'response=$(gh api "repos/Arcanada-one/datarim/check-runs/$CHECK_RUN_ID")\n'
                'jq -e --argjson id "$CHECK_RUN_ID" --arg head "$HEAD_SHA" \\\n'
                '  --arg nonce "$expected_nonce" \\\n'
                "  'select(.id == $id and .name == \"talo-0001-privileged-replay\" and .head_sha == $head and .external_id == $nonce and .status == \"in_progress\")' \\\n"
                '  <<<"$response" >/dev/null\n'
                "gh api --method PATCH \\\n"
                '  "repos/Arcanada-one/datarim/check-runs/$CHECK_RUN_ID" \\\n'
                "  -f status=completed -f conclusion=failure \\\n"
                "  -f 'output[title]=TALO-0001 trusted replay' \\\n"
                "  -f 'output[summary]=Trusted controller checkout failed.' >/dev/null\n"
                "exit 1\n"
            ),
        },
    ]
    expected_initialize = {
        "name": "talo-0001-current-verdict-initializer",
        "if": EXPECTED_JOB_IF,
        "runs-on": "ubuntu-latest",
        "permissions": {"checks": "write"},
        "timeout-minutes": 2,
        "outputs": {
            "check_id": "${{ steps.initialize-verdict.outputs.check_id }}",
            "execution_nonce": "${{ steps.initialize-verdict.outputs.execution_nonce }}",
            "current_base": "${{ steps.initialize-verdict.outputs.current_base }}",
            "head_sha": "${{ steps.initialize-verdict.outputs.head_sha }}",
            "base_sha": "${{ steps.initialize-verdict.outputs.base_sha }}",
            "trusted_run_id": "${{ steps.initialize-verdict.outputs.trusted_run_id }}",
            "trusted_run_attempt": "${{ steps.initialize-verdict.outputs.trusted_run_attempt }}",
            "workflow_sha": "${{ steps.initialize-verdict.outputs.workflow_sha }}",
            "source_run_id": "${{ steps.initialize-verdict.outputs.source_run_id }}",
            "source_run_attempt": "${{ steps.initialize-verdict.outputs.source_run_attempt }}",
        },
        "steps": [expected_steps[0]],
    }
    expected_replay = {
        "name": "talo-0001-trusted-replay-controller",
        "needs": ["initialize"],
        "if": (
            "needs.initialize.result == 'success' && "
            "needs.initialize.outputs.current_base == 'true' && "
            "needs.initialize.outputs.base_sha == "
            "needs.initialize.outputs.workflow_sha"
        ),
        "runs-on": {
            "group": "talo-0001-trusted",
            "labels": ["self-hosted", "Linux", "X64", "talo-0001-trusted"],
        },
        "permissions": {"contents": "read", "checks": "write"},
        "timeout-minutes": 8,
        "steps": expected_steps[1:],
    }
    exact(initialize, expected_initialize, "trusted-initializer-job", findings)
    exact(replay, expected_replay, "trusted-replay-job", findings)


def validate_code(findings: list[str]) -> None:
    files = {
        "preflight": PREFLIGHT,
        "controller": CONTROLLER,
        "publisher": PUBLISHER,
        "evaluator": EVALUATOR,
        "runner-unit": RUNNER_UNIT,
        "provisioner": PROVISIONER,
    }
    texts: dict[str, str] = {}
    for label, path in files.items():
        try:
            content = path.read_bytes()
            texts[label] = content.decode("utf-8")
        except (OSError, UnicodeError):
            findings.append(f"missing:{label}")
            continue
        if hashlib.sha256(content).hexdigest() != EXPECTED_DIGESTS[label]:
            findings.append(f"digest_mismatch:{label}")
    controller = texts.get("controller", "")
    preflight = texts.get("preflight", "")
    publisher = texts.get("publisher", "")
    runner_unit = texts.get("runner-unit", "")
    provisioner = texts.get("provisioner", "")
    if (
        "python3 /trusted/dev-tools/check-talo-0001-trusted-authority.py"
        not in controller
    ):
        findings.append("missing:trusted-evaluator-command")
    if "TRUSTED_EVALUATOR_SHA256=" not in controller:
        findings.append("missing:trusted-evaluator-digest")
    if "python3 /candidate/dev-tools/check-research-authority-audit.py" in controller:
        findings.append("forbidden:candidate-evaluator")
    if 'cmp -s -- "$expected" "$result"' not in controller:
        findings.append("missing:exact-validator-output-comparison")
    if "grep -Fqx" in controller:
        findings.append("forbidden:partial-validator-output-comparison")
    if "del(" in controller:
        findings.append("forbidden:cardinality-changing-mutant")
    for value in (
        '.mapping_source_git_blob)="0000000000000000000000000000000000000000"',
        '.revision_id=="tal-role-design-lead@r4") | .path)',
        '.source_id=="S29") | .git_blob)',
        '.id=="TALO-0032-planning-envelope") | .evidence_path)',
        '.body_sha256)="0000000000000000000000000000000000000000000000000000000000000000"',
        '.task_id="TALO-9999"',
        '.knowledge_snapshot="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
        "research_authority_audit=NOT_MET\\nfinding=",
        "for mutant in mapping candidate external derived comment task snapshot",
    ):
        if value not in controller:
            findings.append(f"missing:sealed-mutant-contract:{value}")
    for value in (
        "--network none",
        "--read-only",
        '--user "$sandbox_uid:$sandbox_gid"',
        "--pids-limit 64",
        'sandbox_uid=$(id -u)',
        '[ "$sandbox_uid" -ne 0 ]',
        '-c safe.directory="$KNOWLEDGE_ROOT"',
    ):
        if value not in controller:
            findings.append(f"missing:sandbox:{value}")
    for value in (
        "materialize_candidate_blob()",
        'candidate_materialized=$(realpath -m "$scratch/candidate")',
        '[ "$mode" != 100644 ]',
        'GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" ls-tree',
        'GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" cat-file blob',
        '-v "$candidate_materialized:/candidate:ro"',
        "candidate_validator_object_sha256",
        "manifest_object_sha256",
        ': >"$OUTPUT"',
        'controller_commit=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$TRUSTED_ROOT" rev-parse HEAD)',
        'execution_nonce_sha256=',
        'attestation_tmp=$(mktemp "${OUTPUT}.tmp.XXXXXXXX")',
        'mv -f -- "$attestation_tmp" "$OUTPUT"',
        '[ "$TALO_BASE_SHA" = "$TALO_TRUSTED_WORKFLOW_SHA" ]',
        '[ "$execution_nonce_sha256" = "$TALO_EXECUTION_NONCE" ]',
    ):
        if value not in controller:
            findings.append(f"missing:candidate-object-contract:{value}")
    for value in (
        "candidate_validator_object_sha256",
        "manifest_object_sha256",
        "expected_nonce=",
        'trusted_run_id == $trusted_run_id',
        'source_run_id == $source_run_id',
        '.base_sha == $base',
        '.controller_commit == $controller',
        '[ ! -L "$ATTESTATION" ]',
        '[ "$attestation_mode" = 600 ]',
        '[ "$BASE_SHA" = "$TRUSTED_WORKFLOW_SHA" ]',
        '[ "$expected_nonce" = "$EXPECTED_EXECUTION_NONCE" ]',
    ):
        if value not in publisher:
            findings.append(f"missing:candidate-object-contract:{value}")
    if '[ "$pr_base_sha" != "$trusted_workflow_sha" ]' not in preflight:
        findings.append("missing:preflight-current-main-binding")
    for value in ("candidate_validator_sha256", "manifest_sha256"):
        if value in controller or value in publisher:
            findings.append("forbidden:worktree-candidate-digest-field")
    if 'git -C "$CANDIDATE" checkout' in controller:
        findings.append("forbidden:candidate-worktree-checkout")
    for value in (
        'sha256sum -- "$candidate_validator"',
        'sha256sum -- "$manifest"',
    ):
        if value in controller:
            findings.append("forbidden:candidate-worktree-content-digest")
    for value in (
        "User=talo-replay",
        "Group=talo-replay",
        "ExecStart=/srv/talo-0001-trusted/runner/bin/Runner.Listener run",
        "NoNewPrivileges=true",
        "ProtectSystem=strict",
        "ProtectHome=true",
        "ReadOnlyPaths=/srv/talo-0001-trusted/knowledge",
        "ReadWritePaths=/srv/talo-0001-trusted/runner",
        "CapabilityBoundingSet=",
    ):
        if value not in runner_unit:
            findings.append(f"missing:runner-unit:{value}")
    for value in (
        "GROUP_NAME=talo-0001-trusted",
        "REPOSITORY_ID=1207050134",
        "WORKFLOW_PATH=.github/workflows/talo-0001-trusted-replay.yml",
        'SELECTED_WORKFLOW="$REPOSITORY/$WORKFLOW_PATH@refs/heads/main"',
        '.visibility == "selected"',
        ".default == false",
        ".allows_public_repositories == true",
        ".restricted_to_workflows == true",
        ".selected_workflows == [$workflow]",
        ".total_count == 1",
        ".repositories[0].id == $repository_id",
        '--runnergroup "$GROUP_NAME"',
    ):
        if value not in provisioner:
            findings.append(f"missing:runner-group-contract:{value}")
    for value in (
        "($document.total_count == 1)",
        "(($document.runners | length) == 1)",
        '($runner.name == $name)',
        '($runner.busy == false)',
        '(([$runner.labels[].name] | sort) == $labels)',
        'settings["AgentId"] == runner_id',
        'settings["PoolId"] == group_id',
        'settings["PoolName"] == group_name',
        'settings["DisableUpdate"] is True',
        'RUNNER_VERSION=2.336.0',
        'RUNNER_ARCHIVE_URL=https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz',
        'RUNNER_ARCHIVE_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d',
        'RUNNER_CONFIG_SHA256=4ad01727c3f29a0b6473d625412af6bdefc6c077763a6410f359c764fc0b3ae8',
        'RUNNER_SCRIPT_SHA256=b39d7e0ca921a3189f7fe4e0a2f686b46719d4ccc2647f156f14407ec4517e8f',
        'RUNNER_LISTENER_SHA256=b73c247aa9f0b4198aeb00ae924b7b137c0a717e5dc1066919a80fa4876fdda4',
        'RUNNER_WORKER_SHA256=a23441ed55e5e967ecfb7b9467310693ea73e429a97596ebdc979745cbcdba15',
        'RUNNER_PAYLOAD_TREE_SHA256=802a94df6d2aee3e458620b5a1175f8646f195092081d3285b8b0dd33c8cc8f6',
        'RUNNER_VERIFY_ATTEMPTS=10',
        'RUNNER_VERIFY_INTERVAL_SECONDS=2',
        'RUNNER_DELETE_ATTEMPTS=3',
        'workflow|$WORKFLOW_PATH',
        'provisioner|dev-tools/provision-talo-0001-trusted-runner.sh',
        'runner-unit|dev-tools/systemd/$UNIT_NAME',
        "--disableupdate",
        'chown -R root:root "$RUNNER_DIR/$path"',
        'chmod -R a-w "$RUNNER_DIR/$path"',
        'verify_runner_payload_tree',
        'install -d -o root -g root -m 0755 "$RUNNER_DIR"',
        'if ! tar --extract --gzip --file "$archive" --directory "$RUNNER_DIR"',
        'systemctl disable --now "$UNIT_NAME"',
        'systemctl stop "$UNIT_NAME"',
        'systemctl is-enabled "$UNIT_NAME"',
        'systemctl is-active "$UNIT_NAME"',
        'rollback_new_registration',
        'remove_remote_new_registration',
        'if api --method DELETE',
        '"orgs/$ORG/actions/runners/$cleanup_runner_id"',
        '[ "$consecutive" -ge 3 ]',
        'rm -f -- "$RUNNER_DIR/.runner"',
        'abort_runner_transaction',
        'fresh_registration=true',
        'pre_registration_empty=true',
        'expected_id=${known_runner_id:-null}',
        'local_registration_absent',
        'bind_pre_reconcile_roster',
        'ACTIONS_RUNNER_INPUT_TOKEN="$token"',
        'sudo --preserve-env=ACTIONS_RUNNER_INPUT_TOKEN',
        'https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/CommandSettings.cs',
        'sha256:937f6552579f7d1eeb0a6d0201586781eb3e2e5ea2ab3878429076560e0cab08',
        'https://github.com/actions/runner/blob/v2.336.0/src/Runner.Common/ConfigurationStore.cs',
        'sha256:5eca29c4f3ce56861680058dbc5e64ec7222421bdb7281f1d502717a235c56a9',
        'https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/Configuration/ConfigurationManager.cs',
        'sha256:beb6d17709f931808b71b8210ee170951a99fac2342110b3600fb8a1b46d740c',
        'https://github.com/actions/runner/blob/v2.336.0/src/Runner.Common/CredentialData.cs',
        'sha256:495cac8f884cf458ecb186820aaac0211f0fd1090015ad1cdbb9f17f314e2de1',
        'https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/Configuration/IRSAKeyManager.cs',
        'sha256:8176f9a5885eb100aa1dec7f5a3222b6e646684e090ff2eb8c2b235fad69bf96',
        'validate_registration_identity_files',
        'os.O_RDONLY | os.O_NOFOLLOW',
        'settings["UseV2Flow"] is True',
        'settings["UseRunnerAdminFlow"] is True',
        'strict_url(settings["ServerUrl"], "tenant")',
        'strict_url(settings["ServerUrlV2"], "broker")',
        'strict_url(data["authorizationUrl"], "authorization")',
        'verify_registration_identity_seal',
        'write_registration_identity_seal',
        '.talo-registration-seal',
        'RUNNER_HOME=/srv/talo-0001-trusted',
        'PROC_ROOT=/proc',
        'verify_runner_account',
        'assert_runner_user_quiescent',
        'verify_started_runner_process',
        '--property=MainPID',
        '--property=ControlGroup',
        '"$PROC_ROOT/$main_pid/exe"',
        '"$PROC_ROOT/$main_pid/status"',
        '"$PROC_ROOT/$main_pid/cgroup"',
        'verify_runner_payload_ownership',
        'harden_executable_payload',
        'open_registration_directory',
        'seal_registration_directory',
        'seal_interrupted_registration_directory',
        'chmod 3775 "$RUNNER_DIR"',
        '[ "$(stat -c \'%u:%g:%a\' "$RUNNER_DIR")" = 0:0:755 ]',
    ):
        if value not in provisioner:
            findings.append(f"missing:runner-runtime-contract:{value}")
    if 'sudo -u "$RUNNER_USER" -- tar' in provisioner:
        findings.append("forbidden:runner-private-staging-traversal")
    if '--token "$token"' in provisioner:
        findings.append("forbidden:runner-token-in-argv")
    if 'chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"' in provisioner:
        findings.append("forbidden:runner-owned-executable-payload")
    if provisioner.count("verify_runner_payload_ownership") != 5:
        findings.append("mismatch:runner-preexec-revalidation-cardinality")
    if provisioner.count("assert_runner_user_quiescent") != 6:
        findings.append("mismatch:runner-quiescence-cardinality")
    if provisioner.count("verify_started_runner_process") != 2:
        findings.append("mismatch:runner-post-start-identity-cardinality")
    try:
        ensure_group = provisioner.split("ensure_group() {", 1)[1].split(
            "\n}", 1
        )[0]
        registration = provisioner.split("register_and_start() {", 1)[1].split(
            "\n}", 1
        )[0]
    except IndexError:
        ensure_group = ""
        registration = ""
        findings.append("missing:registration-function")
    ordered_reconciliation = (
        "verify_trusted_main_workflow",
        "id=$(group_id)",
        "stop_and_disable_runner_service",
        "seal_interrupted_registration_directory",
        "verify_runner_account",
        "assert_runner_user_quiescent",
        'bind_pre_reconcile_roster "$id"',
        'reconcile_group "$id"',
    )
    positions = [ensure_group.find(value) for value in ordered_reconciliation]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        findings.append("mismatch:group-reconciliation-safety-order")
    ordered_registration = (
        'id=$(ensure_group)',
        'verify_group "$id"',
        'group_has_no_runners "$id"',
        'if [ "$install_payload" = true ]',
        'ensure_runner_payload',
        'pre_registration_empty=true',
        'verify_runner_account',
        'assert_runner_user_quiescent',
        'verify_runner_payload_ownership',
        'registration-token" --jq .token',
        'runner executable identity changed before configuration',
        'open_registration_directory',
        '--runnergroup "$GROUP_NAME"',
        'seal_registration_directory',
        'lock_registration_identity_files',
        'runner=$(wait_for_exact_runner "$id" registered)',
        'harden_runner_payload',
        'install -o root -g root -m 0644',
        'systemctl daemon-reload',
        'runner account boundary changed before service start',
        'runner identity is not quiescent before service start',
        'systemctl enable --now "$UNIT_NAME"',
        'systemctl is-active --quiet "$UNIT_NAME"',
        'verify_started_runner_process',
        'runner=$(wait_for_exact_runner "$id" online "$runner_id")',
        'local runner identity changed after start',
    )
    positions = [registration.find(value) for value in ordered_registration]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        findings.append("mismatch:registration-safety-order")


def main() -> int:
    findings: list[str] = []
    validate_projection(load_workflow(PROJECTION, "projection", findings), findings)
    validate_trusted(load_workflow(TRUSTED, "trusted", findings), findings)
    exact(
        load_workflow(ACTIONLINT, "actionlint", findings),
        {"self-hosted-runner": {"labels": ["talo-0001-trusted"]}},
        "actionlint-labels",
        findings,
    )
    validate_code(findings)
    if findings:
        print("talo_0001_workflow_contract=NOT_MET")
        for finding in dict.fromkeys(findings):
            print(f"finding={finding}")
        return 1
    print("talo_0001_workflow_contract=MET")
    return 0


if __name__ == "__main__":
    sys.exit(main())
