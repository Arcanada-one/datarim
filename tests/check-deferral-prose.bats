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

# ---------- fenced-block / blockquote exclusion: a QUOTED detection-target
# phrase is not self-deferral. A report ABOUT the anti-deferral gate inevitably
# quotes the tell-phrases next to the gate's own touched filenames; those quotes
# must not BLOCK. The same phrase as live prose still BLOCKs. ----------

@test "PASS: deferral phrase inside a fenced code block is a quote, not self-deferral" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
The gate output below is a sample, not a live claim about my own work:

```
spaces/aether/runbook.md:5: "informational" on touched file 'runbook.md'
out of scope, not a blocker, will fix later
```

All wishes met; nothing deferred.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 0 ]
}

@test "PASS: deferral phrase inside a blockquote is a quote, not self-deferral" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
Quoting the original incident for context:

> The stale counter in spaces/aether/runbook.md is informational, not a blocker,
> out of scope for this task. Will fix later.

That pattern is exactly what this gate now blocks. All my own wishes are met.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 0 ]
}

@test "BLOCK: live-prose deferral still blocks even when the report also quotes phrases in a fence" {
    cat > "$REPORT" <<'EOF'
## Layer 3b
Sample gate output for reference:

```
out of scope, not a blocker
```

But really, the stale counter in spaces/aether/runbook.md is informational and
out of scope for this task — I will fix it later.
EOF
    run "$SCRIPT" --file "$REPORT" --touched-files "$TOUCHED"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runbook.md"* ]]
}

# ---------- dual-repo: --extra-repo augments the touched-set from a nested
# repository. For a framework (TUNE-*) task the workflow-state report lives in
# the outer workspace repo while the touched code lives in a separate nested
# repo (code/datarim/.git). Without --extra-repo the scanner fail-opens from the
# outer root and the gate is a no-op for that class; --extra-repo teaches it the
# nested repo's touched-set so a genuine self-deferral on framework code BLOCKs.
# ----------

@test "dual-repo: --extra-repo adds nested-repo touched files so a self-deferral on framework code BLOCKs" {
    NESTED="$WORK/nested"
    mkdir -p "$NESTED"
    git -C "$NESTED" init -q
    git -C "$NESTED" config user.email t@t.t
    git -C "$NESTED" config user.name t
    echo "base" > "$NESTED/scanner.sh"
    git -C "$NESTED" add scanner.sh
    git -C "$NESTED" commit -qm base
    # Realistic dual-repo topology: origin/main exists (fetched) and the feature
    # branch is ahead by one touched commit, so merge-base..HEAD resolves the set.
    git -C "$NESTED" update-ref refs/remotes/origin/main HEAD
    echo "changed" >> "$NESTED/scanner.sh"
    git -C "$NESTED" commit -qam change
    # report (outer repo) defers a self-inflicted gap in the nested file scanner.sh
    cat > "$REPORT" <<'EOF'
## Layer 3b
The edge case in scanner.sh is informational, not a blocker, out of scope — will fix later.
EOF
    # Without --touched-files; outer root has no useful diff. Pass the nested set explicitly.
    NESTED_TOUCHED="$WORK/nested-touched.txt"
    echo "scanner.sh" > "$NESTED_TOUCHED"
    run "$SCRIPT" --file "$REPORT" --touched-files "$NESTED_TOUCHED"
    [ "$status" -eq 1 ]
    [[ "$output" == *"scanner.sh"* ]]
    # Now via --extra-repo (auto-derive nested touched-set), no explicit list:
    run "$SCRIPT" --file "$REPORT" --root "$WORK" --extra-repo "$NESTED"
    [ "$status" -eq 1 ]
    [[ "$output" == *"scanner.sh"* ]]
}

@test "dual-repo: --extra-repo with a clean nested set does not false-block a quoted phrase" {
    NESTED="$WORK/nested2"
    mkdir -p "$NESTED"
    git -C "$NESTED" init -q
    git -C "$NESTED" config user.email t@t.t
    git -C "$NESTED" config user.name t
    echo "base" > "$NESTED/other.sh"
    git -C "$NESTED" add other.sh
    git -C "$NESTED" commit -qm base
    # report mentions a file NOT touched in the nested repo → foreign scope → PASS
    cat > "$REPORT" <<'EOF'
## Layer 3b
The legacy module unrelated.sh is out of scope for this task. All my own wishes met.
EOF
    run "$SCRIPT" --file "$REPORT" --root "$WORK" --extra-repo "$NESTED"
    [ "$status" -eq 0 ]
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

# ---------- AC-1..AC-2: space-in-path + traversal guard (TUNE-0446) ----------

@test "AC-1: --file with a space in the path is NOT rejected with exit 2 (spaces accepted)" {
    # Create a file whose path contains a space — the guard must not reject it
    # with exit 2 for the space alone. The file exists, so the scanner proceeds
    # to scan it (exit 0 on clean content or exit 1 on findings, never exit 2).
    SPACE_DIR="$WORK/Long Term Memory"
    mkdir -p "$SPACE_DIR"
    SPACE_REPORT="$SPACE_DIR/report.md"
    cat > "$SPACE_REPORT" <<'EOF'
## QA Report
All wishes met. Fix committed and tested.
EOF
    run "$SCRIPT" --file "$SPACE_REPORT" --touched-files "$TOUCHED"
    # Must NOT be a usage error (exit 2). Exit 0 or 1 are both acceptable.
    [ "$status" -ne 2 ]
}

@test "AC-2a: --file with a .. traversal segment is STILL rejected with exit 2" {
    run "$SCRIPT" --file "../some/report.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"traversal"* || "$output" == *"ERROR"* ]]
}

@test "AC-2b: --file with an embedded .. segment is STILL rejected with exit 2" {
    run "$SCRIPT" --file "a/../../etc/report.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"traversal"* || "$output" == *"ERROR"* ]]
}

@test "AC-2c: --file with a control character is STILL rejected with exit 2" {
    # Pass a path containing a literal tab character.
    TAB_PATH="$(printf 'some\treport.md')"
    run "$SCRIPT" --file "$TAB_PATH"
    [ "$status" -eq 2 ]
    [[ "$output" == *"control"* || "$output" == *"ERROR"* ]]
}
