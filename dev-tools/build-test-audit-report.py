#!/usr/bin/env python3
"""Build a bounded, read-only report for an explicit test selection."""
from __future__ import annotations

import argparse
from decimal import Decimal, InvalidOperation
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys


MAX_SELECTION_BYTES = 64 * 1024
MAX_TEST_BYTES = 256 * 1024
MAX_RECEIPT_BYTES = 64 * 1024
MAX_EVIDENCE_FILES = 20
MAX_AGGREGATE_BYTES = 2 * 1024 * 1024
MAX_PATH_BYTES = 4096
MAX_POINTER_BYTES = 512
MAX_RATIONALE_BYTES = 512
MAX_LIMITS_BYTES = 512
CARD_FIELDS = ("protects", "fails_when", "why_new", "seam", "no_claim")
COST_FIELDS = ("wall_time_ms", "flaky_attempts")
ACTIONS = ("retain", "merge", "refactor", "retire")
SENSITIVE_COMPONENTS = {
    ".git", ".credentials", ".secrets", "credentials", "secrets", "secret",
    ".ssh", "keys", "vault", "private", "certificates",
}
SENSITIVE_SUFFIXES = {".pem", ".key", ".p12", ".pfx", ".kdbx"}
ABSOLUTE_PATH_TEXT = re.compile(r"(?<![A-Za-z0-9._-])/(?!/)[^\s,;)]*")
URI_TEXT = re.compile(r"\b(?:https?|file|ssh|git)://", re.IGNORECASE)
WINDOWS_PATH_TEXT = re.compile(r"\b[A-Za-z]:[\\/]")
SECRET_TEXT = re.compile(
    r"(?:\bBearer\s+\S+|\b(?:password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+|"
    r"\bgh[pousr]_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9_-]{20,})",
    re.IGNORECASE,
)
CONTROL_TEXT = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
SHA256_TEXT = re.compile(r"^[0-9a-f]{64}$")


class AuditError(Exception):
    """A fixed, non-sensitive input or report diagnostic."""

    def __init__(self, code: str):
        self.code = code


class FixedArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        del message
        raise AuditError("CLI_USAGE")


class ReadBudget:
    def __init__(self) -> None:
        self.total = 0

    def check(self, size: int) -> None:
        if size < 0 or self.total + size > MAX_AGGREGATE_BYTES:
            raise AuditError("AGGREGATE_READ_LIMIT")

    def add(self, size: int) -> None:
        self.total += size


def _pairs_without_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    del value
    raise ValueError("non-finite JSON number")


def _decode_json(raw: bytes, code: str) -> object:
    try:
        return json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_pairs_without_duplicates,
            parse_float=Decimal,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, InvalidOperation, ValueError, RecursionError):
        raise AuditError(code) from None


def _contains_sensitive_path(path: PurePosixPath) -> bool:
    parts = [part.casefold() for part in path.parts]
    if any(part in SENSITIVE_COMPONENTS or part.startswith(".env") for part in parts):
        return True
    return path.suffix.casefold() in SENSITIVE_SUFFIXES


