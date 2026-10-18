#!/usr/bin/env bats

setup() {
    CHECKER="${BATS_TEST_DIRNAME}/../check-plan-completion.py"
    REPORT="${BATS_TEST_TMPDIR}/qa-report.md"
}

write_report() {
    cat >"$REPORT" <<'EOF'
### Layer 3: Plan Completeness — PASS_WITH_NOTES

| Step / deliverable | Status | Discrepancy reason | Evidence | Planned approach | Actual replacement | Missing evidence / exact check |
|--------------------|--------|--------------------|----------|------------------|-------------------|--------------------------------|
| output one | DONE | — | artifact itself verified at fixture path | — | — | — |
| output two | PARTIAL | scope cut | retained partial output and diff | — | — | — |
| output three | NOT DONE | blocked | required output absent in checked path | — | — | — |
| output four | CHANGED | misunderstood | alternate output and comparison | original plan | replacement output | — |
| output five | UNVERIFIABLE | context exhaustion | available artifacts reviewed | — | — | exact manual check: compare deployed result to source |
EOF
}

@test "Layer 3 parser accepts all five statuses without modifying the report" {
    write_report
    cp "$REPORT" "${REPORT}.before"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"statuses unchanged"* ]] \
        && cmp -s "$REPORT" "${REPORT}.before"
}

@test "Layer 3 parser rejects an unknown status" {
    write_report
    sed -i 's/| output one | DONE |/| output one | COMPLETE |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"unsupported status 'COMPLETE'"* ]]
}

@test "Layer 3 parser rejects a missing discrepancy reason" {
    write_report
    sed -i 's/| output two | PARTIAL | scope cut |/| output two | PARTIAL | — |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"supported discrepancy reason is required"* ]]
}

@test "Layer 3 parser rejects an unsupported discrepancy reason" {
    write_report
    sed -i 's/| output two | PARTIAL | scope cut |/| output two | PARTIAL | guessed |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"supported discrepancy reason is required"* ]]
}

@test "Layer 3 parser rejects missing evidence" {
    write_report
    sed -i 's/| output two | PARTIAL | scope cut | retained partial output and diff |/| output two | PARTIAL | scope cut | — |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"evidence is required for every status"* ]]
}

@test "CHANGED requires both the plan and its replacement" {
    write_report
    sed -i 's/| output four | CHANGED | misunderstood | alternate output and comparison | original plan | replacement output |/| output four | CHANGED | misunderstood | alternate output and comparison | — | replacement output |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"requires both planned approach and actual replacement"* ]]
}

@test "UNVERIFIABLE requires an exact missing-evidence description or manual check" {
    write_report
    sed -i 's/| output five | UNVERIFIABLE | context exhaustion | available artifacts reviewed | — | — | exact manual check: compare deployed result to source |/| output five | UNVERIFIABLE | context exhaustion | available artifacts reviewed | — | — | — |/' "$REPORT"
    run python3 "$CHECKER" --report "$REPORT"
    [ "$status" -eq 1 ] && [[ "$output" == *"requires the exact missing evidence or manual check"* ]]
}
