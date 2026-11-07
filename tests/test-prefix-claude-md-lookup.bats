#!/usr/bin/env bats
# test-prefix-claude-md-lookup.bats — TUNE-0030
#
# Verifies that datarim-doctor.sh resolves project prefixes by walking up the
# directory tree and parsing `## Task Prefix Registry` sections in AGENTS.md.
# Universal area prefixes resolve from the runtime case-statement; project
# prefixes resolve from the consumer's AGENTS.md; unknown prefixes fall back
# to `general`. Path-traversal and unsafe characters in Archive Subdir are
# rejected.

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"
TEST_SOURCE="$BATS_TEST_DIRNAME/test-prefix-claude-md-lookup.bats"

setup() {
    TMPROOT="$(mktemp -d)" || return 1
    [ -n "$TMPROOT" ] || return 1
    chmod 700 "$TMPROOT" || return 1

    # Resolve the real utility before placing the test-owned wrapper on PATH.
    REAL_DIRNAME="$(command -v dirname)" || return 1
    [ -x "$REAL_DIRNAME" ] || return 1
    DOCTOR_BIN="$TMPROOT/.doctor-bin"
    mkdir -m 700 "$DOCTOR_BIN" || return 1
    cat > "$DOCTOR_BIN/dirname" <<'EOF'
#!/bin/bash
if [ "$#" -eq 1 ] && [ "$1" = "$DOCTOR_FIXTURE_BOUNDARY" ]; then
    printf '/\n'
else
    exec "$DOCTOR_REAL_DIRNAME" "$@"
fi
EOF
    chmod 700 "$DOCTOR_BIN/dirname" || return 1

    if [ "${PREFIX_FIXTURE_CAPTURE_ROOT+x}" = "x" ] && [ -n "$PREFIX_FIXTURE_CAPTURE_ROOT" ]; then
        case "$PREFIX_FIXTURE_CAPTURE_ROOT" in
            /*) ;;
            *) return 1 ;;
        esac
        case "$PREFIX_FIXTURE_CAPTURE_ROOT" in
            "$TMPROOT"|"$TMPROOT"/*) return 1 ;;
        esac
        [ -d "$PREFIX_FIXTURE_CAPTURE_ROOT" ] || return 1
        [ ! -L "$PREFIX_FIXTURE_CAPTURE_ROOT" ] || return 1
        [ -O "$PREFIX_FIXTURE_CAPTURE_ROOT" ] || return 1
        TEST_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)" || return 1
        CAPTURE_PARENT_REAL="$(cd "$PREFIX_FIXTURE_CAPTURE_ROOT" && pwd -P)" || return 1
        case "$CAPTURE_PARENT_REAL" in
            "$TEST_REPO_ROOT"/*) ;;
            *) return 1 ;;
        esac
        if CAPTURE_PARENT_MODE="$(stat -c '%a' "$CAPTURE_PARENT_REAL" 2>/dev/null)"; then
            :
        else
            CAPTURE_PARENT_MODE="$(stat -f '%Lp' "$CAPTURE_PARENT_REAL" 2>/dev/null)" || return 1
        fi
        [ "$CAPTURE_PARENT_MODE" = 700 ] || return 1
        DOCTOR_CAPTURE_ROOT="$(mktemp -d "$CAPTURE_PARENT_REAL/suite388.XXXXXX")" || return 1
        chmod 700 "$DOCTOR_CAPTURE_ROOT" || return 1
        CAPTURE_PARENT="$CAPTURE_PARENT_REAL"
    else
        DOCTOR_CAPTURE_ROOT="$TMPROOT/.doctor-capture"
        mkdir -m 700 "$DOCTOR_CAPTURE_ROOT" || return 1
        CAPTURE_PARENT="$DOCTOR_CAPTURE_ROOT"
    fi
}

teardown() {
    rm -rf "$TMPROOT"
}

# Snapshot lookup candidates only inside the test-owned fixture ancestry. The
# dirname wrapper bounds the production walk at TMPROOT, so parent registries
# are never read. Each child call gets its own retained stdout, stderr, status,
# arguments, lookup paths, and exact copies of present fixture AGENTS.md files.
file_sha256() {
    local output
    if command -v sha256sum >/dev/null 2>&1; then
        output="$(sha256sum "$1")" || return 1
    else
        output="$(shasum -a 256 "$1")" || return 1
    fi
    printf '%s\n' "$output" | cut -d ' ' -f 1 || return 1
}

doctor_call() {
    local call_name="$1"
    shift
    local capture_dir="$DOCTOR_CAPTURE_ROOT/$call_name"
    local manifest="$capture_dir/context.txt"
    local lookup_dir="$PWD" lookup_path lookup_count=0 registry_count=0
    local arg_index=0 arg status registry_hash snapshot_hash
    local doctor_hash test_hash stdout_hash stderr_hash

    mkdir -m 700 "$capture_dir" || return 1
    {
        printf 'fixture_root=%s\n' "$TMPROOT"
        printf 'cwd=%s\n' "$PWD"
        printf 'doctor=%s\n' "$DOCTOR"
        printf 'capture_parent=%s\n' "$CAPTURE_PARENT"
        printf 'capture_root=%s\n' "$DOCTOR_CAPTURE_ROOT"
        for arg in "$@"; do
            printf 'argv[%s]=%s\n' "$arg_index" "$arg"
            arg_index=$((arg_index + 1))
        done
    } > "$manifest" || return 1

    doctor_hash="$(file_sha256 "$DOCTOR")" || return 1
    test_hash="$(file_sha256 "$TEST_SOURCE")" || return 1
    printf 'doctor_sha256=%s\n' "$doctor_hash" >> "$manifest" || return 1
    printf 'test_source_sha256=%s\n' "$test_hash" >> "$manifest" || return 1

    case "$lookup_dir" in
        "$TMPROOT"|"$TMPROOT"/*) ;;
        *) return 1 ;;
    esac
    while [ -n "$lookup_dir" ]; do
        case "$lookup_dir" in
            "$TMPROOT"|"$TMPROOT"/*) ;;
            *) return 1 ;;
        esac
        lookup_count=$((lookup_count + 1))
        lookup_path="$lookup_dir/AGENTS.md"
        if [ -f "$lookup_path" ]; then
            registry_count=$((registry_count + 1))
            registry_hash="$(file_sha256 "$lookup_path")" || return 1
            cp "$lookup_path" "$capture_dir/registry-$registry_count.bytes" || return 1
            snapshot_hash="$(file_sha256 "$capture_dir/registry-$registry_count.bytes")" || return 1
            [ "$registry_hash" = "$snapshot_hash" ] || return 1
            printf 'lookup_registry[%s]=present path=%s snapshot=%s/registry-%s.bytes sha256=%s\n' \
                "$lookup_count" "$lookup_path" "$capture_dir" "$registry_count" "$registry_hash" >> "$manifest" || return 1
        else
            printf 'lookup_registry[%s]=absent path=%s\n' "$lookup_count" "$lookup_path" >> "$manifest" || return 1
        fi
        [ "$lookup_dir" = "$TMPROOT" ] && break
        lookup_dir="$("$REAL_DIRNAME" "$lookup_dir")" || return 1
    done
    printf 'lookup_path_count=%s registry_present_count=%s\n' \
        "$lookup_count" "$registry_count" >> "$manifest" || return 1

    if env PATH="$DOCTOR_BIN:$PATH" \
        DOCTOR_FIXTURE_BOUNDARY="$TMPROOT" \
        DOCTOR_REAL_DIRNAME="$REAL_DIRNAME" \
        "$DOCTOR" "$@" \
        > "$capture_dir/stdout" 2> "$capture_dir/stderr"; then
        status=0
    else
        status=$?
    fi
    printf '%s\n' "$status" > "$capture_dir/status" || return 1
    stdout_hash="$(file_sha256 "$capture_dir/stdout")" || return 1
    stderr_hash="$(file_sha256 "$capture_dir/stderr")" || return 1
    {
        printf 'child_status=%s\n' "$status"
        printf 'stdout_path=%s/stdout sha256=%s\n' "$capture_dir" "$stdout_hash"
        printf 'stderr_path=%s/stderr sha256=%s\n' "$capture_dir" "$stderr_hash"
    } >> "$manifest" || return 1
}

doctor_emit_failure() {
    local call_name="$1"
    local capture_dir="$DOCTOR_CAPTURE_ROOT/$call_name"
    local snapshot
    printf 'Safe owned fixture context for %s:\n' "$call_name" >&2
    cat "$capture_dir/context.txt" >&2 || return 1
    printf 'Captured child status: ' >&2
    cat "$capture_dir/status" >&2 || return 1
    printf 'Captured child stdout:\n' >&2
    cat "$capture_dir/stdout" >&2 || return 1
    printf 'Captured child stderr:\n' >&2
    cat "$capture_dir/stderr" >&2 || return 1
    for snapshot in "$capture_dir"/registry-*.bytes; do
        [ -f "$snapshot" ] || continue
        printf 'Owned registry snapshot %s:\n' "$snapshot" >&2
        cat "$snapshot" >&2 || return 1
    done
}

doctor_assert_result() {
    local call_name="$1" expected_status="$2" expected_stdout="$3"
    local capture_dir="$DOCTOR_CAPTURE_ROOT/$call_name"
    local actual_status actual_stdout
    actual_status="$(cat "$capture_dir/status")" || return 1
    actual_stdout="$(cat "$capture_dir/stdout")" || return 1
    if [ "$actual_status" != "$expected_status" ] || [ "$actual_stdout" != "$expected_stdout" ]; then
        printf 'Expected status=%s stdout=%s; observed status=%s stdout=%s\n' \
            "$expected_status" "$expected_stdout" "$actual_status" "$actual_stdout" >&2
        doctor_emit_failure "$call_name" || return 1
        return 1
    fi
}

doctor_assert_combined_output_contains() {
    local call_name="$1" expected="$2"
    local capture_dir="$DOCTOR_CAPTURE_ROOT/$call_name"
    local actual_stdout actual_stderr
    actual_stdout="$(cat "$capture_dir/stdout")" || return 1
    actual_stderr="$(cat "$capture_dir/stderr")" || return 1
    case "$actual_stdout$actual_stderr" in
        *"$expected"*) ;;
        *)
            printf 'Expected combined child output to contain %s\n' "$expected" >&2
            doctor_emit_failure "$call_name" || return 1
            return 1
            ;;
    esac
}

@test "T-PFX-1 area prefix resolves without AGENTS.md (runtime-owned)" {
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-1 --probe-prefix=INFRA || return 1
    doctor_assert_result T-PFX-1 0 infrastructure || return 1
}

@test "T-PFX-2 unknown prefix in empty tree → general" {
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-2 --probe-prefix=VERD || return 1
    doctor_assert_result T-PFX-2 0 general || return 1
}

@test "T-PFX-3 project prefix resolves from AGENTS.md in cwd" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| ACME | Acme service | acme |
EOF
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-3 --probe-prefix=ACME || return 1
    doctor_assert_result T-PFX-3 0 acme || return 1
}

@test "T-PFX-4 walks up to ancestor AGENTS.md when local has no registry" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Workspace

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| ACME | Acme service | acme |
EOF
    mkdir -p "$TMPROOT/sub/deeper" || return 1
    cd "$TMPROOT/sub/deeper" || return 1
    doctor_call T-PFX-4 --probe-prefix=ACME || return 1
    doctor_assert_result T-PFX-4 0 acme || return 1
}

@test "T-PFX-5 nearer AGENTS.md without prefix → falls through to outer registry" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Workspace

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| OUTER | Outer project | outer |
EOF
    mkdir -p "$TMPROOT/sub" || return 1
    cat > "$TMPROOT/sub/AGENTS.md" <<'EOF' || return 1
# Inner

No registry here.
EOF
    cd "$TMPROOT/sub" || return 1
    doctor_call T-PFX-5 --probe-prefix=OUTER || return 1
    doctor_assert_result T-PFX-5 0 outer || return 1
}

@test "T-PFX-6 path-traversal in Archive Subdir → rejected, falls back to general" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| EVIL | Bad | ../../etc |
EOF
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-6 --probe-prefix=EVIL || return 1
    doctor_assert_result T-PFX-6 0 general || return 1
}

@test "T-PFX-7 spaces / uppercase in Archive Subdir → rejected" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| BADCASE | Bad casing | With Spaces |
EOF
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-7 --probe-prefix=BADCASE || return 1
    doctor_assert_result T-PFX-7 0 general || return 1
}

@test "T-PFX-8 ### heading-level registry also parsed (Project-Specific zone)" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Project

## Project-Specific Configuration

### Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| NESTED | Nested-zone project | nested |
EOF
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-8 --probe-prefix=NESTED || return 1
    doctor_assert_result T-PFX-8 0 nested || return 1
}

@test "T-PFX-9 invalid probe prefix → exit 64" {
    cd "$TMPROOT" || return 1
    doctor_call T-PFX-9 --probe-prefix=lowercase || return 1
    doctor_assert_result T-PFX-9 64 "" || return 1
}

@test "T-PFX-10 area prefix wins over AGENTS.md row of the same name" {
    cat > "$TMPROOT/AGENTS.md" <<'EOF' || return 1
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| INFRA | Trying to override | overridden |
EOF
    cd "$TMPROOT" || return 1
    # Resolution contract is unchanged: the reserved runtime prefix wins.
    # The reserved-prefix follow-up added a WARN naming the ignored row; bats `run` merges
    # stderr into $output, so assert the resolved value on stdout alone.
    doctor_call T-PFX-10-no-warning --probe-prefix=INFRA || return 1
    doctor_assert_result T-PFX-10-no-warning 0 infrastructure || return 1
    doctor_call T-PFX-10-warning --probe-prefix=INFRA || return 1
    doctor_assert_result T-PFX-10-warning 0 infrastructure || return 1
    doctor_assert_combined_output_contains T-PFX-10-warning IGNORED || return 1
}
