#!/usr/bin/env bats
#
# Contract test for dev-tools/check-deferral-prose.sh — the anti-deferral
# prose scanner. A deferral-tell phrase about a TOUCHED file with no traceable
# legitimate-deferral artefact must BLOCK (exit 1); the same phrase about an
# UNTOUCHED file, a clean report, or a phrase next to a verified artefact must
# PASS (exit 0). merge-base-unavailable must fail-open-with-warning.
#
# Maps to PRD V-AC-1 (block), V-AC-2 (clean + foreign-scope pass),
# V-AC-3 (touched + verified artefact pass), V-AC-10 (merge-base fallback warns).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-deferral-prose.sh"
    WORK="$(mktemp -d)"
    REPORT="$WORK/qa-report.md"
    TOUCHED="$WORK/touched.txt"
    BACKLOG="$WORK/backlog.md"
    TASKS="$WORK/tasks.md"
    # touched-file set: agent edited runbook.md and a compose file
    cat > "$TOUCHED" <<'EOF'
spaces/aether/runbook.md
docker-compose.yml
EOF
    # KB with one real follow-up ID + one blocked_by-referable task
    cat > "$BACKLOG" <<'EOF'
- FAKE-9001 · pending · P3 · L1 · Re-verify container count after 7-day prod soak (time-dependent) → tasks/FAKE-9001-task-description.md
EOF
    cat > "$TASKS" <<'EOF'
- FAKE-9002 · blocked · P2 · L2 · Upstream lib fix [blocked_by: FAKE-9003] → tasks/FAKE-9002-task-description.md
EOF
}

teardown() {
    rm -rf "$WORK"
}

# ---------- V-AC-1: self-inflicted deferral on a touched file → BLOCK ----------

@test "BLOCK: deferral phrase about a touched file with no artefact" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The stale counter in spaces/aether/runbook.md is informational, not a blocker,
out of scope for this task. Will fix later.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runbook.md"* ]]
}

# ---------- V-AC-2: clean report + foreign-scope declaration → PASS ----------

@test "PASS: clean report with no deferral-tell phrases" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
All wishes met. Fix implemented, tested, and committed to origin.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 0 ]
}

@test "PASS: deferral phrase about an UNTOUCHED (foreign) file" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The legacy billing migration is out of scope for this task — see services/billing/migrate.ts.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 0 ]
}

# ---------- V-AC-3: touched file + verified legitimate artefact → PASS ----------

@test "PASS: touched-file deferral citing a real FU-ID present in backlog" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The container count in spaces/aether/runbook.md needs re-verification after a
7-day prod soak — deferred to follow-up FAKE-9001 (time-dependent).
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED" --backlog "$BACKLOG" --tasks "$TASKS"
    [ "$status" -eq 0 ]
}

@test "PASS: touched-file deferral citing a real blocked_by reference" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The change in docker-compose.yml is out of scope until upstream lands —
blocked_by: FAKE-9002.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED" --backlog "$BACKLOG" --tasks "$TASKS"
    [ "$status" -eq 0 ]
}

@test "BLOCK: touched-file deferral citing a NON-existent FU-ID" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The stale counter in spaces/aether/runbook.md is cosmetic, deferred to FAKE-7777.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED" --backlog "$BACKLOG" --tasks "$TASKS"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runbook.md"* ]]
}

# ---------- V-AC-10: merge-base unavailable → warn + fail-open ----------

@test "WARN+PASS: no --touched-files and git probe yields nothing → advisory, never false-block" {
    # No --touched-files, run outside any useful git context: scanner must NOT
    # hard-block on its own inability to compute the touched set.
    cat > "$REPORT" <<'EOF'
## Layer 3b
The stale counter is informational, out of scope.
EOF
    run env GIT_DIR=/nonexistent "$SCRIPT" --file "$REPORT" --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"merge-base unavailable"* ]] || [[ "$output" == *"touched-file set empty"* ]]
}

# ---------- usage / shape guards ----------

@test "usage: missing --file → exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "usage: path-traversal --file → exit 2" {
    run "$SCRIPT" --file "../../etc/passwd"
    [ "$status" -eq 2 ]
}
