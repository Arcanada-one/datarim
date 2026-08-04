#!/usr/bin/env bats

# Test contract: dev-tools/check-dr-auto-reassert-wiring.sh asserts that
# commands/dr-auto.md Step 5 carries an imperative, non-skippable
# pre-dispatch invocation of auto-mode-marker.sh reassert.
#
# Tests:
#   1. lint passes (exit 0) on the wired dr-auto.md
#   2. lint fails (exit 1) on a prose-only fixture
#   3. lint exits 2 on usage / bad args (missing root dir)

LINT="$BATS_TEST_DIRNAME/../dev-tools/check-dr-auto-reassert-wiring.sh"
FRAMEWORK_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
    [ -x "$LINT" ] || skip "check-dr-auto-reassert-wiring.sh not executable: $LINT"

    # Build a scratch area for fixtures.
    # Use the real framework repo as the source (git copy approach, not
    # git archive — git archive strips .git which breaks clone-faithful
    # setup; memory: feedback_ci_replica_git_clone_not_archive).
    FIXTURE_ROOT="$BATS_TEST_TMPDIR/fixture-repo"
    mkdir -p "$FIXTURE_ROOT/commands"

    REAL_DR_AUTO="$FRAMEWORK_ROOT/commands/dr-auto.md"
    [ -f "$REAL_DR_AUTO" ] || skip "commands/dr-auto.md not found at $REAL_DR_AUTO"
    cp "$REAL_DR_AUTO" "$FIXTURE_ROOT/commands/dr-auto.md"
}

# ──────────────────────────────────────────────────────────
# Test 1: lint passes (exit 0) on the real wired dr-auto.md
# ──────────────────────────────────────────────────────────
@test "lint passes (exit 0) on the wired dr-auto.md" {
    run "$LINT" --root "$FRAMEWORK_ROOT"
    [ "$status" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────────
# Test 2: lint fails (exit 1) on a prose-only fixture
#
# Strategy: build a minimal synthetic dr-auto.md that mentions the helper
# invocation only in a purely descriptive context — no MUST/mandatory/
# Before spawning / pre-dispatch cues anywhere within 8 lines of the call.
# This is simpler and more robust than transforming the real wired file,
# which can leave residual cues in surrounding prose.
# ──────────────────────────────────────────────────────────────────────────
@test "lint fails (exit 1) on a prose-only fixture" {
    PROSE_FIXTURE="$BATS_TEST_TMPDIR/prose-fixture-repo"
    mkdir -p "$PROSE_FIXTURE/commands"

    cat > "$PROSE_FIXTURE/commands/dr-auto.md" <<'MDEOF'
---
name: dr-auto
---

# /dr-auto

5. **Dispatch the pipeline as subagents.** For each stage that needs running,
   spawn the matching agent via the Agent tool.
   - **Re-assert the marker before each dispatch.** When spawning a stage
     subagent, re-assert the auto-mode marker (mechanics:
     `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/auto-mode-marker.sh reassert --root <workspace> --task-id <TASK-ID>`).
     This is idempotent.
MDEOF

    run "$LINT" --root "$PROSE_FIXTURE"
    [ "$status" -eq 1 ]
}

# ──────────────────────────────────────────────────────────────────────────
# Test 3: lint exits 2 on usage / bad args (non-existent root dir)
# ──────────────────────────────────────────────────────────────────────────
@test "lint exits 2 on usage / bad args" {
    run "$LINT" --root "/nonexistent-path-that-does-not-exist-for-lint-test"
    [ "$status" -eq 2 ]
}

# ──────────────────────────────────────────────────────────────────────────
# Workflow wiring: the lint must run in a BLOCKING CI job.
#
# The lint's header promises "a deterministic CI lint FAILS (exit 1) the
# moment that call decays back to advisory prose only". It once ran as a
# trailing step of a job carrying `continue-on-error: true`, which made it
# advisory in practice — a red run that blocks nothing. Mirrors the wiring
# assertion precedent in tests/check-dr-auto-cross-runtime.bats.
# ──────────────────────────────────────────────────────────────────────────
@test "wiring: a CI job runs the lint itself, not only this suite" {
    WF="$BATS_TEST_DIRNAME/../.github/workflows/dev-tools-lint.yml"
    [ -f "$WF" ]
    run grep -c 'check-dr-auto-reassert-wiring.sh' "$WF"
    [ "$status" -eq 0 ]
}

@test "wiring: the job invoking the lint carries NO continue-on-error" {
    WF="$BATS_TEST_DIRNAME/../.github/workflows/dev-tools-lint.yml"
    [ -f "$WF" ]
    # Walk every top-level job block; for the block(s) invoking the lint,
    # assert `continue-on-error` never appears — at job level or on any step.
    run python3 - "$WF" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8').read()
# strip full-line YAML comments — prose may legitimately DISCUSS the key
s = '\n'.join(l for l in raw.split('\n') if not l.lstrip().startswith('#'))
jobs = s[s.index('\njobs:\n'):]
# split into job blocks at two-space-indented top-level keys
starts = [m.start() for m in re.finditer(r'\n  [a-zA-Z][a-zA-Z0-9_-]*:\n', jobs)]
starts.append(len(jobs))
blocks = [jobs[starts[i]:starts[i+1]] for i in range(len(starts)-1)]
carrying = [b for b in blocks if 'check-dr-auto-reassert-wiring.sh' in b]
if not carrying:
    sys.exit(2)  # lint not wired into any job at all
sys.exit(1 if any('continue-on-error' in b for b in carrying) else 0)
PY
    [ "$status" -eq 0 ]
}
