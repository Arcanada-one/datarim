#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RUNNER="${CUSTOMER_DELIVERY_SHARD_RUNNER_OVERRIDE:-$ROOT/tests/run-customer-delivery-shard.py}"
    REGISTRY="$ROOT/tests/customer-delivery-shards.tsv"
    PYTHON=/usr/bin/python3
}

make_bats_child() {
    local body="$1"
    CHILD="$BATS_TEST_TMPDIR/bats-child"
    printf '%s\n' '#!/bin/bash' "$body" >"$CHILD"
    chmod +x "$CHILD"
}

seed_results() {
    local platform="$1" directory="$2"
    local matrix
    mkdir -p "$directory"
    matrix="$("$PYTHON" "$RUNNER" --registry "$REGISTRY" --matrix "$platform")" || return 1
    "$PYTHON" - "$directory" "$matrix" <<'PY'
import json
from pathlib import Path
import sys
directory = Path(sys.argv[1])
for index, item in enumerate(json.loads(sys.argv[2]), 1):
    (directory / f"result-{index}.json").write_text(json.dumps(item) + "\n")
PY
}

write_runtime_budget_fixture() {
    local oversized_suite="$1" fixture="$2"
    {
        printf '%s\n' '# suite shard total mode first last platforms'
        if [ "$oversized_suite" = functional ]; then
            printf '%s\n' \
                'functional 1 9 ordinal 1 21 linux,macos' \
                'functional 2 9 ordinal 22 40 linux,macos'
        else
            printf '%s\n' \
                'functional 1 9 ordinal 1 20 linux,macos' \
                'functional 2 9 ordinal 21 40 linux,macos'
        fi
        printf '%s\n' \
            'functional 3 9 ordinal 41 60 linux,macos' \
            'functional 4 9 ordinal 61 80 linux,macos' \
            'functional 5 9 ordinal 81 100 linux,macos' \
            'functional 6 9 ordinal 101 120 linux,macos' \
            'functional 7 9 ordinal 121 140 linux,macos' \
            'functional 8 9 ordinal 141 160 linux,macos' \
            'functional 9 9 ordinal 161 177 linux,macos'
        if [ "$oversized_suite" = schema ]; then
            printf '%s\n' \
                'schema 1 4 ordinal 1 45 linux,macos' \
                'schema 2 4 ordinal 46 87 linux,macos'
        else
            printf '%s\n' \
                'schema 1 4 ordinal 1 44 linux,macos' \
                'schema 2 4 ordinal 45 87 linux,macos'
        fi
        printf '%s\n' \
            'schema 3 4 ordinal 88 130 linux,macos' \
            'schema 4 4 ordinal 131 173 linux,macos'
        awk '/^mutation[[:space:]]/ { print }' "$REGISTRY"
    } >"$fixture"
}

@test "customer-delivery shard runner and canonical registry exist" {
    [ -f "$RUNNER" ] && [ -f "$REGISTRY" ]
}

@test "canonical customer-delivery shards cover every logical test exactly once" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"customer_delivery_shards=valid"* ]]
}

@test "customer-delivery shard registry rejects missing coverage" {
    local fixture="$BATS_TEST_TMPDIR/missing.tsv"
    awk 'BEGIN { skipped=0 } /^functional[[:space:]]/ && !skipped { skipped=1; next } { print }' \
        "$REGISTRY" >"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"registry coverage missing"* ]]
}

@test "customer-delivery shard registry rejects duplicate coverage" {
    local fixture="$BATS_TEST_TMPDIR/duplicate.tsv"
    cp "$REGISTRY" "$fixture"
    awk '/^functional[[:space:]]/ { print; exit }' "$REGISTRY" >>"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"duplicate shard"* ]]
}

@test "customer-delivery shard registry rejects an empty shard" {
    local fixture="$BATS_TEST_TMPDIR/empty.tsv"
    awk 'BEGIN { changed=0 } /^functional[[:space:]]/ && !changed { $5=2; $6=1; changed=1 } { print }' \
        "$REGISTRY" >"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"empty shard"* ]]
}

