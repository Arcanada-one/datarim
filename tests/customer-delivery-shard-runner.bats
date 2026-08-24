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
    awk -v target="$oversized_suite" '
        target == "functional" && $1 == "functional" && $2 == 1 { $6=11 }
        target == "functional" && $1 == "functional" && $2 == 2 { $5=12 }
        target == "schema" && $1 == "schema" && $2 == 1 { $6=31 }
        target == "schema" && $1 == "schema" && $2 == 2 { $5=32 }
        { print }
    ' "$REGISTRY" >"$fixture"
}

write_grouped_hot_fixture() {
    local hot_index="$1" fixture="$2"
    "$PYTHON" - "$REGISTRY" "$hot_index" "$fixture" <<'PY'
from pathlib import Path
import sys

registry = Path(sys.argv[1])
hot = int(sys.argv[2])
fixture = Path(sys.argv[3])
lines = registry.read_text(encoding="utf-8").splitlines()
functional = [line.split() for line in lines if line.startswith("functional ")]
groups = []
for row in functional:
    if row[5] == "-":
        groups.append([int(value) for value in row[4].split(",")])
    else:
        groups.append(list(range(int(row[4]), int(row[5]) + 1)))
target = next(index for index, indices in enumerate(groups) if hot in indices)
neighbors = {163: target - 1, 166: target - 1, 167: target + 1}
if hot not in neighbors:
    raise SystemExit(f"unsupported hot index: {hot}")
neighbor = neighbors[hot]
groups[min(target, neighbor)] = sorted(groups[target] + groups[neighbor])
del groups[max(target, neighbor)]

rows = ["# suite shard total mode first last platforms"]
total = len(groups)
for shard, indices in enumerate(groups, 1):
    last = "-" if len(indices) == 1 else str(indices[-1])
    rows.append(f"functional {shard} {total} ordinal {indices[0]} {last} linux,macos")
rows.extend(
    line for line in lines
    if line.startswith("schema ") or line.startswith("mutation ")
)
fixture.write_text("\n".join(rows) + "\n", encoding="utf-8")
PY
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
    awk '/^functional[[:space:]]/ && $2 == 36 { $5=$5-1 } { print }' \
        "$REGISTRY" >"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"registry coverage overlap"* ]]
}

@test "macOS functional shards reject more than 10 tests of runtime work" {
    local fixture="$BATS_TEST_TMPDIR/functional-runtime-budget.tsv"
    write_runtime_budget_fixture functional "$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"macOS ordinal shard exceeds runtime budget: functional 1 has 11 tests (max 10)"* ]]
}

@test "macOS schema shards reject more than 30 tests of runtime work" {
    local fixture="$BATS_TEST_TMPDIR/schema-runtime-budget.tsv"
    write_runtime_budget_fixture schema "$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"macOS ordinal shard exceeds runtime budget: schema 1 has 31 tests (max 30)"* ]]
}

@test "macOS timing-sensitive history tests require identity-pinned singleton shards" {
    local pair hot_index hot_name fixture
    local -a pairs=(
        '163|source history subprocesses share one total deadline'
        '166|source history deadline kills stubborn descendant pipe holders'
        '167|global validation alarm reaps late source history child process group'
    )
    for pair in "${pairs[@]}"; do
        hot_index="${pair%%|*}"
        hot_name="${pair#*|}"
        fixture="$BATS_TEST_TMPDIR/grouped-hot-${hot_index}.tsv"
        write_grouped_hot_fixture "$hot_index" "$fixture"
        run "$PYTHON" "$RUNNER" --registry "$fixture" --check
        [ "$status" -eq 2 ] \
            && [[ "$output" == *"macOS runtime-isolated test requires a dedicated shard: $hot_name"* ]] \
            || { printf 'hot_index=%s output=%s\n' "$hot_index" "$output"; return 1; }
    done
}

