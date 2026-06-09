#!/usr/bin/env bats
# tests/test-fleet-evolution-loop.bats — evolution loop (mock coworker, dry-run).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOOP="$REPO/plugins/dr-fleet-evolution/evolution-loop.sh"
    FIX="$REPO/tests/fixtures/fleet-evolution"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — loop requires jq"
    fi

    # A skill dir under test (copy of a real starter into TMP so we never
    # mutate the shipped skill).
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
Execute the task in one step. Stop and report a level-mismatch if it needs more.
EOF

    # Adapters conf pointing at the fixtures (absolute paths).
    CONF="$TMP/adapters.conf"
    cat > "$CONF" <<EOF
adapters/archive-adapter.sh|$FIX/archive|archive
adapters/dr-dream-adapter.sh|$FIX/dr-dream|dr-dream
EOF

    # Mock coworker: `write` copies the source skill (valid candidate);
    # `ask` prints a score.
    MOCK="$TMP/coworker-mock.sh"
    cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
cmd=$1; shift
target=""; score="0.80"
prev=""
for a in "$@"; do
    case "$prev" in --target) target=$a ;; esac
    prev=$a
done
if [ "$cmd" = "write" ]; then
    # emit a small valid English skill within budget
    cat > "$target" <<'SKILL'
---
name: fleet-l1-basic
metadata:
  fleet_level: 1
  context_budget_tokens: 200
---
# Fleet L1 — Basic (evolved)
Execute the task in one step. If it needs analysis, stop and report level-mismatch.
SKILL
elif [ "$cmd" = "ask" ]; then
    echo "$score"
fi
EOF
    chmod +x "$MOCK"
    export COWORKER_BIN="$MOCK"
}

@test "evolution-loop.sh is executable" {
    [ -x "$LOOP" ]
}

@test "loop exits 2 without --skill" {
    run "$LOOP"
    [ "$status" -eq 2 ]
}

@test "loop skips (exit 0) when dataset below threshold" {
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 999 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "below threshold"
}

@test "loop dry-run collects signals, passes gates, applies best candidate" {
    run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 2 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "collected"
    echo "$output" | grep -q "selected best candidate"
    echo "$output" | grep -q "dry-run"
    # the evolved marker landed in the skill copy (no real git push happened)
    grep -q "evolved" "$SKILLDIR/SKILL.md"
}

@test "loop passes the eval dataset with a .txt extension (coworker file-type policy)" {
    # coworker rejects non-text extensions (.jsonl) in --context with exit 6.
    # This mock records the --context args so we can assert the extension.
    RECMOCK="$TMP/coworker-rec.sh"
    cat > "$RECMOCK" <<'EOF'
#!/usr/bin/env bash
cmd=$1; shift
target=""; prev=""; ctx=""
collect=0
for a in "$@"; do
    case "$a" in --context) collect=1; prev=$a; continue ;; esac
    case "$a" in --*) collect=0 ;; esac
    [ "$collect" = 1 ] && ctx="$ctx $a"
    case "$prev" in --target) target=$a ;; esac
    prev=$a
done
if [ "$cmd" = "write" ]; then
    echo "$ctx" >> "$CTX_LOG"
    cat > "$target" <<'SKILL'
---
name: fleet-l1-basic
metadata:
  context_budget_tokens: 200
---
# Fleet L1 — Basic (evolved)
One step only.
SKILL
elif [ "$cmd" = "ask" ]; then echo "0.7"; fi
EOF
    chmod +x "$RECMOCK"
    export CTX_LOG="$TMP/ctx.log"
    : > "$CTX_LOG"
    COWORKER_BIN="$RECMOCK" run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 1 --dry-run
    [ "$status" -eq 0 ]
    # the dataset path passed to --context must NOT end in .jsonl
    ! grep -qE '\.jsonl( |$)' "$CTX_LOG"
    # and it must include a .txt dataset
    grep -qE '\.txt( |$)' "$CTX_LOG"
}

@test "loop exits 1 when all candidates fail the gates" {
    # Mock that emits an over-budget, Cyrillic candidate (fails gates).
    BADMOCK="$TMP/coworker-bad.sh"
    cat > "$BADMOCK" <<'EOF'
#!/usr/bin/env bash
cmd=$1; shift
target=""; prev=""
for a in "$@"; do case "$prev" in --target) target=$a ;; esac; prev=$a; done
if [ "$cmd" = "write" ]; then
    printf -- '---\nmetadata:\n  context_budget_tokens: 5\n---\nЭто кириллица превышает бюджет много раз подряд тут текст.\n' > "$target"
elif [ "$cmd" = "ask" ]; then echo "0.9"; fi
EOF
    chmod +x "$BADMOCK"
    COWORKER_BIN="$BADMOCK" run "$LOOP" --skill "$SKILLDIR" --adapters-conf "$CONF" --threshold 1 --candidates 2 --dry-run
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no candidate passed"
}