@test "customer-delivery shard registry rejects overlapping coverage" {
    local fixture="$BATS_TEST_TMPDIR/overlap.tsv"
    awk '/^functional[[:space:]]/ && $2 == 9 { $5=$5-1 } { print }' \
        "$REGISTRY" >"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"registry coverage overlap"* ]]
}

@test "macOS functional shards reject more than 20 tests of runtime work" {
    local fixture="$BATS_TEST_TMPDIR/functional-runtime-budget.tsv"
    write_runtime_budget_fixture functional "$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"macOS ordinal shard exceeds runtime budget: functional 1 has 21 tests (max 20)"* ]]
}

@test "macOS schema shards reject more than 44 tests of runtime work" {
    local fixture="$BATS_TEST_TMPDIR/schema-runtime-budget.tsv"
    write_runtime_budget_fixture schema "$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"macOS ordinal shard exceeds runtime budget: schema 1 has 45 tests (max 44)"* ]]
}

@test "customer-delivery shard runner rejects an out-of-range selection" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 10/9 --python-bin /usr/bin/python3
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"unknown shard"* ]]
}

@test "customer-delivery shard runner rejects a command ceiling of 110 seconds" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --python-bin /usr/bin/python3 \
        --timeout-seconds 110
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"timeout-seconds must be between 1 and 109"* ]]
}

@test "customer-delivery shard runner executes its child with the default absolute interpreter" {
    local observed="$BATS_TEST_TMPDIR/observed-python" result="$BATS_TEST_TMPDIR/result.json"
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 20; exit 0; fi; printf '%s\\n' \"\$CUSTOMER_DELIVERY_PYTHON\" > '$observed'; echo '1..20'; for n in {1..20}; do echo \"ok \$n fixture\"; done"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD" \
        --platform linux --result-file "$result"
    [ "$status" -eq 0 ] \
        && [ "$(<"$observed")" = /usr/bin/python3 ] \
        && "$PYTHON" -c 'import json,sys; assert json.load(open(sys.argv[1])) == {"suite":"functional","shard":"1/9"}' "$result"
}

@test "customer-delivery shard runner separates validator and fixture interpreters" {
    local observed="$BATS_TEST_TMPDIR/observed-python"
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 20; exit 0; fi; printf '%s|%s|%s\n' \"\$CUSTOMER_DELIVERY_PYTHON\" \"\$CUSTOMER_DELIVERY_TEST_PYTHON\" \"\$CUSTOMER_SCHEMA_PYTHON\" > '$observed'; echo '1..20'; for n in {1..20}; do echo \"ok \$n fixture\"; done"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD" \
        --python-bin /usr/bin/python3 --test-python-bin /bin/true
    [ "$status" -eq 0 ] \
        && [ "$(<"$observed")" = /usr/bin/python3\|/bin/true\|/bin/true ]
}

@test "customer-delivery shard runner propagates a nonzero child status" {
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 20; exit 0; fi; exit 17'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD"
    [ "$status" -eq 17 ]
}

@test "customer-delivery shard timeout kills the child group and returns 124" {
    local pid_file="$BATS_TEST_TMPDIR/descendant.pid" descendant attempt
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 20; exit 0; fi; (trap '' TERM; sleep 30) & printf '%s\\n' \"\$!\" > '$pid_file'; wait"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD" --timeout-seconds 1
    [ "$status" -eq 124 ] || return 1
    descendant="$(<"$pid_file")"
    for attempt in {1..10}; do
        kill -0 "$descendant" 2>/dev/null || return 0
        sleep 0.05
    done
    kill -KILL "$descendant" 2>/dev/null || true
    return 1
}

@test "customer-delivery shard runner rejects empty successful Bats output" {
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 20; exit 0; fi; exit 0'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"Bats execution inventory mismatch: expected 20, observed 0"* ]]
}

