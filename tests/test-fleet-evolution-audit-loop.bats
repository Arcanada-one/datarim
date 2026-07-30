#!/usr/bin/env bats
# tests/test-fleet-evolution-audit-loop.bats — evolution-loop integration for a
# redis:// (non-filesystem) source: the loop must dispatch the audit-log adapter
# instead of rejecting the URL through its filesystem-existence gate.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOOP="$REPO/plugins/dr-fleet-evolution/evolution-loop.sh"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — loop requires jq"
    fi

    SKILLDIR="$TMP/l1-basic"
    mkdir -p "$SKILLDIR"
    cat > "$SKILLDIR/SKILL.md" <<'EOF'
---
name: fleet-l1-basic
metadata:
  fleet_level: 1
  context_budget_tokens: 200
---
# Fleet L1 — Basic
Execute the task in one step.
EOF

    # Mock redis client (PONG + EVAL flatten of two audit entries).
    MOCK="$TMP/redis-cli-mock.sh"
    cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in
        ping|PING) echo "PONG"; exit 0 ;;
        eval|EVAL) cat "$REDIS_MOCK_DATA" 2>/dev/null; exit 0 ;;
    esac
done
exit 0
EOF
    chmod +x "$MOCK"
    DATA="$TMP/audit-data.tsv"
    printf '%s\n' \
"1700000000000-0	type=audit	task_id=DEMO-0001	reason=clean run	outcome=success" \
"1700000000001-0	type=agent-killed	task_id=DEMO-0002	reason=killed" \
        > "$DATA"

    export REDIS_CLI_BIN="$MOCK"
    export REDIS_MOCK_DATA="$DATA"

    # Minimal coworker mock (write copies a small valid skill; ask scores).
    CW="$TMP/coworker-mock.sh"
    cat > "$CW" <<'EOF'
#!/usr/bin/env bash
cmd=$1; shift; target=""; prev=""
for a in "$@"; do case "$prev" in --target) target=$a ;; esac; prev=$a; done
if [ "$cmd" = "write" ]; then
    cat > "$target" <<'SKILL'
---
name: fleet-l1-basic
metadata:
  context_budget_tokens: 200
---
# Fleet L1 — Basic (evolved)
One step only.
SKILL
elif [ "$cmd" = "ask" ]; then echo "0.8"; fi
EOF
    chmod +x "$CW"
    export COWORKER_BIN="$CW"
}

@test "loop dispatches a redis:// source (does not reject it as a missing path)" {
    local conf="$TMP/audit.conf"
    printf 'adapters/audit-log-adapter.sh|redis://127.0.0.1:6379|audit-log\n' > "$conf"
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$conf" --threshold 1 --candidates 1 --dry-run
    [ "$status" -eq 0 ]
    # the redis:// source must NOT be skipped as "missing"
    ! echo "$output" | grep -q "source path missing"
    # the two mock audit entries were collected
    echo "$output" | grep -qE "collected [1-9]"
}

@test "loop expands the whitelisted DR_ORCH_REDIS_URL in a source-path" {
    local conf="$TMP/env.conf"
    printf 'adapters/audit-log-adapter.sh|${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}|audit-log\n' > "$conf"
    DR_ORCH_REDIS_URL="redis://127.0.0.1:6379" run "$LOOP" \
        --skill "$SKILLDIR" --adapters-conf "$conf" --threshold 1 --candidates 1 --dry-run
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "source path missing"
    echo "$output" | grep -qE "collected [1-9]"
}
