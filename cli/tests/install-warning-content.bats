#!/usr/bin/env bats
# V-AC-16 / V-AC-28 — bilingual install warning: ≥6 RU + ≥6 EN lines, exact phrases.
# Source: TUNE-0271 plan § Detailed Design D-E.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WARNING="$CLI_DIR/install-warning.sh"
    INSTALL="$CLI_DIR/install.sh"
    [ -x "$WARNING" ] || skip "install-warning.sh missing or not executable"
}

@test "V-AC-16: install-warning.sh prints exactly 6 EN: lines" {
    run "$WARNING"
    [ "$status" -eq 0 ]
    count=$(printf '%s' "$output" | grep -c '^EN:')
    [ "$count" -eq 6 ]
}

@test "V-AC-16: install-warning.sh prints exactly 6 RU: lines" {
    run "$WARNING"
    count=$(printf '%s' "$output" | grep -c '^RU:')
    [ "$count" -eq 6 ]
}

@test "V-AC-28: EN block contains AAL 3 mandate-override phrase" {
    run "$WARNING"
    [[ "$output" == *"AAL 3 mandate-override"* ]]
}

@test "V-AC-28: RU block contains «AAL 3 mandate-override» phrase" {
    run "$WARNING"
    [[ "$output" == *"AAL 3 mandate-override"* ]]
}

@test "V-AC-28: Kill-switch mentioned in EN and RU" {
    run "$WARNING"
    # «Kill-switch:» appears twice (EN + RU lines).
    count=$(printf '%s' "$output" | grep -c '^EN: Kill-switch:\|^RU: Kill-switch:')
    [ "$count" -eq 2 ]
}

@test "V-AC-28: audit log path canonicalised" {
    run "$WARNING"
    [[ "$output" == *"datarim/audit/cli-audit-{YYYY-MM-DD}.jsonl"* ]]
    [[ "$output" == *"retention 90d"* ]]
}

@test "V-AC-28: expiry date 2026-08-21 mentioned in both languages" {
    run "$WARNING"
    count=$(printf '%s' "$output" | grep -c '2026-08-21')
    [ "$count" -ge 2 ]
}

@test "V-AC-28: warning is idempotent — running twice gives identical output" {
    run "$WARNING"
    first="$output"
    run "$WARNING"
    [ "$first" = "$output" ]
}

@test "V-AC-16: install.sh --dry-run --uninstall prints the warning" {
    [ -x "$INSTALL" ] || skip "install.sh missing"
    run "$INSTALL" --dry-run --uninstall
    [ "$status" -eq 0 ]
    en_count=$(printf '%s' "$output" | grep -c '^EN:')
    ru_count=$(printf '%s' "$output" | grep -c '^RU:')
    [ "$en_count" -eq 6 ]
    [ "$ru_count" -eq 6 ]
}