def _relative_path(value: object, code: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise AuditError(code)
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError:
        raise AuditError(code) from None
    if len(encoded) > MAX_PATH_BYTES or value.startswith("/") or ":" in value:
        raise AuditError(code)
    raw_parts = value.split("/")
    if any(part in {"", ".", ".."} or any(char in part for char in "*?[]") for part in raw_parts):
        raise AuditError(code)
    path = PurePosixPath(value)
    if path.is_absolute() or _contains_sensitive_path(path):
        raise AuditError(code)
    return value


def _resolved_regular_file(root: Path, relative: str, failure_code: str) -> Path:
    candidate = root
    try:
        for index, component in enumerate(PurePosixPath(relative).parts):
            candidate = candidate / component
            info = candidate.lstat()
            if stat.S_ISLNK(info.st_mode):
                raise AuditError("INPUT_SYMLINK")
            if index < len(PurePosixPath(relative).parts) - 1 and not stat.S_ISDIR(info.st_mode):
                raise AuditError(failure_code)
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
        if not stat.S_ISREG(resolved.stat().st_mode):
            raise AuditError("INPUT_NOT_REGULAR")
        return resolved
    except AuditError:
        raise
    except (OSError, RuntimeError, ValueError):
        raise AuditError(failure_code) from None


def _read_bounded(
    root: Path,
    relative: str,
    per_file_limit: int,
    budget: ReadBudget,
    failure_code: str,
) -> bytes:
    path = _resolved_regular_file(root, relative, failure_code)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except PermissionError:
        raise AuditError("INPUT_UNREADABLE") from None
    except OSError:
        raise AuditError(failure_code) from None

    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AuditError("INPUT_NOT_REGULAR")
        if before.st_mode & 0o444 == 0:
            raise AuditError("INPUT_UNREADABLE")
        if before.st_size > per_file_limit:
            raise AuditError(failure_code.replace("READ_FAILED", "TOO_LARGE"))
        budget.check(before.st_size)
        remaining = before.st_size
        chunks: list[bytes] = []
        while remaining:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                raise AuditError("INPUT_CHANGED")
            chunks.append(chunk)
            remaining -= len(chunk)
        after = os.fstat(descriptor)
        stamp_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
        stamp_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        if stamp_before != stamp_after:
            raise AuditError("INPUT_CHANGED")
        raw = b"".join(chunks)
        if len(raw) != before.st_size:
            raise AuditError("INPUT_CHANGED")
        budget.add(len(raw))
        return raw
    except AuditError:
        raise
    except OSError:
        raise AuditError("INPUT_UNREADABLE") from None
    finally:
        os.close(descriptor)


def _bounded_text(value: object, limit: int) -> str:
    if not isinstance(value, str) or not value.strip() or "\n" in value or "\r" in value:
        raise AuditError("TEXT_INVALID")
    try:
        if len(value.encode("utf-8")) > limit:
            raise AuditError("TEXT_INVALID")
    except UnicodeEncodeError:
        raise AuditError("TEXT_INVALID") from None
    if CONTROL_TEXT.search(value) or ABSOLUTE_PATH_TEXT.search(value) or URI_TEXT.search(value):
        raise AuditError("TEXT_INVALID")
    if "\\" in value or WINDOWS_PATH_TEXT.search(value) or SECRET_TEXT.search(value):
        raise AuditError("TEXT_INVALID")
    return value


def _expect_keys(value: object, expected: set[str], code: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != expected:
        raise AuditError(code)
    return value


def _normalize_card(value: object) -> dict[str, str]:
    card_obj = _expect_keys(value, set(CARD_FIELDS), "CARD_INVALID")
    return {field: _bounded_text(card_obj[field], 160) for field in CARD_FIELDS}


def _normalize_overlaps(value: object) -> list[str]:
    if not isinstance(value, list) or len(value) > 20:
        raise AuditError("SELECTION_INVALID")
    paths = [_relative_path(item, "OVERLAP_NOT_SELECTED") for item in value]
    if len(set(paths)) != len(paths):
        raise AuditError("SELECTION_INVALID")
    return paths


def _normalize_evidence_refs(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        raise AuditError("SELECTION_INVALID")
    refs: list[dict[str, object]] = []
    seen: set[str] = set()
    for raw_ref in value:
        ref = _expect_keys(raw_ref, {"path", "sha256", "cost_pointers"}, "EVIDENCE_INVALID")
        path = _relative_path(ref["path"], "EVIDENCE_PATH_INVALID")
        if not path.casefold().endswith(".json"):
            raise AuditError("EVIDENCE_PATH_INVALID")
        if path in seen:
            raise AuditError("EVIDENCE_INVALID")
        seen.add(path)
        digest = ref["sha256"]
        if not isinstance(digest, str) or not SHA256_TEXT.fullmatch(digest):
            raise AuditError("EVIDENCE_DIGEST_INVALID")
        pointers = ref["cost_pointers"]
        if not isinstance(pointers, dict) or set(pointers) - set(COST_FIELDS):
            raise AuditError("EVIDENCE_INVALID")
        normalized: dict[str, str] = {}
        for field, pointer in pointers.items():
            if not isinstance(pointer, str) or _pointer_tokens(pointer) is None:
                raise AuditError("EVIDENCE_POINTER_INVALID")
            normalized[field] = pointer
        refs.append({"path": path, "sha256": digest, "cost_pointers": normalized})
    return refs


def _normalize_entry(value: object) -> dict[str, object]:
    entry = _expect_keys(
        value,
        {"test_path", "card", "proposed_action", "rationale", "limits", "overlap_with", "evidence_refs"},
        "SELECTION_INVALID",
    )
    test_path = _relative_path(entry["test_path"], "TEST_PATH_INVALID")
    action = entry["proposed_action"]
    if not isinstance(action, str) or action not in ACTIONS:
        raise AuditError("ACTION_UNKNOWN")
    return {
        "test_path": test_path,
        "card": _normalize_card(entry["card"]),
        "proposed_action": action,
        "rationale": _bounded_text(entry["rationale"], MAX_RATIONALE_BYTES),
        "limits": _bounded_text(entry["limits"], MAX_LIMITS_BYTES),
        "overlap_with": _normalize_overlaps(entry["overlap_with"]),
        "evidence_refs": _normalize_evidence_refs(entry["evidence_refs"]),
    }


def _validate_selection(selection: object) -> list[dict[str, object]]:
    top = _expect_keys(selection, {"schema_version", "tests"}, "SELECTION_INVALID")
    tests = top["tests"]
    if isinstance(top["schema_version"], bool) or top["schema_version"] != 1:
        raise AuditError("SELECTION_INVALID")
    if not isinstance(tests, list) or not 1 <= len(tests) <= 20:
        raise AuditError("SELECTION_COUNT_INVALID")
    entries = [_normalize_entry(entry) for entry in tests]
    paths = [entry["test_path"] for entry in entries]
    if len(set(paths)) != len(paths):
        raise AuditError("SELECTION_DUPLICATE_TEST")
    selected = set(paths)
    for entry in entries:
        if any(path not in selected or path == entry["test_path"] for path in entry["overlap_with"]):
            raise AuditError("OVERLAP_NOT_SELECTED")
    return entries


def _pointer_tokens(pointer: str) -> list[str] | None:
    try:
        encoded = pointer.encode("utf-8")
    except UnicodeEncodeError:
        return None
    if len(encoded) > MAX_POINTER_BYTES or (pointer != "" and not pointer.startswith("/")):
        return None
    if pointer == "":
        return []
    tokens: list[str] = []
    for raw in pointer[1:].split("/"):
        if re.search(r"~(?![01])", raw):
            return None
        tokens.append(raw.replace("~1", "/").replace("~0", "~"))
    return tokens


def _pointer_value(document: object, pointer: str) -> object:
    tokens = _pointer_tokens(pointer)
    if tokens is None:
        raise AuditError("EVIDENCE_POINTER_INVALID")
    value = document
    for token in tokens:
        if isinstance(value, dict):
            if token not in value:
                raise AuditError("EVIDENCE_POINTER_INVALID")
            value = value[token]
        elif isinstance(value, list):
            if not re.fullmatch(r"0|[1-9][0-9]*", token):
                raise AuditError("EVIDENCE_POINTER_INVALID")
            index = int(token)
            if index >= len(value):
                raise AuditError("EVIDENCE_POINTER_INVALID")
            value = value[index]
        else:
            raise AuditError("EVIDENCE_POINTER_INVALID")
    return value


def _valid_cost(value: object) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, Decimal):
        if not value.is_finite() or value < 0:
            return False
        try:
            converted = float(value)
        except (OverflowError, ValueError):
            return False
        return math.isfinite(converted) and (value.is_zero() or converted != 0)
    if not isinstance(value, (int, float)) or value < 0:
        return False
    return not isinstance(value, float) or math.isfinite(value)


def _load_input_files(
    root: Path,
    selection_path: str,
    entries: list[dict[str, object]],
    budget: ReadBudget,
) -> tuple[dict[str, bytes], dict[str, object], dict[str, str]]:
    test_paths = [entry["test_path"] for entry in entries]
    evidence_defs: dict[str, str] = {}
    for entry in entries:
        for ref in entry["evidence_refs"]:
            path, digest = ref["path"], ref["sha256"]
            if path in test_paths or path == selection_path:
                raise AuditError("INPUT_PATH_ROLE_CONFLICT")
            if path in evidence_defs and evidence_defs[path] != digest:
                raise AuditError("EVIDENCE_DIGEST_INVALID")
            evidence_defs[path] = digest
    if len(evidence_defs) > MAX_EVIDENCE_FILES:
        raise AuditError("EVIDENCE_COUNT_LIMIT")

    source_bytes = {
        path: _read_bounded(root, path, MAX_TEST_BYTES, budget, "TEST_READ_FAILED")
        for path in test_paths
    }
    receipt_docs: dict[str, object] = {}
    receipt_hashes: dict[str, str] = {}
    for path, expected in evidence_defs.items():
        raw = _read_bounded(root, path, MAX_RECEIPT_BYTES, budget, "EVIDENCE_READ_FAILED")
        actual = hashlib.sha256(raw).hexdigest()
        if actual != expected:
            raise AuditError("EVIDENCE_DIGEST_MISMATCH")
        receipt_docs[path] = _decode_json(raw, "EVIDENCE_JSON_INVALID")
        receipt_hashes[path] = actual
    return source_bytes, receipt_docs, receipt_hashes


def _costs_for_entry(
    entry: dict[str, object], receipt_docs: dict[str, object], receipt_hashes: dict[str, str]
) -> tuple[list[dict[str, object]], dict[str, object]]:
    refs_out: list[dict[str, object]] = []
    metric_sources: dict[str, tuple[str, str, object]] = {}
    for ref in entry["evidence_refs"]:
        path, pointers = ref["path"], ref["cost_pointers"]
        refs_out.append({"path": path, "sha256": receipt_hashes[path], "cost_pointers": dict(pointers)})
        for metric, pointer in pointers.items():
            if metric in metric_sources:
                raise AuditError("EVIDENCE_POINTER_DUPLICATE")
            metric_sources[metric] = (path, pointer, _pointer_value(receipt_docs[path], pointer))

    costs: dict[str, object] = {}
    for metric in COST_FIELDS:
        source = metric_sources.get(metric)
        if source is None:
            costs[metric] = {"status": "NOT_MEASURED", "value": None, "reason": "NO_CITED_OBSERVATION"}
            continue
        path, pointer, value = source
        if not _valid_cost(value):
            raise AuditError("EVIDENCE_VALUE_INVALID")
        costs[metric] = {
            "status": "OBSERVED_IN_RECEIPT", "value": float(value) if isinstance(value, Decimal) else value,
            "evidence": {"path": path, "sha256": receipt_hashes[path], "json_pointer": pointer},
        }
    return refs_out, costs


def _report_entry(
    entry: dict[str, object], source_bytes: dict[str, bytes],
    receipt_docs: dict[str, object], receipt_hashes: dict[str, str],
) -> dict[str, object]:
    refs, costs = _costs_for_entry(entry, receipt_docs, receipt_hashes)
    return {
        "test_path": entry["test_path"],
        "source_sha256": hashlib.sha256(source_bytes[entry["test_path"]]).hexdigest(),
        "card": dict(entry["card"]), "proposed_action": entry["proposed_action"],
        "rationale": entry["rationale"], "limits": entry["limits"],
        "overlap_with": list(entry["overlap_with"]), "evidence_refs": refs, "costs": costs,
    }


def build_report(root_arg: str, selection_arg: str) -> dict[str, object]:
    try:
        root = Path(root_arg).resolve(strict=True)
    except (OSError, RuntimeError, ValueError):
        raise AuditError("ROOT_INVALID") from None
    if not root.is_dir():
        raise AuditError("ROOT_INVALID")
    selection_path = _relative_path(selection_arg, "SELECTION_PATH_INVALID")
    budget = ReadBudget()
    selection_bytes = _read_bounded(root, selection_path, MAX_SELECTION_BYTES, budget, "SELECTION_READ_FAILED")
    selection = _validate_selection(_decode_json(selection_bytes, "SELECTION_INVALID"))
    source_bytes, receipt_docs, receipt_hashes = _load_input_files(root, selection_path, selection, budget)
    tests_out = [_report_entry(entry, source_bytes, receipt_docs, receipt_hashes) for entry in selection]

    return {
        "schema": "datarim.test-audit-report/v1",
        "selection": {"path": selection_path, "sha256": hashlib.sha256(selection_bytes).hexdigest()},
        "tests": tests_out,
    }


def _parser() -> argparse.ArgumentParser:
    parser = FixedArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--root", required=True, help="owned project root")
    parser.add_argument("--selection", required=True, help="root-relative versioned JSON selection")
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        args = _parser().parse_args(argv)
        report = build_report(args.root, args.selection)
        rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        sys.stdout.write(rendered + "\n")
        return 0
    except AuditError as error:
        sys.stderr.write(f"ERROR {error.code}\n")
        return 2
    except BrokenPipeError:
        return 2
    except Exception:
        sys.stderr.write("ERROR REPORT_FAILED\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
