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
    "preflight": "548acccf9f3dd75687f2984698b2b751eb6c810536b29c480546d1f17bbb9a7b",
    "controller": "9f7b6a6e8fefa91d2c3d288439acef736d4d1020c9013c1990cf9e79384ef74d",
    "publisher": "adc8edc95e02c983bfd0a690dc018c0cec986115cf614444879928936f3b578e",
    "evaluator": "a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a",
    "runner-unit": "d9b25e4ea33ed2bddad9e5d1fd5a47acedfed852749f0771fb24838f70edc131",
    "provisioner": "09732bb595f7fbc84401cf32772e2d51b6e6e2aa8e0a3bc215ad25ce2d736f85",
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
        {"contents": "read", "checks": "write"},
        "trusted-permissions",
        findings,
    )
    jobs = workflow.get("jobs")
    replay = (
        jobs.get("replay")
        if isinstance(jobs, dict) and set(jobs) == {"replay"}
        else None
    )
    expected_steps = [
        {
            "name": "Check out trusted default-main controller",
            "uses": CHECKOUT,
            "with": {
                "ref": "main",
                "path": "trusted",
                "persist-credentials": False,
            },
        },
        {
            "name": "Validate workflow-run identity before secret materialization",
            "run": 'trusted/dev-tools/preflight-talo-0001-workflow-run.sh "$GITHUB_EVENT_PATH"',
        },
        {
            "name": "Run trusted collection and sandboxed exact-head replay",
            "env": {"GH_TOKEN": "${{ github.token }}"},
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
                "HEAD_SHA": "${{ github.event.workflow_run.head_sha }}",
                "ATTESTATION": "${{ runner.temp }}/talo-0001-attestation.json",
            },
            "run": "trusted/dev-tools/publish-talo-0001-check.sh",
        },
    ]
    expected_job = {
        "name": "talo-0001-trusted-replay-controller",
        "if": EXPECTED_JOB_IF,
        "runs-on": {
            "group": "talo-0001-trusted",
            "labels": ["self-hosted", "Linux", "X64", "talo-0001-trusted"],
        },
        "timeout-minutes": 8,
        "steps": expected_steps,
    }
    exact(replay, expected_job, "trusted-job", findings)


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
        '.AgentId == $runner_id',
        '.PoolId == $group_id',
        '.PoolName == $group',
        '.DisableUpdate == true',
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
        'chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"',
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
    ):
        if value not in provisioner:
            findings.append(f"missing:runner-runtime-contract:{value}")
    if 'sudo -u "$RUNNER_USER" -- tar' in provisioner:
        findings.append("forbidden:runner-private-staging-traversal")
    if '--token "$token"' in provisioner:
        findings.append("forbidden:runner-token-in-argv")
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
        'registration-token" --jq .token',
        '--runnergroup "$GROUP_NAME"',
        'runner=$(wait_for_exact_runner "$id" registered)',
        'harden_runner_payload',
        'install -o root -g root -m 0644',
        'systemctl enable --now "$UNIT_NAME"',
        'systemctl is-active --quiet "$UNIT_NAME"',
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
