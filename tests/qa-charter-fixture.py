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
            **({"checkpoint_chain": None} if mode == "null-checkpoint-chain" else {}),
            **({"checkpoint_chain": {"required": True}} if mode in {
                "chain", "missing-chain", "stale-checkpoint", "dangling-checkpoint",
                "duplicate-checkpoint", "cyclic-checkpoint", "attempts-only",
            } else {}),
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
    if mode in {"chain", "stale-checkpoint", "dangling-checkpoint", "duplicate-checkpoint", "cyclic-checkpoint"}:
        checkpoint_rows = []
        for index, probe in enumerate(probes):
            observation_hash = digest(probe["observed"].encode("utf-8"))
            if mode == "stale-checkpoint" and index == 0:
                observation_hash = "0" * 64
            checkpoint_rows.append({
                "id": f"checkpoint-{index + 1}",
                "prior_checkpoint_id": None if index == 0 else f"checkpoint-{index}",
                "probe_id": probe["id"],
                "observation_sha256": observation_hash,
                "artifact_sha256": probe["artifact"]["sha256"],
                "hypothesis": f"Synthetic hypothesis {index + 1} predicts the next probe result.",
                "next_probe_id": probes[index + 1]["id"] if index + 1 < len(probes) else None,
            })
        if mode == "dangling-checkpoint":
            checkpoint_rows[0]["next_probe_id"] = "missing-probe"
        if mode == "duplicate-checkpoint":
            checkpoint_rows[1]["id"] = checkpoint_rows[0]["id"]
        if mode == "cyclic-checkpoint":
            checkpoint_rows[0]["prior_checkpoint_id"] = checkpoint_rows[-1]["id"]
        evidence["checkpoint_chains"] = [{
            "behaviour_id": "synthetic-behaviour",
            "checkpoints": checkpoint_rows,
        }]
    if mode == "null-checkpoint-chains":
        evidence["checkpoint_chains"] = None
    if mode == "attempts-only":
        evidence["attempts"] = [{"timestamp": "2026-10-18T12:00:00Z", "probe_id": "returns-result"}]
    (run / "evidence.json").write_text(
        json.dumps(evidence, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    if mode == "mutable":
        (qa / "latest").symlink_to(run.name, target_is_directory=True)


if __name__ == "__main__":
    main()
