#!/usr/bin/env bats
#
# tune-0210-playwright-detection.bats — F4 detection-chain regression.
#
# Covers dev-tools/detect-playwright-tooling.sh resolution chain
# CLI → MCP → env-browser → none, with --require, --json, --headed,
# DATARIM_PLAYWRIGHT override, headed-strict + no-display semantics.
#
# Tests use DATARIM_TEST_MOCK=1 to gate the script onto a stub PATH so
# real `playwright`, `claude`, or browser binaries on the host system do
# NOT interfere with deterministic resolution.

script="$BATS_TEST_DIRNAME/../dev-tools/detect-playwright-tooling.sh"

setup() {
    # Isolated stub PATH per test.
    stub_path="$(mktemp -d)"

    # Default: empty stub PATH; tests opt-in to specific stubs.
    export DATARIM_TEST_MOCK=1
    export DATARIM_TEST_MOCK_PATH="$stub_path"
    # Force-clear any host env-browser candidates so tests are deterministic.
    unset BROWSER PLAYWRIGHT_BROWSER_PATH CHROME_PATH DATARIM_PLAYWRIGHT DATARIM_PLAYWRIGHT_MCP_AVAILABLE
    # DISPLAY is preserved for headed-state tests that need it; reset per-test.
    unset DISPLAY
}

teardown() {
    rm -rf "$stub_path"
}

# write_stub <name> <version-string>
#   Drops a bash stub on $stub_path; calling `--version` prints <version-string>.
write_stub() {
    local name="$1" ver="$2"
    cat >"$stub_path/$name" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
    echo "$ver"
    exit 0
fi
exit 0
EOF
    chmod +x "$stub_path/$name"
}

# -----------------------------------------------------------------------------
# Tier 1 — Resolution chain (≥5 cases per V-AC-12)
# -----------------------------------------------------------------------------

@test "P1 CLI present → resolves to playwright-cli (exit 0)" {
    write_stub playwright "Version 1.48.0"
    write_stub claude "0.6.0"   # also present — CLI must win the precedence

    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "playwright-cli" ]
}

@test "P2 CLI absent, MCP available → resolves to playwright-mcp (exit 0)" {
    # No `playwright` stub — chain must fall through to MCP.
    export DATARIM_PLAYWRIGHT_MCP_AVAILABLE=1

    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "playwright-mcp" ]
}

@test "P3 CLI + MCP absent, BROWSER points at executable → resolves to env-browser (exit 0)" {
    write_stub chromium "Chromium 130.0"
    export BROWSER="$stub_path/chromium"

    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "env-browser" ]
}

@test "P4 no tool resolves, no --require → stdout 'none' (exit 0)" {
    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "P5 no tool resolves, --require set → stdout 'none' (exit 1)" {
    run "$script" --require
    [ "$status" -eq 1 ]
    [ "$output" = "none" ]
}

# -----------------------------------------------------------------------------
# Tier 2 — Override + json + headed semantics
# -----------------------------------------------------------------------------

@test "P6 DATARIM_PLAYWRIGHT override short-circuits the chain" {
    export DATARIM_PLAYWRIGHT=playwright-cli   # set override, no CLI stub present
    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "playwright-cli" ]
}

@test "P7 invalid DATARIM_PLAYWRIGHT override → usage error (exit 2)" {
    export DATARIM_PLAYWRIGHT=banana
    run "$script"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "invalid DATARIM_PLAYWRIGHT" ]]
}

@test "P8 --json emits JSON with tool, headed, display fields" {
    write_stub playwright "Version 1.48.0"
    export DISPLAY=":0"
    run "$script" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"tool":"playwright-cli"'* ]]
    [[ "$output" == *'"headed":"headless"'* ]]
    [[ "$output" == *'"display":true'* ]]
}

@test "P9 --headed records headed=headed in JSON when DISPLAY present" {
    write_stub playwright "Version 1.48.0"
    export DISPLAY=":0"
    run "$script" --headed --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"headed":"headed"'* ]]
    [[ "$output" == *'"display":true'* ]]
}

@test "P10 --headed-strict + no DISPLAY → exit 2 (display required)" {
    write_stub playwright "Version 1.48.0"
    unset DISPLAY
    run "$script" --headed-strict
    [ "$status" -eq 2 ]
    [[ "$output" =~ "DISPLAY" ]]
}

@test "P11 --headed (lenient) + no DISPLAY → finding + falls through (exit 0)" {
    write_stub playwright "Version 1.48.0"
    unset DISPLAY
    run "$script" --headed --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"headed":"headless"'* ]]
    [[ "$output" == *'"display":false'* ]]
    [[ "$output" == *'"finding":"headed-requested-but-no-display"'* ]]
}

@test "P12 --help prints usage and exits 0" {
    run "$script" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "playwright-cli" ]]
}

@test "P13 --version prints version and exits 0" {
    run "$script" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "detect-playwright-tooling" ]]
}

@test "P14 BROWSER pointing at non-executable path is rejected (falls to next chain step)" {
    # File exists but is not chmod +x → MUST be ignored.
    echo "not executable" > "$stub_path/fake-browser"
    export BROWSER="$stub_path/fake-browser"
    run "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]   # CLI/MCP absent, BROWSER rejected → none
}

@test "P15 path-traversal guard on BROWSER (../ rejected)" {
    export BROWSER="$stub_path/../../../bin/sh"
    run "$script"
    [ "$status" -eq 0 ]
    # Refuses the candidate and falls through; no crash, no traversal.
    [ "$output" = "none" ]
}