@test "macOS hot signed-review and mutation work is partitioned by exact identity" {
    run "$PYTHON" - "$ROOT" "$REGISTRY" <<'PY'
import importlib.util
from dataclasses import replace
from pathlib import Path
import sys

root = Path(sys.argv[1])
registry = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("customer_delivery_shards", root / "tests/run-customer-delivery-shard.py")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
rows = module.load_registry(registry)
inventories, _ = module.validate_registry(rows)
expected = {
    "functional": {
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
    },
    "mutation": {
        "Darwin executable pth authority mutant is independently killed",
        "Darwin dependency-site symlink mutant is independently killed",
        "Darwin dist-info type mutant is independently killed",
        "Darwin dist-info nofollow mutant is independently killed",
        "Darwin dist-info working-directory mutant is independently killed",
        "review inventory exact-set mutant is independently killed",
        "review inventory closure mutant is independently killed",
        "review inventory authentication mutant is independently killed",
    },
}
for suite, names in expected.items():
    inventory = inventories[suite]
    for name in names:
        if name not in inventory:
            raise SystemExit(f"missing runtime-isolated identity: {suite}: {name}")
        ordinal = inventory.index(name) + 1
        matching = [
            row for row in rows
            if row.suite == suite and "macos" in row.platforms
            and name in module.selected_names(row, inventory)
        ]
        if len(matching) != 1 or module.selected_names(matching[0], inventory) != [name]:
            raise SystemExit(f"grouped runtime-isolated identity: {suite}: {ordinal}: {name}")
        suite_rows = sorted((row for row in rows if row.suite == suite), key=lambda row: row.shard)
        target = suite_rows.index(matching[0])
        neighbor = min(
            (
                index for index, row in enumerate(suite_rows)
                if index != target
                and "macos" in row.platforms
                and names.isdisjoint(module.selected_names(row, inventory))
            ),
            key=lambda index: len(module.selected_names(suite_rows[index], inventory)),
        )
        neighbor_row = suite_rows[neighbor]
        merged_indices = sorted(
            inventory.index(item) + 1
            for item in module.selected_names(matching[0], inventory)
            + module.selected_names(neighbor_row, inventory)
        )
        merged = replace(
            matching[0], first=",".join(str(item) for item in merged_indices), last="-"
        )
        kept = [row for index, row in enumerate(suite_rows) if index not in {target, neighbor}]
        kept.insert(min(target, neighbor), merged)
        mutant_suite = [
            replace(row, shard=index, total=len(kept))
            for index, row in enumerate(kept, 1)
        ]
        mutant_rows = [row for row in rows if row.suite != suite] + mutant_suite
        try:
            module.validate_registry(mutant_rows)
        except module.ContractError as error:
            if name not in str(error):
                raise SystemExit(f"wrong isolation rejection: {suite}: {name}: {error}") from error
        else:
            raise SystemExit(f"grouped runtime isolation accepted: {suite}: {name}")
PY
    [ "$status" -eq 0 ] \
        || { printf 'partition_guard_status=%s output=%s\n' "$status" "$output"; return 1; }
}

@test "customer-delivery shard runner rejects an out-of-range selection" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 37/36 --python-bin /usr/bin/python3
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"unknown shard"* ]]
}

@test "customer-delivery shard runner rejects a command ceiling of 110 seconds" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --python-bin /usr/bin/python3 \
        --timeout-seconds 110
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"timeout-seconds must be between 1 and 109"* ]]
}

@test "customer-delivery shard runner executes its child with the default absolute interpreter" {
    local observed="$BATS_TEST_TMPDIR/observed-python" result="$BATS_TEST_TMPDIR/result.json"
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 10; exit 0; fi; printf '%s\\n' \"\$CUSTOMER_DELIVERY_PYTHON\" > '$observed'; echo '1..10'; for n in {1..10}; do echo \"ok \$n fixture\"; done"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD" \
        --platform linux --result-file "$result"
    [ "$status" -eq 0 ] \
        && [ "$(<"$observed")" = /usr/bin/python3 ] \
        && "$PYTHON" -c 'import json,sys; assert json.load(open(sys.argv[1])) == {"suite":"functional","shard":"1/36"}' "$result"
}

