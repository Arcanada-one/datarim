#!/usr/bin/env python3
"""Synthetic routing, immutability, snapshot replay, and mutation controls."""
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE_FIXTURE = ROOT / "plugins/product-discovery/tests/fixtures/decision-record-v2"
ROUTER = ROOT / "dev-tools/product-decision-route.py"
CHECKER = ROOT / "dev-tools/check-product-artifact.sh"
WRITER = ROOT / "dev-tools/snapshot-writer-wrapper.sh"
SNAPSHOT_VALIDATOR = ROOT / "dev-tools/check-stage-snapshot-on-exit.sh"
TASK = "SYNROUTE-0001"


def sha(raw):
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def write_artifact(path, front, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    body = "---\n" + yaml.safe_dump(front, sort_keys=False, allow_unicode=True).rstrip() + "\n---\n\n## Data\n\n```product-artifact-data\n"
    body += yaml.safe_dump(data, sort_keys=False, allow_unicode=True).rstrip() + "\n```\n"
    path.write_text(body, encoding="utf-8")
    return path.read_bytes()


def decision_data(outcome="continue", authority=None, evidence="accepted", front_acceptance="accepted", status="submitted"):
    data = {
        "question": "Which synthetic route should be selected?",
        "options": [
            {"id": "selected", "description": "Use the selected synthetic route.", "disposition": "selected", "rationale": "Fixture covers the declared outcome."},
            {"id": "deferred", "description": "Defer unrelated behavior.", "disposition": "deferred", "rationale": "Outside the fixture scope."},
        ],
        "selected_option": "selected", "business_outcome": outcome, "strategist_recommendation": "INCOMPLETE",
        "evidence_acceptance": evidence, "authority_to_act": authority or {"status": "none", "authority_ref": None},
        "evidence_refs": [], "counterevidence_refs": [], "applicable_thresholds": ["Synthetic branch control only."],
        "uncertainty": ["No live user outcome is measured."], "reversal_conditions": ["Revise when decision inputs change."],
        "owner": "fixture-owner", "scope_delta": "Synthetic route fixture only.", "source_refs": [],
        "provenance": {"recorder": "fixture-author", "recorded_at": "2026-10-14T00:00:00Z", "origin_kind": "synthetic_fixture"},
    }
    return data, status, front_acceptance


def make_task(root, latest, *, history=(), include_brief=True, brief_revision=None,
              brief_acceptance="accepted", brief_status="ready_for_delivery", advance_revision=None,
              advance_auth="AUTH-SYN-001", advance_scope=None, parent_hash_override=None, broken_chain=False,
              force_advance=False):
    bundle = root / "datarim/insights/decisions" / TASK
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EVIDENCE_FIXTURE / "ledger.md", bundle / "ledger.md")
    shutil.copytree(EVIDENCE_FIXTURE / "fixtures", bundle / "fixtures")
    task_path = root / "datarim/tasks" / f"{TASK}-task-description.md"
    task_path.parent.mkdir(parents=True, exist_ok=True)
    acceptance = "- Synthetic route is authorized only for its exact bounded scope.\n- Parent criteria remain unchanged.\n"
    task_path.write_text("# Task\n\n## Acceptance Criteria\n" + acceptance + "\n## Scope Advance Records\n", encoding="utf-8")
    history_specs = [*history, latest]
    ledger_text = (EVIDENCE_FIXTURE / "ledger.md").read_text(encoding="utf-8")
    ledger_data = yaml.safe_load(re.search(r"```product-artifact-data\n(.*?)\n```", ledger_text, re.S).group(1))
    decision_refs = {}
    decision_fronts = {}
    previous = None
    for revision, spec in enumerate(history_specs, 1):
        data, status, front_acceptance = spec
        data["evidence_refs"] = [ledger_data["entries"][0]["raw_ref"]]
        data["counterevidence_refs"] = [ledger_data["entries"][1]["raw_ref"]]
        supersedes = None
        if previous:
            previous_raw, previous_front = previous
            supersedes = {"id": previous_front["id"], "revision": revision - 1, "digest": sha(previous_raw)}
            if broken_chain and revision == len(history_specs):
                supersedes["digest"] = "sha256:" + "0" * 64
        front = {
            "schema_version": "product-artifact/2", "id": "artifact:SYN-DECISION-001", "artifact_type": "decision-record",
            "revision": revision, "status": status, "acceptance_state": front_acceptance,
            "source_digest": None, "supersedes": supersedes,
        }
        raw = write_artifact(bundle / f"decision-r{revision}.md", front, data)
        decision_refs[revision] = {"id": front["id"], "revision": revision, "digest": sha(raw)}
        decision_fronts[revision] = front
        previous = (raw, front)
    current_revision = len(history_specs)
    current_ref = decision_refs[current_revision]
    brief_raw = None
    if include_brief:
        brief_decision_revision = brief_revision or current_revision
        brief_front = {
            "schema_version": "product-artifact/1", "id": "artifact:SYN-BRIEF-001", "artifact_type": "product-brief",
            "revision": 1, "status": brief_status, "acceptance_state": brief_acceptance, "source_digest": None, "supersedes": None,
        }
        brief_data = {
            "accepted_intent": "Exercise a synthetic decision route.", "requirements": ["Preserve the exact decision lineage."],
            "risk": ["Synthetic results do not establish live outcomes."], "scope": ["Synthetic route fixture only."], "non_goals": ["No live user action."],
            "hypothesis_refs": [], "input_revisions": [decision_refs[brief_decision_revision]], "success_criteria": ["Expected typed route is emitted."],
            "acceptance_owner": "fixture-owner", "downstream_task_ref": None, "source_refs": [],
            "provenance": {"recorder": "fixture-author", "recorded_at": "2026-10-14T00:00:00Z", "origin_kind": "synthetic_fixture"},
        }
        brief_raw = write_artifact(bundle / "product-brief-r1.md", brief_front, brief_data)
    parent_hash = sha((acceptance + "\n").encode())
    advance_revision = current_revision if advance_revision is None else advance_revision
    for revision, (data, _, _) in enumerate(history_specs, 1):
        authority = data.get("authority_to_act", {})
        if (authority.get("status") != "granted" and not (force_advance and revision == advance_revision)) or revision != advance_revision:
            continue
        advance = {
            "id": f"SYN-SCOPE-{revision:03d}", "status": "authorized", "decision_ref": decision_refs[revision],
            "authorization_ref": advance_auth if advance_auth is not None else authority.get("authority_ref"),
            "authorized_scope": advance_scope if advance_scope is not None else ["Synthetic route fixture only."],
            "parent_acceptance_contract_sha256": parent_hash_override or parent_hash,
        }
        with task_path.open("a", encoding="utf-8") as stream:
            stream.write("```json\n" + json.dumps(advance, sort_keys=True, separators=(",", ":")) + "\n```\n")
    return bundle, task_path, decision_fronts[current_revision], current_ref, brief_raw, parent_hash


