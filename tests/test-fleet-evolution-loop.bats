#!/usr/bin/env bats
# tests/test-fleet-evolution-loop.bats — evolution loop (mock native client, dry-run).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOOP="$REPO/plugins/dr-fleet-evolution/evolution-loop.sh"
    FIX="$REPO/tests/fixtures/fleet-evolution"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — loop requires jq"
    fi

    # A skill dir under test (copy of a real starter into TMP so we never
    # mutate the shipped skill).
    SKILLDIR="$TMP/l1-basic"
    mkdir -p "$SKILLDIR"
    cat > "$SKILLDIR/SKILL.md" <<'EOF'
---
name: fleet-l1-basic
metadata:
  fleet_level: 1
  context_budget_tokens: 200
---
# Fleet L1 — Basic
Execute the task in one step. Stop and report a level-mismatch if it needs more.
EOF

    # Adapters conf pointing at the fixtures (absolute paths).
    CONF="$TMP/adapters.conf"
    cat > "$CONF" <<EOF
adapters/archive-adapter.sh|$FIX/archive|archive
adapters/dr-dream-adapter.sh|$FIX/dr-dream|dr-dream
EOF

    # Mock native client: `write` copies the source skill (valid candidate);
    # `ask` prints a score.
    MOCK="$TMP/native-mock.sh"
    cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
prompt="$(cat)"
[ -z "${NATIVE_INPUT_LOG:-}" ] || printf '%s\n' "$prompt" >> "$NATIVE_INPUT_LOG"
case "$prompt" in
    Score*) echo 0.8 ;;
    *) cat <<'SKILL'
---
name: fleet-l1-basic
metadata:
  fleet_level: 1
  context_budget_tokens: 200
---
# Fleet L1 - Basic (evolved)
Execute the task in one step. If it needs analysis, stop and report level-mismatch.
SKILL
    ;;
esac
EOF
    chmod +x "$MOCK"
    export FLEET_NATIVE_BIN="$MOCK"
}

@test "evolution-loop.sh is executable" {
    [ -x "$LOOP" ]
}

@test "loop exits 2 without --skill" {
    run "$LOOP"
    [ "$status" -eq 2 ]
}

@test "loop skips (exit 0) when dataset below threshold" {
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 999 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "below threshold"
}

@test "loop dry-run collects signals, passes gates, applies best candidate" {
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 2 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "collected"
    echo "$output" | grep -q "selected best candidate"
    echo "$output" | grep -q "dry-run"
    # the evolved marker landed in the skill copy (no real git push happened)
    grep -q "evolved" "$SKILLDIR/SKILL.md"
}

@test "native client receives the dataset as bounded reference data on stdin" {
    export NATIVE_INPUT_LOG="$TMP/native-input.log"
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 1 --dry-run
    [ "$status" -eq 0 ]
    run grep -F '<reference_data>' "$NATIVE_INPUT_LOG"
    [ "$status" -eq 0 ]
    run grep -F 'Score how well' "$NATIVE_INPUT_LOG"
    [ "$status" -eq 0 ]
}

@test "loop does NOT execute injection payloads in adapters.conf source-path (Security S1)" {
    # A malicious source-path must not be eval'd. Canary file must NOT appear.
    local canary="$TMP/pwned"
    rm -f "$canary"
    local evil="$TMP/evil.conf"
    printf 'adapters/archive-adapter.sh|$(touch %s)/x|archive\n' "$canary" > "$evil"
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$evil" --threshold 1 --dry-run
    # loop runs (skips the bad source as missing), but the payload never fired
    [ ! -e "$canary" ]
}

@test "loop expands the whitelisted env-var + default in a source-path" {
    # archive adapter pointed at fixtures via ${DR_FLEET_ARCHIVE_DIR:-...}.
    local envconf="$TMP/env.conf"
    printf 'adapters/archive-adapter.sh|${DR_FLEET_ARCHIVE_DIR:-/nope}|archive\n' > "$envconf"
    DR_FLEET_ARCHIVE_DIR="$FIX/archive" run "$LOOP" \
        --skill "$SKILLDIR" --adapters-conf "$envconf" \
        --threshold 1 --candidates 1 --dry-run
    [ "$status" -eq 0 ]
    # collected count must be > 0 (env-var expanded to the fixtures dir)
    echo "$output" | grep -qE "collected [1-9]"
}

@test "loop exits 1 when all candidates fail the gates" {
    # Mock that emits an over-budget, Cyrillic candidate (fails gates).
    BADMOCK="$TMP/native-bad.sh"
    cat > "$BADMOCK" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf -- '---\nmetadata:\n  context_budget_tokens: 5\n---\nЭто кириллица превышает бюджет много раз подряд тут текст.\n'
EOF
    chmod +x "$BADMOCK"
    FLEET_NATIVE_BIN="$BADMOCK" run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 2 --dry-run
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no candidate passed"
}