@test "customer-delivery shard runner separates validator and fixture interpreters" {
    local observed="$BATS_TEST_TMPDIR/observed-python"
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 10; exit 0; fi; printf '%s|%s|%s\n' \"\$CUSTOMER_DELIVERY_PYTHON\" \"\$CUSTOMER_DELIVERY_TEST_PYTHON\" \"\$CUSTOMER_SCHEMA_PYTHON\" > '$observed'; echo '1..10'; for n in {1..10}; do echo \"ok \$n fixture\"; done"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD" \
        --python-bin /usr/bin/python3 --test-python-bin /bin/true
    [ "$status" -eq 0 ] \
        && [ "$(<"$observed")" = /usr/bin/python3\|/bin/true\|/bin/true ]
}

@test "customer-delivery shard runner propagates a nonzero child status" {
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 10; exit 0; fi; exit 17'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD"
    [ "$status" -eq 17 ]
}

@test "customer-delivery shard timeout kills the child group and returns 124" {
    local pid_file="$BATS_TEST_TMPDIR/descendant.pid" descendant attempt
    make_bats_child "if [ \"\${1:-}\" = --count ]; then echo 10; exit 0; fi; (trap '' TERM; sleep 30) & printf '%s\\n' \"\$!\" > '$pid_file'; wait"
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD" --timeout-seconds 1
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
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 10; exit 0; fi; exit 0'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"Bats execution inventory mismatch: expected 10, observed 0"* ]]
}

@test "customer-delivery shard runner rejects a wrong Bats plan despite child success" {
    make_bats_child 'if [ "${1:-}" = --count ]; then echo 10; exit 0; fi; echo "1..1"; echo "ok 1 fixture"'
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/36 --bats-bin "$CHILD"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"Bats execution inventory mismatch: expected 10, observed 1"* ]]
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
        && "$PYTHON" -c 'import json,sys; rows=json.loads(sys.argv[1]); assert len(rows)==65 and len({(r["suite"],r["shard"]) for r in rows})==65 and [r["shard"] for r in rows if r["suite"]=="functional"]==[f"{i}/36" for i in range(1,37)]' "$output" \
        || return 1
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --matrix macos
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; rows=json.loads(sys.argv[1]); assert len(rows)==59 and {r["suite"] for r in rows}=={"functional","schema","mutation"} and [r["shard"] for r in rows if r["suite"]=="functional"]==[f"{i}/36" for i in range(1,37)] and [r["shard"] for r in rows if r["suite"]=="schema"]==["1/6","2/6","3/6","4/6","5/6","6/6"] and [r["shard"] for r in rows if r["suite"]=="mutation"]==[f"{i}/30" for i in range(14,31)]' "$output"
}

@test "cross-platform mutation cases are split into seventeen bounded exact shards" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check
    [ "$status" -eq 0 ] || return 1
    "$PYTHON" - "$REGISTRY" <<'PY'
import sys
rows = [line.split() for line in open(sys.argv[1], encoding="utf-8") if line.startswith("mutation ")]
portable = [row for row in rows if "macos" in row[-1]]
assert [(row[1], row[2], row[4]) for row in portable] == [
    ("14", "30", "4"), ("15", "30", "12"), ("16", "30", "13"),
    ("17", "30", "14"), ("18", "30", "15"), ("19", "30", "19"),
    ("20", "30", "5"), ("21", "30", "6"), ("22", "30", "7"),
    ("23", "30", "8"), ("24", "30", "9"), ("25", "30", "10"),
    ("26", "30", "11"), ("27", "30", "16"), ("28", "30", "17"),
    ("29", "30", "18"), ("30", "30", "20")
]
PY
}

@test "customer-delivery aggregate accepts an exact generated result inventory" {
    local results="$BATS_TEST_TMPDIR/results"
    seed_results linux "$results" || return 1
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" --check-results linux "$results"
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"customer_delivery_results=valid platform=linux count=65"* ]]
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
