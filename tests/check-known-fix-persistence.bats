#!/usr/bin/env bats
#
# tests/check-known-fix-persistence.bats
#
# The gate exists because three different situations were indistinguishable on
# disk: a task that recorded a fix, a task that correctly recorded "none", and
# a task where the step never ran. These tests pin all three apart, and pin the
# fourth (a present-but-invalid record) as its own failure with its own
# remediation.

setup() {
    ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/datarim/insights" "$ROOT/datarim/reflection"
    GATE="$BATS_TEST_DIRNAME/../dev-tools/check-known-fix-persistence.sh"
}

teardown() {
    rm -rf "$ROOT"
}

write_reflection() {
    printf '# Reflection: FIX-0001\n\n## Summary\n\nDid a thing.\n' \
        >"$ROOT/datarim/reflection/reflection-FIX-0001.md"
}

append_reflection() {
    printf '%s\n' "$1" >>"$ROOT/datarim/reflection/reflection-FIX-0001.md"
}

write_valid_insight() {
    write_reflection
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

# --- verdict: recorded -------------------------------------------------------

@test "recorded: a schema-valid known_fix block passes" {
    write_valid_insight
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *recorded* ]]
}

# --- verdict: declined -------------------------------------------------------

@test "declined: the inline 'Known Fix: none' prose form passes" {
    write_reflection
    append_reflection "Known Fix: none"
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *declined* ]]
}

@test "declined: the template's '## Known Fix' section with a 'none' body passes" {
    write_reflection
    append_reflection ""
    append_reflection "## Known Fix"
    append_reflection ""
    append_reflection "none — the task produced findings, not a reusable failure-to-fix mapping."
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *declined* ]]
}

@test "declined: bold and mixed case do not fail an otherwise valid verdict" {
    write_reflection
    append_reflection "**Known Fix:** None."
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
}

@test "declined: a bullet-prefixed verdict is accepted (found in the real corpus)" {
    write_reflection
    append_reflection "- Known Fix: none. The reusable fixes above are framework recommendations."
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *declined* ]]
}

@test "declined: a bulleted body line under the section heading is accepted" {
    write_reflection
    append_reflection ""
    append_reflection "## Known Fix"
    append_reflection ""
    append_reflection "- none — findings only."
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *declined* ]]
}

# --- verdict: silent (the defect state this gate exists to expose) -----------

@test "silent: a reflection with no verdict at all fails" {
    write_reflection
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *silent* ]]
    [[ "$output" == *remediation* ]]
}

@test "silent: no reflection and no insight fails" {
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *silent* ]]
}

@test "silent: an insight file with no known_fix block is not a verdict" {
    write_reflection
    printf '# Insights\n\n## Gap Discoveries\n\nSomething unrelated.\n' \
        >"$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *silent* ]]
}

@test "silent: a 'Known Fix' section that is present but not 'none' is not a verdict" {
    write_reflection
    append_reflection ""
    append_reflection "## Known Fix"
    append_reflection ""
    append_reflection "TODO — decide this later."
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *silent* ]]
}

# --- verdict: invalid, distinct from silent ---------------------------------

@test "invalid: a present-but-malformed record fails as 'invalid', not 'silent'" {
    write_reflection
    cat >"$ROOT/datarim/insights/INSIGHTS-FIX-0001.md" <<'EOF'
# Insights

```json known_fix
{"schema_version": 1, "task_id": "FIX-0001"}
```
EOF
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *invalid* ]]
    [[ "$output" != *silent* ]]
}

@test "invalid: a task_id mismatch is caught by the delegated validator" {
    write_reflection
    write_valid_insight
    sed -i.bak 's/"task_id": "FIX-0001"/"task_id": "FIX-0002"/' \
        "$ROOT/datarim/insights/INSIGHTS-FIX-0001.md"
    run "$GATE" --task FIX-0001 --root "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *invalid* ]]
}

# --- usage and untrusted input ----------------------------------------------

@test "usage: missing arguments exit 2, distinct from any verdict" {
    run "$GATE" --task FIX-0001
    [ "$status" -eq 2 ]
    run "$GATE" --root "$ROOT"
    [ "$status" -eq 2 ]
}

@test "usage: a malformed task id is refused before it reaches a path" {
    run "$GATE" --task "../../etc/passwd" --root "$ROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid task id"* ]]
}

@test "usage: an unknown argument exits 2" {
    run "$GATE" --task FIX-0001 --root "$ROOT" --bogus
    [ "$status" -eq 2 ]
}

@test "usage: a missing root exits 2, not a false 'silent'" {
    run "$GATE" --task FIX-0001 --root "$ROOT/nope"
    [ "$status" -eq 2 ]
    [[ "$output" != *silent* ]]
}

@test "--quiet suppresses the pass line but keeps the exit contract" {
    write_valid_insight
    run "$GATE" --task FIX-0001 --root "$ROOT" --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the gate is executable and shellcheck-clean" {
    [ -x "$GATE" ]
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$GATE"
    [ "$status" -eq 0 ]
}
