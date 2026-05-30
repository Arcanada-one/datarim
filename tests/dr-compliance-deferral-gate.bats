#!/usr/bin/env bats
#
# Integration test for /dr-compliance Step 5c (hard anti-deferral gate). The
# command is markdown instruction; this test verifies the deterministic scanner
# it wires in maps a deferral-on-touched-file finding to a BLOCK (which the
# command instructs to record as NON-COMPLIANT). Fictional task ID throughout.
#
# Maps to PRD V-AC-7: a deferral finding on a touched file → NON-COMPLIANT
# (exit 1 from the scanner that the command honours as a hard verdict).

setup() {
    PROSE_SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-deferral-prose.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/qa" "$WORK/datarim/reports"
    printf '# Tasks\n## Active\n' > "$WORK/datarim/tasks.md"
    cat > "$WORK/datarim/backlog.md" <<'EOF'
- FAKE-9301 · pending · P3 · L1 · Re-verify after 7-day soak (time-dependent) → x
EOF
    TOUCHED="$WORK/touched.txt"
    printf 'src/handler.ts\ndocker-compose.yml\n' > "$TOUCHED"
}

teardown() {
    rm -rf "$WORK"
}

@test "5c BLOCK: deferral on touched src file in compliance report → exit 1 (NON-COMPLIANT)" {
    cat > "$WORK/datarim/reports/compliance-report-FAKE-9300.md" <<'EOF'
## Compliance
The null-guard in src/handler.ts is a minor cosmetic gap, out of scope, will fix later.
EOF
    run "$PROSE_SCRIPT" --file "$WORK/datarim/reports/compliance-report-FAKE-9300.md" \
        --touched-files "$TOUCHED" --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"handler.ts"* ]]
}

@test "5c PASS: deferral on touched file backed by a real FU-ID in backlog → exit 0" {
    cat > "$WORK/datarim/reports/compliance-report-FAKE-9300.md" <<'EOF'
## Compliance
The soak result for src/handler.ts cannot be verified now — deferred to FAKE-9301
(time-dependent, needs a 7-day soak).
EOF
    run "$PROSE_SCRIPT" --file "$WORK/datarim/reports/compliance-report-FAKE-9300.md" \
        --touched-files "$TOUCHED" --root "$WORK"
    [ "$status" -eq 0 ]
}

@test "5c PASS: deferral about an untouched (foreign) component → exit 0" {
    cat > "$WORK/datarim/reports/compliance-report-FAKE-9300.md" <<'EOF'
## Compliance
The legacy auth rewrite is out of scope for this task — tracked separately.
EOF
    run "$PROSE_SCRIPT" --file "$WORK/datarim/reports/compliance-report-FAKE-9300.md" \
        --touched-files "$TOUCHED" --root "$WORK"
    [ "$status" -eq 0 ]
}
