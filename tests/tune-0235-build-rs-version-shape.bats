#!/usr/bin/env bats
# tune-0235-build-rs-version-shape.bats — build-rs-version.rs template shape guards.

TEMPLATE="$BATS_TEST_DIRNAME/../templates/build-rs-version.rs"

# ---------- T1 template exists, no vergen dependency ----------

@test "T1 build-rs-version.rs exists and does not use the vergen crate" {
    [ -f "$TEMPLATE" ]
    ! grep -q 'vergen::' "$TEMPLATE"
}

# ---------- T2 fallback preserves the [0-9a-f]{7} regex shape ----------

@test "T2 fallback literal is a 7-char lowercase-hex-shaped placeholder" {
    grep -q '"0000000"' "$TEMPLATE"
    fallback=$(grep -o '"0000000"' "$TEMPLATE" | head -1 | tr -d '"')
    [ "${#fallback}" -eq 7 ]
    [[ "$fallback" =~ ^[0-9a-f]{7}$ ]]
}

# ---------- T3 rerun-if-changed directives present for .git/HEAD and refs/heads ----------

@test "T3 emits cargo:rerun-if-changed for .git/HEAD and .git/refs/heads" {
    grep -q 'cargo:rerun-if-changed=../../.git/HEAD' "$TEMPLATE"
    grep -q 'cargo:rerun-if-changed=../../.git/refs/heads' "$TEMPLATE"
}

# ---------- T4 sets ARCANA_GIT_SHA via rustc-env ----------

@test "T4 sets ARCANA_GIT_SHA via cargo:rustc-env" {
    grep -q 'cargo:rustc-env=ARCANA_GIT_SHA=' "$TEMPLATE"
}

# ---------- T5 no unwrap/expect (workspace-lint friendly) ----------

@test "T5 no unwrap/expect calls (workspace-lint friendly)" {
    ! grep -qE '\.unwrap\(\)|\.expect\(' "$TEMPLATE"
}