def run_checker(bundle):
    return subprocess.run(["bash", str(CHECKER), "--root", str(bundle), "--bundle", "."], text=True, capture_output=True)


def route(root, router=ROUTER):
    return subprocess.run(["python3", str(router), "--root", str(root), "--task", TASK], text=True, capture_output=True)


def case(name, setup, expected_route, expected_token, verify=None, allow_error=False):
    with tempfile.TemporaryDirectory(prefix="d5a-route-") as temp:
        root = Path(temp)
        bundle, _, front, decision_ref, brief_raw, parent_hash = setup(root)
        current_record = bundle / f"decision-r{decision_ref['revision']}.md"
        latest_data = yaml.safe_load(re.search(r"```product-artifact-data\n(.*?)\n```", current_record.read_text(), re.S).group(1))
        checker_result = run_checker(bundle)
        assert checker_result.returncode in (0, 1), checker_result.stderr
        routed = route(root)
        assert (routed.returncode == 1 if allow_error else routed.returncode == 0), f"{name} failed: {routed.stdout}{routed.stderr}"
        result = json.loads(routed.stdout)
        assert (result["route"], result["token"]) == (expected_route, expected_token), f"{name}: {routed.stdout}"
        if expected_token == "PRODUCT_ROUTE_STOP":
            assert result["research_status"] == "accepted" and result["delivery_work_created"] is False
        if expected_token == "PRODUCT_ROUTE_MORE_EVIDENCE":
            assert result["research_status"] == "incomplete" and result["delivery_work_created"] is False
        if verify:
            verify(result, front, decision_ref, brief_raw, parent_hash)
        print(f"TRANSCRIPT {name}: checker=exit{checker_result.returncode}; route={routed.stdout.strip()}")
        return result


def make_simple(root, outcome, **kwargs):
    return make_task(root, decision_data(outcome, **kwargs))


