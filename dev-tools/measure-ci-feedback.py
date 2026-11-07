#!/usr/bin/env python3
"""Measure reproducible CI feedback metrics for Arcanada-one/datarim.

Reads GitHub Actions job timing for one or more workflow runs and emits a
JSON receipt with p50/p95 feedback time, runner-seconds, queue decomposition
and shard balance. Values that lack a sufficient sample are reported as
NOT_MEASURED rather than invented.

Usage:
  measure-ci-feedback.py --repo OWNER/NAME --workflow bats.yml --limit 10
  measure-ci-feedback.py --repo OWNER/NAME --run-id 42423807029 [--run-id ...]
  measure-ci-feedback.py --jobs-json /path/to/jobs.json --run-id 1

Requires `gh` authenticated for live fetches. Offline --jobs-json mode is for
fixtures and local receipts.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


NOT_MEASURED = "NOT_MEASURED"
MIN_SAMPLE = 10


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    index = int(round(p * (len(ordered) - 1)))
    return ordered[index]


def median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def measured_or_nm(value: float | None, sample: int, minimum: int = MIN_SAMPLE) -> Any:
    if value is None or sample < minimum:
        return NOT_MEASURED
    return round(value, 3)


def gh_api(path: str) -> Any:
    raw = subprocess.check_output(["gh", "api", path], text=True)
    return json.loads(raw)


def list_success_runs(repo: str, workflow: str, limit: int) -> list[dict[str, Any]]:
    raw = subprocess.check_output(
        [
            "gh",
            "run",
            "list",
            "-R",
            repo,
            "--workflow",
            workflow,
            "--limit",
            str(max(limit * 3, limit)),
            "--json",
            "databaseId,conclusion,status,headSha,createdAt,updatedAt,event,url,displayTitle",
        ],
        text=True,
    )
    runs = [row for row in json.loads(raw) if row.get("conclusion") == "success"]
    return runs[:limit]


def fetch_jobs(repo: str, run_id: int) -> list[dict[str, Any]]:
    jobs: list[dict[str, Any]] = []
    page = 1
    while True:
        data = gh_api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100&page={page}")
        batch = data.get("jobs") or []
        jobs.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return jobs


def peak_concurrency(jobs: list[dict[str, Any]], predicate=None) -> int:
    events: list[tuple[datetime, int]] = []
    for job in jobs:
        if predicate and not predicate(job):
            continue
        started = parse_ts(job.get("started_at"))
        completed = parse_ts(job.get("completed_at"))
        if started and completed:
            events.append((started, 1))
            events.append((completed, -1))
    events.sort()
    current = 0
    peak = 0
    for _, delta in events:
        current += delta
        peak = max(peak, current)
    return peak


def summarize_run(run_id: int, jobs: list[dict[str, Any]]) -> dict[str, Any]:
    queues: list[float] = []
    runs: list[float] = []
    shard_runs: list[float] = []
    cd_queues: list[float] = []
    cd_runs: list[float] = []
    setup_seconds = 0.0
    setup_steps = 0
    created_at = [parse_ts(job.get("created_at")) for job in jobs]
    completed_at = [parse_ts(job.get("completed_at")) for job in jobs]
    created_at = [value for value in created_at if value is not None]
    completed_at = [value for value in completed_at if value is not None]
    feedback = None
    if created_at and completed_at:
        feedback = (max(completed_at) - min(created_at)).total_seconds()

    for job in jobs:
        name = job.get("name") or ""
        created = parse_ts(job.get("created_at"))
        started = parse_ts(job.get("started_at"))
        completed = parse_ts(job.get("completed_at"))
        if created and started:
            queues.append((started - created).total_seconds())
        if started and completed:
            duration = (completed - started).total_seconds()
            runs.append(duration)
            if name.startswith("shard ") and "/8" in name:
                shard_runs.append(duration)
            if name.startswith("customer delivery") and "(Linux)" in name:
                cd_runs.append(duration)
                if created and started:
                    cd_queues.append((started - created).total_seconds())
        for step in job.get("steps") or []:
            step_name = step.get("name") or ""
            if "Set up Python" in step_name or "setup-python" in step_name.lower():
                step_started = parse_ts(step.get("started_at"))
                step_completed = parse_ts(step.get("completed_at"))
                if step_started and step_completed:
                    setup_seconds += (step_completed - step_started).total_seconds()
                    setup_steps += 1

    shard_ratio = None
    if len(shard_runs) >= 8:
        shard_ratio = max(shard_runs) / statistics.median(shard_runs)

    return {
        "run_id": run_id,
        "job_count": len(jobs),
        "feedback_s": feedback,
        "queue_p50_s": median(queues),
        "queue_p95_s": percentile(queues, 0.95),
        "run_p50_s": median(runs),
        "run_p95_s": percentile(runs, 0.95),
        "runner_seconds": sum(runs) if runs else None,
        "setup_python_job_seconds": setup_seconds,
        "setup_python_steps": setup_steps,
        "customer_delivery_linux_n": len(cd_runs),
        "customer_delivery_linux_queue_p50_s": median(cd_queues),
        "customer_delivery_linux_run_p50_s": median(cd_runs),
        "shard_runs_s": shard_runs,
        "shard_longest_median_ratio": shard_ratio,
        "peak_concurrency": peak_concurrency(jobs),
        "customer_delivery_linux_peak_concurrency": peak_concurrency(
            jobs,
            predicate=lambda job: (job.get("name") or "").startswith("customer delivery")
            and "(Linux)" in (job.get("name") or ""),
        ),
    }


def propose_group_size(slots: int, logical_jobs: int, median_run_s: float | None) -> int:
    """Choose a microjob group size from measured slots, not a fixed constant."""
    slots = max(1, slots)
    logical_jobs = max(1, logical_jobs)
    by_slots = int(math.ceil(logical_jobs / slots))
    if median_run_s and median_run_s > 0:
        by_wall = max(1, int(180 // median_run_s))
        return max(1, min(by_slots, by_wall))
    return max(1, by_slots)


def aggregate(summaries: list[dict[str, Any]]) -> dict[str, Any]:
    sample = len(summaries)

    def collect(key: str) -> list[float]:
        return [float(row[key]) for row in summaries if row.get(key) is not None]

    feedback = collect("feedback_s")
    queue_p50 = collect("queue_p50_s")
    queue_p95 = collect("queue_p95_s")
    run_p50 = collect("run_p50_s")
    runner_seconds = collect("runner_seconds")
    cd_queue = collect("customer_delivery_linux_queue_p50_s")
    cd_run = collect("customer_delivery_linux_run_p50_s")
    peak = collect("peak_concurrency")
    cd_peak = collect("customer_delivery_linux_peak_concurrency")
    shard_ratio = collect("shard_longest_median_ratio")
    setup = collect("setup_python_job_seconds")
    cd_n = collect("customer_delivery_linux_n")

    slots = int(median(cd_peak) or 0) or int(median(peak) or 1)
    logical = int(median(cd_n) or 0) or 1
    group_size = propose_group_size(slots, logical, median(cd_run))

    return {
        "schema": "CiFeedbackReceipt/v1",
        "measured_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sample_size": sample,
        "min_sample": MIN_SAMPLE,
        "feedback_time_s": {
            "p50": measured_or_nm(median(feedback), sample),
            "p95": measured_or_nm(percentile(feedback, 0.95), sample),
        },
        "queue_time_s": {
            "p50": measured_or_nm(median(queue_p50), sample),
            "p95": measured_or_nm(median(queue_p95), sample),
            "note": "created_at->started_at across jobs; capacity vs needs vs scheduling are not separated further here",
        },
        "run_time_s": {
            "p50": measured_or_nm(median(run_p50), sample),
            "p95": measured_or_nm(percentile(collect("run_p95_s"), 0.95), sample),
        },
        "runner_seconds_per_successful_check": {
            "p50": measured_or_nm(median(runner_seconds), sample),
            "p95": measured_or_nm(percentile(runner_seconds, 0.95), sample),
        },
        "setup_python_job_seconds": {
            "p50": measured_or_nm(median(setup), sample),
            "p95": measured_or_nm(percentile(setup, 0.95), sample),
        },
        "customer_delivery_linux": {
            "jobs_p50": measured_or_nm(median(cd_n), sample),
            "queue_p50_s": measured_or_nm(median(cd_queue), sample),
            "run_p50_s": measured_or_nm(median(cd_run), sample),
            "peak_concurrency_p50": measured_or_nm(median(cd_peak), sample),
        },
        "bats_shards": {
            "count": 8,
            "longest_median_ratio_p50": measured_or_nm(median(shard_ratio), len(shard_ratio), minimum=1),
            "experiment_target_longest_median_ratio": 1.5,
        },
        "measured_slots": {
            "customer_delivery_linux_peak_concurrency_p50": measured_or_nm(median(cd_peak), sample),
            "all_jobs_peak_concurrency_p50": measured_or_nm(median(peak), sample),
            "proposed_microjob_group_size": group_size,
            "formula": "min(ceil(logical_jobs/slots), floor(180/median_run_s))",
        },
        "runs": summaries,
        "claims": {
            "percentage_speedup_from_single_run": False,
            "runtime_authorized": False,
            "KC2": NOT_MEASURED,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="Arcanada-one/datarim")
    parser.add_argument("--workflow", default="bats.yml")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--run-id", action="append", type=int, default=[])
    parser.add_argument("--jobs-json", type=Path, help="Offline jobs array for a single --run-id")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summaries: list[dict[str, Any]] = []

    if args.jobs_json:
        if len(args.run_id) != 1:
            print("ERROR: --jobs-json requires exactly one --run-id", file=sys.stderr)
            return 2
        jobs = json.loads(args.jobs_json.read_text(encoding="utf-8"))
        summaries.append(summarize_run(args.run_id[0], jobs))
    else:
        run_ids = list(args.run_id)
        if not run_ids:
            runs = list_success_runs(args.repo, args.workflow, args.limit)
            run_ids = [int(row["databaseId"]) for row in runs]
        for run_id in run_ids:
            jobs = fetch_jobs(args.repo, run_id)
            summaries.append(summarize_run(run_id, jobs))
            print(f"measured run {run_id} jobs={len(jobs)}", file=sys.stderr)

    receipt = aggregate(summaries)
    text = json.dumps(receipt, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
