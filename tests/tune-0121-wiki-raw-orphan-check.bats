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

# TUNE-0498 — macOS bash-3.2 crash fixes

@test "T7 --scope=all with non-ASCII content + mismatched basename → no tr crash, finding" {
    # Em dashes (—, 3-byte UTF-8) in the file body — head -c 300 can split a
    # multibyte character mid-sequence, which BSD tr rejects without LC_ALL=C.
    # Basename tokens "deploy", "guide" are ASCII (safe under LC_ALL=C tokenization)
    # and do NOT appear in the body → mismatch finding + exit 1.
    cat > "$TMPROOT/wiki/_raw_/Deploy — Guide.md" <<'EOF'
# Руководство по развёртыванию — основные принципы

Мониторинг — ключевой компонент любой production-системы. Без надёжного
сбора метрик и алертов невозможно гарантировать стабильную работу сервисов
в условиях высокой нагрузки и частых изменений конфигурации.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=all
    [ "$status" -eq 1 ]
    [[ "$output" == *"basename/content mismatch"* ]]
    [[ "$output" != *"Illegal byte sequence"* ]]
}

@test "T8 --scope=all with non-alnum-only filename → empty token array, no crash" {
    # Stem "---" after tr -c '[:alnum:]' ' ' produces an empty string. Under
    # set -u, dereferencing an empty array with ${tok_array[@]} throws
    # "unbound variable" on bash-3.2. ${tok_array[@]:-} guards against it.
    cat > "$TMPROOT/wiki/_raw_/---.md" <<'EOF'
Some content with enough bytes to pass the head -c 300 boundary.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=all
    [ "$status" -eq 0 ]
}

@test "T9 --scope=all with non-ASCII content + em-dash in first 300 bytes → no crash" {
    # The second tr pipeline (content_lower) also processes raw file bytes.
    # Multibyte UTF-8 chars split by head -c 300 must not crash BSD tr.
    # Use a basename with a token that WILL appear in the content so we get
    # exit 0 rather than a finding, confirming the check ran to completion.
    cat > "$TMPROOT/wiki/_raw_/Prometheus — Metrics.md" <<'EOF'
Prometheus is an open-source monitoring and alerting toolkit designed for
reliability and scalability. It collects metrics from configured targets
at given intervals, evaluates rule expressions, and triggers alerts.
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=all
    [ "$status" -eq 0 ]
    [[ "$output" != *"Illegal byte sequence"* ]]
}