def assert_continue_lineage(result, front, decision_ref, brief_raw, parent_hash):
    assert result["decision_ref"] == decision_ref
    assert result["product_brief_ref"]["digest"] == sha(brief_raw)
    assert result["parent_acceptance_contract_sha256"] == parent_hash
    assert result["authorization_ref"] == "AUTH-SYN-001"
    assert result["scope_advance_id"] == "SYN-SCOPE-001"


def run_resume_case(outcome):
    with tempfile.TemporaryDirectory(prefix="d5a-resume-") as temp:
        root = Path(temp)
        prior = decision_data("continue", {"status": "granted", "authority_ref": "AUTH-SYN-001"})
        latest = decision_data(outcome)
        _, _, front, decision_ref, _, _ = make_task(root, latest, history=[prior], include_brief=False)
        before = json.loads(route(root).stdout)
        projection = {"decision_ref": before["decision_ref"], "supersedes": before["supersedes"], "token": before["token"],
                      "research_status": before["research_status"], "delivery_work_created": before["delivery_work_created"]}
        body = root / "route-projection.txt"
        body.write_text("Research route projection\nROUTE_PROJECTION_JSON: " + json.dumps(projection, sort_keys=True) + "\n", encoding="utf-8")
        snapshot = subprocess.run([
            "bash", str(WRITER), "--root", str(root), "--task", TASK, "--stage", "auto", "--command", "/dr-auto",
            "--captured-by", "agent", "--recommended-next", "/dr-do", "--body-file", str(body),
            "--captured-at", "2026-10-14T00:00:00Z",
        ], text=True, capture_output=True)
        assert snapshot.returncode == 0, snapshot.stderr
        validation = subprocess.run(["bash", str(SNAPSHOT_VALIDATOR), "--validate-frontmatter", "--task", TASK, "--root", str(root)], text=True, capture_output=True)
        assert validation.returncode == 0, validation.stderr
        snapshot_text = (root / "datarim/snapshots" / f"{TASK}.snapshot.md").read_text()
        saved = json.loads(re.search(r"(?m)^ROUTE_PROJECTION_JSON: (.+)$", snapshot_text).group(1))
        after = json.loads(route(root).stdout)
        assert saved["decision_ref"] == before["decision_ref"] == after["decision_ref"] == decision_ref
        assert saved["supersedes"] == before["supersedes"] == after["supersedes"] == front["supersedes"]
        assert before["token"] == after["token"]
        assert saved["research_status"] == before["research_status"] == after["research_status"]
        assert saved["delivery_work_created"] is False and after["delivery_work_created"] is False
        if outcome == "stop":
            assert before["research_status"] == "accepted" and before["route"] == "/dr-archive"
        else:
            assert before["research_status"] == "incomplete" and before["route"] == "/dr-do"
        print(f"TRANSCRIPT auto-interrupt-{outcome}: writer=exit0; validator=exit0; route={json.dumps(before, sort_keys=True)}")
        print(f"TRANSCRIPT dr-next-resume-{outcome}: fresh-route={json.dumps(after, sort_keys=True)}; decision_ref-and-supersedes-identical=true; research_status={after['research_status']}; delivery_work_created=false")


