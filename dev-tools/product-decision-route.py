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
    return raw, yaml.safe_load(front.group(1)), yaml.safe_load(data.group(1))


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


def check_bundle(bundle, checker):
    checked = subprocess.run(
        ["bash", str(checker), "--root", str(bundle), "--bundle", "."],
        capture_output=True, text=True, check=False,
    )
    return checked.returncode, checked.stdout.strip() or checked.stderr.strip()


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
    check_rc, check_text = check_bundle(bundle, checker)
    if check_rc:
        refuse("invalid_artifact", detail=check_text)
        return 0
    decision_docs = [artifact(path) for path in decisions]
    for index, (path, item) in enumerate(zip(decisions, decision_docs)):
        raw, front, _ = item
        if front.get("revision") != index + 1 or front.get("artifact_type") != "decision-record":
            raise ValueError("DecisionRecord revision does not match its canonical filename")
        if index:
            previous_raw, previous_front, _ = decision_docs[index - 1]
            expected_supersedes = {"id": previous_front.get("id"), "revision": index, "digest": digest(previous_raw)}
            if front.get("id") != previous_front.get("id") or front.get("supersedes") != expected_supersedes or previous_front.get("status") != "superseded":
                raise ValueError("DecisionRecord revisions do not form an exact supersedes chain")
    latest_path = decisions[-1]
    latest_raw, latest_front, latest_data = decision_docs[-1]
    decision_digest = digest(latest_raw)
    if latest_front.get("artifact_type") != "decision-record" or latest_front.get("schema_version") != "product-artifact/2":
        refuse("invalid_artifact", detail="latest record is not DecisionRecord product-artifact/2")
        return 0
    decision_ref = {"id": latest_front.get("id"), "revision": latest_front.get("revision"), "digest": decision_digest}
    if latest_front.get("status") == "superseded":
        result("/dr-do", TOKENS["superseded"], decision_ref=decision_ref)
        return 0
    if latest_front.get("status") != "submitted" or latest_front.get("acceptance_state") != "accepted":
        result("/dr-qa", TOKENS["evidence_pending"], decision_ref=decision_ref)
        return 0
    if latest_data.get("evidence_acceptance") != "accepted":
        result("/dr-qa", TOKENS["evidence_pending"], decision_ref=decision_ref)
        return 0
    outcome = latest_data.get("business_outcome")
    if outcome == "stop":
        result("/dr-archive", TOKENS["stop"], decision_ref=decision_ref)
        return 0
    if outcome == "pivot":
        result("/dr-do", TOKENS["pivot"], decision_ref=decision_ref)
        return 0
    if outcome == "more-evidence":
        result("/dr-do", TOKENS["more_evidence"], decision_ref=decision_ref, open_evidence=latest_data.get("uncertainty", []))
        return 0
    if outcome != "continue":
        refuse("invalid_artifact", detail="unknown business_outcome", decision_ref=decision_ref)
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
    brief_docs = [artifact(path) for path in briefs]
    for index, (path, front, _) in enumerate(brief_docs):
        if front.get("revision") != index + 1 or front.get("artifact_type") != "product-brief":
            raise ValueError("ProductBrief revision does not match its canonical filename")
        if index:
            previous_raw, previous_front, _ = brief_docs[index - 1]
            expected_supersedes = {"id": previous_front.get("id"), "revision": index, "digest": digest(previous_raw)}
            if front.get("id") != previous_front.get("id") or front.get("supersedes") != expected_supersedes or previous_front.get("status") != "superseded":
                raise ValueError("ProductBrief revisions do not form an exact supersedes chain")
    brief_raw, brief_front, brief_data = brief_docs[-1]
    brief_digest = digest(brief_raw)
    brief_ref = {"id": brief_front.get("id"), "revision": brief_front.get("revision"), "digest": brief_digest}
    if (brief_front.get("artifact_type") != "product-brief" or brief_front.get("status") != "ready_for_delivery"
            or brief_front.get("acceptance_state") != "accepted"):
        refuse("brief_missing", decision_ref=decision_ref, product_brief_ref=brief_ref)
        return 0
    if not any(ref == decision_ref for ref in brief_data.get("input_revisions", [])):
        refuse("brief_mismatch", decision_ref=decision_ref, product_brief_ref=brief_ref)
        return 0
    authority = latest_data.get("authority_to_act") or {}
    ids = [item.get("id") for item in advances if isinstance(item, dict)]
    matching = [item for item in advances if isinstance(item, dict) and item.get("status") == "authorized" and item.get("decision_ref") == decision_ref]
    if len(ids) != len(set(ids)) or len(matching) > 1:
        refuse("authorization_mismatch", decision_ref=decision_ref, product_brief_ref=brief_ref)
        return 0
    if authority.get("status") != "granted" or not authority.get("authority_ref") or not matching:
        refuse("authorization_missing", decision_ref=decision_ref, product_brief_ref=brief_ref, parent_acceptance_contract_sha256=parent_hash)
        return 0
    advance = matching[-1]
    required = {"id", "status", "decision_ref", "authorization_ref", "authorized_scope", "parent_acceptance_contract_sha256"}
    if set(advance) != required or not isinstance(advance.get("id"), str) or not advance["id"].strip():
        refuse("authorization_mismatch", decision_ref=decision_ref, product_brief_ref=brief_ref)
        return 0
    if (advance.get("authorization_ref") != authority.get("authority_ref")
            or advance.get("authorized_scope") != brief_data.get("scope")):
        refuse("authorization_mismatch", decision_ref=decision_ref, product_brief_ref=brief_ref)
        return 0
    if advance.get("parent_acceptance_contract_sha256") != parent_hash:
        refuse("parent_mismatch", decision_ref=decision_ref, product_brief_ref=brief_ref,
               parent_acceptance_contract_sha256=parent_hash)
        return 0
    result("/dr-prd", TOKENS["continue"], decision_ref=decision_ref, product_brief_ref=brief_ref,
           authorization_ref=advance["authorization_ref"], scope_advance_id=advance["id"],
           parent_acceptance_contract_sha256=parent_hash, requirements=brief_data.get("requirements", []))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        result("/dr-status", TOKENS["invalid_artifact"], detail=str(exc))
        raise SystemExit(1)
