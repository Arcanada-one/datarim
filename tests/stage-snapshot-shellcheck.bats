#!/usr/bin/env bats
#
# TUNE-0254 — shellcheck gate for snapshot-writer.sh + check-stage-snapshot-on-exit.sh.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

@test "shellcheck -S warning clean on snapshot-writer.sh and validator" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck -S warning \
        "${REPO_ROOT}/scripts/lib/snapshot-writer.sh" \
        "${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"
    [ "$status" -eq 0 ]
}
