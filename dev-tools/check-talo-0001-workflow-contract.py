#!/usr/bin/env python3
"""Fail closed when either TALO-0001 workflow loses its trust boundary."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECTION = ROOT / ".github/workflows/talo-0001-projection-contract.yml"
TRUSTED = ROOT / ".github/workflows/talo-0001-trusted-replay.yml"
CONTROLLER = ROOT / "dev-tools/trusted-talo-0001-replay.sh"
PREFLIGHT = ROOT / "dev-tools/preflight-talo-0001-workflow-run.sh"


def require(text: str, needle: str, label: str, findings: list[str]) -> None:
    if needle not in text:
        findings.append(f"missing:{label}")


def main() -> int:
    findings: list[str] = []
    projection = PROJECTION.read_text(encoding="utf-8")
    trusted = TRUSTED.read_text(encoding="utf-8")
    controller = CONTROLLER.read_text(encoding="utf-8")
    preflight = PREFLIGHT.read_text(encoding="utf-8")
    for needle, label in (
        ("pull_request:", "projection-trigger"),
        ("contents: read", "projection-least-permission"),
        ("persist-credentials: false", "projection-no-credentials"),
        (
            "python3 dev-tools/check-talo-0001-research-projection.py",
            "projection-command",
        ),
    ):
        require(projection, needle, label, findings)
    for needle, label in (
        ("workflow_run:", "trusted-trigger"),
        ("workflows: ['TALO-0001 projection contract']", "trusted-upstream"),
        ("types: [completed]", "trusted-terminal-trigger"),
        ("checks: write", "trusted-check-permission"),
        ("pull-requests: read", "trusted-pr-permission"),
        ("ref: main", "trusted-controller-ref"),
        ("persist-credentials: false", "trusted-no-checkout-credentials"),
        ("secrets.TALOMNIA_KNOWLEDGE_DEPLOY_KEY", "trusted-dedicated-key"),
        ("trusted/dev-tools/trusted-talo-0001-replay.sh", "trusted-controller-command"),
        (
            "trusted/dev-tools/preflight-talo-0001-workflow-run.sh",
            "trusted-preflight-command",
        ),
        ("trusted/dev-tools/publish-talo-0001-check.sh", "trusted-publisher-command"),
    ):
        require(trusted, needle, label, findings)
    if "pull_request_target:" in trusted or "pull_request:" in trusted:
        findings.append("forbidden:trusted-pr-authored-trigger")
    if "secrets." in projection or "contents: write" in projection:
        findings.append("forbidden:projection-privilege")
    checkout = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
    if projection.count(checkout) != 1 or trusted.count(checkout) != 1:
        findings.append("mismatch:pinned-checkout-count")
    if (
        projection.count("persist-credentials: false") != 1
        or trusted.count("persist-credentials: false") != 1
    ):
        findings.append("mismatch:no-credential-checkout-count")
    for needle, label in (
        ("--network none", "sandbox-network-none"),
        ("--read-only", "sandbox-read-only"),
        ("--user 65534:65534", "sandbox-non-root"),
        ("--memory 256m", "sandbox-memory"),
        ("--cpus 1", "sandbox-cpu"),
        ("--pids-limit 64", "sandbox-pids"),
        ("--cap-drop ALL", "sandbox-capabilities"),
        ('rm -f -- "$DEPLOY_KEY"', "credential-removal"),
        (
            "research_authority_audit=MET items=66 candidates=19 external_pins=8",
            "fixed-verdict",
        ),
    ):
        require(controller, needle, label, findings)
    guard_needles = (
        ("conclusion=$(jq -er", "guard-conclusion"),
        ("event=$(jq -er", "guard-event"),
        ("head_repository=$(jq -er", "guard-head-repository"),
        ("pr_count=$(jq -er", "guard-pr-count"),
        ('[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]]', "guard-head-sha"),
        ('[ "$conclusion" != success ]', "guard-success"),
        ('[ "$event" != pull_request ]', "guard-pull-request-event"),
        ('[ "$head_repository" != Arcanada-one/datarim ]', "guard-same-repository"),
        ('[ "$pr_count" -ne 1 ]', "guard-single-pr"),
    )
    preflight_command = trusted.find(
        "trusted/dev-tools/preflight-talo-0001-workflow-run.sh"
    )
    secret_materialization = trusted.find("printf '%s\\n' \"$DEPLOY_KEY\"")
    if (
        preflight_command < 0
        or secret_materialization < 0
        or preflight_command > secret_materialization
    ):
        findings.append("order:preflight-before-secret")
    for needle, label in guard_needles:
        position = preflight.find(needle)
        if position < 0:
            findings.append(f"missing:{label}")
    if findings:
        print("talo_0001_workflow_contract=NOT_MET")
        for finding in findings:
            print(f"finding={finding}")
        return 1
    print("talo_0001_workflow_contract=MET")
    return 0


if __name__ == "__main__":
    sys.exit(main())
