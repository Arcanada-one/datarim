#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RUNNER="$ROOT/tests/run-customer-delivery-shard.py"
    REGISTRY="$ROOT/tests/customer-delivery-shards.tsv"
    PYTHON=/usr/bin/python3
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
    awk 'BEGIN { seen=0 } /^functional[[:space:]]/ { seen++; if (seen==2) $5=$5-1 } { print }' \
        "$REGISTRY" >"$fixture"
    run "$PYTHON" "$RUNNER" --registry "$fixture" --check
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"registry coverage overlap"* ]]
}

@test "customer-delivery shard runner rejects an out-of-range selection" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 4/3 --python-bin /usr/bin/python3
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"unknown shard"* ]]
}

@test "customer-delivery shard runner rejects a command ceiling of 110 seconds" {
    run "$PYTHON" "$RUNNER" --registry "$REGISTRY" \
        --suite functional --shard 1/3 --python-bin /usr/bin/python3 \
        --timeout-seconds 110
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"timeout-seconds must be between 1 and 109"* ]]
}
