#!/usr/bin/env bats
# tune-0270-multi-instance-id-collision.bats
#
# TUNE-0270 — multi-instance Datarim ID-collision probe scope.
#
# /dr-init Step-4 ID-collision probe historically scanned only the single
# resolved datarim/ instance. A fleet can hold several datarim/ instances
# (workspace root + nested Projects/*/datarim/); universal AREA prefixes span
# them all, so the same ID string can be claimed cross-instance for different
# work without /dr-init noticing (the 3-way TUNE-0251 collision that motivated
# this task). This suite covers:
#   Group A — markdown-contract assertions on commands/dr-init.md (the new
#             CROSS-INSTANCE advisory branch + history-agnostic guard).
#   Group B — functional harness for dev-tools/scan-id-across-instances.sh
#             against fixture multi-instance trees.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
DR_INIT="${REPO_ROOT}/commands/dr-init.md"
HELPER="${REPO_ROOT}/dev-tools/scan-id-across-instances.sh"

# ── Group A — markdown-contract assertions (commands/dr-init.md Step 4) ──────

@test "A01: dr-init.md documents a CROSS-INSTANCE advisory collision branch" {
    grep -iE "CROSS-INSTANCE" "$DR_INIT"
}

@test "A02: dr-init.md names the scan-id-across-instances.sh helper" {
    grep -F "scan-id-across-instances.sh" "$DR_INIT"
}

@test "A03: dr-init.md marks the cross-instance branch advisory / non-blocking" {
    # Advisory wording must appear in the CROSS-INSTANCE block.
    grep -iE "cross-instance.*(advisory|non-blocking)|(advisory|non-blocking).*cross-instance" "$DR_INIT" \
        || grep -iEA6 "CROSS-INSTANCE" "$DR_INIT" | grep -iE "advisory|non-blocking"
}

@test "A04: dr-init.md cross-instance prose stays history-agnostic (no task-ID citation)" {
    # task-id-gate.sh forbids provenance IDs in the shipped command surface.
    run grep -coE "[A-Z]{2,6}-[0-9]{4}" "$DR_INIT"
    [ "$output" = "0" ]
}

@test "A05: dr-init.md still passes the history-agnostic task-id-gate" {
    run bash "${REPO_ROOT}/scripts/task-id-gate.sh" "$DR_INIT"
    [ "$status" -eq 0 ]
}

# ── Group B — functional harness for scan-id-across-instances.sh ─────────────

setup() {
    SCAN_ROOT="$(mktemp -d)"
    # self instance (the one /dr-init resolved) + two sibling instances
    mkdir -p "${SCAN_ROOT}/datarim"
    mkdir -p "${SCAN_ROOT}/Projects/Alpha/datarim"
    mkdir -p "${SCAN_ROOT}/Projects/Beta/datarim"
    # excluded surfaces
    mkdir -p "${SCAN_ROOT}/Projects/Datarim/code/datarim"
    mkdir -p "${SCAN_ROOT}/node_modules/pkg/datarim"
    SELF="${SCAN_ROOT}/datarim"
    printf -- '- TUNE-0100 · unrelated self entry\n' > "${SCAN_ROOT}/datarim/backlog.md"
    : > "${SCAN_ROOT}/datarim/tasks.md"
    : > "${SCAN_ROOT}/Projects/Alpha/datarim/backlog.md"
    : > "${SCAN_ROOT}/Projects/Beta/datarim/tasks.md"
}

teardown() {
    rm -rf "${SCAN_ROOT}"
}

@test "B01: helper is executable and passes bash -n" {
    [ -x "$HELPER" ]
    run bash -n "$HELPER"
    [ "$status" -eq 0 ]
}

@test "B02: detects the same ID as an entry line in a sibling backlog.md" {
    printf -- '- TUNE-0270 · different work in a sibling instance\n' \
        >> "${SCAN_ROOT}/Projects/Alpha/datarim/backlog.md"
    run bash "$HELPER" "TUNE-0270" "$SCAN_ROOT" "$SELF"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Projects/Alpha/datarim/backlog.md"
}

@test "B03: detects the same ID as an entry line in a sibling tasks.md" {
    printf -- '- TUNE-0270 · already in flight elsewhere\n' \
        >> "${SCAN_ROOT}/Projects/Beta/datarim/tasks.md"
    run bash "$HELPER" "TUNE-0270" "$SCAN_ROOT" "$SELF"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Projects/Beta/datarim/tasks.md"
}

# The scope banner is written to stderr; these assertions isolate stdout
# (the match channel) via `2>/dev/null` so an empty stdout means "no match".

@test "B04: self-exclusion — the current instance's own entry is NOT reported" {
    printf -- '- TUNE-0270 · this is our own just-assigned entry\n' \
        >> "${SCAN_ROOT}/datarim/backlog.md"
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B05: prose mention (not entry-anchored) is NOT reported" {
    printf -- '- TUNE-0001 · real task\n  see also TUNE-0270 in earlier discussion\n' \
        >> "${SCAN_ROOT}/Projects/Alpha/datarim/backlog.md"
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B06: framework code/datarim template surface is pruned (not reported)" {
    printf -- '- TUNE-0270 · template placeholder in framework source tree\n' \
        > "${SCAN_ROOT}/Projects/Datarim/code/datarim/backlog.md"
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B07: node_modules is pruned (not reported)" {
    printf -- '- TUNE-0270 · vendored noise\n' \
        > "${SCAN_ROOT}/node_modules/pkg/datarim/backlog.md"
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B08: no cross-instance match → exit 0, empty stdout (advisory contract)" {
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B09: a match still exits 0 (advisory contract — never gates /dr-init)" {
    printf -- '- TUNE-0270 · sibling collision\n' \
        >> "${SCAN_ROOT}/Projects/Alpha/datarim/backlog.md"
    run bash "$HELPER" "TUNE-0270" "$SCAN_ROOT" "$SELF"
    [ "$status" -eq 0 ]
}

@test "B10: scope banner (root + file count) is emitted on stderr for transparency" {
    run bash -c "bash '$HELPER' 'TUNE-0270' '$SCAN_ROOT' '$SELF' 2>&1 1>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -iqE "scann?ed|scope|instance"
}

@test "B11: invalid TASK-ID → non-zero exit + stderr error, no scan" {
    run bash "$HELPER" "tune-0270" "$SCAN_ROOT" "$SELF"
    [ "$status" -ne 0 ]
    echo "$output" | grep -iq "invalid"
}

@test "B12: non-directory SCAN-ROOT → non-zero exit + stderr error" {
    run bash "$HELPER" "TUNE-0270" "${SCAN_ROOT}/does-not-exist" "$SELF"
    [ "$status" -ne 0 ]
    echo "$output" | grep -iqE "not (a )?(exist|directory)|does not exist"
}

@test "B13: SELF arg omitted → self instance IS scanned (no exclusion)" {
    printf -- '- TUNE-0270 · own entry, but no self-exclusion requested\n' \
        >> "${SCAN_ROOT}/datarim/backlog.md"
    run bash "$HELPER" "TUNE-0270" "$SCAN_ROOT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "datarim/backlog.md"
}
