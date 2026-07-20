#!/usr/bin/env bash
# self-verify-degradation-policy.sh -- pure automatic verification profile evaluator.

set -euo pipefail
IFS=$'\n\t'

exec python3 - "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from typing import Any


MAX_INTEGER = 2**63 - 1
MAX_LEDGER_BYTES = 1024 * 1024
MAX_ROLE_TOKENS = 32000
TOKEN_LIMIT = 96000
POLICY_VERSION = "tune-0139-v1"
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
TASK_ID = re.compile(r"^[A-Z]+-[0-9]+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ROLES = ("reviewer", "tester", "security")
AXES = ("tokens", "cost")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--ledger-file", required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--stage", choices=("prd", "plan", "do"), required=True)
    parser.add_argument("--invocation", required=True)
    parser.add_argument("--cycle", required=True)
    parser.add_argument("--previous-sequence", required=True)
    parser.add_argument("--expected-sequence", required=True)
    parser.add_argument("--expected-digest", required=True)
    parser.add_argument("--invocation-start", required=True)
    return parser.parse_args()


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def invalid() -> None:
    emit({
        "execution_status": "incomplete",
        "policy_version": POLICY_VERSION,
        "reason": "Budget evidence is invalid; verification did not advance.",
        "reason_code": "invalid_budget_evidence",
        "selected_profile": None,
    })


def checked_integer(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("invalid_integer")
    if value < 0 or value > MAX_INTEGER:
        raise ValueError("invalid_integer")
    return value


def argument_integer(value: str) -> int:
    if not re.fullmatch(r"[0-9]+", value):
        raise ValueError("invalid_integer")
    return checked_integer(int(value))


def checked_sum(values: list[int]) -> int:
    total = 0
    for value in values:
        if value > MAX_INTEGER - total:
            raise ValueError("integer_overflow")
        total += value
    return total


def parse_utc(value: Any) -> dt.datetime:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value):
        raise ValueError("invalid_time")
    return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


def validate_identity(args: argparse.Namespace) -> tuple[int, int]:
    if not TASK_ID.fullmatch(args.task):
        raise ValueError("invalid_task")
    if not SAFE_ID.fullmatch(args.invocation) or not SAFE_ID.fullmatch(args.cycle):
        raise ValueError("invalid_identity")
    if not SHA256.fullmatch(args.expected_digest):
        raise ValueError("invalid_digest")
    previous = argument_integer(args.previous_sequence)
    expected = argument_integer(args.expected_sequence)
    if expected == 0 or previous == MAX_INTEGER or expected != previous + 1:
        raise ValueError("invalid_sequence")
    return previous, expected


def reject_symlink_components(path: Path, workspace: Path) -> None:
    relative = path.relative_to(workspace)
    current = workspace
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("symlink_component")


def validated_paths(args: argparse.Namespace) -> tuple[Path, Path]:
    workspace = Path(args.workspace)
    ledger = Path(args.ledger_file)
    if not workspace.is_absolute() or not ledger.is_absolute():
        raise ValueError("path_not_absolute")
    if workspace.is_symlink() or not workspace.is_dir() or workspace.resolve(strict=True) != workspace:
        raise ValueError("invalid_workspace")
    relative = ledger.relative_to(workspace)
    if len(relative.parts) != 4 or relative.parts[:3] != ("datarim", ".auto", "self-verification-budget"):
        raise ValueError("ledger_outside_namespace")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json", relative.name):
        raise ValueError("invalid_ledger_name")
    reject_symlink_components(ledger, workspace)
    return workspace, ledger


