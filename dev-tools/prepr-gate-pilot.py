#!/usr/bin/env python3
"""Conservative, read-only PRE-PR structure gate (not a CI or trust attestation).

A report of structural readiness is NOT proof that commands ran, that the
reviewer is independent, or that a build can be released. No network or writes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

SHA = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
NAME = re.compile(r"[A-Za-z][A-Za-z0-9_.:-]{0,95}\Z")
MAX_BYTES = 262144


class Refusal(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def unique_pairs(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise Refusal("DUPLICATE_JSON_KEY")
        obj[k] = v
    return obj


def reject_constant(_):
    raise Refusal("NONFINITE_JSON")


def read_json(path: Path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_BYTES:
        raise Refusal("INVALID_INPUT_FILE")
    try:
        result = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs,
                            parse_constant=reject_constant)
    except (UnicodeError, ValueError) as exc:
        raise Refusal("INVALID_JSON") from exc
    if not isinstance(result, dict):
        raise Refusal("ROOT_NOT_OBJECT")
    return result


def git(root: Path, *args: str) -> str:
    try:
        return subprocess.check_output(["git", "--no-optional-locks", "-c", "core.fsmonitor=false",
                                        "-c", "diff.external=", "-C", str(root), *args],
                                       stderr=subprocess.DEVNULL, timeout=10, text=True).strip()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        raise Refusal("GIT_UNAVAILABLE") from exc


def sha256(value):
    return isinstance(value, str) and SHA256.fullmatch(value) is not None


def name(value):
    return isinstance(value, str) and NAME.fullmatch(value) is not None


def sha(value):
    return isinstance(value, str) and SHA.fullmatch(value) is not None


def path(value):
    return (isinstance(value, str) and len(value) <= 240 and value != "" and
            not value.startswith(("/", "~")) and "\\" not in value and
            not any(ord(c) < 32 or ord(c) == 127 for c in value) and
            all(part not in ("", ".", "..") for part in value.split("/")))


CHANGE_OPS = ("A", "D", "M", "T")


def git_bytes(root: Path, *args: str, ok_codes=(0,)) -> bytes:
    try:
        run = subprocess.run(["git", "-c", "core.fsmonitor=false", "-c", "diff.external=",
                              "-c", "core.quotepath=false", "-C", str(root), *args],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refusal("GIT_UNAVAILABLE") from exc
    if run.returncode not in ok_codes:
        raise Refusal("GIT_UNAVAILABLE")
    return run.stdout


def decode_path(raw: bytes) -> str:
    try:
        value = raw.decode("utf-8", errors="strict")
    except UnicodeError as exc:
        raise Refusal("CHANGED_PATH_UNSAFE") from exc
    if not path(value):
        raise Refusal("CHANGED_PATH_UNSAFE")
    return value


def changed_operations(root: Path, base: str, head: str) -> dict:
    """Exact path -> status for base...head; renames split into D old + A new (NUL-parsed)."""
    raw = git_bytes(root, "diff", "--no-ext-diff", "--no-textconv", "--no-renames",
                    "-z", "--name-status", base + "..." + head)
    fields = raw.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) % 2:
        raise Refusal("DIFF_UNPARSEABLE")
    ops = {}
    for i in range(0, len(fields), 2):
        status = fields[i].decode("ascii", errors="replace")
        if status not in CHANGE_OPS:
            raise Refusal("DIFF_STATUS_UNSUPPORTED")
        changed_path = decode_path(fields[i + 1])
        if changed_path in ops:
            raise Refusal("DIFF_UNPARSEABLE")
        ops[changed_path] = status
    return ops


def exists_at(root: Path, commit: str, rel: str) -> bool:
    out = git_bytes(root, "ls-tree", "-z", "--full-tree", "--name-only", commit, "--", rel)
    return out.split(b"\0")[0] == rel.encode("utf-8")


def referencing_files(root: Path, commit: str, needle: str) -> set:
    """Files at commit whose text contains needle (fixed string). Heuristic consumer scan."""
    out = git_bytes(root, "grep", "-z", "-l", "-I", "-F", "--full-name", "-e", needle,
                    commit, "--", ok_codes=(0, 1))
    prefix = (commit + ":").encode("ascii")
    found = set()
    for item in out.split(b"\0"):
        if item:
            if not item.startswith(prefix):
                raise Refusal("GIT_UNAVAILABLE")
            found.add(decode_path(item[len(prefix):]))
    return found


def plan_digest(plan):
    b = json.dumps({k: plan[k] for k in ("goal", "nodes", "edges")},
                   sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(b).hexdigest()


def check(root: Path, plan: dict, evidence: dict):
    if plan.get("schema") != "DatarimPrePRPlan/v1" or evidence.get("schema") != "DatarimPrePREvidence/v1":
        raise Refusal("SCHEMA_MISMATCH")
    if not name(plan.get("task_id")) or evidence.get("task_id") != plan["task_id"]:
        raise Refusal("TASK_ID_MISMATCH")

    goal = plan.get("goal")
    if not isinstance(goal, dict) or not all(name(goal.get(k)) for k in ("owner", "metric", "unit")):
        raise Refusal("GOAL_UNDEFINED")
    baseline, target = goal.get("baseline"), goal.get("target")
    if not isinstance(baseline, dict) or not isinstance(target, dict):
        raise Refusal("GOAL_UNDEFINED")
    a, b = baseline.get("value"), target.get("value")
    if (not isinstance(a, (float, int)) or isinstance(a, bool) or not math.isfinite(a) or
            not isinstance(b, (float, int)) or isinstance(b, bool) or not math.isfinite(b) or
            not isinstance(baseline.get("source"), str) or not baseline["source"].strip() or
            not isinstance(target.get("deadline_utc"), str) or not target["deadline_utc"].endswith("Z")):
        raise Refusal("GOAL_UNMEASURED")
    if goal.get("direction") == "decrease":
        improvement = b < a
    elif goal.get("direction") == "increase":
        improvement = b > a
    else:
        raise Refusal("GOAL_DIRECTION_INVALID")
    if not improvement:
        raise Refusal("GOAL_NOT_IMPROVING")

    source = plan.get("source")
    if not isinstance(source, dict) or not all(sha(source.get(k)) for k in ("base", "head", "tree")):
        raise Refusal("SOURCE_UNPINNED")
    if not name(source.get("base_ref")):
        raise Refusal("BASE_REF_INVALID")
    if git(root, "rev-parse", "HEAD") != source["head"] or git(root, "rev-parse", "HEAD^{tree}") != source["tree"]:
        raise Refusal("SOURCE_DRIFT")
    if git(root, "merge-base", source["base_ref"], "HEAD") != source["base"]:
        raise Refusal("BASE_DRIFT")
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise Refusal("DIRTY_TREE")
    ops = changed_operations(root, source["base"], source["head"])
    changed = set(ops)
    if not changed:
        raise Refusal("NO_CHANGED_FILES")

    nodes = plan.get("nodes")
    edges = plan.get("edges")
    if (not isinstance(nodes, list) or not nodes or len(nodes) > 512 or
            not isinstance(edges, list) or len(edges) > 4096):
        raise Refusal("GRAPH_INVALID")
    by_id, seen = {}, set()
    for node in nodes:
        if (not isinstance(node, dict) or not name(node.get("id")) or
                node.get("kind") not in ("change", "test", "consumer") or
                not path(node.get("path")) or node["id"] in by_id or
                (node["kind"], node["path"]) in seen):
            raise Refusal("GRAPH_INVALID")
        if node["kind"] == "change" and node.get("op") not in CHANGE_OPS:
            raise Refusal("GRAPH_INVALID")
        by_id[node["id"]] = node
        seen.add((node["kind"], node["path"]))
    # Changed-path equality uses change-operation nodes only; selected tests may be unchanged.
    change_nodes = {n["path"]: n for n in nodes if n["kind"] == "change"}
    if set(change_nodes) != changed:
        raise Refusal("CHANGED_FILE_GRAPH_MISMATCH")
    if any(change_nodes[p]["op"] != ops[p] for p in changed):
        raise Refusal("CHANGE_OP_MISMATCH")
    for node in nodes:
        if node["kind"] == "test" and not exists_at(root, source["head"], node["path"]):
            raise Refusal("TEST_PATH_MISSING")
        if node["kind"] == "consumer" and (node["path"] in changed or
                                           not exists_at(root, source["head"], node["path"])):
            raise Refusal("GRAPH_INVALID")
    depends = {key: set() for key in by_id}
    covers = {key: set() for key in by_id if by_id[key]["kind"] in ("change", "consumer")}
    for edge in edges:
        if (not isinstance(edge, dict) or edge.get("from") not in by_id or
                edge.get("to") not in by_id or edge["from"] == edge["to"]):
            raise Refusal("GRAPH_INVALID")
        if edge.get("kind") == "depends_on":
            depends[edge["from"]].add(edge["to"])
        elif edge.get("kind") == "verifies":
            if by_id[edge["from"]]["kind"] != "test" or by_id[edge["to"]]["kind"] == "test":
                raise Refusal("GRAPH_INVALID")
            covers[edge["to"]].add(edge["from"])
        else:
            raise Refusal("GRAPH_INVALID")
    if any(not witnesses for witnesses in covers.values()):
        raise Refusal("CHANGE_WITHOUT_TEST")
    # A deleted path (including the old side of a rename) must not leave unmapped consumers:
    # every head file that still names it must be a graph node depending on the deletion.
    id_by_path = {}
    for key, node in by_id.items():
        if node["kind"] != "change":
            id_by_path.setdefault(node["path"], set()).add(key)
    for deleted, op in sorted(ops.items()):
        if op != "D":
            continue
        stem = deleted.rsplit(".", 1)[0] if "." in deleted.rsplit("/", 1)[-1] else deleted
        deletion_id = next(k for k, n in by_id.items() if n["kind"] == "change" and n["path"] == deleted)
        for consumer in sorted(referencing_files(root, source["head"], stem)):
            if not any(deletion_id in depends[k] for k in id_by_path.get(consumer, ())):
                raise Refusal("DELETED_PATH_UNMAPPED_CONSUMER")
    active, visited = set(), set()
    def visit(node_id):
        if node_id in active:
            raise Refusal("DEPENDENCY_CYCLE")
        if node_id not in visited:
            active.add(node_id)
            for target_id in sorted(depends[node_id]):
                visit(target_id)
            active.remove(node_id)
            visited.add(node_id)
    for node_id in sorted(by_id):
        visit(node_id)

    imp, rev = plan.get("implementation"), plan.get("plan_review")
    if not isinstance(imp, dict) or not isinstance(rev, dict):
        raise Refusal("PLAN_REVIEW_MISSING")
    if (not name(imp.get("provider")) or not name(rev.get("provider")) or
            imp["provider"] == rev["provider"] or rev.get("decision") != "accepted"):
        raise Refusal("PLAN_REVIEW_NOT_INDEPENDENT")
    if rev.get("plan_sha256") != plan_digest(plan):
        raise Refusal("PLAN_REVIEW_STALE")

    runs = evidence.get("runs")
    if not isinstance(runs, list):
        raise Refusal("TEST_EVIDENCE_MISSING")
    expected_tests = {key for key in by_id if by_id[key]["kind"] == "test"}
    if {r.get("test_id") for r in runs if isinstance(r, dict)} != expected_tests or len(runs) != len(expected_tests):
        raise Refusal("TEST_EVIDENCE_INCOMPLETE")
    for run in runs:
        if (run.get("status") != "passed" or run.get("head") != source["head"] or
                run.get("tree") != source["tree"] or not isinstance(run.get("command"), str) or
                not run["command"].strip() or not sha256(run.get("log_sha256")) or
                run.get("sandbox") != "isolated-no-secrets"):
            raise Refusal("TEST_EVIDENCE_NOT_PASSING")
    return {"schema": "DatarimPrePRGateResult/v1", "task_id": plan["task_id"],
            "status": "STRUCTURALLY_READY", "source_head": source["head"],
            "plan_sha256": plan_digest(plan), "changed_files": len(changed),
            "changed_operations": {op: sum(1 for v in ops.values() if v == op) for op in CHANGE_OPS},
            "tests_claimed_passed": len(runs), "trusted_execution": "NOT_VERIFIED",
            "independent_reviewer_identity": "NOT_VERIFIED",
            "release_eligible": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        result = check(args.repo, read_json(args.plan), read_json(args.evidence))
    except Refusal as exc:
        result = {"schema": "DatarimPrePRGateResult/v1", "status": "BLOCKED",
                  "reason": exc.code, "trusted_execution": "NOT_VERIFIED", "release_eligible": False}
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "STRUCTURALLY_READY" else 1


if __name__ == "__main__":
    sys.exit(main())
