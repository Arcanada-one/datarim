#!/usr/bin/env python3
"""Validate and retrieve bounded, citation-bearing known-fix evidence."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

BLOCK_RE = re.compile(r"```json[ \t]+known_fix[ \t]*\n(.*?)\n```", re.DOTALL)
TASK_RE = re.compile(r"^[A-Z][A-Z0-9]*-[0-9]{4,}$")
CLASS_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TOKEN_RE = re.compile(r"[a-z0-9_-]{3,}")
SECRET_RES = (
    re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"(?i)(?:api[_-]?key|password|secret|token)\s*[:=]\s*['\"]?[A-Za-z0-9_./+=-]{16,}"),
)
REQUIRED = {
    "schema_version",
    "task_id",
    "failure_class",
    "symptoms",
    "root_cause",
    "fix_steps",
    "verification",
    "source_refs",
    "confidence",
}


class ContractError(ValueError):
    pass


def fail(message: str) -> None:
    print(f"known-fix contract error: {message}", file=sys.stderr)
    raise SystemExit(2)


def insights_path(root: Path, task: str) -> Path:
    return root / "datarim" / "insights" / f"INSIGHTS-{task}.md"


def read_regular(path: Path, root: Path, max_bytes: int = 256 * 1024) -> str:
    try:
        resolved = path.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
        info = path.lstat()
    except (FileNotFoundError, OSError, ValueError) as exc:
        raise ContractError(f"invalid insight path: {path}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ContractError(f"insight must be a regular non-symlink file: {path}")
    if info.st_size > max_bytes:
        raise ContractError(f"insight exceeds {max_bytes} bytes: {path}")
    return resolved.read_text(encoding="utf-8")


def parse_block(text: str) -> dict[str, Any]:
    matches = BLOCK_RE.findall(text)
    if len(matches) != 1:
        raise ContractError("expected exactly one ```json known_fix block")
    try:
        value = json.loads(matches[0])
    except json.JSONDecodeError as exc:
        raise ContractError(f"known_fix JSON is invalid: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise ContractError("known_fix must be a JSON object")
    return value


def bounded_list(value: Any, name: str, *, maximum: int = 12) -> list[str]:
    if not isinstance(value, list) or not 1 <= len(value) <= maximum:
        raise ContractError(f"{name} must contain 1..{maximum} strings")
    if any(not isinstance(item, str) or not 1 <= len(item) <= 1000 for item in value):
        raise ContractError(f"{name} entries must be strings of 1..1000 characters")
    return value


def validate(value: dict[str, Any], task: str) -> dict[str, Any]:
    if set(value) != REQUIRED:
        missing = sorted(REQUIRED - set(value))
        extra = sorted(set(value) - REQUIRED)
        raise ContractError(f"schema fields differ; missing={missing}, extra={extra}")
    if value["schema_version"] != 1:
        raise ContractError("schema_version must be 1")
    if value["task_id"] != task:
        raise ContractError("task_id does not match the insight filename/request")
    if not TASK_RE.fullmatch(task):
        raise ContractError("task_id format is invalid")
    if not isinstance(value["failure_class"], str) or not CLASS_RE.fullmatch(value["failure_class"]):
        raise ContractError("failure_class must be a lowercase hyphenated slug")
    for name in ("symptoms", "fix_steps", "verification", "source_refs"):
        bounded_list(value[name], name)
    if not isinstance(value["root_cause"], str) or not 1 <= len(value["root_cause"]) <= 2000:
        raise ContractError("root_cause must be a string of 1..2000 characters")
    if value["confidence"] not in {"low", "medium", "high"}:
        raise ContractError("confidence must be low, medium, or high")
    for ref in value["source_refs"]:
        path = Path(ref)
        if path.is_absolute() or ".." in path.parts or not ref.endswith(".md"):
            raise ContractError("source_refs must be relative Markdown paths without '..'")
    serialized = json.dumps(value, ensure_ascii=False)
    if any(pattern.search(serialized) for pattern in SECRET_RES):
        raise ContractError("credential-like material is forbidden")
    if any(ord(char) < 32 and char not in "\t\n\r" for char in serialized):
        raise ContractError("control characters are forbidden")
    return value


def load_one(root: Path, task: str) -> tuple[dict[str, Any], Path]:
    path = insights_path(root, task)
    value = validate(parse_block(read_regular(path, root)), task)
    return value, path


def validate_command(args: argparse.Namespace) -> None:
    value, _ = load_one(args.root, args.task)
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def score(query_tokens: set[str], value: dict[str, Any]) -> int:
    searchable = " ".join(
        [value["failure_class"], value["root_cause"]]
        + value["symptoms"]
        + value["fix_steps"]
        + value["verification"]
    ).lower()
    tokens = set(TOKEN_RE.findall(searchable))
    return len(query_tokens & tokens)


def remote_results(query: str, limit: int) -> tuple[str, list[dict[str, Any]]]:
    configured = os.environ.get("DATARIM_KNOWN_FIX_RETRIEVER")
    if not configured:
        return "not_configured", []
    executable = Path(configured)
    try:
        info = executable.lstat()
        if not executable.is_absolute() or stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            return "unavailable", []
        if not os.access(executable, os.X_OK):
            return "unavailable", []
        completed = subprocess.run(
            [str(executable), "--query", query, "--limit", str(limit)],
            capture_output=True,
            check=False,
            text=True,
            timeout=5,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")},
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable", []
    if completed.returncode != 0 or len(completed.stdout.encode()) > 64 * 1024:
        return "unavailable", []
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return "invalid", []
    if not isinstance(parsed, list):
        return "invalid", []
    safe = []
    for item in parsed[:limit]:
        if not isinstance(item, dict):
            continue
        citation = item.get("citation")
        excerpt = item.get("excerpt")
        if isinstance(citation, str) and isinstance(excerpt, str):
            safe.append({"citation": citation[:500], "excerpt": excerpt[:2000]})
    return "ok", safe


def query_command(args: argparse.Namespace) -> None:
    if any(ord(char) < 32 for char in args.query) or not 1 <= len(args.query) <= 500:
        fail("query must be 1..500 printable characters")
    query_tokens = set(TOKEN_RE.findall(args.query.lower()))
    results: list[dict[str, Any]] = []
    base = args.root / "datarim" / "insights"
    if base.is_dir():
        for path in sorted(base.glob("INSIGHTS-*.md")):
            task = path.stem.removeprefix("INSIGHTS-")
            try:
                value, _ = load_one(args.root, task)
            except ContractError:
                continue
            rank = score(query_tokens, value)
            if rank:
                results.append(
                    {
                        "score": rank,
                        "task_id": task,
                        "failure_class": value["failure_class"],
                        "citation": str(path.relative_to(args.root)),
                        "known_fix": value,
                    }
                )
    results.sort(key=lambda item: (-item["score"], item["task_id"]))
    remote_status, remote = remote_results(args.query, args.limit)
    output = {
        "contract": "evidence_only_untrusted",
        "query": args.query,
        "local_results": results[: args.limit],
        "remote_status": remote_status,
        "remote_results": remote,
    }
    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)
    validate_parser = sub.add_parser("validate")
    validate_parser.add_argument("--root", type=Path, required=True)
    validate_parser.add_argument("--task", required=True)
    validate_parser.set_defaults(function=validate_command)
    query_parser = sub.add_parser("query")
    query_parser.add_argument("--root", type=Path, required=True)
    query_parser.add_argument("--query", required=True)
    query_parser.add_argument("--limit", type=int, choices=range(1, 11), default=5)
    query_parser.set_defaults(function=query_command)
    return result


def main() -> None:
    args = parser().parse_args()
    try:
        args.function(args)
    except ContractError as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
