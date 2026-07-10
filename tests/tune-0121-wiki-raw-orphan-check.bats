#!/usr/bin/env bats
# tune-0121-wiki-raw-orphan-check.bats — TUNE-0121 regression.
#
# /dr-doctor semantic orphan-content check for wiki/_raw_/: flags a file whose
# basename shares no token with its first ~300 bytes of content (Class A
# proposal, reflection-RESEARCH-0003 Proposal 2, approved 2026-05-07).

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim" "$TMPROOT/wiki/_raw_"
}

teardown() {
    rm -rf "$TMPROOT"
}

@test "T1 matching basename/content → no finding, exit 0" {
    cat > "$TMPROOT/wiki/_raw_/AGENTMEMORY — PERSISTENT MEMORY.md" <<'EOF'
# AgentMemory — Persistent Memory for AI Coding Agents

AgentMemory is a benchmark suite for evaluating long-term memory systems in AI
coding agents across real-world tasks.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T2 mismatched basename/content → finding + exit 1" {
    cat > "$TMPROOT/wiki/_raw_/DEV-1315 project notes.md" <<'EOF'
## Методология BMAD и Agile

BMAD is a multi-agent framework with 12+ specialized personas covering
planning, architecture, development, and QA phases.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DEV-1315 project notes.md"* ]]
    [[ "$output" == *"basename/content mismatch"* ]]
}

@test "T3 basename with no token >=4 chars → inconclusive, no finding" {
    cat > "$TMPROOT/wiki/_raw_/a1 b2.md" <<'EOF'
Some unrelated content about anything at all.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T4 no wiki/_raw_/ directory → no-op, exit 0" {
    rm -rf "$TMPROOT/wiki"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T5 empty wiki/_raw_/ directory → no-op, exit 0" {
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T6 --fix does not touch wiki/_raw_ (advisory-only, report survives fix)" {
    cat > "$TMPROOT/wiki/_raw_/DEV-1315 project notes.md" <<'EOF'
## Методология BMAD и Agile
BMAD is a multi-agent framework.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ -f "$TMPROOT/wiki/_raw_/DEV-1315 project notes.md" ]
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
}