def same_file(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def validate_ledger_stat(snapshot: os.stat_result) -> None:
    if not stat.S_ISREG(snapshot.st_mode) or snapshot.st_uid != os.getuid():
        raise ValueError("invalid_ledger_owner")
    if stat.S_IMODE(snapshot.st_mode) != 0o600 or snapshot.st_size > MAX_LEDGER_BYTES:
        raise ValueError("invalid_ledger_mode_or_size")


def open_ledger_parent(workspace: Path) -> int:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_DIRECTORY", 0)
    descriptor = os.open(workspace, flags)
    try:
        for component in ("datarim", ".auto", "self-verification-budget"):
            child = os.open(component, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def read_descriptor(descriptor: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(descriptor, 131072)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_LEDGER_BYTES:
            raise ValueError("ledger_too_large")
        chunks.append(chunk)
    return b"".join(chunks)


def read_bound_ledger(path: Path, workspace: Path, expected_digest: str) -> dict[str, Any]:
    parent = open_ledger_parent(workspace)
    descriptor = -1
    try:
        before = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        validate_ledger_stat(before)
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path.name, flags, dir_fd=parent)
        opened = os.fstat(descriptor)
        validate_ledger_stat(opened)
        if not same_file(before, opened):
            raise ValueError("ledger_replaced")
        raw = read_descriptor(descriptor)
        final_opened = os.fstat(descriptor)
        validate_ledger_stat(final_opened)
        if not same_file(opened, final_opened):
            raise ValueError("ledger_replaced")
        after = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        validate_ledger_stat(after)
        if not same_file(final_opened, after):
            raise ValueError("ledger_replaced")
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent)
    if hashlib.sha256(raw).hexdigest() != expected_digest:
        raise ValueError("digest_mismatch")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("ledger_not_object")
    return payload


def validate_axis(axis: Any, name: str) -> dict[str, int | str]:
    if not isinstance(axis, dict) or set(axis) != {"unit", "limit", "consumed", "reserved", "remaining"}:
        raise ValueError("invalid_axis")
    expected_unit = "tokens" if name == "tokens" else "microunits"
    if axis["unit"] != expected_unit:
        raise ValueError("invalid_unit")
    values = {key: checked_integer(axis[key]) for key in ("limit", "consumed", "reserved", "remaining")}
    if checked_sum([values["consumed"], values["reserved"], values["remaining"]]) != values["limit"]:
        raise ValueError("invalid_conservation")
    if name == "tokens" and values["limit"] > TOKEN_LIMIT:
        raise ValueError("token_limit_exceeded")
    return {"unit": expected_unit, **values}


def validate_roles(raw: Any, with_cost: bool) -> dict[str, dict[str, int]]:
    if not isinstance(raw, dict) or set(raw) != set(ROLES):
        raise ValueError("invalid_roles")
    expected_fields = {"input_bytes", "estimated_tokens"}
    if with_cost:
        expected_fields.add("estimated_cost_microunits")
    normalized: dict[str, dict[str, int]] = {}
    for name in ROLES:
        role = raw[name]
        if not isinstance(role, dict) or set(role) != expected_fields:
            raise ValueError("invalid_role")
        input_bytes = checked_integer(role["input_bytes"])
        estimated = checked_integer(role["estimated_tokens"])
        if estimated != (input_bytes + 3) // 4 + 4000 or estimated > MAX_ROLE_TOKENS:
            raise ValueError("invalid_token_proxy")
        normalized[name] = {"input_bytes": input_bytes, "estimated_tokens": estimated}
        if with_cost:
            normalized[name]["estimated_cost_microunits"] = checked_integer(role["estimated_cost_microunits"])
    return normalized


def validate_ledger(payload: dict[str, Any], args: argparse.Namespace, expected_sequence: int) -> tuple[dict[str, Any], dict[str, dict[str, int]]]:
    required = {"schema_version", "policy_version", "signal_source", "cycle_id", "task_id", "stage", "invocation_id", "sequence", "observed_at", "tokens", "roles"}
    allowed = required | {"cost"}
    if set(payload) != required and set(payload) != allowed:
        raise ValueError("invalid_schema")
    if payload["schema_version"] != 1 or payload["policy_version"] != POLICY_VERSION:
        raise ValueError("invalid_policy")
    if payload["signal_source"] not in ("runtime_ledger", "deterministic_proxy"):
        raise ValueError("invalid_source")
    if (payload["task_id"], payload["stage"], payload["invocation_id"], payload["cycle_id"]) != (args.task, args.stage, args.invocation, args.cycle):
        raise ValueError("binding_mismatch")
    if checked_integer(payload["sequence"]) != expected_sequence:
        raise ValueError("sequence_mismatch")
    observed = parse_utc(payload["observed_at"])
    invocation_start = parse_utc(args.invocation_start)
    now = dt.datetime.now(dt.timezone.utc)
    if observed < invocation_start or observed > now or (now - observed).total_seconds() > 300:
        raise ValueError("invalid_freshness")
    axes = {"tokens": validate_axis(payload["tokens"], "tokens")}
    if "cost" in payload:
        axes["cost"] = validate_axis(payload["cost"], "cost")
    roles = validate_roles(payload["roles"], "cost" in axes)
    if payload["signal_source"] == "deterministic_proxy":
        token_axis = axes["tokens"]
        if "cost" in axes or token_axis != {"unit": "tokens", "limit": 96000, "consumed": 0, "reserved": 0, "remaining": 96000}:
            raise ValueError("invalid_proxy")
    return axes, roles


def profile_requirements(roles: dict[str, dict[str, int]], axes: dict[str, Any]) -> dict[str, dict[str, int]]:
    requirements: dict[str, dict[str, int]] = {}
    for axis in AXES:
        if axis not in axes:
            continue
        field = "estimated_tokens" if axis == "tokens" else "estimated_cost_microunits"
        deep = roles["reviewer"][field]
        full = checked_sum([roles[name][field] for name in ROLES])
        requirements[axis] = {"full": full, "deep_only": deep, "floor_only": 0}
    return requirements


def choose_profile(requirements: dict[str, dict[str, int]], axes: dict[str, Any]) -> tuple[str, list[str]]:
    def fits(profile: str) -> bool:
        return all(requirements[axis][profile] <= axes[axis]["remaining"] for axis in requirements)
    if fits("full"):
        return "full", []
    if fits("deep_only"):
        return "deep_only", [axis for axis in AXES if axis in requirements and requirements[axis]["full"] > axes[axis]["remaining"]]
    return "floor_only", [
        axis for axis in AXES
        if axis in requirements
        and (
            requirements[axis]["full"] > axes[axis]["remaining"]
            or requirements[axis]["deep_only"] > axes[axis]["remaining"]
        )
    ]


def decision(payload: dict[str, Any], axes: dict[str, Any], roles: dict[str, dict[str, int]], digest: str) -> dict[str, Any]:
    requirements = profile_requirements(roles, axes)
    profile, trigger_axes = choose_profile(requirements, axes)
    pass_sets = {
        "full": (["deterministic_floor", "deep_cross_artifact", "multi_vote_adversarial"], []),
        "deep_only": (["deterministic_floor", "deep_cross_artifact"], ["multi_vote_adversarial"]),
        "floor_only": (["deterministic_floor"], ["multi_vote_adversarial", "deep_cross_artifact"]),
    }
    role_sets = {
        "full": (["reviewer", "tester", "security"], []),
        "deep_only": (["reviewer"], ["tester", "security"]),
        "floor_only": ([], ["reviewer", "tester", "security"]),
    }
    reasons = {
        "full": ("budget_sufficient", "Budget supports the full automatic verification profile."),
        "deep_only": ("adversarial_bundle_omitted", "Budget pressure omitted the adversarial bundle and retained the deep review."),
        "floor_only": ("model_passes_omitted", "Budget pressure omitted model passes and retained the deterministic floor."),
    }
    reason_code, reason = reasons[profile]
    return {
        "base_profile": "full",
        "budget_axes": axes,
        "degradation_applied": profile != "full",
        "execution_status": "complete",
        "kept_passes": pass_sets[profile][0],
        "kept_roles": role_sets[profile][0],
        "omitted_passes": pass_sets[profile][1],
        "omitted_roles": role_sets[profile][1],
        "policy_version": POLICY_VERSION,
        "reason": reason,
        "reason_code": reason_code,
        "role_estimates": roles,
        "selected_profile": profile,
        "signal_digest": digest,
        "signal_sequence": payload["sequence"],
        "signal_source": payload["signal_source"],
        "trigger_axes": trigger_axes,
        "verification_coverage": profile,
    }


def main() -> int:
    args = parse_args()
    try:
        _, expected_sequence = validate_identity(args)
        workspace, ledger_path = validated_paths(args)
        payload = read_bound_ledger(ledger_path, workspace, args.expected_digest)
        axes, roles = validate_ledger(payload, args, expected_sequence)
        emit(decision(payload, axes, roles, args.expected_digest))
        return 0
    except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError):
        invalid()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
PY
