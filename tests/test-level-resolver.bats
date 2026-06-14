#!/usr/bin/env bats
# tests/test-level-resolver.bats — fleet task level classifier tests.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RESOLVER="$REPO/plugins/dr-orchestrate/scripts/level_resolver.sh"
    TMP="$BATS_TEST_TMPDIR"
    # Disable LLM fallback in tests — heuristic-only, deterministic.
    export FLEET_RESOLVER_NO_LLM=1
}

@test "resolver exists and is executable" {
    [ -x "$RESOLVER" ]
}

@test "emits valid JSON with complexity, aal, confidence, reason" {
    echo "Fix a typo in README." > "$TMP/t.md"
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.complexity and .aal and (.confidence != null) and .reason' >/dev/null
}

@test "trivial one-line task classifies as L1" {
    echo "Rename variable foo to bar." > "$TMP/t.md"
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$(echo "$output" | jq -r '.complexity')" -eq 1 ]
}

@test "templated multi-step task classifies as L2" {
    cat > "$TMP/t.md" <<'EOF'
Add a new config key and update the three template files that reference it.
Follow the existing pattern. Touches config.yaml plus two templates.
EOF
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$(echo "$output" | jq -r '.complexity')" -eq 2 ]
}

@test "analytical task with choice classifies as L3" {
    cat > "$TMP/t.md" <<'EOF'
Analyze the retry behavior and decide between exponential backoff and a token
bucket. Compare tradeoffs, choose an approach, justify it, then implement across
src/retry.ts and src/queue.ts.
EOF
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$(echo "$output" | jq -r '.complexity')" -eq 3 ]
}

@test "complex multi-subtask task classifies as L4 or higher" {
    cat > "$TMP/t.md" <<'EOF'
Design and implement a new subsystem with several subtasks: schema, validator,
five skill files, a classifier, CI gate, and two test suites. Coordinate the
phases, threat-model the surface, and wire it into the orchestrator.
EOF
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$(echo "$output" | jq -r '.complexity')" -ge 4 ]
}

@test "complexity and aal are independent fields (two axes)" {
    echo "Rename a variable." > "$TMP/t.md"
    run "$RESOLVER" --task-file "$TMP/t.md"
    # both present, aal not derived as equal-to-complexity by construction
    echo "$output" | jq -e 'has("complexity") and has("aal")' >/dev/null
}

@test "missing task-file is usage error (exit 2)" {
    run "$RESOLVER"
    [ "$status" -eq 2 ]
}

@test "nonexistent task-file is failure (exit 1)" {
    run "$RESOLVER" --task-file "$TMP/nope.md"
    [ "$status" -eq 1 ]
}

@test "V-AC-7: known-input returns BOTH axes (complexity and aal) as separate fields" {
    echo "Rename variable foo to bar." > "$TMP/t.md"
    run "$RESOLVER" --task-file "$TMP/t.md"
    [ "$status" -eq 0 ]
    # both axes present and independently typed
    echo "$output" | jq -e '(.complexity | type == "number") and (.aal | type == "number")' >/dev/null
}

@test "V-AC-7: PM-override file reassigns complexity and aal" {
    echo "Rename variable foo to bar." > "$TMP/job-42.md"
    mkdir -p "$TMP/overrides"
    printf '{"complexity": 4, "aal": 3}\n' > "$TMP/overrides/job-42.json"
    run "$RESOLVER" --task-file "$TMP/job-42.md" --override-dir "$TMP/overrides"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.complexity')" -eq 4 ]
    [ "$(echo "$output" | jq -r '.aal')" -eq 3 ]
    echo "$output" | jq -e '.reason | test("override")' >/dev/null
}

@test "V-AC-7: PM-override ignored when no override file for this task" {
    echo "Rename variable foo to bar." > "$TMP/job-99.md"
    mkdir -p "$TMP/overrides"
    run "$RESOLVER" --task-file "$TMP/job-99.md" --override-dir "$TMP/overrides"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.complexity')" -eq 1 ]
}

@test "V-AC-7: ambiguous input triggers a REAL LLM-fallback call (not a stub)" {
    # Ambiguous brief → confidence < 0.5 → fallback. Inject a mock LLM command
    # that returns a structured complexity verdict; resolver must USE it.
    cat > "$TMP/ambig.md" <<'EOF'
something or other about a thing maybe
EOF
    MOCK="$TMP/mock_llm.sh"
    cat > "$MOCK" <<'MOCKEOF'
#!/usr/bin/env bash
# Emit a JSON complexity verdict regardless of args (stand-in for coworker/DeepSeek).
echo '{"complexity": 3, "aal": 2, "confidence": 0.7, "reason": "llm-mock verdict"}'
MOCKEOF
    chmod +x "$MOCK"
    # Enable fallback (unset NO_LLM) and point the resolver at the mock.
    run env -u FLEET_RESOLVER_NO_LLM FLEET_RESOLVER_LLM_CMD="bash $MOCK" \
        "$RESOLVER" --task-file "$TMP/ambig.md"
    [ "$status" -eq 0 ]
    # The verdict came from the mock, proving a real call path (not "would run here").
    echo "$output" | jq -e '.reason | test("llm")' >/dev/null
}

@test "V-AC-7: low-confidence with NO_LLM does NOT emit the old stub phrase" {
    echo "something or other about a thing maybe" > "$TMP/ambig2.md"
    run "$RESOLVER" --task-file "$TMP/ambig2.md"
    [ "$status" -eq 0 ]
    # The retired stub literal must be gone.
    ! echo "$output" | grep -q "would run here"
}
