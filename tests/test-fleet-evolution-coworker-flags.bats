#!/usr/bin/env bats
# tests/test-fleet-evolution-coworker-flags.bats — Security S1 static check.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECK="$REPO/plugins/dr-fleet-evolution/dev-tools/check-coworker-file-flags.sh"
    PLUGIN="$REPO/plugins/dr-fleet-evolution"
    TMP="$BATS_TEST_TMPDIR"
}

@test "check-coworker-file-flags.sh is executable" {
    [ -x "$CHECK" ]
}

@test "the real plugin passes the S1 check (free-form via files only)" {
    run "$CHECK" "$PLUGIN"
    [ "$status" -eq 0 ]
}

@test "S1 check flags a variable interpolated into --spec" {
    local bad="$TMP/plug"
    mkdir -p "$bad"
    cat > "$bad/offender.sh" <<'EOF'
#!/usr/bin/env bash
coworker write --spec "$SKILL_BODY" --target out.md
EOF
    run "$CHECK" "$bad"
    [ "$status" -eq 1 ]
}

@test "S1 check flags a long literal in --question" {
    local bad="$TMP/plug2"
    mkdir -p "$bad"
    {
        echo '#!/usr/bin/env bash'
        printf 'coworker ask --question "'
        head -c 150 /dev/zero | tr '\0' 'x'
        printf '"\n'
    } > "$bad/offender.sh"
    run "$CHECK" "$bad"
    [ "$status" -eq 1 ]
}

@test "S1 check allows a short constant instruction in --spec" {
    local ok="$TMP/plug3"
    mkdir -p "$ok"
    cat > "$ok/fine.sh" <<'EOF'
#!/usr/bin/env bash
coworker write --spec "Improve this skill." --context body.md data.jsonl --target out.md
EOF
    run "$CHECK" "$ok"
    [ "$status" -eq 0 ]
}

@test "S1 check exits 2 on a missing directory" {
    run "$CHECK" "$TMP/nope"
    [ "$status" -eq 2 ]
}
