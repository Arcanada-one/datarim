#!/usr/bin/python3
"""Validate and execute bounded customer-delivery Bats shards."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass


ROOT = Path(__file__).resolve().parent.parent
SUITE_PATHS = {
    "functional": ROOT / "dev-tools/tests/check-customer-delivery.bats",
    "schema": ROOT / "dev-tools/tests/customer-delivery-schema.bats",
    "mutation": ROOT / "dev-tools/tests/customer-delivery-mutation.bats",
}
TEST_PATTERN = re.compile(r'^@test "([^"]+)" \{$')
ALTERNATE_TEST_PATTERN = re.compile(r'^function\s+[A-Za-z_][A-Za-z0-9_]*\s*\{\s*#\s*@test(?:\s.*)?$')
TAP_RESULT_PATTERN = re.compile(r"^(?:ok|not ok)\s+[0-9]+(?:\s|$)", re.MULTILINE)
TAP_PLAN_PATTERN = re.compile(r"^1\.\.([0-9]+)\s*$", re.MULTILINE)
# consumer review CI evidence: 20/44-case shards reached 103-106 seconds, and a
# 15-case functional shard still reached 91 seconds at the fixed 105-second
# macOS child ceiling. These limits preserve margin while exact coverage
# prevents omissions.
MACOS_ORDINAL_TEST_LIMITS = {"functional": 10, "schema": 15}
PLATFORM_SHARD_POLICY = {
    "functional": {shard: ("linux", "macos") for shard in range(1, 39)},
    "schema": {shard: ("linux", "macos") for shard in range(1, 13)},
    "mutation": {
        **{shard: ("linux",) for shard in range(1, 14)},
        **{shard: ("linux", "macos") for shard in range(14, 16)},
        **{shard: ("macos",) for shard in range(16, 23)},
        **{shard: ("linux", "macos") for shard in range(23, 58)},
    },
}
MACOS_RUNTIME_ISOLATED_TESTS = {
    "functional": (
        "signed review inventory rejects a duplicate review identity",
        "signed review inventory rejects an extra review pair",
        "signed review inventory manifest signature is independently verified",
        "every same-requirement review remains independently authenticated",
        "two-requirement epic cannot close with its second originating review missing",
        "two-requirement epic closes when its exact signed review inventory is APPROVED",
        "two-requirement epic cannot close with its second originating review OPEN",
        "two-requirement epic cannot close with its second originating review CHANGES_REQUESTED",
        "every originating review inventory record is authenticated",
        "originating review inventory rejects requirements outside the exact set",
        "all validation subprocesses share one total deadline",
        "OpenSSL deadline terminates stubborn descendant pipe holders",
        "validation supervisor completed and signalled cleanup remains bounded",
        "wrapper signal and alarm initialization remains normalized",
        "validation consumer failures and cleanup waits remain bounded",
        "source history subprocesses share one total deadline",
        "source history deadline kills stubborn descendant pipe holders",
        "global validation alarm reaps late source history child process group",
    ),
    "mutation": (
        # Independent repository-binding arms previously shared one 105s budget.
        "repository root identity mutant is independently killed",
        "repository gitdir identity mutant is independently killed",
        "repository gitdir descriptor mutant is independently killed",
        "repository control identity mutant is independently killed",
        "Darwin executable pth authority mutant is independently killed",
        "Darwin dependency-site symlink mutant is independently killed",
        "Darwin dist-info type mutant is independently killed",
        "Darwin dist-info nofollow mutant is independently killed",
        "Darwin dist-info working-directory mutant is independently killed",
        "review inventory exact-set mutant is independently killed",
        "review inventory closure mutant is independently killed",
        "review inventory authentication mutant is independently killed",
        "mutation kill attribution rejects setup syntax timeout and wrong-assertion failures",
        "same-clock elapsed marker mutation attribution is fail-closed",
        "cleanup signal-mask and process lifecycle mutants are independently killed",
        "SIGCHLD portable spawn mutants are independently killed",
        "terminal cleanup output mutants are independently killed",
        "terminal signal-mask mutation attribution is independently killed",
        "post-Popen silent and bounded deadline mutants are independently killed",
        "SIGCHLD consumer normalization mutants are independently killed",
        "wrapper SIGCHLD reset unblock and drain mutants are independently killed",
        "wrapper exec and interpreter mutants are independently killed",
        "wrapper worker transport mutants are independently killed",
        "Alarm diagnostic grammar mutation attribution is fail-closed",
        "Alarm initialization handler-order mutant is independently killed",
        "Alarm initialization timer-bound mutant is independently killed",
        "Alarm initialization init-hard-abort mutant is independently killed",
        "Alarm initialization cancel-inherited mutant is independently killed",
        "Alarm initialization drain-inherited mutant is independently killed",
        "Alarm initialization arm-before-unblock mutant is independently killed",
        "post-Popen source-history and masked deadline mutants are independently killed",
        "post-Popen readiness and stale marker mutants are independently killed",
    ),
}


class ContractError(ValueError):
    pass


MAX_TIMEOUT_OUTPUT_BYTES = 64 * 1024
RESULT_FIELDS = {"suite", "shard", "status", "exit_code", "phase"}


class BoundedProcessTimeout(subprocess.TimeoutExpired):
    def __init__(self, command, timeout, output_excerpt: str, output_truncated: bool):
        super().__init__(command, timeout, output=output_excerpt)
        self.output_truncated = output_truncated


class BoundedProcessOutputExceeded(ContractError):
    def __init__(self, output_excerpt: str):
        super().__init__(f"Bats output exceeded {MAX_TIMEOUT_OUTPUT_BYTES} byte limit")
        self.output_excerpt = output_excerpt


def bounded_timeout_excerpt(
    output: str | bytes | None,
    *,
    force_truncated: bool = False,
    marker: str = "[timeout output truncated; showing final bytes]\n",
) -> tuple[str, bool]:
    if output is None:
        text = ""
    elif isinstance(output, bytes):
        text = output.decode("utf-8", errors="replace")
    else:
        text = output
    encoded = text.encode("utf-8")
    if not force_truncated and len(encoded) <= MAX_TIMEOUT_OUTPUT_BYTES:
        return text, False

    available = MAX_TIMEOUT_OUTPUT_BYTES - len(marker.encode("utf-8"))
    tail = encoded[-available:]
    while True:
        try:
            tail_text = tail.decode("utf-8")
            break
        except UnicodeDecodeError as error:
            tail = tail[error.end:]
    return marker + tail_text, True


def append_bounded_tail(buffer: bytearray, chunk: bytes) -> None:
    if len(chunk) >= MAX_TIMEOUT_OUTPUT_BYTES:
        buffer[:] = chunk[-MAX_TIMEOUT_OUTPUT_BYTES:]
        return
    excess = len(buffer) + len(chunk) - MAX_TIMEOUT_OUTPUT_BYTES
    if excess > 0:
        del buffer[:excess]
    buffer.extend(chunk)


@dataclass(frozen=True)
class Row:
    suite: str
    shard: int
    total: int
    mode: str
    first: str
    last: str
    platforms: tuple[str, ...]


def extract_tests(path: Path) -> list[str]:
    names: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if ALTERNATE_TEST_PATTERN.fullmatch(line):
            raise ContractError(f"noncanonical Bats test syntax: {path}:{line_number}")
        if match := TEST_PATTERN.fullmatch(line):
            names.append(match.group(1))
        elif line.lstrip().startswith("@test"):
            raise ContractError(f"noncanonical Bats test syntax: {path}:{line_number}")
    if not names or len(names) != len(set(names)):
        raise ContractError(f"test inventory is empty or duplicated: {path}")
    return names


def validate_bats_execution(output: str, expected: int) -> None:
    plans = [int(value) for value in TAP_PLAN_PATTERN.findall(output)]
    observed = len(TAP_RESULT_PATTERN.findall(output))
    if plans != [expected] or observed != expected:
        raise ContractError(
            f"Bats execution inventory mismatch: expected {expected}, observed {observed}"
        )


def run_bounded_process(
    command: list[str], environment: dict[str, str], timeout_seconds: int
) -> tuple[int, str]:
    process = subprocess.Popen(
        command,
        env=environment,
        start_new_session=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    captured = bytearray()
    total_bytes = 0
    deadline = time.monotonic() + timeout_seconds
    timed_out = False
    output_exceeded = False
    group_stopped = False

    def stop_process_group() -> None:
        nonlocal group_stopped
        if process.poll() is not None and not selector.get_map():
            group_stopped = True
            return
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        group_stopped = True

    def drain_ready(wait_seconds: float) -> None:
        nonlocal total_bytes, output_exceeded
        for key, _ in selector.select(wait_seconds):
            chunk = os.read(key.fd, 16 * 1024)
            if not chunk:
                selector.unregister(key.fileobj)
                key.fileobj.close()
                continue
            total_bytes += len(chunk)
            append_bounded_tail(captured, chunk)
            output_exceeded = output_exceeded or total_bytes > MAX_TIMEOUT_OUTPUT_BYTES

    def finish_stopped_group() -> None:
        cleanup_deadline = time.monotonic() + 2.0
        while selector.get_map() and time.monotonic() < cleanup_deadline:
            drain_ready(min(cleanup_deadline - time.monotonic(), 0.1))
        if selector.get_map():
            for key in list(selector.get_map().values()):
                selector.unregister(key.fileobj)
                key.fileobj.close()
        try:
            process.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            stop_process_group()
            process.kill()
            process.wait()

    try:
        while process.poll() is None or selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            drain_ready(min(remaining, 0.1))

        if timed_out:
            stop_process_group()
            finish_stopped_group()
            raw = bytes(captured)
            excerpt, truncated = bounded_timeout_excerpt(
                raw, force_truncated=total_bytes > MAX_TIMEOUT_OUTPUT_BYTES
            )
            raise BoundedProcessTimeout(
                command, timeout_seconds, excerpt, truncated
            )

        if output_exceeded:
            stop_process_group()
            finish_stopped_group()
            excerpt, _ = bounded_timeout_excerpt(
                bytes(captured),
                force_truncated=True,
                marker="[process output exceeded capture limit; showing final bytes]\n",
            )
            raise BoundedProcessOutputExceeded(excerpt)

        returncode = process.wait()
        raw = bytes(captured)
        output = raw.decode("utf-8", errors="replace")
        if total_bytes > MAX_TIMEOUT_OUTPUT_BYTES or len(output.encode("utf-8")) > MAX_TIMEOUT_OUTPUT_BYTES:
            excerpt, _ = bounded_timeout_excerpt(
                raw,
                force_truncated=True,
                marker="[process output exceeded capture limit; showing final bytes]\n",
            )
            raise BoundedProcessOutputExceeded(excerpt)
        return returncode, output
    except BaseException:
        if not group_stopped:
            stop_process_group()
            if process.poll() is None:
                process.wait()
        raise
    finally:
        selector.close()
        if process.stdout and not process.stdout.closed:
            process.stdout.close()


def extract_security_arms(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    test_header = '@test "every security-critical production branch is killed by its focused regression" {'
    try:
        cursor = lines.index(test_header)
        cursor = next(
            index for index in range(cursor + 1, len(lines))
            if "local -a pairs=(" in lines[index]
        ) + 1
    except (ValueError, StopIteration) as error:
        raise ContractError("security mutation inventory is missing") from error
    arms: list[str] = []
    pair_pattern = re.compile(r"\s*'([^']+)\|([^']+)'\s*")
    while cursor < len(lines) and lines[cursor].strip() != ")":
        match = pair_pattern.fullmatch(lines[cursor])
        if match:
            arms.append(match.group(1))
        cursor += 1
    if not arms or len(arms) != len(set(arms)):
        raise ContractError("security mutation inventory is empty or duplicated")
    return arms


def load_registry(path: Path) -> list[Row]:
    if not path.is_file():
        raise ContractError(f"registry unavailable: {path}")
    rows: list[Row] = []
    keys: set[tuple[str, int]] = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 7:
            raise ContractError(f"invalid registry row {line_number}")
        suite, shard_text, total_text, mode, first, last, platforms_text = fields
        if suite not in SUITE_PATHS or not shard_text.isdigit() or not total_text.isdigit():
            raise ContractError(f"invalid registry row {line_number}")
        platforms = tuple(platforms_text.split(","))
        if not platforms or len(platforms) != len(set(platforms)) or not set(platforms) <= {"linux", "macos"}:
            raise ContractError(f"invalid registry platforms {line_number}")
        row = Row(suite, int(shard_text), int(total_text), mode, first, last, platforms)
        key = (row.suite, row.shard)
        if key in keys:
            raise ContractError(f"duplicate shard: {suite} {row.shard}")
        keys.add(key)
        rows.append(row)
    return rows


def increment(coverage: list[int], index: int, label: str) -> None:
    if index < 1 or index >= len(coverage):
        raise ContractError(f"registry coverage out of range: {label} {index}")
    coverage[index] += 1
    if coverage[index] > 1:
        raise ContractError(f"registry coverage overlap: {label} {index}")


def validate_registry(rows: list[Row]) -> tuple[dict[str, list[str]], list[str]]:
    inventories = {suite: extract_tests(path) for suite, path in SUITE_PATHS.items()}
    security_arms = extract_security_arms(SUITE_PATHS["mutation"])
    isolated_indices: dict[str, dict[int, str]] = {}
    for suite, names in MACOS_RUNTIME_ISOLATED_TESTS.items():
        isolated_indices[suite] = {}
        for name in names:
            if name not in inventories[suite]:
                raise ContractError(f"macOS runtime-isolated test is missing: {suite}: {name}")
            isolated_indices[suite][inventories[suite].index(name) + 1] = name
    for suite in SUITE_PATHS:
        suite_rows = [row for row in rows if row.suite == suite]
        if not suite_rows:
            raise ContractError(f"registry coverage missing: {suite}")
        totals = {row.total for row in suite_rows}
        if len(totals) != 1 or next(iter(totals)) < 1:
            raise ContractError(f"invalid shard total: {suite}")
        total = next(iter(totals))
        shard_ids = {row.shard for row in suite_rows}
        if shard_ids != set(range(1, total + 1)):
            raise ContractError(f"registry coverage missing: {suite} shard")

        test_coverage = [0] * (len(inventories[suite]) + 1)
        security_coverage = [0] * (len(security_arms) + 1)
        for row in suite_rows:
            if row.mode == "ordinal":
                if row.last == "-":
                    try:
                        indices = [int(value) for value in row.first.split(",") if value]
                    except ValueError as error:
                        raise ContractError(f"invalid ordinal shard: {suite} {row.shard}") from error
                    if not indices:
                        raise ContractError(f"empty shard: {suite} {row.shard}")
                else:
                    if not row.first.isdigit() or not row.last.isdigit():
                        raise ContractError(f"invalid ordinal shard: {suite} {row.shard}")
                    start, end = int(row.first), int(row.last)
                    if start > end:
                        raise ContractError(f"empty shard: {suite} {row.shard}")
                    indices = list(range(start, end + 1))
                runtime_limit = MACOS_ORDINAL_TEST_LIMITS.get(suite)
                if (
                    runtime_limit is not None
                    and "macos" in row.platforms
                    and len(indices) > runtime_limit
                ):
                    raise ContractError(
                        "macOS ordinal shard exceeds runtime budget: "
                        f"{suite} {row.shard} has {len(indices)} tests "
                        f"(max {runtime_limit})"
                    )
                isolated_hits = [
                    isolated_indices[suite][index]
                    for index in indices
                    if index in isolated_indices.get(suite, {})
                ]
                if isolated_hits and (len(indices) != 1 or "macos" not in row.platforms):
                    raise ContractError(
                        "macOS runtime-isolated test requires a dedicated shard: "
                        f"{isolated_hits[0]}"
                    )
                for index in indices:
                    if suite == "mutation" and index == 2:
                        raise ContractError("mutation security test requires security mode")
                    increment(test_coverage, index, f"{suite} test")
            elif row.mode == "security" and suite == "mutation":
                if not row.first.isdigit() or not row.last.isdigit():
                    raise ContractError(f"invalid security shard: {row.shard}")
                start, end = int(row.first), int(row.last)
                if start > end:
                    raise ContractError(f"empty shard: mutation {row.shard}")
                for index in range(start, end + 1):
                    increment(security_coverage, index, "mutation security")
            else:
                raise ContractError(f"invalid shard mode: {suite} {row.shard}")

        expected_test_indices = range(1, len(test_coverage))
        for index in expected_test_indices:
            expected = 0 if suite == "mutation" and index == 2 else 1
            if test_coverage[index] != expected:
                raise ContractError(f"registry coverage missing: {suite} test {index}")
        if suite == "mutation":
            for index in range(1, len(security_coverage)):
                if security_coverage[index] != 1:
                    raise ContractError(f"registry coverage missing: mutation security {index}")
        expected_platforms = PLATFORM_SHARD_POLICY[suite]
        if set(expected_platforms) != shard_ids:
            raise ContractError(f"registry platform policy mismatch: {suite} shard inventory")
        for row in suite_rows:
            expected = expected_platforms.get(row.shard)
            if row.platforms != expected:
                raise ContractError(
                    "registry platform policy mismatch: "
                    f"{suite} {row.shard} expected "
                    f"{','.join(expected or ()) or 'undefined'}, observed "
                    f"{','.join(row.platforms)}"
                )
    return inventories, security_arms


def ere_escape(value: str) -> str:
    return re.sub(r"([][\\.^$*+?(){}|])", r"\\\1", value)


def selected_names(row: Row, inventory: list[str]) -> list[str]:
    if row.last == "-":
        indices = [int(value) for value in row.first.split(",")]
    else:
        indices = list(range(int(row.first), int(row.last) + 1))
    return [inventory[index - 1] for index in indices]


def matrix_for(rows: list[Row], platform: str) -> list[dict[str, str]]:
    return [
        {"suite": row.suite, "shard": f"{row.shard}/{row.total}"}
        for row in rows if platform in row.platforms
    ]


def load_group_size(baseline_path: Path) -> int:
    if not baseline_path.is_file():
        raise ContractError(f"slot baseline unavailable: {baseline_path}")
    try:
        payload = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeError) as error:
        raise ContractError(f"slot baseline invalid: {baseline_path}") from error
    group_size = payload.get("proposed_microjob_group_size")
    if not isinstance(group_size, int) or group_size < 1:
        raise ContractError("slot baseline missing proposed_microjob_group_size")
    return group_size


def matrix_jobs_for(
    rows: list[Row], platform: str, group_size: int
) -> list[dict[str, object]]:
    """Batch compatible logical shards into runner jobs.

    Each logical shard keeps its own identity in `members`. Group size comes
    from the measured slot baseline, not a fixed workflow constant.
    """
    if group_size < 1:
        raise ContractError("group size must be >= 1")
    flat = matrix_for(rows, platform)
    jobs: list[dict[str, object]] = []
    total_groups = (len(flat) + group_size - 1) // group_size if flat else 0
    for index in range(0, len(flat), group_size):
        members = flat[index : index + group_size]
        group_number = (index // group_size) + 1
        jobs.append(
            {
                "group": f"{group_number}/{total_groups}",
                "members": members,
            }
        )
    return jobs


def run_logical_shard(
    *,
    rows: list[Row],
    inventories: dict[str, list[str]],
    suite: str,
    shard_token: str,
    python_bin: Path,
    test_python_bin: Path,
    bats: str,
    timeout_seconds: int,
    platform: str | None,
    result_file: Path | None,
) -> int:
    """Execute one logical shard and optionally write its result JSON.

    Returns the shard exit code. Timeouts and failures still write a result so
    siblings in a microjob group remain visible to the aggregate.
    """
    timeout_phase = "count"
    row = None
    try:
        if not re.fullmatch(r"[1-9][0-9]*/[1-9][0-9]*", shard_token):
            raise ContractError("suite and shard N/T are required")
        if timeout_seconds < 1 or timeout_seconds >= 110:
            raise ContractError("timeout-seconds must be between 1 and 109")
        shard, total = (int(value) for value in shard_token.split("/"))
        matching = [
            candidate
            for candidate in rows
            if candidate.suite == suite
            and candidate.shard == shard
            and candidate.total == total
        ]
        if len(matching) != 1:
            raise ContractError(f"unknown shard: {suite} {shard_token}")
        row = matching[0]
        if platform and platform not in row.platforms:
            raise ContractError(f"shard not approved for platform: {platform}")
        environment = os.environ.copy()
        environment["CUSTOMER_DELIVERY_PYTHON"] = str(python_bin)
        environment["CUSTOMER_DELIVERY_TEST_PYTHON"] = str(test_python_bin)
        environment["CUSTOMER_SCHEMA_PYTHON"] = str(test_python_bin)
        if row.mode == "security":
            names = [inventories["mutation"][1]]
            environment["CUSTOMER_DELIVERY_SECURITY_RANGE"] = f"{row.first}-{row.last}"
        else:
            names = selected_names(row, inventories[row.suite])
        filter_pattern = "^(" + "|".join(ere_escape(name) for name in names) + ")$"
        count_timeout = min(timeout_seconds, 10)
        timeout_context = (
            f"authoritative count exceeded {count_timeout}s: {suite} {shard_token}"
        )
        count_returncode, count_output = run_bounded_process(
            [bats, "--count", "--filter", filter_pattern, str(SUITE_PATHS[row.suite])],
            environment,
            count_timeout,
        )
        if count_returncode != 0:
            raise ContractError("Bats authoritative count failed")
        try:
            authoritative_count = int(count_output.strip())
        except ValueError as error:
            raise ContractError("Bats authoritative count is invalid") from error
        if authoritative_count != len(names):
            raise ContractError(
                "Bats authoritative inventory mismatch: "
                f"expected {len(names)}, observed {authoritative_count}"
            )
        timeout_context = f"shard exceeded {timeout_seconds}s: {suite} {shard_token}"
        timeout_phase = "shard"
        returncode, output = run_bounded_process(
            [bats, "--filter", filter_pattern, str(SUITE_PATHS[row.suite])],
            environment,
            timeout_seconds,
        )
        print(output, end="")
        if returncode == 0:
            validate_bats_execution(output, len(names))
        if result_file:
            if not platform:
                raise ContractError("result-file requires platform")
            write_result(
                result_file,
                row,
                "passed" if returncode == 0 else "failed",
                returncode,
                "shard",
            )
        return returncode
    except BoundedProcessTimeout as error:
        if error.output:
            print(error.output, end="" if error.output.endswith("\n") else "\n")
        if error.output_truncated:
            print(f"timeout output limit: {MAX_TIMEOUT_OUTPUT_BYTES} bytes", file=sys.stderr)
        if result_file and row is not None:
            if not platform:
                print("ERROR: result-file requires platform", file=sys.stderr)
                return 2
            try:
                write_result(result_file, row, "timed_out", 124, timeout_phase)
            except OSError as write_error:
                print(f"ERROR: could not record timed-out shard: {write_error}", file=sys.stderr)
                return 2
        print(f"ERROR: {timeout_context}", file=sys.stderr)
        return 124
    except BoundedProcessOutputExceeded as error:
        if error.output_excerpt:
            print(error.output_excerpt, end="" if error.output_excerpt.endswith("\n") else "\n")
        print(f"ERROR: {error}", file=sys.stderr)
        if result_file and row is not None and timeout_phase == "shard":
            if not platform:
                print("ERROR: result-file requires platform", file=sys.stderr)
                return 2
            try:
                write_result(result_file, row, "failed", 2, "shard")
            except OSError as write_error:
                print(f"ERROR: could not record failed shard: {write_error}", file=sys.stderr)
                return 2
        return 2
    except (ContractError, OSError, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        if result_file and row is not None:
            if not platform:
                return 2
            try:
                write_result(result_file, row, "failed", 2, "shard")
            except OSError:
                pass
        return 2


def check_results(rows: list[Row], platform: str, directory: Path) -> int:
    expected = Counter((item["suite"], item["shard"]) for item in matrix_for(rows, platform))
    if not directory.is_dir():
        raise ContractError("result inventory mismatch: missing directory")
    observed: Counter[tuple[str, str]] = Counter()
    failed = 0
    timed_out = 0
    for path in sorted(directory.glob("*.json")):
        try:
            item = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeError) as error:
            raise ContractError(f"result inventory mismatch: changed {path.name}") from error
        if not isinstance(item, dict) or set(item) != RESULT_FIELDS:
            raise ContractError(f"result inventory mismatch: changed {path.name}")
        if (
            not all(isinstance(item[field], str) for field in ("suite", "shard", "status", "phase"))
            or isinstance(item["exit_code"], bool)
            or not isinstance(item["exit_code"], int)
            or item["status"] not in {"passed", "failed", "timed_out"}
            or item["phase"] not in {"count", "shard"}
        ):
            raise ContractError(f"result inventory mismatch: changed {path.name}")
        if (
            (item["status"] == "passed" and (item["exit_code"] != 0 or item["phase"] != "shard"))
            or (item["status"] == "failed" and (item["exit_code"] == 0 or item["phase"] != "shard"))
            or (item["status"] == "timed_out" and item["exit_code"] != 124)
        ):
            raise ContractError(f"result inventory mismatch: changed {path.name}")
        key = (item["suite"], item["shard"])
        observed[key] += 1
        if observed[key] > 1:
            raise ContractError(f"result inventory mismatch: duplicate {key[0]} {key[1]}")
        if item["status"] == "timed_out":
            timed_out += 1
        elif item["status"] == "failed":
            failed += 1
    missing = expected - observed
    extra = observed - expected
    if missing:
        key = next(iter(missing))
        raise ContractError(f"result inventory mismatch: missing {key[0]} {key[1]}")
    if extra:
        key = next(iter(extra))
        raise ContractError(f"result inventory mismatch: extra {key[0]} {key[1]}")
    print(
        f"customer_delivery_results=complete platform={platform} count={sum(observed.values())} "
        f"passed={sum(observed.values()) - failed - timed_out} failed={failed} timed_out={timed_out}"
    )
    return 1 if failed or timed_out else 0


def write_result(path: Path, row: Row, status: str, exit_code: int, phase: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({
            "suite": row.suite,
            "shard": f"{row.shard}/{row.total}",
            "status": status,
            "exit_code": exit_code,
            "phase": phase,
        }) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, default=ROOT / "tests/customer-delivery-shards.tsv")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--matrix", choices=("linux", "macos"))
    parser.add_argument(
        "--matrix-jobs",
        choices=("linux", "macos"),
        help="Emit batched runner jobs sized from the measured slot baseline",
    )
    parser.add_argument(
        "--slots-baseline",
        type=Path,
        default=ROOT / "tests/ci-slot-baseline.json",
    )
    parser.add_argument("--check-results", nargs=2, metavar=("PLATFORM", "DIRECTORY"))
    parser.add_argument("--suite", choices=sorted(SUITE_PATHS))
    parser.add_argument("--shard")
    parser.add_argument(
        "--group-members",
        help="JSON array of {suite,shard} logical members to run in one runner job",
    )
    parser.add_argument("--python-bin", default="/usr/bin/python3")
    parser.add_argument("--test-python-bin")
    parser.add_argument("--bats-bin")
    parser.add_argument("--timeout-seconds", type=int, default=105)
    parser.add_argument("--platform", choices=("linux", "macos"))
    parser.add_argument("--result-file", type=Path)
    parser.add_argument(
        "--result-dir",
        type=Path,
        help="Directory for per-logical-shard result JSON when running --group-members",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        rows = load_registry(args.registry)
        inventories, security_arms = validate_registry(rows)
        if args.matrix:
            print(json.dumps(matrix_for(rows, args.matrix), separators=(",", ":")))
            return 0
        if args.matrix_jobs:
            group_size = load_group_size(args.slots_baseline)
            jobs = matrix_jobs_for(rows, args.matrix_jobs, group_size)
            print(json.dumps(jobs, separators=(",", ":")))
            return 0
        if args.check_results:
            platform, directory = args.check_results
            if platform not in {"linux", "macos"}:
                raise ContractError(f"unknown results platform: {platform}")
            # Inventory expectations stay on the flat logical matrix.
            return check_results(rows, platform, Path(directory))
        if args.check:
            print(
                "customer_delivery_shards=valid "
                f"functional={len(inventories['functional'])} "
                f"schema={len(inventories['schema'])} "
                f"mutation_tests={len(inventories['mutation'])} "
                f"mutation_security={len(security_arms)}"
            )
            return 0

        python_bin = Path(args.python_bin)
        if not python_bin.is_absolute() or not python_bin.is_file() or not os.access(python_bin, os.X_OK):
            raise ContractError("python-bin must be an absolute executable")
        test_python_bin = Path(args.test_python_bin) if args.test_python_bin else python_bin
        if (
            not test_python_bin.is_absolute()
            or not test_python_bin.is_file()
            or not os.access(test_python_bin, os.X_OK)
        ):
            raise ContractError("test-python-bin must be an absolute executable")
        bats = args.bats_bin or shutil.which("bats")
        if not bats or not Path(bats).is_absolute() or not os.access(bats, os.X_OK):
            raise ContractError("bats executable unavailable")

        if args.group_members:
            try:
                members = json.loads(args.group_members)
            except json.JSONDecodeError as error:
                raise ContractError("group-members must be JSON") from error
            if not isinstance(members, list) or not members:
                raise ContractError("group-members must be a non-empty JSON array")
            if not args.result_dir or not args.platform:
                raise ContractError("group-members requires --result-dir and --platform")
            args.result_dir.mkdir(parents=True, exist_ok=True)
            worst = 0
            for member in members:
                if (
                    not isinstance(member, dict)
                    or not isinstance(member.get("suite"), str)
                    or not isinstance(member.get("shard"), str)
                ):
                    raise ContractError("group member must include suite and shard")
                suite = member["suite"]
                shard_token = member["shard"]
                result_path = args.result_dir / f"{suite}-{shard_token.replace('/', '-')}.json"
                print(f"=== logical shard {suite} {shard_token}")
                code = run_logical_shard(
                    rows=rows,
                    inventories=inventories,
                    suite=suite,
                    shard_token=shard_token,
                    python_bin=python_bin,
                    test_python_bin=test_python_bin,
                    bats=bats,
                    timeout_seconds=args.timeout_seconds,
                    platform=args.platform,
                    result_file=result_path,
                )
                # Keep running siblings after a partial failure; aggregate decides.
                if code != 0 and worst == 0:
                    worst = code
                elif code not in (0, 124) and worst in (0, 124):
                    worst = code
            expected = {(item["suite"], item["shard"]) for item in members}
            observed = set()
            for path in args.result_dir.glob("*.json"):
                item = json.loads(path.read_text(encoding="utf-8"))
                observed.add((item["suite"], item["shard"]))
            missing = expected - observed
            if missing:
                key = next(iter(missing))
                print(
                    f"ERROR: missing required logical result after group run: {key[0]} {key[1]}",
                    file=sys.stderr,
                )
                return 1
            return worst

        if not args.suite or not args.shard:
            raise ContractError("suite and shard N/T are required")
        return run_logical_shard(
            rows=rows,
            inventories=inventories,
            suite=args.suite,
            shard_token=args.shard,
            python_bin=python_bin,
            test_python_bin=test_python_bin,
            bats=bats,
            timeout_seconds=args.timeout_seconds,
            platform=args.platform,
            result_file=args.result_file,
        )
    except (ContractError, OSError, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
