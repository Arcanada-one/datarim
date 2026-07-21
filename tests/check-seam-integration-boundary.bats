#!/usr/bin/env bats
#
# Contract test for dev-tools/check-seam-integration-boundary.sh — the plan-time
# seam-vs-integration scope-boundary advisory scanner (TUNE-0239).
#
# A backlog one-liner that mixes a seam/contract concern with an
# integration/call-site concern must FLAG (advisory on stdout; exit 3 under
# --strict). A single-concern one-liner (seam only, or integration only) and a
# neutral one-liner must PASS (exit 0, no advisory). --task must resolve the
# one-liner from a backlog index. Usage guards must exit 2.
#
# Maps to task-description AC-1 (bats green), AC-2 (mixed → advisory + strict
# exit 3), AC-3 (single concern → PASS exit 0).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-seam-integration-boundary.sh"
    WORK="$(mktemp -d)"
    BACKLOG="$WORK/datarim/backlog.md"
    mkdir -p "$WORK/datarim"
    # Synthetic backlog: one mixed one-liner, one single-concern one-liner.
    cat > "$BACKLOG" <<'EOF'
- FAKE-0001 · pending · P2 · L3 · Agent loop core — formalize the TurnOutcome state machine + Tool trait / ToolDispatcher seam in arcana-core, and wire --max-cost / --max-turns CLI flags into CostTracker → tasks/FAKE-0001-task-description.md
- FAKE-0002 · pending · P2 · L3 · Formalize the TurnOutcome state machine and Tool trait seam in arcana-core (foundation only) → tasks/FAKE-0002-task-description.md
EOF
}

teardown() {
    rm -rf "$WORK"
}

# ---------- AC-2: mixed seam + integration one-liner → FLAG ----------

@test "FLAG: --line mixing a seam concern with an integration concern emits an advisory" {
    run "$SCRIPT" --line "define a Tool trait seam in arcana-core and wire it into the CLI"
    [ "$status" -eq 0 ]                       # advisory never blocks by default
    [[ "$output" == *"ADVISORY"* ]]
    [[ "$output" == *"seam+integration"* ]]
}

@test "FLAG+strict: mixed one-liner exits 3 under --strict" {
    run "$SCRIPT" --strict --line "formalize the ToolDispatcher seam, then wire --max-cost CLI flags end-to-end"
    [ "$status" -eq 3 ]
    [[ "$output" == *"ADVISORY"* ]]
}

@test "FLAG+report: mixed one-liner lists matched signal tokens per class" {
    run "$SCRIPT" --report --line "add a Tool trait seam and wire it into the CLI call site"
    [ "$status" -eq 0 ]
    [[ "$output" == *"seam signals:"* ]]
    [[ "$output" == *"integration signals:"* ]]
}

# ---------- AC-3: single-concern one-liners → PASS ----------

@test "PASS: seam-only one-liner (no integration signal)" {
    run "$SCRIPT" --strict --line "Formalize the TurnOutcome state machine and Tool trait seam in arcana-core"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"ADVISORY"* ]]
}

@test "PASS: integration-only one-liner (no seam signal)" {
    run "$SCRIPT" --strict --line "Wire the existing CostTracker into the CLI --max-cost flag end-to-end"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"ADVISORY"* ]]
}

@test "PASS: neutral one-liner with neither concern signal" {
    run "$SCRIPT" --strict --line "Fix the typo in the landing page hero copy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# ---------- --task mode: resolve the one-liner from a backlog index ----------

@test "FLAG: --task resolves a mixed one-liner from the backlog and flags it" {
    run "$SCRIPT" --task FAKE-0001 --backlog "$BACKLOG" --strict
    [ "$status" -eq 3 ]
    [[ "$output" == *"ADVISORY"* ]]
}

@test "PASS: --task resolves a single-concern one-liner from the backlog" {
    run "$SCRIPT" --task FAKE-0002 --backlog "$BACKLOG" --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "--task with default backlog path under --root resolves" {
    run "$SCRIPT" --task FAKE-0001 --root "$WORK" --strict
    [ "$status" -eq 3 ]
    [[ "$output" == *"ADVISORY"* ]]
}

# ---------- usage / shape guards ----------

@test "usage: no --line and no --task → exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "usage: --line and --task together → exit 2" {
    run "$SCRIPT" --line "x" --task FAKE-0001 --backlog "$BACKLOG"
    [ "$status" -eq 2 ]
}

@test "usage: --task with a malformed ID → exit 2" {
    run "$SCRIPT" --task not-an-id --backlog "$BACKLOG"
    [ "$status" -eq 2 ]
}

@test "usage: --task for an ID absent from the backlog → exit 2" {
    run "$SCRIPT" --task FAKE-9999 --backlog "$BACKLOG"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no backlog one-liner"* ]]
}

@test "usage: --task with a missing backlog file → exit 2" {
    run "$SCRIPT" --task FAKE-0001 --backlog "$WORK/nope.md"
    [ "$status" -eq 2 ]
}