def sandbox_prd_run(name, latest, *, history=(), brief_revision=None, include_brief=True):
    with tempfile.TemporaryDirectory(prefix="sandbox-dr-prd-") as temp:
        root = Path(temp)
        bundle, _, _, _, _, _ = make_task(root, latest, history=history, include_brief=include_brief, brief_revision=brief_revision)
        task_file = root / "datarim/tasks" / f"{TASK}-task-description.md"
        with task_file.open("a", encoding="utf-8") as stream:
            stream.write("\n## Profile\nprofile: product-discovery\n")
        active_plugins = root / "datarim/enabled-plugins.md"
        active_plugins.parent.mkdir(parents=True, exist_ok=True)
        active_plugins.write_text("## Active\n- id: product-discovery\n", encoding="utf-8")
        runtime = root / "runtime"
        entry = runtime / "skills/product-discovery/product-framing/SKILL.md"
        entry.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "plugins/product-discovery/skills/product-framing/SKILL.md", entry)
        profile = subprocess.run(["bash", str(ROOT / "dev-tools/read-product-profile.sh"), "--root", str(root), "--task", TASK, "--runtime", str(runtime)], text=True, capture_output=True)
        assert profile.returncode == 0 and profile.stdout.strip() == "profile_active", profile.stdout + profile.stderr
        mapping = {"bindings": [{"workspace": str(root), "required_host": "runner-primary", "host_aliases": ["runner-alias"], "tailscale_ip": "100.64.0.7", "ssh_user": "fixture", "default_agent": "claude", "allowed_agents": ["claude"], "space": "synthetic"}]}
        map_path = root / "execution-hosts.yml"
        map_path.write_text(yaml.safe_dump(mapping, sort_keys=False), encoding="utf-8")
        map_hash = sha(map_path.read_bytes())
        lib = ROOT / "dev-tools/lib/execution-host.sh"
        host = subprocess.run(["bash", "-c", 'source "$1"; EH_TEST_HOSTNAME=runner-alias eh_decision "$2" "$3"; rc=$?; printf "%s %s" "$rc" "$EH_STATE"', "route-test", str(lib), str(root), str(map_path)], text=True, capture_output=True)
        assert host.returncode == 0 and host.stdout.strip() == "0 on-host", host.stdout + host.stderr
        foreign = subprocess.run(["bash", "-c", 'source "$1"; EH_TEST_HOSTNAME=foreign-host eh_decision "$2" "$3"; rc=$?; printf "%s %s" "$rc" "$EH_STATE"', "route-test", str(lib), str(root), str(map_path)], text=True, capture_output=True)
        assert foreign.returncode == 0 and foreign.stdout.strip() == "10 off-host", foreign.stdout + foreign.stderr
        routed = route(root)
        assert routed.returncode == 0, routed.stdout + routed.stderr
        result = json.loads(routed.stdout)
        prd_path = root / "datarim/prd" / f"PRD-{TASK}.md"
        discovery = None
        if result["token"] == "PRODUCT_ROUTE_CONTINUE":
            decision = result["decision_ref"]
            brief = result["product_brief_ref"]
            discovery = (f"DecisionRecord {decision['id']} revision {decision['revision']} digest {decision['digest']}; "
                         f"ProductBrief digest {brief['digest']}; parent acceptance {result['parent_acceptance_contract_sha256']}")
            assert decision["digest"] in discovery and brief["digest"] in discovery
            prd_path.parent.mkdir(parents=True, exist_ok=True)
            prd_path.write_text("## Discovery\n\n" + discovery + "\n", encoding="utf-8")
            assert decision["digest"] in prd_path.read_text()
        else:
            assert result["token"] != "PRODUCT_ROUTE_CONTINUE" and not prd_path.exists()
        assert sha(map_path.read_bytes()) == map_hash
        print(f"TRANSCRIPT sandbox-dr-prd-{name}: profile_active; host=0/on-host; foreign-host=10/off-host; host-hash-before={map_hash}; host-hash-after={sha(map_path.read_bytes())}; stable=true; agent-produced-prd=NOT_MEASURED; route={result['token']}; " + (f"PRD discovery includes decision digest {result['decision_ref']['digest']}" if discovery else "no PRD or delivery text"))
        return result


