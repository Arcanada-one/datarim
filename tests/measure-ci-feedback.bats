#!/usr/bin/env bats
# ARC-CI follow-up: run-window selection, offline compare, remote contract check.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    MEASURE="$ROOT/dev-tools/measure-ci-feedback.py"
    CHECK="$ROOT/dev-tools/check-required-contexts.sh"
    PYTHON=/usr/bin/python3
}

receipt() {  # receipt <file> <sample_size> <feedback_p50>
    "$PYTHON" - "$1" "$2" "$3" <<'PY'
import json, sys
path, n, p50 = sys.argv[1], int(sys.argv[2]), sys.argv[3]
val = "NOT_MEASURED" if p50 == "NM" else float(p50)
json.dump({
    "schema": "CiFeedbackReceipt/v1", "sample_size": n,
    "feedback_time_s": {"p50": val, "p95": val},
    "queue_time_s": {"p50": 10.0}, "run_time_s": {"p50": 5.0},
    "runner_seconds_per_successful_check": {"p50": 100.0},
    "setup_python_job_seconds": {"p50": 7.0},
    "customer_delivery_linux": {"jobs_p50": 100, "queue_p50_s": 9.0},
    "bats_shards": {"longest_median_ratio_p50": 2.0},
}, open(path, "w"))
PY
}

@test "select_runs keeps only successful runs inside the window and event" {
    run "$PYTHON" -I - "$MEASURE" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
rows = [
    {"databaseId": 1, "conclusion": "success", "event": "push", "createdAt": "2026-11-07T10:00:00Z"},
    {"databaseId": 2, "conclusion": "success", "event": "push", "createdAt": "2026-11-08T01:00:00Z"},
    {"databaseId": 3, "conclusion": "failure", "event": "push", "createdAt": "2026-11-08T02:00:00Z"},
    {"databaseId": 4, "conclusion": "success", "event": "pull_request", "createdAt": "2026-11-08T03:00:00Z"},
    {"databaseId": 5, "conclusion": "success", "event": "push", "createdAt": "2026-11-09T00:00:00Z"},
]
ids = lambda r: [x["databaseId"] for x in r]
assert ids(m.select_runs(rows, 10, since="2026-11-08T00:53:43Z")) == [2, 4, 5], "since"
assert ids(m.select_runs(rows, 10, since="2026-11-08T00:00:00Z", until="2026-11-09T00:00:00Z")) == [2, 4], "until is exclusive"
assert ids(m.select_runs(rows, 10, event="push")) == [1, 2, 5], "event"
assert ids(m.select_runs(rows, 1, since="2026-11-08T00:00:00Z")) == [2], "limit"
assert ids(m.select_runs(rows, 10)) == [1, 2, 4, 5], "no filter keeps the old behaviour"
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok ]]
}

@test "compare reports a delta only when both samples reach 10" {
    receipt "$BATS_TEST_TMPDIR/b.json" 10 435
    receipt "$BATS_TEST_TMPDIR/a.json" 12 300
    run "$PYTHON" "$MEASURE" --compare "$BATS_TEST_TMPDIR/b.json" "$BATS_TEST_TMPDIR/a.json"
    [ "$status" -eq 0 ]
    echo "$output" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema"] == "CiFeedbackCompare/v1" and d["samples_sufficient"] is True
row = [r for r in d["metrics"] if r["metric"] == "feedback_time_s.p50"][0]
assert row["delta"] == -135.0, row
assert d["claims"]["percentage_speedup_from_single_run"] is False
assert not any("percent" in k for k in row)
'
}

@test "compare keeps NOT_MEASURED when the after sample is short" {
    receipt "$BATS_TEST_TMPDIR/b.json" 10 435
    receipt "$BATS_TEST_TMPDIR/a.json" 3 300
    run "$PYTHON" "$MEASURE" --compare "$BATS_TEST_TMPDIR/b.json" "$BATS_TEST_TMPDIR/a.json"
    [ "$status" -eq 0 ]
    echo "$output" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["samples_sufficient"] is False
assert all(r["delta"] == "NOT_MEASURED" for r in d["metrics"]), d["metrics"]
'
}

@test "compare keeps NOT_MEASURED for a metric that was not measured on one side" {
    receipt "$BATS_TEST_TMPDIR/b.json" 10 NM
    receipt "$BATS_TEST_TMPDIR/a.json" 10 300
    run "$PYTHON" "$MEASURE" --compare "$BATS_TEST_TMPDIR/b.json" "$BATS_TEST_TMPDIR/a.json"
    [ "$status" -eq 0 ]
    echo "$output" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
by = {r["metric"]: r for r in d["metrics"]}
assert by["feedback_time_s.p50"]["delta"] == "NOT_MEASURED"
assert by["queue_time_s.p50"]["delta"] == 0.0
'
}

contract_fixture() {  # contract_fixture <dir> ; writes protection.json + rules.json equal to contract
    mkdir -p "$1"
    "$PYTHON" - "$ROOT/tests/required-check-contexts.json" "$1" <<'PY'
import json, sys
ctx = json.load(open(sys.argv[1]))["contexts"]
json.dump({"contexts": ctx}, open(sys.argv[2] + "/protection.json", "w"))
json.dump([{"type": "deletion"}], open(sys.argv[2] + "/rules.json", "w"))
PY
}

@test "remote check passes when protection equals the contract" {
    contract_fixture "$BATS_TEST_TMPDIR/fx"
    CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fx" run bash "$CHECK" remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"remote_match=true count=19"* ]]
    [[ "$output" == *'"branch_protection": 19'* ]]
}

@test "remote check passes in a different order and when a ruleset also names a context" {
    contract_fixture "$BATS_TEST_TMPDIR/fx"
    "$PYTHON" - "$BATS_TEST_TMPDIR/fx" <<'PY'
import json, sys
d = sys.argv[1]
p = json.load(open(d + "/protection.json")); p["contexts"].reverse()
json.dump(p, open(d + "/protection.json", "w"))
json.dump([{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "gitleaks"}]}}],
          open(d + "/rules.json", "w"))
PY
    CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fx" run bash "$CHECK" remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch_protection+ruleset"* ]]
}

@test "remote check fails on a ruleset-only extra context (R-REQUIRED-CHECKS)" {
    contract_fixture "$BATS_TEST_TMPDIR/fx"
    echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"new-required-gate"}]}}]' \
        >"$BATS_TEST_TMPDIR/fx/rules.json"
    CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fx" run bash "$CHECK" remote
    [ "$status" -eq 1 ]
    [[ "$output" == *"new-required-gate"* ]]
    [[ "$output" == *"ruleset"* ]]
}

@test "remote check fails when a contract context is missing on the remote" {
    contract_fixture "$BATS_TEST_TMPDIR/fx"
    "$PYTHON" - "$BATS_TEST_TMPDIR/fx" <<'PY'
import json, sys
f = sys.argv[1] + "/protection.json"
p = json.load(open(f)); p["contexts"].remove("shard 4/8")
json.dump(p, open(f, "w"))
PY
    CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fx" run bash "$CHECK" remote
    [ "$status" -eq 1 ]
    [[ "$output" == *"shard 4/8"* ]]
}

@test "remote check never reads an unreadable answer as a pass" {
    mkdir -p "$BATS_TEST_TMPDIR/fx"
    CHECK_REQUIRED_CONTEXTS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fx" run bash "$CHECK" remote
    [ "$status" -ne 0 ]
}
