#!/usr/bin/env python3
"""Fail-closed route selector for a product-research handoff."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml

TOKENS = {
    "missing_decision": "PRODUCT_REFUSE_DECISION_MISSING",
    "invalid_artifact": "PRODUCT_REFUSE_ARTIFACT_INVALID",
    "superseded": "PRODUCT_ROUTE_SUPERSEDED",
    "evidence_pending": "PRODUCT_ROUTE_EVIDENCE_PENDING",
    "stop": "PRODUCT_ROUTE_STOP",
    "pivot": "PRODUCT_ROUTE_PIVOT",
    "more_evidence": "PRODUCT_ROUTE_MORE_EVIDENCE",
    "brief_missing": "PRODUCT_REFUSE_PRODUCT_BRIEF_MISSING",
    "brief_mismatch": "PRODUCT_REFUSE_PRODUCT_BRIEF_INPUT_MISMATCH",
    "authorization_missing": "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISSING",
    "authorization_mismatch": "PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH",
    "parent_mismatch": "PRODUCT_REFUSE_PARENT_CONTRACT_MISMATCH",
    "continue": "PRODUCT_ROUTE_CONTINUE",
}


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def artifact(path):
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    front = re.search(r"\A---\n(.*?)\n---\n", text, re.S)
    data = re.search(r"```product-artifact-data\n(.*?)\n```\n?", text, re.S)
    if not front or not data:
        raise ValueError(f"malformed product artifact: {path.name}")
    front_value = yaml.safe_load(front.group(1))
    data_value = yaml.safe_load(data.group(1))
    if not isinstance(front_value, dict):
        raise ValueError("product artifact frontmatter must be a mapping")
    return raw, front_value, data_value


def result(route, token, **fields):
    print(json.dumps({"route": route, "token": token, **fields}, sort_keys=True))


def refuse(token, **fields):
    result("/dr-status", TOKENS[token], **fields)


def revisions(directory, prefix):
    pattern = re.compile(rf"{re.escape(prefix)}-r([1-9][0-9]*)\.md\Z")
    found = []
    for path in directory.iterdir():
        match = pattern.fullmatch(path.name)
        if match:
            found.append((int(match.group(1)), path))
    found.sort(key=lambda item: item[0])
    numbers = [number for number, _ in found]
    if len(numbers) != len(set(numbers)) or numbers != list(range(1, len(numbers) + 1)):
        raise ValueError(f"{prefix} revisions must be unique and contiguous from r1")
    return [path for _, path in found]


def current_closure(bundle, decision_path, brief_path=None):
    """Select current artifacts plus non-revision evidence in their actual bundle."""
    revisioned = re.compile(r"(?:decision|product-brief)-r[1-9][0-9]*\.md\Z")
    files = [path for path in bundle.rglob("*.md") if not revisioned.fullmatch(path.name)]
    files = [path for path in files if path != decision_path and path != brief_path]
    files.extend(path for path in (decision_path, brief_path) if path is not None)
    return sorted({path.relative_to(bundle).as_posix() for path in files})


def check_artifacts(bundle, checker, decision_path, brief_path=None):
    """Validate only the active decision closure, preserving evidence paths in place."""
    closure = current_closure(bundle, decision_path, brief_path)
    checked = subprocess.run(
        ["bash", str(checker), "--root", str(bundle), "--files", *closure],
        capture_output=True, text=True, check=False,
    )
    return checked.returncode, checked.stdout.strip() or checked.stderr.strip()


def validate_revision_chain(paths, kind):
    documents = [artifact(path) for path in paths]
    for index, (path, (raw, front, _)) in enumerate(zip(paths, documents)):
        if front.get("revision") != index + 1 or front.get("artifact_type") != kind:
            raise ValueError(f"{kind} revision does not match canonical filename {path.name}")
        if index:
            previous_raw, previous_front, _ = documents[index - 1]
            expected = {"id": previous_front.get("id"), "revision": index, "digest": digest(previous_raw)}
            if front.get("id") != previous_front.get("id") or front.get("supersedes") != expected:
                raise ValueError(f"{kind} revisions do not form an exact immutable supersedes chain")
    return documents


def lineage(decision_ref, front):
    return {"decision_ref": decision_ref, "supersedes": front.get("supersedes")}


def acceptance_hash(task_path):
    raw = task_path.read_bytes()
    match = re.search(rb"(?m)^## Acceptance Criteria\r?\n(.*?)(?=^## |\Z)", raw, re.S)
    if not match:
        raise ValueError("task record has no Acceptance Criteria section")
    return digest(match.group(1))


def scope_advances(task_path):
    text = task_path.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^## Scope Advance Records\s*\n(.*?)(?=^## |\Z)", text)
    if not match:
        return []
    return [json.loads(body) for body in re.findall(r"```json\s*\n(.*?)\n```", match.group(1), re.S)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path, help="workspace root containing datarim/")
    parser.add_argument("--task", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.task):
        raise ValueError("task identifier contains unsupported characters")
    bundle = args.root / "datarim/insights/decisions" / args.task
    task_record = args.root / "datarim/tasks" / f"{args.task}-task-description.md"
    checker = Path(__file__).with_name("check-product-artifact.sh")
    if not bundle.is_dir() or bundle.is_symlink():
        refuse("missing_decision", task_id=args.task)
        return 0
    decisions = revisions(bundle, "decision")
    if not decisions:
        refuse("missing_decision", task_id=args.task)
        return 0
    decision_docs = validate_revision_chain(decisions, "decision-record")
    latest_path = decisions[-1]
    latest_raw, latest_front, latest_data = decision_docs[-1]
    if not isinstance(latest_data, dict):
        raise ValueError("active product artifact data must be a mapping")
    decision_digest = digest(latest_raw)
    if latest_front.get("schema_version") != "product-artifact/2":
        refuse("invalid_artifact", detail="latest record is not DecisionRecord product-artifact/2")
        return 0
    decision_ref = {"id": latest_front.get("id"), "revision": latest_front.get("revision"), "digest": decision_digest}
    if latest_front.get("status") == "superseded":
        result("/dr-do", TOKENS["superseded"], **lineage(decision_ref, latest_front), research_status="stale", delivery_work_created=False)
        return 0
    if latest_front.get("status") != "submitted" or latest_front.get("acceptance_state") != "accepted":
        result("/dr-qa", TOKENS["evidence_pending"], **lineage(decision_ref, latest_front), research_status="incomplete", delivery_work_created=False)
        return 0
    if latest_data.get("evidence_acceptance") != "accepted":
        result("/dr-qa", TOKENS["evidence_pending"], **lineage(decision_ref, latest_front), research_status="incomplete", delivery_work_created=False)
        return 0
    outcome = latest_data.get("business_outcome")
    if outcome != "continue":
        check_rc, check_text = check_artifacts(bundle, checker, latest_path)
        if check_rc:
            refuse("invalid_artifact", **lineage(decision_ref, latest_front), detail=check_text)
            return 0
    if outcome == "stop":
        result("/dr-archive", TOKENS["stop"], **lineage(decision_ref, latest_front), research_status="accepted", delivery_work_created=False)
        return 0
    if outcome == "pivot":
        result("/dr-do", TOKENS["pivot"], **lineage(decision_ref, latest_front), research_status="incomplete", delivery_work_created=False)
        return 0
    if outcome == "more-evidence":
        result("/dr-do", TOKENS["more_evidence"], **lineage(decision_ref, latest_front), research_status="incomplete", delivery_work_created=False, open_evidence=latest_data.get("uncertainty", []))
        return 0
    if outcome != "continue":
        refuse("invalid_artifact", **lineage(decision_ref, latest_front), detail="unknown business_outcome")
        return 0
    if not task_record.is_file() or task_record.is_symlink():
        refuse("authorization_missing", decision_ref=decision_ref)
        return 0
    try:
        parent_hash = acceptance_hash(task_record)
        advances = scope_advances(task_record)
    except (ValueError, json.JSONDecodeError) as exc:
        refuse("authorization_missing", decision_ref=decision_ref, detail=str(exc))
        return 0
    briefs = revisions(bundle, "product-brief")
    if not briefs:
        refuse("brief_missing", decision_ref=decision_ref, parent_acceptance_contract_sha256=parent_hash)
        return 0
    brief_docs = validate_revision_chain(briefs, "product-brief")
    latest_brief_path = briefs[-1]
    brief_raw, brief_front, brief_data = brief_docs[-1]
    if not isinstance(brief_data, dict):
        raise ValueError("active product artifact data must be a mapping")
    brief_digest = digest(brief_raw)
    brief_ref = {"id": brief_front.get("id"), "revision": brief_front.get("revision"), "digest": brief_digest}
    if (brief_front.get("artifact_type") != "product-brief" or brief_front.get("status") != "ready_for_delivery"
            or brief_front.get("acceptance_state") != "accepted"):
        refuse("brief_missing", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    inputs = brief_data.get("input_revisions", [])
    if inputs is None:
        inputs = []
    elif not isinstance(inputs, list):
        raise ValueError("ProductBrief input_revisions must be a list")
    if not any(ref == decision_ref for ref in inputs):
        stale_input = any(isinstance(ref, dict) and ref.get("id") == decision_ref["id"]
                          and type(ref.get("revision")) is int and ref["revision"] < decision_ref["revision"] for ref in inputs)
        if stale_input:
            result("/dr-do", TOKENS["superseded"], **lineage(decision_ref, latest_front), research_status="stale", delivery_work_created=False, product_brief_ref=brief_ref)
        else:
            refuse("brief_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    check_rc, check_text = check_artifacts(bundle, checker, latest_path, latest_brief_path)
    if check_rc:
        refuse("invalid_artifact", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref, detail=check_text)
        return 0
    authority = latest_data.get("authority_to_act") or {}
    invalid_advance_id = any(
        isinstance(item, dict)
        and (not isinstance(item.get("id"), str) or not item["id"].strip())
        for item in advances
    )
    if invalid_advance_id:
        refuse("authorization_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    ids = [item.get("id") for item in advances if isinstance(item, dict)]
    matching = [item for item in advances if isinstance(item, dict) and item.get("status") == "authorized" and item.get("decision_ref") == decision_ref]
    if len(ids) != len(set(ids)) or len(matching) > 1:
        refuse("authorization_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    stale_advance = any(isinstance(item, dict) and item.get("status") == "authorized"
                        and isinstance(item.get("decision_ref"), dict)
                        and item["decision_ref"].get("id") == decision_ref["id"]
                        and type(item["decision_ref"].get("revision")) is int
                        and item["decision_ref"]["revision"] < decision_ref["revision"] for item in advances)
    if not matching and stale_advance:
        refuse("authorization_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    if authority.get("status") != "granted" or not authority.get("authority_ref") or not matching:
        refuse("authorization_missing", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref, parent_acceptance_contract_sha256=parent_hash)
        return 0
    advance = matching[-1]
    required = {"id", "status", "decision_ref", "authorization_ref", "authorized_scope", "parent_acceptance_contract_sha256"}
    if set(advance) != required or not isinstance(advance.get("id"), str) or not advance["id"].strip():
        refuse("authorization_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    if (advance.get("authorization_ref") != authority.get("authority_ref")
            or advance.get("authorized_scope") != brief_data.get("scope")):
        refuse("authorization_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref)
        return 0
    if advance.get("parent_acceptance_contract_sha256") != parent_hash:
        refuse("parent_mismatch", **lineage(decision_ref, latest_front), product_brief_ref=brief_ref,
               parent_acceptance_contract_sha256=parent_hash)
        return 0
    result("/dr-prd", TOKENS["continue"], **lineage(decision_ref, latest_front), product_brief_ref=brief_ref,
           authorization_ref=advance["authorization_ref"], scope_advance_id=advance["id"],
           parent_acceptance_contract_sha256=parent_hash, requirements=brief_data.get("requirements", []))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        result("/dr-status", TOKENS["invalid_artifact"], detail=str(exc))
        raise SystemExit(1)
