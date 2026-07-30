#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."

@test "/dr-init owns runtime-qualified baseline capture" {
  grep -qF '${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/capture-framework-version-baseline.sh' "$ROOT/commands/dr-init.md"
}

@test "/dr-do unconditionally runs the runtime-qualified checker as a hard transition" {
  grep -qF '${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-framework-version-accountability.sh' "$ROOT/commands/dr-do.md" \
    && grep -qF 'exit 1 or exit 2' "$ROOT/commands/dr-do.md" \
    && grep -qF 'route to `/dr-do`' "$ROOT/commands/dr-do.md"
}

@test "/dr-qa independently runs the same checker and blocks PASS routes" {
  grep -qF '${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-framework-version-accountability.sh' "$ROOT/commands/dr-qa.md" \
    && grep -qF 'overall QA result is **FAIL**' "$ROOT/commands/dr-qa.md" \
    && grep -qF 'route to `/dr-do`' "$ROOT/commands/dr-qa.md"
}

@test "existing /dr-do spec graph self-verification and network gates remain" {
  grep -qF 'AUTOMATIC SPEC-GRAPH EVIDENCE CHECK' "$ROOT/commands/dr-do.md" \
    && grep -qF 'NETWORK EXPOSURE PRE-COMMIT GATE' "$ROOT/commands/dr-do.md" \
    && grep -qF 'automatic self-verification hook for this stage' "$ROOT/commands/dr-do.md"
}

@test "existing QA expectations anti-deferral and test gates remain" {
  grep -qF 'Layer 3b: Expectations Verification' "$ROOT/commands/dr-qa.md" \
    && grep -qF 'Anti-deferral prose scan' "$ROOT/commands/dr-qa.md" \
    && grep -qF '### 4a. Tests' "$ROOT/commands/dr-qa.md"
}

@test "new wiring contains no prohibited network or release command" {
  ! sed -n '/FRAMEWORK VERSION ACCOUNTABILITY/,/^[0-9].*\*\*/p' "$ROOT/commands/dr-do.md" "$ROOT/commands/dr-qa.md" \
    | grep -Eq 'git (push|fetch|tag)|gh release|deploy\.sh'
}