@test "customer-delivery shard runner rejects a wrong Bats plan despite child success" {
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 20; exit 0; fi; echo "1..1"; echo "ok 1 fixture"'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/9 --bats-bin "$CHILD"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"Bats execution inventory mismatch: expected 20, observed 1"* ]]
}

@test "customer-delivery shard runner rejects alternate Bats syntax instead of dead-testing it" {
    local mutant_source="$BATS_TEST_TMPDIR/alternate.bats" probe="$BATS_TEST_TMPDIR/probe.py"
    cp "$ROOT/dev-tools/tests/check-customer-delivery.bats" "$mutant_source"
    printf '%s\n' 'function alternate_form { # @test' '  true' '}' >>"$mutant_source"
    cat >"$probe" <<'PY'
from pathlib import Path
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("runner", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.extract_tests(Path(sys.argv[2]))
PY
    run "$PYTHON" "$probe" "$RUNNER" "$mutant_source"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"noncanonical Bats test syntax"* ]]
}

@test "customer-delivery registry generates the complete Linux and approved macOS matrices" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --matrix linux
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; rows=json.loads(sys.argv[1]); assert len(rows)==33 and len({(r["suite"],r["shard"]) for r in rows})==33 and [r["shard"] for r in rows if r["suite"]=="functional"]==["1/9","2/9","3/9","4/9","5/9","6/9","7/9","8/9","9/9"]' "$output" \
        || return 1
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --matrix macos
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; rows=json.loads(sys.argv[1]); assert len(rows)==23 and {r["suite"] for r in rows}=={"functional","schema","mutation"} and [r["shard"] for r in rows if r["suite"]=="functional"]==["1/9","2/9","3/9","4/9","5/9","6/9","7/9","8/9","9/9"] and [r["shard"] for r in rows if r["suite"]=="schema"]==["1/4","2/4","3/4","4/4"] and [r["shard"] for r in rows if r["suite"]=="mutation"]==["14/23","15/23","16/23","17/23","18/23","19/23","20/23","21/23","22/23","23/23"]' "$output"
}

@test "cross-platform mutation cases are split into ten bounded exact shards" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check
    [ "$status" -eq 0 ] || return 1
    "$PYTHON" - "$REGISTRY" <<'PY'
import sys
rows = [line.split() for line in open(sys.argv[1], encoding="utf-8") if line.startswith("mutation ")]
portable = [row for row in rows if "macos" in row[-1]]
assert [(row[1], row[2], row[4]) for row in portable] == [
    ("14", "23", "4"), ("15", "23", "8"), ("16", "23", "9"),
    ("17", "23", "10"), ("18", "23", "11"), ("19", "23", "12"),
    ("20", "23", "5"), ("21", "23", "6"), ("22", "23", "7,14"),
    ("23", "23", "13")
]
PY
}

@test "customer-delivery aggregate accepts an exact generated result inventory" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"customer_delivery_results=valid platform=linux count=33"* ]]
}

@test "customer-delivery aggregate rejects a missing result" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    rm "$results/result-1.json"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 2 ] && [[ "$output" == *"result inventory mismatch: missing"* ]]
}

@test "customer-delivery aggregate rejects a duplicate result" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    cp "$results/result-1.json" "$results/duplicate.json"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 2 ] && [[ "$output" == *"result inventory mismatch: duplicate"* ]]
}

@test "customer-delivery aggregate rejects an extra result" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    printf '%s\n' '{"suite":"foreign","shard":"1/1"}' >"$results/extra.json"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 2 ] && [[ "$output" == *"result inventory mismatch: extra"* ]]
}

@test "customer-delivery aggregate rejects a changed result" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    printf '%s\n' '{"suite":"functional","shard":"9/9"}' >"$results/result-1.json"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 2 ] && [[ "$output" == *"result inventory mismatch:"* ]] || return 1
    printf '%s\n' '{"suite":[],"shard":"1/3"}' >"$results/result-1.json"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 2 ] && [[ "$output" == *"result inventory mismatch: changed"* ]]
}
