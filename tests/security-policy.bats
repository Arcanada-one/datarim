#!/usr/bin/env bats
# ARCA-0099 — check-security-policy.sh contract.
#
# Two orthogonal modes: presence-gate (--check) and YAML schema v1 validation
# (--validate-yaml). Covers happy path, every enum/range/regex rejection, and
# the auxiliary --help / --version surfaces.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-security-policy.sh"
    F="$REPO_ROOT/tests/fixtures/security-policy"
}

# --- Presence-gate (--check) ----------------------------------------------

@test "check: passes on repo with SECURITY.md (datarim repo itself)" {
    run "$SCRIPT" --check --repo "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "check: defaults --repo to current working directory" {
    cd "$REPO_ROOT"
    run "$SCRIPT" --check
    [ "$status" -eq 0 ]
}

@test "check: fails on directory without SECURITY.md" {
    empty="$(mktemp -d)"
    run "$SCRIPT" --check --repo "$empty"
    [ "$status" -eq 1 ]
    rmdir "$empty"
}

@test "check: exits 2 when --repo path is not a directory" {
    run "$SCRIPT" --check --repo "/nonexistent-path-arca0099"
    [ "$status" -eq 2 ]
}

@test "check: exits 2 on unknown sub-flag" {
    run "$SCRIPT" --check --bogus
    [ "$status" -eq 2 ]
}

# --- YAML schema validation (--validate-yaml) -----------------------------

@test "validate-yaml: accepts a valid fixture" {
    run "$SCRIPT" --validate-yaml "$F/valid.yml"
    [ "$status" -eq 0 ]
}

@test "validate-yaml: rejects re_review > last_review + 90d" {
    run "$SCRIPT" --validate-yaml "$F/over90d.yml"
    [ "$status" -eq 1 ]
}

@test "validate-yaml: rejects reason shorter than 20 non-whitespace chars" {
    run "$SCRIPT" --validate-yaml "$F/short-reason.yml"
    [ "$status" -eq 1 ]
}

@test "validate-yaml: rejects severity outside the enum" {
    run "$SCRIPT" --validate-yaml "$F/bad-severity.yml"
    [ "$status" -eq 1 ]
}

@test "validate-yaml: exits 3 when file does not exist" {
    run "$SCRIPT" --validate-yaml "/nonexistent/accepted-risk.yml"
    [ "$status" -eq 3 ]
}

@test "validate-yaml: exits 2 when path argument is missing" {
    run "$SCRIPT" --validate-yaml
    [ "$status" -eq 2 ]
}

# --- Auxiliary surfaces ---------------------------------------------------

@test "help: --help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"check-security-policy.sh"* ]]
    [[ "$output" == *"--check"* ]]
    [[ "$output" == *"--validate-yaml"* ]]
}

@test "version: --version prints script version and exits 0" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"check-security-policy.sh"* ]]
}

@test "usage: bare invocation exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "usage: unknown subcommand exits 2" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}
