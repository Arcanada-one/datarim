#!/usr/bin/python3
"""Validate and execute bounded customer-delivery Bats shards."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
from dataclasses import dataclass


ROOT = Path(__file__).resolve().parent.parent
SUITE_PATHS = {
    "functional": ROOT / "dev-tools/tests/check-customer-delivery.bats",
    "schema": ROOT / "dev-tools/tests/customer-delivery-schema.bats",
    "mutation": ROOT / "dev-tools/tests/customer-delivery-mutation.bats",
}
TEST_PATTERN = re.compile(r'^@test "([^"]+)" \{$')


class ContractError(ValueError):
    pass


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
    names = [
        match.group(1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := TEST_PATTERN.fullmatch(line))
    ]
    if not names or len(names) != len(set(names)):
        raise ContractError(f"test inventory is empty or duplicated: {path}")
    return names


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


def check_results(rows: list[Row], platform: str, directory: Path) -> int:
    expected = Counter((item["suite"], item["shard"]) for item in matrix_for(rows, platform))
    if not directory.is_dir():
        raise ContractError("result inventory mismatch: missing directory")
    observed: Counter[tuple[str, str]] = Counter()
    for path in sorted(directory.glob("*.json")):
        try:
            item = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeError) as error:
            raise ContractError(f"result inventory mismatch: changed {path.name}") from error
        if (
            not isinstance(item, dict)
            or set(item) != {"suite", "shard"}
            or not all(isinstance(item[field], str) for field in ("suite", "shard"))
        ):
            raise ContractError(f"result inventory mismatch: changed {path.name}")
        key = (item["suite"], item["shard"])
        observed[key] += 1
        if observed[key] > 1:
            raise ContractError(f"result inventory mismatch: duplicate {key[0]} {key[1]}")
    missing = expected - observed
    extra = observed - expected
    if missing:
        key = next(iter(missing))
        raise ContractError(f"result inventory mismatch: missing {key[0]} {key[1]}")
    if extra:
        key = next(iter(extra))
        raise ContractError(f"result inventory mismatch: extra {key[0]} {key[1]}")
    print(f"customer_delivery_results=valid platform={platform} count={sum(observed.values())}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, default=ROOT / "tests/customer-delivery-shards.tsv")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--matrix", choices=("linux", "macos"))
    parser.add_argument("--check-results", nargs=2, metavar=("PLATFORM", "DIRECTORY"))
    parser.add_argument("--suite", choices=sorted(SUITE_PATHS))
    parser.add_argument("--shard")
    parser.add_argument("--python-bin", default="/usr/bin/python3")
    parser.add_argument("--bats-bin")
    parser.add_argument("--timeout-seconds", type=int, default=105)
    parser.add_argument("--platform", choices=("linux", "macos"))
    parser.add_argument("--result-file", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        rows = load_registry(args.registry)
        inventories, security_arms = validate_registry(rows)
        if args.matrix:
            print(json.dumps(matrix_for(rows, args.matrix), separators=(",", ":")))
            return 0
        if args.check_results:
            platform, directory = args.check_results
            if platform not in {"linux", "macos"}:
                raise ContractError(f"unknown results platform: {platform}")
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
        if not args.suite or not args.shard or not re.fullmatch(r"[1-9][0-9]*/[1-9][0-9]*", args.shard):
            raise ContractError("suite and shard N/T are required")
        if args.timeout_seconds < 1 or args.timeout_seconds >= 110:
            raise ContractError("timeout-seconds must be between 1 and 109")
        shard, total = (int(value) for value in args.shard.split("/"))
        matching = [
            row for row in rows
            if row.suite == args.suite and row.shard == shard and row.total == total
        ]
        if len(matching) != 1:
            raise ContractError(f"unknown shard: {args.suite} {args.shard}")
        python_bin = Path(args.python_bin)
        if not python_bin.is_absolute() or not python_bin.is_file() or not os.access(python_bin, os.X_OK):
            raise ContractError("python-bin must be an absolute executable")
        bats = args.bats_bin or shutil.which("bats")
        if not bats or not Path(bats).is_absolute() or not os.access(bats, os.X_OK):
            raise ContractError("bats executable unavailable")
        row = matching[0]
        if args.platform and args.platform not in row.platforms:
            raise ContractError(f"shard not approved for platform: {args.platform}")
        environment = os.environ.copy()
        environment["CUSTOMER_DELIVERY_PYTHON"] = str(python_bin)
        environment["CUSTOMER_SCHEMA_PYTHON"] = str(python_bin)
        if row.mode == "security":
            names = [inventories["mutation"][1]]
            environment["CUSTOMER_DELIVERY_SECURITY_RANGE"] = f"{row.first}-{row.last}"
        else:
            names = selected_names(row, inventories[row.suite])
        filter_pattern = "^(" + "|".join(ere_escape(name) for name in names) + ")$"
        process = subprocess.Popen(
            [bats, "--filter", filter_pattern, str(SUITE_PATHS[row.suite])],
            env=environment,
            start_new_session=True,
        )
        try:
            returncode = process.wait(timeout=args.timeout_seconds)
            if returncode == 0 and args.result_file:
                if not args.platform:
                    raise ContractError("result-file requires platform")
                args.result_file.parent.mkdir(parents=True, exist_ok=True)
                args.result_file.write_text(
                    json.dumps({"suite": row.suite, "shard": f"{row.shard}/{row.total}"}) + "\n",
                    encoding="utf-8",
                )
            return returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            process.wait()
            print(
                f"ERROR: shard exceeded {args.timeout_seconds}s: {args.suite} {args.shard}",
                file=sys.stderr,
            )
            return 124
    except (ContractError, OSError, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
