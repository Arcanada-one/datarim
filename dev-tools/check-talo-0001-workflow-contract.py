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

CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
EXPECTED_DIGESTS = {
    "preflight": "548acccf9f3dd75687f2984698b2b751eb6c810536b29c480546d1f17bbb9a7b",
    "controller": "960c15f55cbd62e59d8d3858dce1d3d9c21a0166edd94059101c94ed96613f26",
    "publisher": "adc8edc95e02c983bfd0a690dc018c0cec986115cf614444879928936f3b578e",
    "evaluator": "a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a",
    "runner-unit": "929c8f138a839383bd754600fa65c72996b04703ba8050d1714c3ea51a50c67a",
}
EXPECTED_PATHS = {
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
}
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
    paths = (
        trigger.get("pull_request", {}).get("paths")
        if isinstance(trigger, dict)
        else None
    )
    exact(
        set(paths) if isinstance(paths, list) else None,
        EXPECTED_PATHS,
        "projection-paths",
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
        {"contents": "read", "pull-requests": "read", "checks": "write"},
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
        "runs-on": ["self-hosted", "Linux", "X64", "talo-0001-trusted"],
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
    if (
        "python3 /trusted/dev-tools/check-talo-0001-trusted-authority.py"
        not in controller
    ):
        findings.append("missing:trusted-evaluator-command")
    if "TRUSTED_EVALUATOR_SHA256=" not in controller:
        findings.append("missing:trusted-evaluator-digest")
    if "python3 /candidate/dev-tools/check-research-authority-audit.py" in controller:
        findings.append("forbidden:candidate-evaluator")
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
        "NoNewPrivileges=true",
        "ProtectSystem=strict",
        "ProtectHome=true",
        "ReadOnlyPaths=/srv/talo-0001-trusted/knowledge",
        "ReadWritePaths=/srv/talo-0001-trusted/runner",
        "CapabilityBoundingSet=",
    ):
        if value not in runner_unit:
            findings.append(f"missing:runner-unit:{value}")


def main() -> int:
    findings: list[str] = []
    validate_projection(load_workflow(PROJECTION, "projection", findings), findings)
    validate_trusted(load_workflow(TRUSTED, "trusted", findings), findings)
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
