#!/usr/bin/env bash
# self-verify-auto-fix.sh — guarded deterministic auto-fix transaction runner.

set -euo pipefail
IFS=$'\n\t'

exec python3 - "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tempfile
from typing import Any


MAX_INPUT_BYTES = 2 * 1024 * 1024
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
TASK_ID = re.compile(r"^[A-Z]+-[0-9]+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
RECORD_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
REGISTERED_RECIPES = {
    ("formatting", "final-newline-detector-v1", "final-newline-v1"),
    ("lint", "trailing-whitespace-detector-v1", "trailing-whitespace-v1"),
    ("obvious_typo", "typo-receive-detector-v1", "typo-receive-v1"),
    ("obvious_typo", "typo-occurred-detector-v1", "typo-occurred-v1"),
}
TYPO_RECIPES = {
    "typo-receive-v1": ("recieve", "receive"),
    "typo-occurred-v1": ("occured", "occurred"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--stage", choices=("prd", "plan", "do"), required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--finding-file", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--journal-dir", required=True)
    parser.add_argument("--transaction-id", required=True)
    return parser.parse_args()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(131072), b""):
            digest.update(chunk)
    return digest.hexdigest()


def has_write_bits(path: Path) -> bool:
    return bool(path.stat(follow_symlinks=False).st_mode & (stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))


def inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def validate_regular_input(path: Path, workspace: Path, max_bytes: int = MAX_INPUT_BYTES) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValueError("input_not_regular")
    resolved = path.resolve(strict=True)
    if not inside(resolved, workspace):
        raise ValueError("input_outside_workspace")
    if path.stat().st_size > max_bytes:
        raise ValueError("input_too_large")


def validate_relative_path(raw: Any) -> str:
    if not isinstance(raw, str) or not raw or raw.startswith(("/", "-")):
        raise ValueError("invalid_relative_path")
    if any(ord(char) < 32 or ord(char) == 127 for char in raw):
        raise ValueError("invalid_relative_path")
    parsed = PurePosixPath(raw)
    if any(part in ("", ".", "..") for part in parsed.parts):
        raise ValueError("invalid_relative_path")
    return raw


def reject_symlink_components(path: Path, workspace: Path) -> None:
    relative = path.relative_to(workspace)
    current = workspace
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("symlink_component")


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("json_not_object")
    return value


def result(
    finding_id: str,
    disposition: str,
    reason_code: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    values = details or {}
    false_positive = values.get("false_positive", 0)
    total = values.get("total", 0)
    basis_points = (false_positive * 10000 // total) if total else 0
    return {
        "finding_id": finding_id,
        "disposition": disposition,
        "reason_code": reason_code,
        "history_false_positive": false_positive,
        "history_total": total,
        "history_rate_basis_points": basis_points,
        "fixer_id": values.get("fixer_id", ""),
        "target": values.get("target", ""),
        "before_sha256": values.get("before_sha256", ""),
        "after_sha256": values.get("after_sha256", ""),
        "transaction_log": values.get("transaction_log", ""),
        "postcondition_verified": values.get("postcondition_verified", False),
        "rollback_verified": values.get("rollback_verified", False),
    }


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def validate_finding(finding: dict[str, Any]) -> tuple[str, str, str, str, int | None]:
    finding_id = finding.get("finding_id")
    if not isinstance(finding_id, str) or not SAFE_ID.fullmatch(finding_id):
        raise ValueError("invalid_finding_id")
    if finding.get("source_layer") != "floor":
        raise PermissionError("untrusted_source")
    canonical = (
        isinstance(finding.get("artifact_ref"), str)
        and isinstance(finding.get("ac_criteria"), list)
        and finding.get("severity") == "low"
        and finding.get("category") in ("correctness", "completeness", "consistency")
        and isinstance(finding.get("evidence"), dict)
        and finding["evidence"].get("type") in ("file_quote", "test_output")
        and isinstance(finding["evidence"].get("source"), str)
        and isinstance(finding["evidence"].get("excerpt"), str)
        and 0 < len(finding["evidence"]["excerpt"]) <= 200
        and isinstance(finding.get("check_name"), str)
        and finding.get("risk_level") == "low"
        and finding.get("sensitivity") == "none"
        and finding.get("deterministic") is True
        and finding.get("discarded") is False
        and finding.get("evidence_verified") is True
    )
    if not canonical:
        raise PermissionError("ineligible_metadata")
    finding_class = finding.get("finding_class")
    detector = finding.get("detector_version")
    fixer = finding.get("fixer_id")
    if (finding_class, detector, fixer) not in REGISTERED_RECIPES:
        raise PermissionError("unknown_recipe")
    target = validate_relative_path(finding.get("target"))
    digest = finding.get("preimage_sha256")
    if not isinstance(digest, str) or not SHA256.fullmatch(digest):
        raise PermissionError("invalid_preimage")
    line = finding.get("line")
    if fixer == "final-newline-v1":
        if line is not None:
            raise PermissionError("invalid_line")
    elif not isinstance(line, int) or isinstance(line, bool) or line < 1:
        raise PermissionError("invalid_line")
    return finding_class, detector, fixer, target, line


def parse_manifest(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    if "\r" in text or "\x00" in text:
        raise ValueError("invalid_manifest")
    entries = text.splitlines()
    if not entries or any(not entry for entry in entries):
        raise ValueError("invalid_manifest")
    validated = [validate_relative_path(entry) for entry in entries]
    if len(validated) != len(set(validated)):
        raise ValueError("invalid_manifest")
    return set(validated)


def parse_time(raw: Any) -> dt.datetime:
    if not isinstance(raw, str) or not raw.endswith("Z"):
        raise ValueError("invalid_record_time")
    parsed = dt.datetime.fromisoformat(raw[:-1] + "+00:00")
    if parsed > dt.datetime.now(dt.timezone.utc):
        raise ValueError("future_record")
    return parsed


def validate_history_record(record: dict[str, Any]) -> tuple[str, str, str]:
    identity_fields = ("finding_id", "finding_class", "detector_version", "fixer_id")
    for field in identity_fields:
        value = record.get(field)
        if not isinstance(value, str) or not SAFE_ID.fullmatch(value):
            raise ValueError("history_unverifiable")
    recipe = (record["finding_class"], record["detector_version"], record["fixer_id"])
    if recipe not in REGISTERED_RECIPES or record.get("outcome") not in ("confirmed", "false_positive"):
        raise ValueError("history_unverifiable")
    parse_time(record.get("recorded_at"))
    return recipe


def load_history(workspace: Path, finding_class: str, detector: str, fixer: str) -> tuple[int, int]:
    history = workspace / "datarim/qa/self-verification-auto-fix-history/records"
    if not history.exists():
        raise FileNotFoundError("history_unavailable")
    if history.is_symlink() or not history.is_dir() or has_write_bits(history):
        raise ValueError("history_unverifiable")
    reject_symlink_components(history, workspace)
    entries = sorted(history.iterdir(), key=lambda item: item.name)
    if not entries:
        raise FileNotFoundError("history_unavailable")
    seen: set[str] = set()
    matching: list[dict[str, Any]] = []
    for entry in entries:
        if entry.is_symlink() or not entry.is_file() or entry.suffix != ".json" or has_write_bits(entry):
            raise ValueError("history_unverifiable")
        if entry.stat().st_size > 65536:
            raise ValueError("history_unverifiable")
        record = read_json(entry)
        record_id = record.get("record_id")
        if not isinstance(record_id, str) or not RECORD_ID.fullmatch(record_id):
            raise ValueError("history_unverifiable")
        if entry.stem != record_id or record_id in seen:
            raise ValueError("history_unverifiable")
        seen.add(record_id)
        recipe = validate_history_record(record)
        if recipe == (finding_class, detector, fixer):
            matching.append(record)
    if not matching:
        raise FileNotFoundError("history_unavailable")
    false_positive = sum(record["outcome"] == "false_positive" for record in matching)
    return false_positive, len(matching)


def transform(data: bytes, fixer: str, line_number: int | None) -> bytes:
    if fixer == "final-newline-v1":
        return data if data.endswith(b"\n") else data + b"\n"
    text = data.decode("utf-8")
    lines = text.splitlines(keepends=True)
    if line_number is None or line_number > len(lines):
        raise PermissionError("invalid_line")
    index = line_number - 1
    body = lines[index]
    ending = ""
    if body.endswith("\r\n"):
        body, ending = body[:-2], "\r\n"
    elif body.endswith("\n"):
        body, ending = body[:-1], "\n"
    if fixer == "trailing-whitespace-v1":
        body = re.sub(r"[ \t]+$", "", body)
    elif fixer in TYPO_RECIPES:
        typo, correction = TYPO_RECIPES[fixer]
        body = re.sub(rf"\b{re.escape(typo)}\b", correction, body)
    else:
        raise PermissionError("unknown_recipe")
    lines[index] = body + ending
    return "".join(lines).encode("utf-8")


def postcondition(data: bytes, fixer: str, line_number: int | None) -> bool:
    if fixer == "final-newline-v1":
        return data.endswith(b"\n")
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return False
    if line_number is None or line_number > len(lines):
        return False
    selected = lines[line_number - 1]
    if fixer == "trailing-whitespace-v1":
        return re.search(r"[ \t]+$", selected) is None
    typo, _ = TYPO_RECIPES[fixer]
    return re.search(rf"\b{re.escape(typo)}\b", selected) is None


def fsync_dir(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def durable_create(path: Path, data: bytes, mode: int = 0o600) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(descriptor)
    fsync_dir(path.parent)


def durable_json(path: Path, payload: dict[str, Any]) -> None:
    durable_create(path, (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def atomic_replace_target(target: Path, data: bytes, mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=".self-verify-auto-fix-", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IMODE(mode))
        os.replace(temporary, target)
        fsync_dir(target.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def acquire_lock(lock_dir: Path, transaction_id: str) -> dict[str, Any] | None:
    owner_path = lock_dir / "owner.json"
    try:
        os.mkdir(lock_dir, 0o700)
    except FileExistsError:
        if lock_dir.is_symlink() or not lock_dir.is_dir():
            return None
        try:
            owner = read_json(owner_path)
            pid = owner.get("pid")
            if isinstance(pid, int) and pid > 1:
                try:
                    os.kill(pid, 0)
                    return None
                except ProcessLookupError:
                    pass
                except PermissionError:
                    return None
            owner_path.unlink()
            lock_dir.rmdir()
            os.mkdir(lock_dir, 0o700)
        except (OSError, ValueError, json.JSONDecodeError):
            return None
    owner = {"pid": os.getpid(), "transaction_id": transaction_id}
    durable_json(owner_path, owner)
    return owner


def release_lock(lock_dir: Path, owner: dict[str, Any]) -> None:
    owner_path = lock_dir / "owner.json"
    try:
        current = read_json(owner_path)
        if current == owner:
            owner_path.unlink()
            lock_dir.rmdir()
    except (OSError, ValueError, json.JSONDecodeError):
        pass


def maybe_failpoint(workspace: Path, name: str) -> None:
    enabled = os.environ.get("DR_AUTOFIX_TEST_MODE") == "1"
    selected = os.environ.get("DR_AUTOFIX_TEST_FAILPOINT") == name
    sentinel = workspace / ".datarim-test-only"
    if enabled and selected and sentinel.is_file() and "bats-run-" in str(workspace):
        os._exit(97)


def maybe_perturb_target(context: dict[str, Any], name: str) -> None:
    enabled = os.environ.get("DR_AUTOFIX_TEST_MODE") == "1"
    selected = os.environ.get("DR_AUTOFIX_TEST_PERTURB") == name
    sentinel = context["workspace"] / ".datarim-test-only"
    if enabled and selected and sentinel.is_file() and "bats-run-" in str(context["workspace"]):
        context["target"].write_bytes(b"test-only perturbed postimage\n")


def write_terminal(path: Path, prepared: dict[str, Any], disposition: str, reason_code: str) -> None:
    terminal = {
        "transaction_id": prepared["transaction_id"],
        "finding_id": prepared["finding_id"],
        "finding_class": prepared["finding_class"],
        "detector_version": prepared["detector_version"],
        "fixer_id": prepared["fixer_id"],
        "target": prepared["target"],
        "line": prepared["line"],
        "before_sha256": prepared["before_sha256"],
        "after_sha256": prepared["after_sha256"],
        "original_mode": prepared["original_mode"],
        "disposition": disposition,
        "reason_code": reason_code,
        "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    durable_json(path, terminal)


def payload(context: dict[str, Any], disposition: str, reason_code: str, **extra: Any) -> dict[str, Any]:
    values = {
        "false_positive": context.get("false_positive", 0),
        "total": context.get("total", 0),
        "fixer_id": context.get("fixer", ""),
        "target": context.get("target_rel", ""),
        "before_sha256": context.get("before_digest", ""),
        "transaction_log": context.get("transaction_log", ""),
    }
    values.update(extra)
    return result(context.get("finding_id", ""), disposition, reason_code, values)


def load_request(args: argparse.Namespace) -> dict[str, Any]:
    if not TASK_ID.fullmatch(args.task) or not SAFE_ID.fullmatch(args.transaction_id):
        raise RuntimeError("invalid_identifier")
    workspace = Path(args.workspace).resolve(strict=True)
    if not workspace.is_dir():
        raise RuntimeError("invalid_workspace")
    finding_path = Path(args.finding_file)
    manifest_path = Path(args.manifest)
    validate_regular_input(finding_path, workspace, 65536)
    validate_regular_input(manifest_path, workspace, 262144)
    finding = read_json(finding_path)
    finding_id = finding.get("finding_id") if isinstance(finding.get("finding_id"), str) else ""
    finding_class, detector, fixer, target_rel, line_number = validate_finding(finding)
    return {
        "args": args,
        "workspace": workspace,
        "finding": finding,
        "finding_id": finding_id,
        "finding_class": finding_class,
        "detector": detector,
        "fixer": fixer,
        "target_rel": target_rel,
        "line_number": line_number,
        "manifest_path": manifest_path,
    }


def validate_target(context: dict[str, Any]) -> dict[str, Any] | None:
    try:
        manifest = parse_manifest(context["manifest_path"])
    except (OSError, UnicodeError, ValueError):
        return payload(context, "advisory", "invalid_manifest")
    if context["target_rel"] not in manifest:
        return payload(context, "advisory", "target_not_manifested")
    target = context["workspace"] / context["target_rel"]
    try:
        reject_symlink_components(target, context["workspace"])
        valid_type = target.is_file() and target.suffix.lower() in (".md", ".markdown", ".txt")
        if target.is_symlink() or not valid_type or target.stat().st_size > MAX_INPUT_BYTES:
            raise ValueError("unsafe_target")
        if not inside(target.resolve(strict=True), context["workspace"]):
            raise ValueError("unsafe_target")
    except (OSError, ValueError):
        return payload(context, "advisory", "unsafe_target")
    context["target"] = target
    context["before_digest"] = sha256_file(target)
    return None


def validate_history(context: dict[str, Any]) -> dict[str, Any] | None:
    try:
        counts = load_history(
            context["workspace"], context["finding_class"], context["detector"], context["fixer"]
        )
    except FileNotFoundError:
        return payload(context, "advisory", "history_unavailable")
    except (OSError, ValueError, json.JSONDecodeError):
        return payload(context, "advisory", "history_unverifiable")
    context["false_positive"], context["total"] = counts
    if 10 * context["false_positive"] >= 3 * context["total"]:
        return payload(context, "advisory", "history_rate_too_high")
    return None


def prepare_journal(context: dict[str, Any]) -> dict[str, Any] | None:
    journal = Path(context["args"].journal_dir)
    try:
        journal_parent = journal.parent.resolve(strict=True)
        if not inside(journal_parent, context["workspace"] / "datarim/qa") or journal.is_symlink():
            raise ValueError("unsafe_journal")
        journal.mkdir(mode=0o700, exist_ok=True)
        if journal.is_symlink() or not journal.is_dir():
            raise ValueError("unsafe_journal")
        reject_symlink_components(journal, context["workspace"])
    except (OSError, ValueError):
        return payload(context, "failed", "journal_conflict")
    transaction_id = context["args"].transaction_id
    context.update({
        "journal": journal,
        "before_path": journal / f"before-{transaction_id}.bin",
        "candidate_path": journal / f"candidate-{transaction_id}.bin",
        "prepared_path": journal / f"prepared-{transaction_id}.json",
        "terminal_path": journal / f"terminal-{transaction_id}.json",
    })
    context["transaction_log"] = str(context["terminal_path"].relative_to(context["workspace"]))
    return None


def revalidate_locked_target(context: dict[str, Any]) -> str:
    target = context["target"]
    reject_symlink_components(target, context["workspace"])
    if target.is_symlink() or not target.is_file() or not inside(target.resolve(strict=True), context["workspace"]):
        raise ValueError("unsafe_target")
    locked_digest = sha256_file(target)
    return locked_digest


def transaction_record_valid(context: dict[str, Any], record: dict[str, Any]) -> bool:
    expected = {
        "transaction_id": context["args"].transaction_id,
        "finding_id": context["finding_id"],
        "finding_class": context["finding_class"],
        "detector_version": context["detector"],
        "fixer_id": context["fixer"],
        "target": context["target_rel"],
        "line": context["line_number"],
    }
    if any(record.get(key) != value for key, value in expected.items()):
        return False
    if not all(isinstance(record.get(key), str) and SHA256.fullmatch(record[key]) for key in ("before_sha256", "after_sha256")):
        return False
    original_mode = record.get("original_mode")
    if not isinstance(original_mode, int) or isinstance(original_mode, bool) or not 0 <= original_mode <= 0o7777:
        return False
    try:
        parse_time(record.get("recorded_at"))
    except (TypeError, ValueError):
        return False
    return True


def live_image(context: dict[str, Any]) -> tuple[str, int]:
    target = context["target"]
    return sha256_file(target), stat.S_IMODE(target.stat().st_mode)


def replay_terminal(context: dict[str, Any]) -> dict[str, Any]:
    terminal = read_json(context["terminal_path"])
    if not transaction_record_valid(context, terminal):
        return payload(context, "failed", "journal_conflict")
    previous, reason = terminal.get("disposition"), terminal.get("reason_code")
    if previous not in ("applied", "already_applied", "rolled_back", "failed"):
        return payload(context, "failed", "journal_conflict")
    if not isinstance(reason, str) or not SAFE_ID.fullmatch(reason):
        return payload(context, "failed", "journal_conflict")
    digest, mode = live_image(context)
    context["before_digest"] = terminal["before_sha256"]
    common = {"before_sha256": terminal["before_sha256"], "after_sha256": terminal["after_sha256"]}
    if previous in ("applied", "already_applied"):
        valid = digest == terminal["after_sha256"] and mode == terminal["original_mode"]
        valid = valid and postcondition(context["target"].read_bytes(), context["fixer"], context["line_number"])
        if valid:
            return payload(context, "already_applied", reason, postcondition_verified=True, **common)
        return payload(context, "failed", "journal_conflict", **common)
    if previous == "rolled_back" and digest == terminal["before_sha256"] and mode == terminal["original_mode"]:
        return payload(context, "rolled_back", reason, rollback_verified=True, **common)
    return payload(context, "failed", reason if previous == "failed" else "journal_conflict", **common)


def load_prepared(context: dict[str, Any]) -> tuple[dict[str, Any], bytes, bytes] | None:
    prepared = read_json(context["prepared_path"])
    if not transaction_record_valid(context, prepared):
        return None
    before_path, candidate_path = context["before_path"], context["candidate_path"]
    if before_path.is_symlink() or candidate_path.is_symlink():
        return None
    if not before_path.is_file() or not candidate_path.is_file():
        return None
    before_data, candidate = before_path.read_bytes(), candidate_path.read_bytes()
    if sha256_bytes(before_data) != prepared.get("before_sha256"):
        return None
    if sha256_bytes(candidate) != prepared.get("after_sha256"):
        return None
    return prepared, before_data, candidate


def rollback(context: dict[str, Any], prepared: dict[str, Any], before_data: bytes) -> dict[str, Any]:
    atomic_replace_target(context["target"], before_data, prepared["original_mode"])
    digest, mode = live_image(context)
    rollback_ok = digest == prepared["before_sha256"] and mode == prepared["original_mode"]
    disposition = "rolled_back" if rollback_ok else "failed"
    reason = "postcondition_rolled_back" if rollback_ok else "rollback_integrity_failure"
    write_terminal(context["terminal_path"], prepared, disposition, reason)
    return payload(
        context, disposition, reason,
        before_sha256=prepared["before_sha256"], after_sha256=prepared["after_sha256"],
        rollback_verified=rollback_ok,
    )


def apply_candidate(
    context: dict[str, Any], prepared: dict[str, Any], before_data: bytes, candidate: bytes
) -> dict[str, Any]:
    atomic_replace_target(context["target"], candidate, prepared["original_mode"])
    maybe_perturb_target(context, "after_target_replace")
    maybe_failpoint(context["workspace"], "after_target_replace")
    digest, mode = live_image(context)
    valid_image = digest == prepared["after_sha256"] and mode == prepared["original_mode"]
    if not valid_image or not postcondition(context["target"].read_bytes(), context["fixer"], context["line_number"]):
        return rollback(context, prepared, before_data)
    write_terminal(context["terminal_path"], prepared, "applied", "eligible_applied")
    return payload(
        context, "applied", "eligible_applied",
        before_sha256=prepared["before_sha256"], after_sha256=prepared["after_sha256"],
        postcondition_verified=True,
    )


def replay_prepared(context: dict[str, Any]) -> dict[str, Any]:
    loaded = load_prepared(context)
    if loaded is None:
        return payload(context, "failed", "journal_conflict")
    prepared, before_data, candidate = loaded
    current, current_mode = live_image(context)
    context["before_digest"] = prepared["before_sha256"]
    if current == prepared["before_sha256"]:
        return apply_candidate(context, prepared, before_data, candidate)
    if current == prepared["after_sha256"]:
        if current_mode != prepared["original_mode"]:
            return rollback(context, prepared, before_data)
        if postcondition(context["target"].read_bytes(), context["fixer"], context["line_number"]):
            write_terminal(context["terminal_path"], prepared, "already_applied", "recovered_applied")
            return payload(
                context, "already_applied", "recovered_applied",
                before_sha256=prepared["before_sha256"], after_sha256=prepared["after_sha256"],
                postcondition_verified=True,
            )
        return rollback(context, prepared, before_data)
    return payload(context, "failed", "journal_conflict", before_sha256=current, after_sha256=prepared["after_sha256"])


def create_prepared(context: dict[str, Any], before_data: bytes, candidate: bytes, mode: int) -> dict[str, Any]:
    durable_create(context["before_path"], before_data)
    durable_create(context["candidate_path"], candidate)
    prepared = {
        "transaction_id": context["args"].transaction_id,
        "finding_id": context["finding_id"],
        "finding_class": context["finding_class"],
        "detector_version": context["detector"],
        "fixer_id": context["fixer"],
        "target": context["target_rel"],
        "line": context["line_number"],
        "before_sha256": context["before_digest"],
        "after_sha256": sha256_bytes(candidate),
        "original_mode": stat.S_IMODE(mode),
        "before_companion_sha256": sha256_file(context["before_path"]),
        "candidate_companion_sha256": sha256_file(context["candidate_path"]),
        "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    durable_json(context["prepared_path"], prepared)
    maybe_failpoint(context["workspace"], "after_prepared")
    return prepared


def start_transaction(context: dict[str, Any], mode: int) -> dict[str, Any]:
    if context["before_path"].exists() or context["candidate_path"].exists():
        return payload(context, "failed", "journal_conflict")
    before_data = context["target"].read_bytes()
    candidate = transform(before_data, context["fixer"], context["line_number"])
    after_digest = sha256_bytes(candidate)
    if after_digest == context["before_digest"] or not postcondition(
        candidate, context["fixer"], context["line_number"]
    ):
        return payload(context, "advisory", "postcondition_not_applicable")
    prepared = create_prepared(context, before_data, candidate, mode)
    if sha256_file(context["target"]) != context["before_digest"]:
        return payload(context, "advisory", "stale_preimage", after_sha256=after_digest)
    return apply_candidate(context, prepared, before_data, candidate)


def run_locked(context: dict[str, Any]) -> dict[str, Any]:
    locked_digest = revalidate_locked_target(context)
    if context["terminal_path"].exists():
        return replay_terminal(context)
    if context["prepared_path"].exists():
        return replay_prepared(context)
    context["before_digest"] = locked_digest
    if locked_digest != context["finding"].get("preimage_sha256"):
        return payload(context, "advisory", "stale_preimage")
    return start_transaction(context, stat.S_IMODE(context["target"].stat().st_mode))


def execute_transaction(context: dict[str, Any]) -> dict[str, Any]:
    args, workspace = context["args"], context["workspace"]
    lock_dir = workspace / f"datarim/qa/.self-verify-auto-fix-{args.task}-{args.stage}.lock"
    owner = acquire_lock(lock_dir, args.transaction_id)
    if owner is None:
        return payload(context, "advisory", "lock_conflict")
    try:
        return run_locked(context)
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError):
        return payload(context, "failed", "journal_conflict")
    finally:
        release_lock(lock_dir, owner)


def recover_finding_id(args: argparse.Namespace) -> str:
    try:
        finding = read_json(Path(args.finding_file))
        finding_id = finding.get("finding_id")
        if isinstance(finding_id, str) and SAFE_ID.fullmatch(finding_id):
            return finding_id
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    return ""


def main() -> int:
    args = parse_args()
    try:
        context = load_request(args)
    except RuntimeError as error:
        print(f"self-verify-auto-fix: {error}", file=sys.stderr)
        return 2
    except PermissionError as error:
        emit(result(recover_finding_id(args), "advisory", str(error)))
        return 0
    except (OSError, ValueError, json.JSONDecodeError):
        emit(result("", "advisory", "invalid_input"))
        return 0
    for validator in (validate_target, validate_history, prepare_journal):
        outcome = validator(context)
        if outcome is not None:
            emit(outcome)
            return 0
    emit(execute_transaction(context))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
