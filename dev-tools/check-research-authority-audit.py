#!/usr/bin/env python3
"""Validate a pinned research authority audit and its mutation-sensitive joins."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import quote


HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ITEM_ID = re.compile(r"^R[12]-[0-9]{2}$")
SOURCE_HEADING = re.compile(r"^## (R[12]-[0-9]{2}) · (.+)$", re.MULTILINE)
INLINE_SOURCE_HEADING = re.compile(
    r"^\*\*(R[12]-[0-9]{2}) · (.+?)\*\*", re.MULTILINE | re.DOTALL
)
CYRILLIC = re.compile(r"[\u0400-\u04ff]")
TASK_REF = re.compile(r"TALO-[0-9]{4}")
COMMENT_ALGORITHM = "github-json-body-utf8-no-extra-lf/1"
ITEM_ALGORITHM = "cells-trimmed-unit-separator-rows-lf-no-final-lf/1"
MAX_EXTERNAL_SOURCE_BYTES = 16 * 1024 * 1024
CLOSED_AUDIT_PROFILES: dict[str, dict[str, Any]] = {
    "TALO-0001": {
        "candidates": {
            "tal-role-design-lead@r4": "tal-role-design-lead",
            "tal-role-knowledge-curator@r2": "tal-role-knowledge-curator",
            "tal-role-evidence-auditor@r2": "tal-role-evidence-auditor",
            "tal-role-deployment-operator@r2": "tal-role-deployment-operator",
            "tal-skill-design-research@r3": "tal-skill-design-research",
            "datarim-skill-frontend-ui@r2": "datarim-skill-frontend-ui",
            "datarim-skill-playwright-qa@r2": "datarim-skill-playwright-qa",
            "tal-skill-theming-anti-fouc@r3": "tal-skill-theming-anti-fouc",
            "tal-skill-graph-neighbor-visualization@r1": (
                "tal-skill-graph-neighbor-visualization"
            ),
            "tal-skill-success-criterion-measurement@r2": (
                "tal-skill-success-criterion-measurement"
            ),
            "tal-blueprint-design-system-atlas@r4": "tal-blueprint-design-system-atlas",
            "tal-blueprint-component-library@r4": "tal-blueprint-component-library",
            "tal-blueprint-evidence-bearing-verification@r2": (
                "tal-blueprint-evidence-bearing-verification"
            ),
            "tal-constraint-style-guide@r4": "tal-constraint-style-guide",
            "tal-constraint-sanitized-projection@r2": (
                "tal-constraint-sanitized-projection"
            ),
            "tal-policy-honesty-presentation@r2": "tal-policy-honesty-presentation",
            "tal-sc-design-accessibility@r2": "tal-sc-design-accessibility",
            "tal-sc-design-system@r2": "tal-sc-design-system",
            "tal-capability-design-systems@r1": "tal-capability-design-systems",
        },
        "derived_records": {
            "TALO-0032-planning-envelope": {
                "record_type": "planning-envelope",
                "pointers": {
                    "/contract/contract_digest",
                    "/contract/body/resolution_receipt_digest",
                    "/issuance_envelope/envelope_digest",
                },
            },
            "TALO-0050-planning-envelope": {
                "record_type": "planning-envelope",
                "pointers": {
                    "/contract/contract_digest",
                    "/contract/body/resolution_receipt_digest",
                    "/issuance_envelope/envelope_digest",
                },
            },
            "tal-skill-customer-narrative@r1": {
                "record_type": "approved-artifact",
                "pointers": {"/logical_id", "/revision_id", "/content_digest"},
            },
        },
        "external_source_ids": {"S20", "S21", "S22", "S23", "S24", "S27", "S28", "S29"},
        "comment_ids": {"5347868439", "5347971637"},
    },
    "TALO-TEST": {
        "candidates": {"candidate-role@r1": "candidate-role"},
        "derived_records": {
            "planning": {
                "record_type": "planning-envelope",
                "pointers": {
                    "/contract/contract_digest",
                    "/contract/body/resolution_receipt_digest",
                    "/issuance_envelope/envelope_digest",
                },
            },
            "candidate-role@r1": {
                "record_type": "approved-artifact",
                "pointers": {"/logical_id", "/revision_id", "/content_digest"},
            },
        },
        "external_source_ids": {"S20"},
        "comment_ids": {"101"},
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate item-level research authority, candidate approvals, and source pins."
    )
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--insights", required=True, type=Path)
    parser.add_argument("--knowledge-root", required=True, type=Path)
    parser.add_argument(
        "--comment-json",
        action="append",
        default=[],
        metavar="ID=PATH",
        help="GitHub API JSON response used to replay a canonical comment-body digest.",
    )
    parser.add_argument("--external-cache-dir", type=Path)
    parser.add_argument(
        "--verify-external-remote",
        action="store_true",
        help="Fetch each derived immutable raw URL and bind the cache to live remote bytes.",
    )
    return parser.parse_args()


def load_json(path: Path, label: str, findings: list[str]) -> Any | None:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        return json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        findings.append(f"invalid_json:{label}")
        return None


def load_json_bytes(content: bytes, label: str, findings: list[str]) -> Any | None:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        return json.loads(content.decode("utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (UnicodeError, json.JSONDecodeError, ValueError):
        findings.append(f"invalid_json:{label}")
        return None


def safe_relative_path(root: Path, raw_path: Any) -> Path | None:
    if not isinstance(raw_path, str):
        return None
    posix = PurePosixPath(raw_path)
    if posix.is_absolute() or not posix.parts or ".." in posix.parts:
        return None
    candidate = root.joinpath(*posix.parts)
    try:
        candidate.resolve(strict=False).relative_to(root.resolve())
    except (OSError, ValueError):
        return None
    return candidate


def safe_git_source_path(raw_path: Any) -> PurePosixPath | None:
    """Return an unambiguous repository-relative Git path, without filesystem I/O."""
    if not isinstance(raw_path, str) or not raw_path or ":" in raw_path:
        return None
    posix = PurePosixPath(raw_path)
    if (
        posix.is_absolute()
        or not posix.parts
        or any(part in {".", ".."} for part in posix.parts)
        or posix.as_posix() != raw_path
    ):
        return None
    return posix


def git_value(root: Path, *arguments: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
            env={**os.environ, "GIT_NO_REPLACE_OBJECTS": "1"},
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip()


def git_object_bytes(
    root: Path,
    snapshot: str,
    raw_path: Any,
    findings: list[str] | None = None,
    label: str = "git-object",
) -> bytes | None:
    if safe_git_source_path(raw_path) is None:
        return None
    object_id = git_value(root, "rev-parse", "--verify", f"{snapshot}:{raw_path}")
    if object_id is None or HEX40.fullmatch(object_id) is None:
        return None
    object_type = git_value(root, "cat-file", "-t", object_id)
    if object_type != "blob":
        if findings is not None:
            findings.append(f"git_object_type_invalid:{label}")
        return None
    raw_size = git_value(root, "cat-file", "-s", object_id)
    try:
        object_size = int(raw_size) if raw_size is not None else -1
    except ValueError:
        object_size = -1
    if object_size < 0:
        if findings is not None:
            findings.append(f"git_object_size_invalid:{label}")
        return None
    if object_size > MAX_EXTERNAL_SOURCE_BYTES:
        if findings is not None:
            findings.append(f"git_object_too_large:{label}")
        return None
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(
                ["git", "-C", str(root), "cat-file", "blob", object_id],
                stdout=output,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=5,
                env={**os.environ, "GIT_NO_REPLACE_OBJECTS": "1"},
            )
            if result.returncode != 0:
                return None
            output.seek(0)
            content = output.read(MAX_EXTERNAL_SOURCE_BYTES + 1)
    except (OSError, subprocess.SubprocessError):
        return None
    if len(content) != object_size or len(content) > MAX_EXTERNAL_SOURCE_BYTES:
        if findings is not None:
            findings.append(f"git_object_size_mismatch:{label}")
        return None
    return content


def git_blob_id(content: bytes) -> str | None:
    if len(content) > MAX_EXTERNAL_SOURCE_BYTES:
        return None
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(
                ["git", "hash-object", "--stdin"],
                input=content,
                stdout=output,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=5,
            )
            if result.returncode != 0:
                return None
            output.seek(0)
            value = output.read(129).decode("ascii", errors="strict").strip()
    except (OSError, UnicodeError, subprocess.SubprocessError):
        return None
    return value if HEX40.fullmatch(value) is not None else None


def fetch_remote_source(url: str) -> bytes | None:
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(
                [
                    "curl",
                    "--fail",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--max-time",
                    "15",
                    "--max-filesize",
                    str(MAX_EXTERNAL_SOURCE_BYTES),
                    "--proto",
                    "=https",
                    url,
                ],
                stdout=output,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=20,
            )
            if result.returncode != 0:
                return None
            output.seek(0)
            content = output.read(MAX_EXTERNAL_SOURCE_BYTES + 1)
    except (OSError, subprocess.SubprocessError):
        return None
    return content if len(content) <= MAX_EXTERNAL_SOURCE_BYTES else None


def table_rows(insights: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in insights.splitlines():
        if not re.match(r"^\|\s*R[12]-[0-9]{2}\s*\|", line):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 4 and ITEM_ID.fullmatch(cells[0]):
            rows.append(cells)
    return rows


def item_table_digest(rows: list[list[str]]) -> str:
    canonical = "\n".join("\x1f".join(cells) for cells in rows).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def source_item_headings(source_text: str) -> list[tuple[str, str]]:
    matches = list(SOURCE_HEADING.finditer(source_text)) + list(
        INLINE_SOURCE_HEADING.finditer(source_text)
    )
    matches.sort(key=lambda match: match.start())
    return [
        (match.group(1), re.sub(r"\s+", " ", match.group(2)).strip())
        for match in matches
    ]


def mapping_targets(value: str) -> tuple[str, ...]:
    targets = {f"TALO-{match}" for match in re.findall(r"TALO-([0-9]{4})", value)}
    targets.update(
        f"TALO-{match}"
        for match in re.findall(r"(?<![A-Za-z0-9-])(00[0-9]{2})(?![0-9])", value)
    )
    if "all subtasks" in value.lower():
        targets.add("ALL_SUBTASKS")
    return tuple(sorted(targets))


def mapping_rows(source_text: str) -> dict[str, tuple[str, ...]]:
    result: dict[str, tuple[str, ...]] = {}
    mapping_index: int | None = None
    decision_index: int | None = None
    for line in source_text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        if "Subtask" in cells:
            mapping_index = cells.index("Subtask")
            decision_index = cells.index("Decision") if "Decision" in cells else None
            continue
        if "Lands in" in cells:
            mapping_index = cells.index("Lands in")
            decision_index = cells.index("Decision") if "Decision" in cells else None
            continue
        match = re.match(r"^(R[12]-[0-9]{2})(?:\s|$)", cells[0])
        if match is not None:
            selected_index = mapping_index if mapping_index is not None else len(cells) - 1
            if selected_index < len(cells):
                targets = set(mapping_targets(cells[selected_index]))
                if decision_index is not None and decision_index < len(cells):
                    targets.update(
                        re.findall(
                            r"(?i)routes?\s+to\s+(TALO-[0-9]{4})", cells[decision_index]
                        )
                    )
                result[match.group(1)] = tuple(sorted(targets))
    return result


def validate_git_blob(
    root: Path,
    snapshot: str,
    path_value: Any,
    expected_blob: Any,
    label: str,
    findings: list[str],
) -> bytes | None:
    content = git_object_bytes(root, snapshot, path_value, findings, label)
    if content is None:
        findings.append(f"source_path_missing:{label}")
        return None
    actual_blob = git_value(root, "rev-parse", f"{snapshot}:{path_value}")
    if not isinstance(expected_blob, str) or actual_blob != expected_blob:
        findings.append(f"source_blob_mismatch:{label}")
    return content


def parse_comment_arguments(values: list[str], findings: list[str]) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        identifier, separator, raw_path = value.partition("=")
        if not separator or not identifier or not raw_path or identifier in result:
            findings.append("invalid_comment_json_argument")
            continue
        result[identifier] = Path(raw_path)
    return result


def validate_reviews_and_items(
    manifest: dict[str, Any],
    insights: str,
    knowledge_root: Path,
    snapshot: str,
    comment_bodies: dict[str, str],
    findings: list[str],
) -> int:
    reviews = manifest.get("reviews")
    if not isinstance(reviews, list) or not reviews:
        findings.append("reviews_missing")
        return 0

    source_headings: dict[str, str] = {}
    source_mappings: dict[str, tuple[str, ...]] = {}
    expected_ids: set[str] = set()
    for review in reviews:
        if not isinstance(review, dict):
            findings.append("review_invalid")
            continue
        review_id = review.get("id")
        expected_items = review.get("expected_items")
        if review_id not in ("R1", "R2") or not isinstance(expected_items, int) or expected_items < 1:
            findings.append(f"review_identity_invalid:{review_id}")
            continue
        source = validate_git_blob(
            knowledge_root,
            snapshot,
            review.get("source_path"),
            review.get("git_blob"),
            review_id,
            findings,
        )
        if source is not None:
            try:
                source_text = source.decode("utf-8")
            except UnicodeError:
                findings.append(f"source_unreadable:{review_id}")
            else:
                selected = source_item_headings(source_text)
                if len(selected) != expected_items:
                    findings.append(
                        f"source_item_count_mismatch:{review_id}:expected={expected_items}:actual={len(selected)}"
                    )
                for item_id, heading in selected:
                    if item_id in source_headings:
                        findings.append(f"source_duplicate_item_id:{item_id}")
                    source_headings[item_id] = heading
        mapping_path = review.get("mapping_source_path")
        if mapping_path is not None:
            mapping_source = validate_git_blob(
                knowledge_root,
                snapshot,
                mapping_path,
                review.get("mapping_source_git_blob"),
                f"{review_id}-mapping",
                findings,
            )
            if mapping_source is not None:
                try:
                    source_mappings.update(mapping_rows(mapping_source.decode("utf-8")))
                except UnicodeError:
                    findings.append(f"mapping_source_unreadable:{review_id}")
        mapping_comment_id = review.get("mapping_comment_id")
        if mapping_comment_id is not None:
            body = comment_bodies.get(str(mapping_comment_id))
            if body is None:
                findings.append(f"mapping_comment_evidence_missing:{review_id}")
            else:
                source_mappings.update(mapping_rows(body))
        expected_ids.update(f"{review_id}-{ordinal:02d}" for ordinal in range(1, expected_items + 1))

    rows = table_rows(insights)
    if "authorized_mapping_additions" in manifest:
        findings.append("authorized_mapping_additions_forbidden")
    counts = Counter(cells[0] for cells in rows)
    for item_id in sorted(identifier for identifier, count in counts.items() if count > 1):
        findings.append(f"duplicate_item_id:{item_id}")
    actual_ids = set(counts)
    for review in reviews:
        if not isinstance(review, dict) or review.get("id") not in ("R1", "R2"):
            continue
        review_id = review["id"]
        expected_items = review.get("expected_items")
        if not isinstance(expected_items, int):
            continue
        actual_count = sum(1 for cells in rows if cells[0].startswith(f"{review_id}-"))
        if actual_count != expected_items:
            findings.append(
                f"item_count_mismatch:{review_id}:expected={expected_items}:actual={actual_count}"
            )
    for item_id in sorted(expected_ids - actual_ids):
        findings.append(f"item_missing:{item_id}")
    for item_id in sorted(actual_ids - expected_ids):
        findings.append(f"unexpected_item:{item_id}")

    for cells in rows:
        item_id, heading, mapping, selection = cells
        if source_headings.get(item_id) != heading:
            findings.append(f"verbatim_heading_mismatch:{item_id}")
        if TASK_REF.search(mapping) is None and mapping != "Standing constraint -> all subtasks":
            findings.append(f"delivery_mapping_missing:{item_id}")
        expected_mapping = source_mappings.get(item_id)
        if expected_mapping is None:
            findings.append(f"authoritative_mapping_missing:{item_id}")
        else:
            if set(mapping_targets(mapping)) != set(expected_mapping):
                findings.append(f"delivery_mapping_mismatch:{item_id}")
        if not selection.startswith(("Direct:", "Cross-functional:", "Human boundary:")):
            findings.append(f"selection_applicability_invalid:{item_id}")
        if "Rejected" in selection:
            findings.append(f"selected_item_rejected:{item_id}")
        if manifest.get("declared_language") == "en" and any(CYRILLIC.search(cell) for cell in cells):
            findings.append(f"declared_english_contains_cyrillic:{item_id}")

    table_contract = manifest.get("item_table")
    if not isinstance(table_contract, dict):
        findings.append("item_table_contract_missing")
    else:
        if table_contract.get("canonicalization") != ITEM_ALGORITHM:
            findings.append("item_table_canonicalization_invalid")
        if table_contract.get("expected_rows") != len(rows):
            findings.append("item_table_expected_rows_mismatch")
        expected_digest = table_contract.get("sha256")
        if not isinstance(expected_digest, str) or item_table_digest(rows) != expected_digest:
            findings.append("item_table_digest_mismatch")
    return len(rows)


def validate_comments(
    manifest: dict[str, Any],
    comment_paths: dict[str, Path],
    insights: str,
    findings: list[str],
) -> dict[str, str]:
    bodies: dict[str, str] = {}
    if manifest.get("comment_body_digest_algorithm") != COMMENT_ALGORITHM:
        findings.append("comment_body_digest_algorithm_invalid")
    comments = manifest.get("comments")
    if not isinstance(comments, list):
        findings.append("comments_missing")
        return bodies
    seen: set[str] = set()
    for comment in comments:
        if not isinstance(comment, dict):
            findings.append("comment_invalid")
            continue
        identifier = str(comment.get("id", ""))
        if not identifier or identifier in seen:
            findings.append(f"comment_id_invalid:{identifier}")
            continue
        seen.add(identifier)
        repository = comment.get("repository")
        issue_number = comment.get("issue_number")
        canonical_navigation = (
            f"https://github.com/{repository}/issues/{issue_number}#issuecomment-{identifier}"
        )
        canonical_issue_api = (
            f"https://api.github.com/repos/{repository}/issues/{issue_number}"
        )
        if (
            not isinstance(repository, str)
            or re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is None
            or not isinstance(issue_number, int)
            or issue_number < 1
        ):
            findings.append(f"comment_issue_identity_invalid:{identifier}")
        if comment.get("navigation_url") != canonical_navigation:
            findings.append(f"comment_navigation_url_invalid:{identifier}")
        if canonical_navigation not in insights:
            findings.append(f"comment_navigation_not_documented:{identifier}")
        expected = comment.get("body_sha256")
        path = comment_paths.get(identifier)
        if path is None:
            findings.append(f"comment_body_evidence_missing:{identifier}")
            continue
        payload = load_json(path, f"comment-{identifier}", findings)
        if not isinstance(payload, dict) or not isinstance(payload.get("body"), str):
            findings.append(f"comment_body_invalid:{identifier}")
            continue
        if str(payload.get("id", "")) != identifier:
            findings.append(f"comment_payload_id_mismatch:{identifier}")
        if payload.get("html_url") != canonical_navigation:
            findings.append(f"comment_payload_html_url_mismatch:{identifier}")
        if payload.get("issue_url") != canonical_issue_api:
            findings.append(f"comment_payload_issue_url_mismatch:{identifier}")
        bodies[identifier] = payload["body"]
        actual = hashlib.sha256(payload["body"].encode("utf-8")).hexdigest()
        if not isinstance(expected, str) or actual != expected:
            findings.append(f"comment_body_digest_mismatch:{identifier}")
    return bodies


def report_closed_set(
    label: str,
    actual_values: list[Any],
    expected_values: set[str],
    findings: list[str],
) -> None:
    if ":" in label:
        category, identity = label.split(":", 1)
        finding_prefix = f"{category}_set_mismatch:{identity}"
    else:
        finding_prefix = f"{label}_set_mismatch"
    actual = {value for value in actual_values if isinstance(value, str)}
    missing = sorted(expected_values - actual)
    extra = sorted(actual - expected_values)
    if missing:
        findings.append(f"{finding_prefix}:missing={','.join(missing)}")
    if extra:
        findings.append(f"{finding_prefix}:extra={','.join(extra)}")
    duplicates = sorted(
        value
        for value, count in Counter(
            value for value in actual_values if isinstance(value, str)
        ).items()
        if count > 1
    )
    if duplicates:
        findings.append(f"{finding_prefix}:duplicate={','.join(duplicates)}")


def validate_closed_profile(manifest: dict[str, Any], findings: list[str]) -> None:
    task_id = manifest.get("task_id")
    profile = CLOSED_AUDIT_PROFILES.get(task_id)
    if profile is None:
        findings.append(f"task_id_invalid:{task_id}")
        findings.append(f"closed_audit_profile_missing:{task_id}")
        return

    candidates = manifest.get("candidates")
    candidate_entries = candidates if isinstance(candidates, list) else []
    report_closed_set(
        "candidate",
        [
            entry.get("revision_id")
            for entry in candidate_entries
            if isinstance(entry, dict)
        ],
        set(profile["candidates"]),
        findings,
    )

    records = manifest.get("derived_records")
    record_entries = records if isinstance(records, list) else []
    expected_records = profile["derived_records"]
    report_closed_set(
        "derived_record",
        [entry.get("id") for entry in record_entries if isinstance(entry, dict)],
        set(expected_records),
        findings,
    )
    for record in record_entries:
        if not isinstance(record, dict) or record.get("id") not in expected_records:
            continue
        record_id = record["id"]
        expected_record = expected_records[record_id]
        if record.get("record_type") != expected_record["record_type"]:
            findings.append(f"derived_record_type_mismatch:{record_id}")
        assertions = record.get("assertions")
        if isinstance(assertions, list):
            pointers = [
                assertion.get("json_pointer")
                for assertion in assertions
                if isinstance(assertion, dict)
            ]
            report_closed_set(
                f"derived_record_assertion:{record_id}",
                pointers,
                set(expected_record["pointers"]),
                findings,
            )

    pins = manifest.get("external_pins")
    pin_entries = pins if isinstance(pins, list) else []
    report_closed_set(
        "external_pin",
        [entry.get("source_id") for entry in pin_entries if isinstance(entry, dict)],
        set(profile["external_source_ids"]),
        findings,
    )

    comments = manifest.get("comments")
    comment_entries = comments if isinstance(comments, list) else []
    report_closed_set(
        "comment",
        [str(entry.get("id")) for entry in comment_entries if isinstance(entry, dict)],
        set(profile["comment_ids"]),
        findings,
    )


def validate_candidates(
    manifest: dict[str, Any],
    insights: str,
    knowledge_root: Path,
    snapshot: str,
    findings: list[str],
) -> int:
    candidates = manifest.get("candidates")
    if not isinstance(candidates, list):
        findings.append("candidates_missing")
        return 0
    authority_bytes = git_object_bytes(
        knowledge_root,
        snapshot,
        manifest.get("authority_events_path"),
        findings,
        "candidate-authority-events",
    )
    events = (
        load_json_bytes(authority_bytes, "authority-events", findings)
        if authority_bytes is not None
        else None
    )
    if not isinstance(events, list):
        findings.append("authority_events_invalid")
        events = []
    seen: set[str] = set()
    for candidate in candidates:
        if not isinstance(candidate, dict):
            findings.append("candidate_invalid")
            continue
        revision_id = candidate.get("revision_id")
        path_value = candidate.get("path")
        content_digest = candidate.get("content_digest")
        if not isinstance(revision_id, str) or revision_id in seen:
            findings.append(f"candidate_revision_duplicate:{revision_id}")
            continue
        seen.add(revision_id)
        candidate_bytes = git_object_bytes(
            knowledge_root, snapshot, path_value, findings, f"candidate:{revision_id}"
        )
        if candidate_bytes is None:
            findings.append(f"candidate_path_missing:{revision_id}")
            continue
        payload = load_json_bytes(candidate_bytes, f"candidate-{revision_id}", findings)
        if not isinstance(payload, dict):
            continue
        expected_logical_id = CLOSED_AUDIT_PROFILES.get(
            manifest.get("task_id"), {}
        ).get("candidates", {}).get(revision_id)
        if payload.get("logical_id") != expected_logical_id:
            findings.append(f"candidate_logical_id_mismatch:{revision_id}")
        if payload.get("revision_id") != revision_id:
            findings.append(f"candidate_revision_mismatch:{revision_id}")
        if payload.get("content_digest") != content_digest:
            findings.append(f"candidate_digest_mismatch:{revision_id}")
        documented = any(
            isinstance(value, str) and value in line
            for value in (path_value, revision_id, content_digest)
            for line in insights.splitlines()
            if all(str(required) in line for required in (path_value, revision_id, content_digest))
        )
        if not documented:
            findings.append(f"candidate_not_documented:{revision_id}")
        matching = [
            event
            for event in events
            if isinstance(event, dict)
            and isinstance(event.get("subject"), dict)
            and event["subject"].get("id") == revision_id
        ]
        if not matching:
            findings.append(f"candidate_authority_missing:{revision_id}")
            continue
        latest = max(enumerate(matching), key=lambda pair: (str(pair[1].get("issued_at", "")), pair[0]))[1]
        if latest.get("event_type") != "approve":
            findings.append(
                f"candidate_latest_authority_not_approve:{revision_id}:{latest.get('event_type')}"
            )
        subject = latest.get("subject", {})
        if subject.get("content_digest") != content_digest:
            findings.append(f"candidate_authority_digest_mismatch:{revision_id}")
    return len(candidates)


def validate_derived_records(
    manifest: dict[str, Any],
    insights: str,
    knowledge_root: Path,
    snapshot: str,
    findings: list[str],
) -> None:
    records = manifest.get("derived_records", [])
    if not isinstance(records, list):
        findings.append("derived_records_invalid")
        return
    authority_bytes = git_object_bytes(
        knowledge_root,
        snapshot,
        manifest.get("authority_events_path"),
        findings,
        "derived-authority-events",
    )
    authority_events = (
        load_json_bytes(authority_bytes, "derived-authority-events", findings)
        if authority_bytes is not None
        else []
    )
    if not isinstance(authority_events, list):
        authority_events = []

    def pointer_value(payload: Any, pointer: str) -> Any:
        if not pointer.startswith("/"):
            raise KeyError(pointer)
        current = payload
        for token in pointer[1:].split("/"):
            token = token.replace("~1", "/").replace("~0", "~")
            if isinstance(current, dict) and token in current:
                current = current[token]
            elif isinstance(current, list) and token.isdigit() and int(token) < len(current):
                current = current[int(token)]
            else:
                raise KeyError(pointer)
        return current

    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            findings.append("derived_record_invalid")
            continue
        record_id = record["id"]
        evidence_bytes = git_object_bytes(
            knowledge_root,
            snapshot,
            record.get("evidence_path"),
            findings,
            f"derived:{record_id}",
        )
        if evidence_bytes is None:
            findings.append(f"derived_record_path_missing:{record_id}")
            continue
        payload = load_json_bytes(evidence_bytes, f"derived-{record_id}", findings)
        if payload is None:
            continue
        assertions = record.get("assertions")
        if not isinstance(assertions, list) or not assertions:
            findings.append(f"derived_record_assertions_missing:{record_id}")
            continue
        for assertion in assertions:
            if not isinstance(assertion, dict):
                findings.append(f"derived_record_assertion_invalid:{record_id}")
                continue
            pointer = assertion.get("json_pointer")
            expected = assertion.get("equals")
            if not isinstance(pointer, str) or not isinstance(expected, str):
                findings.append(f"derived_record_assertion_invalid:{record_id}")
                continue
            try:
                actual = pointer_value(payload, pointer)
            except KeyError:
                actual = None
            if actual != expected:
                findings.append(f"derived_record_pointer_mismatch:{record_id}:{pointer}")
            if expected not in insights:
                findings.append(f"derived_record_not_documented:{record_id}:{pointer}")
        authority_required = record.get("authority_required")
        if authority_required is not None:
            revision_id = record.get("authority_revision_id")
            content_digest = record.get("authority_content_digest")
            matching = [
                event
                for event in authority_events
                if isinstance(event, dict)
                and isinstance(event.get("subject"), dict)
                and event["subject"].get("id") == revision_id
            ]
            if not matching:
                findings.append(f"derived_record_authority_missing:{record_id}")
                continue
            latest = max(
                enumerate(matching),
                key=lambda pair: (str(pair[1].get("issued_at", "")), pair[0]),
            )[1]
            if latest.get("event_type") != authority_required:
                findings.append(f"derived_record_authority_state_mismatch:{record_id}")
            if latest.get("subject", {}).get("content_digest") != content_digest:
                findings.append(f"derived_record_authority_digest_mismatch:{record_id}")


def validate_external_pins(
    manifest: dict[str, Any],
    insights: str,
    cache_dir: Path | None,
    verify_remote: bool,
    findings: list[str],
) -> int:
    pins = manifest.get("external_pins")
    if not isinstance(pins, list) or not pins:
        findings.append("external_pins_missing")
        return 0
    seen: set[str] = set()
    for pin in pins:
        if not isinstance(pin, dict):
            findings.append("external_pin_invalid")
            continue
        source_id = pin.get("source_id")
        if not isinstance(source_id, str) or source_id in seen:
            findings.append(f"external_pin_id_invalid:{source_id}")
            continue
        seen.add(source_id)
        commit = pin.get("commit")
        blob = pin.get("git_blob")
        digest = pin.get("content_sha256")
        immutable_url = pin.get("immutable_url")
        repository = pin.get("repository")
        source_path = pin.get("path")
        repository_valid = isinstance(repository, str) and re.fullmatch(
            r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository
        ) is not None
        source_path_valid = safe_git_source_path(source_path) is not None
        if not repository_valid:
            findings.append(f"external_pin_repository_invalid:{source_id}")
        if not source_path_valid:
            findings.append(f"external_pin_path_invalid:{source_id}")
        if not isinstance(commit, str) or HEX40.fullmatch(commit) is None:
            findings.append(f"external_pin_commit_invalid:{source_id}")
        if not isinstance(blob, str) or HEX40.fullmatch(blob) is None:
            findings.append(f"external_pin_blob_invalid:{source_id}")
        if not isinstance(digest, str) or HEX64.fullmatch(digest) is None:
            findings.append(f"external_pin_content_digest_invalid:{source_id}")
        expected_immutable = (
            f"https://github.com/{repository}/blob/{commit}/{quote(str(source_path), safe='/')}"
        )
        if immutable_url != expected_immutable:
            findings.append(f"external_pin_immutable_url_invalid:{source_id}")
        navigation_url = pin.get("navigation_url")
        if not isinstance(navigation_url, str) or not any(
            source_id in line and navigation_url in line for line in insights.splitlines()
        ):
            findings.append(f"external_pin_navigation_not_documented:{source_id}")
        if cache_dir is None:
            findings.append(f"external_pin_cache_missing:{source_id}")
            continue
        cache_path = safe_relative_path(cache_dir, pin.get("cache_file"))
        if cache_path is None or not cache_path.is_file():
            findings.append(f"external_pin_cache_missing:{source_id}")
            continue
        try:
            with cache_path.open("rb") as handle:
                content = handle.read(MAX_EXTERNAL_SOURCE_BYTES + 1)
        except OSError:
            findings.append(f"external_pin_cache_unreadable:{source_id}")
            continue
        if len(content) > MAX_EXTERNAL_SOURCE_BYTES:
            findings.append(f"external_pin_cache_too_large:{source_id}")
            continue
        actual_digest = hashlib.sha256(content).hexdigest()
        actual_blob = git_blob_id(content)
        if actual_digest != digest:
            findings.append(f"external_pin_content_digest_mismatch:{source_id}")
        if actual_blob is None:
            findings.append(f"external_pin_blob_computation_failed:{source_id}")
        elif actual_blob != blob:
            findings.append(f"external_pin_blob_mismatch:{source_id}")
        if verify_remote and repository_valid and source_path_valid and isinstance(commit, str):
            raw_url = (
                f"https://raw.githubusercontent.com/{repository}/{commit}/"
                f"{quote(source_path, safe='/')}"
            )
            remote_content = fetch_remote_source(raw_url)
            if remote_content is None:
                findings.append(f"external_pin_remote_fetch_failed:{source_id}")
            else:
                if remote_content != content:
                    findings.append(f"external_pin_remote_cache_mismatch:{source_id}")
                if hashlib.sha256(remote_content).hexdigest() != digest:
                    findings.append(f"external_pin_remote_digest_mismatch:{source_id}")
                remote_blob = git_blob_id(remote_content)
                if remote_blob is None:
                    findings.append(f"external_pin_remote_blob_computation_failed:{source_id}")
                elif remote_blob != blob:
                    findings.append(f"external_pin_remote_blob_mismatch:{source_id}")
    return len(pins)


def main() -> int:
    args = parse_args()
    findings: list[str] = []
    manifest = load_json(args.manifest, "manifest", findings)
    if not isinstance(manifest, dict):
        print("research_authority_audit=ERROR finding=invalid_manifest")
        return 2
    try:
        insights = args.insights.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        print("research_authority_audit=ERROR finding=invalid_insights")
        return 2
    knowledge_root = args.knowledge_root.resolve()
    if not knowledge_root.is_dir():
        print("research_authority_audit=ERROR finding=invalid_knowledge_root")
        return 2

    if manifest.get("schema_version") != "datarim.research-authority-audit/v1":
        findings.append("schema_version_invalid")
    if manifest.get("declared_language") != "en":
        findings.append("declared_language_invalid")
    validate_closed_profile(manifest, findings)
    snapshot = manifest.get("knowledge_snapshot")
    actual_head = git_value(knowledge_root, "rev-parse", "HEAD")
    if not isinstance(snapshot, str) or not HEX40.fullmatch(snapshot) or actual_head != snapshot:
        findings.append("knowledge_snapshot_mismatch")
        snapshot = actual_head or "HEAD"

    comment_paths = parse_comment_arguments(args.comment_json, findings)
    comment_bodies = validate_comments(manifest, comment_paths, insights, findings)
    item_count = validate_reviews_and_items(
        manifest, insights, knowledge_root, snapshot, comment_bodies, findings
    )
    candidate_count = validate_candidates(
        manifest, insights, knowledge_root, snapshot, findings
    )
    validate_derived_records(manifest, insights, knowledge_root, snapshot, findings)
    external_count = validate_external_pins(
        manifest,
        insights,
        args.external_cache_dir,
        args.verify_external_remote,
        findings,
    )

    unique_findings = list(dict.fromkeys(findings))
    if unique_findings:
        print("research_authority_audit=NOT_MET")
        for finding in unique_findings:
            print(f"finding={finding}")
        return 1
    print(
        "research_authority_audit=MET "
        f"items={item_count} candidates={candidate_count} external_pins={external_count}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
