#!/usr/bin/env bats
# dr-init-topic-overlap.bats — base bats spec for the Step 2.5b advisory detector.
# Covers PRD acceptance cases (a) overlap surfaced, (b) orthogonal not flagged,
# (c) RU+EN mixed extraction works. AC-6 (non-blocking exit 0) is asserted in
# every case via [ "$status" -eq 0 ].

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-topic-overlap.py"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/topic-overlap/backlog-with-overlap.md"

@test "(a) overlap advisory: pending item surfaced for related description" {
    run python3 "$SCRIPT" --task-description - --backlog "$FIXTURE" <<< \
        "fb playwright publishing helper for MCP sandbox"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TST-0001"* ]]
    [[ "$output" == *"matched:"* ]]
}

@test "(b) orthogonal description produces no matches and exit 0" {
    run python3 "$SCRIPT" --task-description - --backlog "$FIXTURE" <<< \
        "quantum lattice TLS cipher suite migration roadmap"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "(c) RU+EN mixed description still extracts stems and surfaces overlap" {
    run python3 "$SCRIPT" --task-description - --backlog "$FIXTURE" <<< \
        "Реализация output-guard middleware для observability — middleware валидация контента"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TST-0003"* ]]
}

@test "(d) TUNE-0207: /dev/fd process-substitution backlog path is accepted (not silently empty)" {
    # Regression: Path.is_file() returned False for /dev/fd/N (pipe-backed symlink),
    # making <(...) backlog args silently produce no output. exists() fixes it.
    run python3 "$SCRIPT" --task-description - \
        --backlog <(printf -- '- TUNE-0999 · pending · P3 · L1 · process substitution path handling script fixture\n') <<< \
        "process substitution path handling script fixture test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0999"* ]]
    [[ "$output" == *"matched:"* ]]
}
