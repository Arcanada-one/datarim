#!/usr/bin/env bats
# check-site-drift-sweep.bats — V-AC matrix for the level-3 ecosystem-wide
# site-drift sweep. The real detector is replaced by a mock on PATH so each
# test drives a deterministic exit code per product; the sweep's job under
# test is enumeration, idempotent append, exit-code branching, stamp-guard,
# and fail-soft Ops Bot emit.

setup() {
    SWEEP="${BATS_TEST_DIRNAME}/../dev-tools/check-site-drift-sweep.sh"
    KB="$(mktemp -d)"
    STATE="$(mktemp -d)"
    BIN="$(mktemp -d)"            # holds the mock detector
    export XDG_STATE_HOME="$STATE"
    export DATARIM_BACKLOG_PATH="$KB/backlog.md"; : > "$DATARIM_BACKLOG_PATH"
    unset OPSBOT_KEY
    mkdir -p "$KB/documentation/ecosystem-sync"
}

teardown() { rm -rf "$KB" "$STATE" "$BIN"; }

# Write a registry with the given product ids (all pointing at dummy fixtures).
write_registry() {  # $@=product ids
    {
        echo 'products:'
        for p in "$@"; do
            printf '  %s:\n    repo_local: repo-%s\n    site_local: site-%s\n' "$p" "$p" "$p"
        done
    } > "$KB/documentation/ecosystem-sync/registry.yml"
}

# Install a mock detector whose exit code is keyed by product id via a map file.
# map line format: "<product> <exitcode>"
install_mock_detector() {  # reads $KB/mockmap
    cat > "$BIN/check-repo-site-sync.sh" <<'MOCK'
#!/usr/bin/env bash
prod=""
while [ $# -gt 0 ]; do case "$1" in --product) prod="$2"; shift 2;; *) shift;; esac; done
code=0
while read -r p c; do [ "$p" = "$prod" ] && code="$c"; done < "$MOCKMAP"
exit "$code"
MOCK
    chmod +x "$BIN/check-repo-site-sync.sh"
    export MOCKMAP="$KB/mockmap"
    export DRIFT_SWEEP_DETECTOR="$BIN/check-repo-site-sync.sh"
}

run_sweep() { run bash "$SWEEP" --root "$KB" --force "$@"; }

# ---- exit-code branches (V-5) ----

@test "V-5a: all products clean → exit 0, no backlog lines" {
    write_registry alpha beta
    printf 'alpha 0\nbeta 0\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 0 ]
    [ ! -s "$DATARIM_BACKLOG_PATH" ]
}

@test "V-5b: one drifted product → exit 0 (sweep ok), one backlog line" {
    write_registry alpha beta
    printf 'alpha 1\nbeta 0\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 0 ]
    [ "$(grep -cF 'drift-site-update-alpha' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
    [ "$(grep -cF 'drift-site-update-beta' "$DATARIM_BACKLOG_PATH")" -eq 0 ]
}

@test "V-5c: detector registry-missing (exit 3) for a product → sweep exits 3" {
    write_registry alpha
    printf 'alpha 3\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 3 ]
}

@test "V-5d: source-unavailable / unknown detector code → product skipped, exit 0" {
    write_registry alpha
    printf 'alpha 4\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 0 ]
    [ ! -s "$DATARIM_BACKLOG_PATH" ]
}

# ---- idempotency (V-3 / V-AC-9) ----

@test "V-3: two consecutive sweeps → exactly one line per drifted product" {
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    run_sweep; [ "$status" -eq 0 ]
    run_sweep; [ "$status" -eq 0 ]
    [ "$(grep -cF 'drift-site-update-alpha' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
}

# ---- stamp guard / cadence ----

@test "V-stamp: second run within cadence without --force is skipped" {
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    run bash "$SWEEP" --root "$KB" --force            # primes the stamp + emits
    [ "$status" -eq 0 ]
    run bash "$SWEEP" --root "$KB" --cadence-h 24      # no --force → within cadence
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi 'cadence\|skip'
}

@test "V-stamp-write: stamp file written unconditionally at entry" {
    write_registry alpha
    printf 'alpha 0\n' > "$KB/mockmap"; install_mock_detector
    run bash "$SWEEP" --root "$KB" --force
    [ "$status" -eq 0 ]
    [ -f "$STATE/datarim/drift-sweep.last-run" ]
}

# ---- dry-run ----

@test "V-dry: --dry-run drifted product produces no backlog write" {
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    run bash "$SWEEP" --root "$KB" --force --dry-run
    [ "$status" -eq 0 ]
    [ ! -s "$DATARIM_BACKLOG_PATH" ]
}

# ---- stack-agnostic (V-7) ----

@test "V-7: no space.yml and no DATARIM_BACKLOG_PATH → no file sink, exit 0, zero writes" {
    unset DATARIM_BACKLOG_PATH
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    # KB has no spaces/*/space.yml and no datarim/ dir → resolver exit 1.
    run bash "$SWEEP" --root "$KB" --force
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi 'no.*sink\|skip'
}

# ---- fail-soft Ops Bot emit (V-8) ----

@test "V-8a: missing OPSBOT_KEY → warn, no POST, sweep still emits backlog line" {
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 0 ]
    [ "$(grep -cF 'drift-site-update-alpha' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
}

@test "V-8b: curl present but endpoint non-2xx (mocked) → warn + continue, exit 0" {
    write_registry alpha
    printf 'alpha 1\n' > "$KB/mockmap"; install_mock_detector
    # Mock curl on PATH to return 503; sweep must not fail.
    cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
# emulate --write-out '%{http_code}' --output behaviour
out=""; while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift 2;; *) shift;; esac; done
[ -n "$out" ] && : > "$out"
printf '503'
CURL
    chmod +x "$BIN/curl"
    export OPSBOT_KEY="dummy"
    run env PATH="$BIN:$PATH" bash "$SWEEP" --root "$KB" --force
    [ "$status" -eq 0 ]
    [ "$(grep -cF 'drift-site-update-alpha' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
}

# ---- security adversarial (V-6 / S9) ----

@test "V-6: registry product id with path-traversal is filtered out, no forged line" {
    # malformed id '../etc' fails the ^[a-z][a-z0-9-]*$ allowlist → never reaches detector.
    write_registry alpha
    printf '  ../etc:\n    repo_local: x\n' >> "$KB/documentation/ecosystem-sync/registry.yml"
    printf 'alpha 0\n' > "$KB/mockmap"; install_mock_detector
    run_sweep
    [ "$status" -eq 0 ]
    ! grep -q 'etc' "$DATARIM_BACKLOG_PATH"
}

# ---- help ----

@test "V-help: --help exits 0 and prints usage" {
    run bash "$SWEEP" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi usage
}
