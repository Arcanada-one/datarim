#!/usr/bin/env python3
"""Duration-aware, reproducible Bats shard assignment (LPT packing).

Reads the discovered suite list on stdin (or --list-file) and optional
per-suite durations, then prints the suites for shard N/M. Suites without a
measured duration receive the median measured duration and are counted under
durations_missing (NOT_MEASURED for those rows, not invented certainty).

The required-check contract keeps eight shards named shard 1/8 .. shard 8/8;
this helper only reorders membership inside that fixed M.
"""

from __future__ import annotations

import argparse
import statistics
import sys
from pathlib import Path


def load_durations(path: Path) -> dict[str, float]:
    durations: dict[str, float] = {}
    if not path.is_file():
        return durations
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        durations[parts[0]] = float(parts[1])
    return durations


def pack(suites: list[str], durations: dict[str, float], shard_count: int) -> list[list[str]]:
    if shard_count < 1:
        raise SystemExit("ERROR: shard count must be >= 1")
    measured = list(durations.values())
    default = statistics.median(measured) if measured else 1.0
    loads = [0.0] * shard_count
    bins: list[list[str]] = [[] for _ in range(shard_count)]
    ranked = sorted(
        ((suite, durations.get(suite, default)) for suite in suites),
        key=lambda item: (-item[1], item[0]),
    )
    for suite, seconds in ranked:
        index = min(range(shard_count), key=lambda i: (loads[i], i))
        bins[index].append(suite)
        loads[index] += seconds
    for bucket in bins:
        bucket.sort()
    return bins


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shard", required=True, help="N/M")
    parser.add_argument("--durations", type=Path, required=True)
    parser.add_argument("--list-file", type=Path)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()
    try:
        shard_n_text, shard_m_text = args.shard.split("/", 1)
        shard_n = int(shard_n_text)
        shard_m = int(shard_m_text)
    except ValueError:
        print("ERROR: --shard expects N/M", file=sys.stderr)
        return 2
    if shard_m < 1 or shard_n < 1 or shard_n > shard_m:
        print(f"ERROR: invalid shard {args.shard}", file=sys.stderr)
        return 2

    if args.list_file:
        suites = [
            line.strip()
            for line in args.list_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    else:
        suites = [line.strip() for line in sys.stdin if line.strip()]

    durations = load_durations(args.durations)
    missing = [suite for suite in suites if suite not in durations]
    bins = pack(suites, durations, shard_m)
    if args.report:
        measured = [durations[s] for s in suites if s in durations]
        default = statistics.median(measured) if measured else 1.0
        loads = []
        for bucket in bins:
            loads.append(sum(durations.get(suite, default) for suite in bucket))
        ratio = max(loads) / statistics.median(loads) if loads else 0.0
        print(
            "assignment="
            f"shards={shard_m} suites={len(suites)} durations_known={len(suites) - len(missing)} "
            f"durations_missing={len(missing)} longest={max(loads):.3f} "
            f"median={statistics.median(loads):.3f} longest_median_ratio={ratio:.3f} "
            f"missing_duration_policy=median_or_1s",
            file=sys.stderr,
        )
        if missing:
            print(
                "durations_missing_sample=" + ",".join(missing[:5]),
                file=sys.stderr,
            )
    for suite in bins[shard_n - 1]:
        print(suite)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
