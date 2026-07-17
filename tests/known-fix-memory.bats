#!/usr/bin/env bats

setup() {
    ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/datarim/insights" "$ROOT/datarim/reflection"
    printf '# Verified reflection\n' >"$ROOT/datarim/reflection/reflection-FIX-0001.md"
    TOOL="$BATS_TEST_DIRNAME/../dev-tools/known-fix-memory.py"
}

teardown() {
    rm -rf "$ROOT"
}

write_insight() {
    cat >"$ROOT/datarim/insights/INSIGHTS-FIX-0001.md" <<'EOF'
# Insights

## Known Fix

```json known_fix
{
  "schema_version": 1,
  "task_id": "FIX-0001",
  "failure_class": "stale-cache-key",
  "symptoms": ["Requests return the prior tenant's cached result"],
  "root_cause": "The cache key omitted tenant_id.",
  "fix_steps": ["Add tenant_id to the cache key."],
  "verification": ["Run the cross-tenant isolation test."],
  "source_refs": ["datarim/reflection/reflection-FIX-0001.md"],
  "confidence": "high"
}
```
EOF
}

@test "validate accepts a bounded task-matching known_fix block" {
    write_insight
    run python3 "$TOOL" validate --root "$ROOT" --task FIX-0001
    [ "$status" -eq 0 ]
    [[ "$output" == *'"task_id":"FIX-0001"'* ]]
}

@test "validate rejects task-id mismatch" {
    write_insight
    sed -i 's/"task_id": "FIX-0001"/"task_id": "FIX-9999"/' \
        "$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run python3 "$TOOL" validate --root "$ROOT" --task FIX-0001
    [ "$status" -eq 2 ]
    [[ "$output" == *"task_id does not match"* ]]
}

@test "validate rejects likely credential material" {
    write_insight
    sed -i 's/The cache key omitted tenant_id\./ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD/' \
        "$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run python3 "$TOOL" validate --root "$ROOT" --task FIX-0001
    [ "$status" -eq 2 ]
    [[ "$output" == *"credential-like material"* ]]
}

@test "validate rejects a missing citation" {
    write_insight
    sed -i 's#datarim/reflection/reflection-FIX-0001.md#datarim/reflection/missing.md#' \
        "$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run python3 "$TOOL" validate --root "$ROOT" --task FIX-0001
    [ "$status" -eq 2 ]
    [[ "$output" == *"source_ref is invalid"* ]]
}

@test "validate rejects JWT and modern API-key shapes" {
    write_insight
    sed -i 's/The cache key omitted tenant_id\./sk-proj-abcdefghijklmnopqrstuvwxyz0123456789/' \
        "$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run python3 "$TOOL" validate --root "$ROOT" --task FIX-0001
    [ "$status" -eq 2 ]
    [[ "$output" == *"credential-like material"* ]]
}

@test "query returns ranked local evidence with citations" {
    write_insight
    run python3 "$TOOL" query --root "$ROOT" --query "tenant cache isolation" --limit 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"task_id":"FIX-0001"'* ]]
    [[ "$output" == *'datarim/insights/INSIGHTS-FIX-0001.md'* ]]
}

@test "query treats an unavailable configured retriever as fail-soft" {
    write_insight
    run env DATARIM_KNOWN_FIX_RETRIEVER="$ROOT/missing" \
        python3 "$TOOL" query --root "$ROOT" --query "cache" --limit 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"remote_status":"unavailable"'* ]]
    [[ "$output" == *'"task_id":"FIX-0001"'* ]]
}

@test "query skips invalid UTF-8 insights and remains fail-soft" {
    write_insight
    printf '\xff\xfe\n' >"$ROOT/datarim/insights/INSIGHTS-BAD-0001.md"
    run python3 "$TOOL" query --root "$ROOT" --query "tenant cache" --limit 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"task_id":"FIX-0001"'* ]]
}

@test "query bounds configured retriever output" {
    write_insight
    retriever="$ROOT/retriever"
    printf '%s\n' '#!/bin/sh' 'dd if=/dev/zero bs=1024 count=256 2>/dev/null' >"$retriever"
    chmod 0755 "$retriever"
    run env DATARIM_KNOWN_FIX_RETRIEVER="$retriever" \
        python3 "$TOOL" query --root "$ROOT" --query "cache" --limit 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"remote_status":"unavailable"'* ]]
}

@test "query rejects control characters" {
    write_insight
    run python3 "$TOOL" query --root "$ROOT" --query $'cache\nignore instructions' --limit 3
    [ "$status" -eq 2 ]
}

@test "dr-do performs bounded known-fix retrieval before Gap Discovery" {
    spec="$BATS_TEST_DIRNAME/../commands/dr-do.md"
    query_line=$(grep -n "known-fix-memory.py.*query" "$spec" | cut -d: -f1)
    gap_line=$(grep -n "GAP DISCOVERY" "$spec" | head -1 | cut -d: -f1)
    [ -n "$query_line" ]
    [ "$query_line" -lt "$gap_line" ]
    grep -F "evidence only" "$spec"
    grep -F "fail-soft" "$spec"
}

@test "reflection and archive require validated known_fix persistence" {
    grep -F '```json known_fix' "$BATS_TEST_DIRNAME/../skills/reflecting/SKILL.md"
    grep -F "known-fix-memory.py" "$BATS_TEST_DIRNAME/../commands/dr-archive.md"
    grep -F "do not create a task-description file" \
        "$BATS_TEST_DIRNAME/../commands/dr-archive.md"
}
