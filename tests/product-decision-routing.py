#!/usr/bin/env python3
"""Synthetic end-to-end route fixtures using the shipped product artifact checker."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "dev-tools/product-decision-route.py"
CHECKER = ROOT / "dev-tools/check-product-artifact.sh"
TASK = "SYN-ROUTE-001"


def sha(raw):
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def write_artifact(path, front, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    body = "---\n" + yaml.safe_dump(front, sort_keys=False, allow_unicode=True).rstrip() + "\n---\n\n## Data\n\n```product-artifact-data\n"
    body += yaml.safe_dump(data, sort_keys=False, allow_unicode=True).rstrip() + "\n```\n"
    path.write_text(body, encoding="utf-8")
    return path.read_bytes()


def make_task(root, decision_data, include_brief=True, scope_hash_override=None):
    bundle = root / "datarim/insights/decisions" / TASK
    task_path = root / "datarim/tasks" / f"{TASK}-task-description.md"
    task_path.parent.mkdir(parents=True, exist_ok=True)
    acceptance = "- Synthetic route is authorized only for its exact bounded scope.\n- Parent criteria remain unchanged.\n"
    task_path.write_text("# Task\n\n## Acceptance Criteria\n" + acceptance + "\n## Scope Advance Records\n", encoding="utf-8")
    decision_front = {
        "schema_version": "product-artifact/2", "id": "artifact:SYN-DECISION-001", "artifact_type": "decision-record",
        "revision": 1, "status": decision_data.pop("_status", "submitted"), "acceptance_state": decision_data.pop("_acceptance", "accepted"),
        "source_digest": None, "supersedes": None,
    }
    decision_data = {
        "question": "Which synthetic route should be selected?",
        "options": [
            {"id": "selected", "description": "Use the selected synthetic route.", "disposition": "selected", "rationale": "Fixture covers the declared outcome."},
            {"id": "deferred", "description": "Defer unrelated behavior.", "disposition": "deferred", "rationale": "Outside the fixture scope."},
        ],
        "selected_option": "selected", "business_outcome": "continue", "strategist_recommendation": "INCOMPLETE",
        "evidence_acceptance": "accepted", "authority_to_act": {"status": "none", "authority_ref": None},
        "evidence_refs": [], "counterevidence_refs": [], "applicable_thresholds": ["Synthetic branch control only."],
        "uncertainty": ["No live user outcome is measured."], "reversal_conditions": ["Revise when the decision inputs change."],
        "owner": "fixture-owner", "scope_delta": "Synthetic route fixture only.", "source_refs": [],
        "provenance": {"recorder": "fixture-author", "recorded_at": "2026-10-14T00:00:00Z", "origin_kind": "synthetic_fixture"},
        **decision_data,
    }
    decision_raw = write_artifact(bundle / "decision-r1.md", decision_front, decision_data)
    decision_ref = {"id": decision_front["id"], "revision": 1, "digest": sha(decision_raw)}
    brief_raw = None
    if include_brief:
        brief_front = {
            "schema_version": "product-artifact/1", "id": "artifact:SYN-BRIEF-001", "artifact_type": "product-brief",
            "revision": 1, "status": "ready_for_delivery", "acceptance_state": "accepted", "source_digest": None, "supersedes": None,
        }
        brief_data = {
            "accepted_intent": "Exercise a synthetic decision route.", "requirements": ["Preserve the exact decision lineage."],
            "risk": ["Synthetic results do not establish live outcomes."], "scope": ["Synthetic route fixture only."], "non_goals": ["No live user action."],
            "hypothesis_refs": [], "input_revisions": [decision_ref], "success_criteria": ["Expected typed route is emitted."],
            "acceptance_owner": "fixture-owner", "downstream_task_ref": None, "source_refs": [],
            "provenance": {"recorder": "fixture-author", "recorded_at": "2026-10-14T00:00:00Z", "origin_kind": "synthetic_fixture"},
        }
        brief_raw = write_artifact(bundle / "product-brief-r1.md", brief_front, brief_data)
    parent_hash = sha((acceptance + "\n").encode())
    if decision_data["business_outcome"] == "continue" and decision_data["authority_to_act"]["status"] == "granted":
        scope_hash = scope_hash_override or parent_hash
        advance = {
            "id": "SYN-SCOPE-001", "status": "authorized", "decision_ref": decision_ref,
            "authorization_ref": decision_data["authority_to_act"]["authority_ref"],
            "authorized_scope": ["Synthetic route fixture only."], "parent_acceptance_contract_sha256": scope_hash,
        }
        with task_path.open("a", encoding="utf-8") as stream:
            stream.write("```json\n" + json.dumps(advance, sort_keys=True, separators=(",", ":")) + "\n```\n")
    return bundle, task_path, decision_front, decision_ref, brief_raw, parent_hash


def run_checker(bundle):
    return subprocess.run(["bash", str(CHECKER), "--root", str(bundle), "--bundle", "."], text=True, capture_output=True)


def route(root, router=ROUTER):
    return subprocess.run(["python3", str(router), "--root", str(root), "--task", TASK], text=True, capture_output=True)


def check_case(name, setup, expected_route, expected_token, verify=None):
    with tempfile.TemporaryDirectory(prefix="d5a-route-") as temp:
        root = Path(temp)
        bundle, task_path, front, decision_ref, brief_raw, parent_hash = setup(root)
        checked = run_checker(bundle)
        assert checked.returncode == 0, f"{name} checker refused fixture: {checked.stdout}{checked.stderr}"
        routed = route(root)
        assert routed.returncode == 0, f"{name} route command failed: {routed.stdout}{routed.stderr}"
        result = json.loads(routed.stdout)
        assert (result["route"], result["token"]) == (expected_route, expected_token), f"{name}: {routed.stdout}"
        if verify:
            verify(result, front, decision_ref, brief_raw, parent_hash)
        print(f"TRANSCRIPT {name}: checker=exit0; route={routed.stdout.strip()}")
        return result


def main():
    def continue_setup(root):
        return make_task(root, {"business_outcome": "continue", "authority_to_act": {"status": "granted", "authority_ref": "AUTH-SYN-001"}})

    def assert_lineage(result, front, decision_ref, brief_raw, parent_hash):
        assert result["decision_ref"] == decision_ref
        assert result["product_brief_ref"]["digest"] == sha(brief_raw)
        assert result["parent_acceptance_contract_sha256"] == parent_hash
        assert result["authorization_ref"] == "AUTH-SYN-001"
        assert result["scope_advance_id"] == "SYN-SCOPE-001"

    check_case("continue", continue_setup, "/dr-prd", "PRODUCT_ROUTE_CONTINUE", assert_lineage)
    check_case("stop", lambda root: make_task(root, {"business_outcome": "stop"}), "/dr-archive", "PRODUCT_ROUTE_STOP")
    check_case("more-evidence", lambda root: make_task(root, {"business_outcome": "more-evidence"}), "/dr-do", "PRODUCT_ROUTE_MORE_EVIDENCE")
    check_case("evidence-rejected", lambda root: make_task(root, {"business_outcome": "continue", "evidence_acceptance": "rejected"}), "/dr-qa", "PRODUCT_ROUTE_EVIDENCE_PENDING")
    check_case("superseded", lambda root: make_task(root, {"business_outcome": "continue", "_status": "superseded"}, include_brief=False), "/dr-do", "PRODUCT_ROUTE_SUPERSEDED")
    check_case("missing-authority", lambda root: make_task(root, {"business_outcome": "continue"}), "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISSING")
    check_case("wrong-parent-contract", lambda root: make_task(root, {"business_outcome": "continue", "authority_to_act": {"status": "granted", "authority_ref": "AUTH-SYN-001"}}, scope_hash_override="sha256:" + "0" * 64), "/dr-status", "PRODUCT_REFUSE_PARENT_CONTRACT_MISMATCH")
    with tempfile.TemporaryDirectory(prefix="d5a-invalid-outcome-") as temp:
        root = Path(temp)
        bundle, *_ = make_task(root, {"business_outcome": "rejected"})
        checked = run_checker(bundle)
        assert checked.returncode == 1 and "E_OUTCOME_INVALID" in checked.stdout
        refused = json.loads(route(root).stdout)
        assert refused["token"] == "PRODUCT_REFUSE_ARTIFACT_INVALID"
        print(f"TRANSCRIPT rejected-is-not-an-outcome: checker=exit{checked.returncode}; route={json.dumps(refused, sort_keys=True)}")

    with tempfile.TemporaryDirectory(prefix="d5a-resume-") as temp:
        root = Path(temp)
        make_task(root, {"business_outcome": "more-evidence"})
        before_interrupt = route(root)
        snapshot = {"stage": "auto", "route_projection": json.loads(before_interrupt.stdout)}
        snapshot_path = root / "datarim/snapshots" / f"{TASK}.snapshot.md"
        snapshot_path.parent.mkdir(parents=True)
        snapshot_path.write_text("---\nstage: auto\n---\n\n```json\n" + json.dumps(snapshot, sort_keys=True) + "\n```\n")
        after_resume = route(root)
        assert json.loads(before_interrupt.stdout)["token"] == "PRODUCT_ROUTE_MORE_EVIDENCE"
        assert json.loads(after_resume.stdout)["token"] == "PRODUCT_ROUTE_MORE_EVIDENCE"
        print(f"TRANSCRIPT auto-interrupt: {before_interrupt.stdout.strip()}")
        print(f"TRANSCRIPT dr-next-resume: snapshot=context-only; fresh-route={after_resume.stdout.strip()}")

    with tempfile.TemporaryDirectory(prefix="d5a-mutant-") as temp:
        root = Path(temp)
        bundle, *_ = make_task(root, {"business_outcome": "stop"})
        checked = run_checker(bundle)
        assert checked.returncode == 0, checked.stdout + checked.stderr
        source = ROUTER.read_text()
        original = '''    if outcome == "stop":\n        result("/dr-archive", TOKENS["stop"], decision_ref=decision_ref)\n        return 0\n'''
        mutant = '''    if outcome == "stop":\n        result("/dr-prd", TOKENS["continue"], decision_ref=decision_ref)\n        return 0\n'''
        assert original in source, "mutation anchor changed"
        mutant_dir = root / "dev-tools"
        mutant_dir.mkdir()
        mutant_path = mutant_dir / "product-decision-route-mutant.py"
        mutant_path.write_text(source.replace(original, mutant, 1))
        shutil.copy(CHECKER, mutant_dir / CHECKER.name)
        shutil.copy(CHECKER.with_suffix(".py"), mutant_dir / CHECKER.with_suffix(".py").name)
        mutated = route(root, mutant_path)
        assert mutated.returncode == 0
        mutant_result = json.loads(mutated.stdout)
        assert (mutant_result["route"], mutant_result["token"]) == ("/dr-prd", "PRODUCT_ROUTE_CONTINUE")
        expected = json.loads(route(root).stdout)
        assert expected["token"] == "PRODUCT_ROUTE_STOP" and expected != mutant_result
        print(f"TRANSCRIPT red-control: expected={expected['token']}; inverted-stop-mutant={mutated.stdout.strip()}; detected=true")


if __name__ == "__main__":
    main()