def main():
    granted = {"status": "granted", "authority_ref": "AUTH-SYN-001"}
    case("continue", lambda root: make_simple(root, "continue", authority=granted), "/dr-prd", "PRODUCT_ROUTE_CONTINUE", assert_continue_lineage)
    case("stop", lambda root: make_simple(root, "stop"), "/dr-archive", "PRODUCT_ROUTE_STOP")
    case("more-evidence", lambda root: make_simple(root, "more-evidence"), "/dr-do", "PRODUCT_ROUTE_MORE_EVIDENCE")
    case("evidence-rejected", lambda root: make_simple(root, "continue", evidence="rejected"), "/dr-qa", "PRODUCT_ROUTE_EVIDENCE_PENDING")
    case("decision-not-accepted", lambda root: make_simple(root, "continue", front_acceptance="submitted"), "/dr-qa", "PRODUCT_ROUTE_EVIDENCE_PENDING")
    case("brief-not-accepted", lambda root: make_task(root, decision_data("continue", authority=granted), brief_acceptance="submitted"), "/dr-status", "PRODUCT_REFUSE_PRODUCT_BRIEF_MISSING")
    case("missing-authority-with-orphan-advance", lambda root: make_task(root, decision_data("continue"), force_advance=True), "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISSING")
    case("authorization-ref-mismatch", lambda root: make_task(root, decision_data("continue", authority=granted), advance_auth="AUTH-OTHER"), "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH")
    case("authorization-scope-mismatch", lambda root: make_task(root, decision_data("continue", authority=granted), advance_scope=["unrelated scope"]), "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH")
    case("wrong-parent-contract", lambda root: make_task(root, decision_data("continue", authority=granted), parent_hash_override="sha256:" + "0" * 64), "/dr-status", "PRODUCT_REFUSE_PARENT_CONTRACT_MISMATCH")

    prior = decision_data("continue", authority=granted)
    def assert_revision_two(result, front, ref, brief, parent):
        assert result["decision_ref"] == ref and result["decision_ref"]["revision"] == 2
    case("r2-stop-over-authorized-r1", lambda root: make_task(root, decision_data("stop"), history=[prior]), "/dr-archive", "PRODUCT_ROUTE_STOP", assert_revision_two)
    case("r2-continue-with-r1-brief", lambda root: make_task(root, decision_data("continue", authority=granted), history=[prior], brief_revision=1, advance_revision=1), "/dr-do", "PRODUCT_ROUTE_SUPERSEDED")
    case("r2-continue-with-r1-advance", lambda root: make_task(root, decision_data("continue", authority=granted), history=[prior], advance_revision=1), "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH")
    case("latest-status-superseded", lambda root: make_simple(root, "continue", authority=granted, status="superseded"), "/dr-do", "PRODUCT_ROUTE_SUPERSEDED")

    def duplicate_advance_ids(root):
        made = make_task(root, decision_data("continue", authority=granted))
        task_path = made[1]
        record = json.loads(re.findall(r"```json\s*\n(.*?)\n```", task_path.read_text(), re.S)[-1])
        with task_path.open("a", encoding="utf-8") as stream:
            stream.write("```json\n" + json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n```\n")
        return made
    case("duplicate-scope-advance-id", duplicate_advance_ids, "/dr-status", "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH")

    def checker_pair_refusal(root):
        made = make_task(root, decision_data("continue", authority=granted))
        (made[0] / "fixtures/counterevidence.txt").write_text("mutated counterevidence\n", encoding="utf-8")
        return made
    case("checker-pair-refusal", checker_pair_refusal, "/dr-status", "PRODUCT_REFUSE_ARTIFACT_INVALID")

    def broken_chain(root):
        return make_task(root, decision_data("stop"), history=[decision_data("continue")], broken_chain=True)
    case("broken-supersedes-chain", broken_chain, "/dr-status", "PRODUCT_REFUSE_ARTIFACT_INVALID", allow_error=True)

    def invalid_checker_artifact(root):
        result = make_simple(root, "rejected")
        bundle = result[0]
        checked = run_checker(bundle)
        assert checked.returncode == 1 and "E_OUTCOME_INVALID" in checked.stdout
        return result
    def assert_checker_diagnostic(result, front, ref, brief, parent):
        assert "E_OUTCOME_INVALID" in result["detail"]
    case("checker-refusal", invalid_checker_artifact, "/dr-status", "PRODUCT_REFUSE_ARTIFACT_INVALID", assert_checker_diagnostic)

    sandbox_prd_run("continue", decision_data("continue", authority=granted))
    sandbox_prd_run("stop", decision_data("stop"), include_brief=False)
    sandbox_prd_run("more-evidence", decision_data("more-evidence"), include_brief=False)
    sandbox_prd_run("superseded", decision_data("continue", authority=granted),
                    history=[prior], brief_revision=1)

    for outcome in ("more-evidence", "stop"):
        run_resume_case(outcome)

    with tempfile.TemporaryDirectory(prefix="d5a-mutant-") as temp:
        root = Path(temp)
        make_simple(root, "stop")
        source = ROUTER.read_text()
        original = '''    if outcome == "stop":\n        result("/dr-archive", TOKENS["stop"], **lineage(decision_ref, latest_front), research_status="accepted", delivery_work_created=False)\n        return 0\n'''
        mutant = '''    if outcome == "stop":\n        result("/dr-prd", TOKENS["continue"], **lineage(decision_ref, latest_front))\n        return 0\n'''
        assert original in source, "mutation anchor changed"
        mutant_dir = root / "mutant-tools"
        mutant_dir.mkdir()
        mutant_path = mutant_dir / "product-decision-route-mutant.py"
        mutant_path.write_text(source.replace(original, mutant, 1))
        shutil.copy(CHECKER, mutant_dir / CHECKER.name)
        shutil.copy(CHECKER.with_suffix(".py"), mutant_dir / CHECKER.with_suffix(".py").name)
        changed = json.loads(route(root, mutant_path).stdout)
        correct = json.loads(route(root).stdout)
        assert changed["token"] == "PRODUCT_ROUTE_CONTINUE" and correct["token"] == "PRODUCT_ROUTE_STOP"
        print(f"TRANSCRIPT red-control: expected={correct['token']}; stop-mutant={changed['token']}; detected=true")


if __name__ == "__main__":
    main()
