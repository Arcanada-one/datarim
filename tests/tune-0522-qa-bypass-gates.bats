#!/usr/bin/env bats
# tune-0522-qa-bypass-gates.bats — TUNE-0522: verify the three QA bypass
# gate scripts exist, work, and are wired into dr-qa.md.
# Usage: bats tests/tune-0522-qa-bypass-gates.bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
GV="$REPO_DIR/dev-tools/check-qa-verdict-blocked.sh"
RS="$REPO_DIR/dev-tools/check-raw-sql-smoke-test.sh"
LE="$REPO_DIR/dev-tools/check-live-evidence.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ===========================================================================
# check-qa-verdict-blocked.sh
# ===========================================================================

@test "G1: check-qa-verdict-blocked exists and is executable" {
    [ -f "$GV" ]
    [ -x "$GV" ]
}

@test "G1: BLOCKED verdict → exit 1" {
    cat > "$TEST_TMP/qa-blocked.md" <<'EOF'
---
verdict: BLOCKED
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-blocked.md"
    [ "$status" -eq 1 ]
}

@test "G1: FAIL verdict → exit 1" {
    cat > "$TEST_TMP/qa-fail.md" <<'EOF'
---
verdict: FAIL
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-fail.md"
    [ "$status" -eq 1 ]
}

@test "G1: ALL_PASS verdict → exit 0" {
    cat > "$TEST_TMP/qa-pass.md" <<'EOF'
---
verdict: ALL_PASS
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-pass.md"
    [ "$status" -eq 0 ]
}

@test "G1: CONDITIONAL_PASS verdict → exit 0" {
    cat > "$TEST_TMP/qa-cond.md" <<'EOF'
---
verdict: CONDITIONAL_PASS
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-cond.md"
    [ "$status" -eq 0 ]
}

@test "G1: missing QA report (legacy task) → exit 0" {
    run bash "$GV" --qa-report "$TEST_TMP/nonexistent.md"
    [ "$status" -eq 0 ]
}

@test "G1: no verdict in frontmatter → exit 0" {
    cat > "$TEST_TMP/qa-no-verdict.md" <<'EOF'
---
title: something
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-no-verdict.md"
    [ "$status" -eq 0 ]
}

@test "G1: --report mode emits BLOCKED message on failure" {
    cat > "$TEST_TMP/qa-blocked2.md" <<'EOF'
---
verdict: BLOCKED
---
...
EOF
    run bash "$GV" --qa-report "$TEST_TMP/qa-blocked2.md" --report
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

# ===========================================================================
# check-raw-sql-smoke-test.sh
# ===========================================================================

@test "G2: check-raw-sql-smoke-test exists and is executable" {
    [ -f "$RS" ]
    [ -x "$RS" ]
}

@test "G2: no raw SQL in diff → exit 0" {
    printf 'console.log("hello")\n' > "$TEST_TMP/diff.txt"
    cat > "$TEST_TMP/qa.md" <<'EOF'
---
title: qa
---
EOF
    run bash "$RS" --diff "$TEST_TMP/diff.txt" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

@test "G2: raw SQL found, smoke test present → exit 0" {
    printf '+  const rows = await prisma.$queryRaw`SELECT 1`\n' > "$TEST_TMP/diff.txt"
    cat > "$TEST_TMP/qa.md" <<'EOF'
## 4d. Live Smoke-Test Gate
```bash
mysql -e "SELECT 1"
row count: 1
```
EOF
    run bash "$RS" --diff "$TEST_TMP/diff.txt" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

@test "G2: raw SQL found, no smoke test → exit 1" {
    printf '+  const rows = await prisma.$queryRaw`SELECT 1`\n' > "$TEST_TMP/diff.txt"
    cat > "$TEST_TMP/qa.md" <<'EOF'
## QA Report
No smoke test here.
EOF
    run bash "$RS" --diff "$TEST_TMP/diff.txt" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 1 ]
}

@test "G2: raw SQL found, no QA report → exit 1" {
    printf '+  db.raw("SELECT 1")\n' > "$TEST_TMP/diff.txt"
    run bash "$RS" --diff "$TEST_TMP/diff.txt" --qa-report "$TEST_TMP/nonexistent.md"
    [ "$status" -eq 1 ]
}

@test "G2: missing diff file → exit 0 (no concern)" {
    run bash "$RS" --diff "$TEST_TMP/nonexistent.txt" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

# ===========================================================================
# check-live-evidence.sh
# ===========================================================================

@test "G3: check-live-evidence exists and is executable" {
    [ -f "$LE" ]
    [ -x "$LE" ]
}

@test "G3: no expectations file → exit 0" {
    cat > "$TEST_TMP/qa.md" <<'EOF'
---
verdict: ALL_PASS
---
EOF
    run bash "$LE" --expectations "$TEST_TMP/nonexistent.md" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

@test "G3: no empirical items → exit 0" {
    cat > "$TEST_TMP/exp.md" <<'EOF'
---
task_id: TEST-1
schema_version: 1
---
## wish-1
evidence_type: static
## wish-2
evidence_type: static
EOF
    cat > "$TEST_TMP/qa.md" <<'EOF'
---
verdict: ALL_PASS
---
EOF
    run bash "$LE" --expectations "$TEST_TMP/exp.md" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

@test "G3: empirical items present, live markers sufficient → exit 0" {
    cat > "$TEST_TMP/exp.md" <<'EOF'
---
task_id: TEST-2
schema_version: 1
---
## wish-1
evidence_type: empirical
EOF
    cat > "$TEST_TMP/qa.md" <<'EOF'
## QA Report
Command and result:
```bash
$ tool --version
v1.2.3
$ tool run
real output here
Exit code: 0
```
EOF
    run bash "$LE" --expectations "$TEST_TMP/exp.md" --qa-report "$TEST_TMP/qa.md"
    [ "$status" -eq 0 ]
}

@test "G3: empirical items present, insufficient markers → exit 1" {
    cat > "$TEST_TMP/exp2.md" <<'EOF'
---
task_id: TEST-3
schema_version: 1
---
## wish-1
evidence_type: empirical
EOF
    cat > "$TEST_TMP/qa2.md" <<'EOF'
## QA Report
All tests passed. Mocked the external call.
EOF
    run bash "$LE" --expectations "$TEST_TMP/exp2.md" --qa-report "$TEST_TMP/qa2.md"
    [ "$status" -eq 1 ]
}

# ===========================================================================
# Wiring: dr-qa.md references the gates
# ===========================================================================

@test "W1: dr-qa.md references check-qa-verdict-blocked.sh" {
    run grep -c "check-qa-verdict-blocked" "$REPO_DIR/commands/dr-qa.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "W2: dr-qa.md references check-raw-sql-smoke-test.sh" {
    run grep -c "check-raw-sql-smoke-test" "$REPO_DIR/commands/dr-qa.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "W3: dr-qa.md references check-live-evidence.sh" {
    run grep -c "check-live-evidence" "$REPO_DIR/commands/dr-qa.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
