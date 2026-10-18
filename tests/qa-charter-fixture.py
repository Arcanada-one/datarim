#!/usr/bin/env python3
"""Create synthetic charter/evidence fixtures for qa-charter-coverage.bats."""
import hashlib
import json
import pathlib
import subprocess
import sys


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    mode, root_text = sys.argv[1:3]
    root = pathlib.Path(root_text)
    qa = root / "datarim/qa/example"
    run = qa / "run-20261018T120000Z"
    run.mkdir(parents=True, exist_ok=True)
    artifact = run / "probe.txt"
    artifact.write_text("synthetic probe evidence\n", encoding="utf-8")
    charter_data = {
        "schema": "DatarimQaCharter/v1",
        "owner": "synthetic-fixture-owner",
        "behaviours": [{
            "id": "synthetic-behaviour",
            "contract": "A synthetic request returns its declared result.",
            "risk": "Incorrect result could be accepted.",
            "entrypoint": "fixture command",
            "isolation": "Temporary synthetic repository only.",
            "exit_condition": "Expected result is observed.",
            "source": "source.txt",
            "commands": ["synthetic-command"],
            "inputs": ["synthetic-input"],
            "surfaces": ["cli"],
            "probes": [
                {"id": "returns-result", "surface": "cli", "required": True,
                 "description": "The command returns the declared result."},
                {"id": "preserves-state", "surface": "cli", "required": True,
                 "description": "The command preserves unrelated state."},
            ],
        }],
    }
    charter_path = qa / "qa-charter.md"
    charter_path.write_text(
        "# Synthetic QA charter fixture\n\n"
        "```qa-charter-json\n"
        + json.dumps(charter_data, sort_keys=True, indent=2)
        + "\n```\n",
        encoding="utf-8",
    )
    if mode == "duplicate-required":
        charter_text = charter_path.read_text(encoding="utf-8").replace(
            '"required": true,',
            '"required": true,\n          "required": false,',
        )
        charter_path.write_text(charter_text, encoding="utf-8")
    revision = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if mode == "stale":
        revision = "0" * len(revision)
    outcomes = ["pass", "pass"]
    if mode == "not-run":
        outcomes[0] = "not run"
    probes = [
        {
            "id": "returns-result",
            "outcome": outcomes[0],
            "observed": "synthetic result observed",
            "command": "synthetic-command",
            "exit_code": 0,
            **({"reason": "synthetic probe intentionally not run"} if outcomes[0] == "not run" else {}),
            "artifact": {"path": "probe.txt", "sha256": digest(artifact.read_bytes())},
        },
        {
            "id": "preserves-state",
            "outcome": outcomes[1],
            "observed": "synthetic state preserved",
            "command": "synthetic-command",
            "exit_code": 0,
            "artifact": {"path": "probe.txt", "sha256": digest(artifact.read_bytes())},
        },
    ]
    if mode == "omit":
        probes.pop()
    if mode == "duplicate-required":
        probes = []
    evidence = {
        "schema": "DatarimQaCharterEvidence/v1",
        "charter_sha256": digest(charter_path.read_bytes()),
        "source_revision": revision,
        "run_id": run.name,
        "captured_at": "2026-10-18T12:00:00Z",
        "probes": probes,
    }
    (run / "evidence.json").write_text(
        json.dumps(evidence, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    if mode == "mutable":
        (qa / "latest").symlink_to(run.name, target_is_directory=True)


if __name__ == "__main__":
    main()
