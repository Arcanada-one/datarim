#!/usr/bin/env python3
"""Create synthetic UI/DX evidence for the focused validator suite."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path


STATES = ("loading", "empty", "error", "success", "partial")
PASSES = (
    "getting-started", "api-cli-sdk", "errors", "documentation", "upgrade",
    "development-environment", "community", "measurement",
)
STAGES = ("install", "configure", "first-accepted-result", "recover")
ARTIFACT_REL = "datarim/qa/synthetic/run-20261018T170000Z/evidence.txt"


def evidence(root: Path) -> dict:
    revision = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    artifact_path = root / ARTIFACT_REL
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path.write_bytes(b"Synthetic UI and DX evidence fixture.\n")
    artifact_hash = hashlib.sha256(artifact_path.read_bytes()).hexdigest()

    def evidence_ref(kind: str = "observed") -> dict:
        return {"type": kind, "path": ARTIFACT_REL, "sha256": artifact_hash}

    states = {
        state: {
            "status": "present",
            "trigger": f"Synthetic trigger for {state}",
            "feedback": f"Synthetic feedback for {state}",
            "action": "Continue safely or recover from the displayed result",
            "evidence": evidence_ref(),
            "score": 2,
        }
        for state in STATES
    }
    stages = [
        {
            "stage": stage,
            "status": "present",
            "does": f"Synthetic journey step: {stage}",
            "evidence": evidence_ref(),
            **({"acceptance_signal": "Synthetic result matches the declared expected value"} if stage == "first-accepted-result" else {}),
            **({"recovery_action": "Correct the setting and retry the failed install"} if stage == "recover" else {}),
        }
        for stage in STAGES
    ]
    return {
        "schema": "DatarimUiDxEvidence/v1",
        "source_revision": revision,
        "ui": {
            "applicability": {"status": "applicable"},
            "features": [{
                "id": "synthetic-login",
                "name": "Synthetic login flow",
                "states": states,
                "storyboard": [{
                    "step": "Submit the synthetic form",
                    "does": "Shows the expected synthetic response",
                    "feels": "The next action is clear",
                    "plan_specifies": True,
                    "design_reference": "synthetic/design.md#login",
                    "evidence": evidence_ref(),
                }],
            }],
        },
        "dx": {
            "applicability": {"status": "applicable"},
            "mode": "triage",
            "persona": {
                "role": "Synthetic developer",
                "goal": "Reach a synthetic accepted result",
                "starting_point": "A clean fixture environment",
                "constraints": "No external service or customer data",
            },
            "stages": stages,
            "passes": [{
                "name": name,
                "status": "reviewed",
                "evidence": evidence_ref(),
            } for name in PASSES],
        },
        "inputs": [{"kind": "design-source", "reference": "synthetic/design.md"}],
        "retained_material": [],
    }


def main() -> int:
    if len(sys.argv) != 3:
        return 2
    scenario, root_arg = sys.argv[1:]
    root = Path(root_arg)
    value = evidence(root)
    artifact_ref = value["ui"]["features"][0]["states"]["error"]["evidence"]
    if scenario == "missing-ui-error":
        value["ui"]["features"][0]["states"]["error"] = {
            "status": "missing", "reason": "Synthetic defect: no error feedback",
            "evidence": artifact_ref,
            "score": 0,
        }
    elif scenario == "missing-recovery":
        value["dx"]["stages"][3] = {
            "stage": "recover", "status": "missing",
            "reason": "Synthetic defect: failed install has no recovery path",
            "evidence": artifact_ref,
        }
    elif scenario == "adoption-statistic":
        value["inputs"].append({"kind": "adoption-statistic", "reference": "synthetic/adoption.csv"})
    elif scenario == "designer-binary":
        value["inputs"].append({"kind": "designer-binary", "reference": "synthetic/designer-tool"})
    elif scenario == "unattributed":
        value["retained_material"].append({
            "section": "synthetic-section", "source": "impeccable-derived phrasing",
            "license": "", "notice": "", "modified": True,
        })
    elif scenario == "not-applicable":
        value["ui"] = {"applicability": {"status": "not_applicable", "reason": "Synthetic CLI-only fixture"}, "features": []}
        value["dx"] = {"applicability": {"status": "not_applicable", "reason": "Synthetic non-developer fixture"}}
    elif scenario == "stale":
        value["source_revision"] = "0" * 40
    elif scenario == "artifact-digest-mismatch":
        (root / ARTIFACT_REL).write_bytes(b"Changed synthetic evidence bytes.\n")
    elif scenario != "clean":
        return 2

    out = root / "datarim/qa/synthetic/ui-dx-evidence.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
