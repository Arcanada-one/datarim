#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup() {
    D5_OWN_CLONE="${D5_OWN_CLONE:-$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)}"
    D5_CAPTURE_DIR="${D5_CAPTURE_DIR:-$BATS_FILE_TMPDIR/capture}"
    if [[ ! -e "$D5_CAPTURE_DIR" ]]; then
        (umask 077 && mkdir -m 700 -p -- "$D5_CAPTURE_DIR")
    fi
    SCRIPT="$D5_OWN_CLONE/dev-tools/hash-cli-inputs.py"
    MANIFEST_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$MANIFEST_ROOT"
}

cli_at_root() {
    local root="$1"
    shift
    if [[ -n "${D5_CAPTURE_HELPER:-}" ]]; then
        "$D5_CAPTURE_HELPER" \
            --cwd "$D5_OWN_CLONE" \
            --source "$SCRIPT" \
            --test "$D5_OWN_CLONE/tests/cli-input-manifest.bats" \
            --fixture "$BATS_TEST_TMPDIR" \
            -- "$SCRIPT" --root "$root" "$@"
    else
        "$SCRIPT" --root "$root" "$@"
    fi
}

cli() {
    cli_at_root "$MANIFEST_ROOT" "$@"
}

cli_without_nonblock() {
    local root="$1" relative_path="$2"
    local case_dir="$BATS_TEST_TMPDIR/nonblock-unavailable"
    local hook_dir="$case_dir/hook"
    local marker="$case_dir/os-open-count"
    mkdir -m 700 "$case_dir" || return
    mkdir -m 700 "$hook_dir" || return
    cat > "$hook_dir/sitecustomize.py" <<'PY'
import atexit
import os

marker = os.environ.pop("D5_NONBLOCK_OPEN_COUNT")
real_open = os.open
open_count = 0

def counted_open(*args, **kwargs):
    global open_count
    open_count += 1
    return real_open(*args, **kwargs)

os.open = counted_open
if hasattr(os, "O_NONBLOCK"):
    del os.O_NONBLOCK

def write_open_count():
    fd = real_open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="ascii") as stream:
        stream.write(str(open_count) + "\n")

atexit.register(write_open_count)
PY
    if [[ -n "${D5_CAPTURE_HELPER:-}" ]]; then
        "$D5_CAPTURE_HELPER" \
            --cwd "$D5_OWN_CLONE" \
            --source "$SCRIPT" \
            --test "$D5_OWN_CLONE/tests/cli-input-manifest.bats" \
            --fixture "$BATS_TEST_TMPDIR" \
            -- env "PYTHONPATH=$hook_dir" "D5_NONBLOCK_OPEN_COUNT=$marker" \
            "$SCRIPT" --root "$root" --file "$relative_path"
    else
        env "PYTHONPATH=$hook_dir" "D5_NONBLOCK_OPEN_COUNT=$marker" \
            "$SCRIPT" --root "$root" --file "$relative_path"
    fi
}

assert_refused() {
    [ "$status" -eq 2 ] \
        && printf '%s\n' "$output" | python3 -c 'import json,sys; lines=sys.stdin.read().splitlines(); rows=[json.loads(line) for line in lines if line.startswith("{")]; assert len(rows)==1; d=rows[0]; assert list(d)==["schema","result","exit_code","diagnostic_codes","file_count","file_count_status","files"]; assert d=={"schema":"DatarimCliInputManifest/v1","result":"INPUT_REFUSED","exit_code":2,"diagnostic_codes":["INPUT_MANIFEST_REFUSED"],"file_count":None,"file_count_status":"NOT_MEASURED","files":[]}; assert "INPUT_MANIFEST_REFUSED" in lines' \
        && [[ "$output" != *"$MANIFEST_ROOT"* ]] \
        && [[ "$output" != *"/etc/passwd"* ]]
}

assert_complete_rows() {
    local expected="$1"
    [ "$status" -eq 0 ] \
        && printf '%s\n' "$output" | python3 -c 'import json,sys; lines=sys.stdin.read().splitlines(); rows=[json.loads(line) for line in lines if line.startswith("{")]; assert len(rows)==1 and len(lines)==1; d=rows[0]; assert list(d)==["schema","result","exit_code","diagnostic_codes","file_count","file_count_status","files"]; assert d["schema"]=="DatarimCliInputManifest/v1" and d["result"]=="COMPLETE" and d["exit_code"]==0 and d["diagnostic_codes"]==[] and d["file_count"]==len(d["files"]) and d["file_count_status"]=="MEASURED"; assert d["files"]==json.loads(sys.argv[1])' "$expected"
}

@test "empty and known abc files produce exact byte counts and SHA-256 rows in sorted order" {
    : > "$MANIFEST_ROOT/z-empty"
    printf 'abc' > "$MANIFEST_ROOT/a-abc"
    run cli --file z-empty --file a-abc
    assert_complete_rows '[{"relative_path":"a-abc","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","byte_count":3},{"relative_path":"z-empty","sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","byte_count":0}]'
}

@test "refuses before any filesystem open when O_NONBLOCK is unavailable" {
    local marker="$BATS_TEST_TMPDIR/nonblock-unavailable/os-open-count"
    printf 'abc' > "$MANIFEST_ROOT/input"
    run cli_without_nonblock "$MANIFEST_ROOT" input
    assert_refused \
        && [ -f "$marker" ] \
        && [ "$(cat "$marker")" = "0" ]
}

@test "a present O_NONBLOCK flag still hashes a regular file from its opened bytes" {
    printf 'abc' > "$MANIFEST_ROOT/input"
    run cli --file input
    assert_complete_rows '[{"relative_path":"input","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","byte_count":3}]'
}

@test "printable Unicode and shell-looking filename remain literal and inert" {
    local literal="$MANIFEST_ROOT/Ω \$(touch manifest-canary).txt"
    [ ! -e "$D5_OWN_CLONE/manifest-canary" ] \
        && python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"literal")' "$literal" \
        && run cli --file "Ω \$(touch manifest-canary).txt" \
        && assert_complete_rows '[{"relative_path":"Ω $(touch manifest-canary).txt","sha256":"829f8d848b44fa3098194754af5b60e2fb1517b0195956841beb6cac9bc68067","byte_count":7}]' \
        && [ ! -e "$D5_OWN_CLONE/manifest-canary" ]
}

@test "rejects traversal path" {
    run cli --file ../outside
    assert_refused
}

@test "rejects absolute file path without opening it" {
    run cli --file /etc/passwd
    assert_refused
}

@test "rejects duplicate selected path" {
    printf 'x' > "$MANIFEST_ROOT/a"
    run cli --file a --file a
    assert_refused
}

@test "rejects symlink root" {
    local root_link="$BATS_TEST_TMPDIR/root-link"
    ln -s "$MANIFEST_ROOT" "$root_link"
    run cli_at_root "$root_link" --file anything
    [ "$status" -eq 2 ] \
        && printf '%s\n' "$output" | python3 -c 'import json,sys; lines=sys.stdin.read().splitlines(); d=next(json.loads(x) for x in lines if x.startswith("{")); assert d["result"]=="INPUT_REFUSED" and d["files"]==[] and d["file_count"] is None' \
        && [[ "$output" != *"$root_link"* ]]
}

@test "rejects symlink intermediate directory" {
    mkdir "$MANIFEST_ROOT/real"
    printf 'x' > "$MANIFEST_ROOT/real/file"
    ln -s "$MANIFEST_ROOT/real" "$MANIFEST_ROOT/link"
    run cli --file link/file
    assert_refused
}

@test "rejects symlink final file" {
    printf 'x' > "$MANIFEST_ROOT/real-file"
    ln -s "$MANIFEST_ROOT/real-file" "$MANIFEST_ROOT/link-file"
    run cli --file link-file
    assert_refused
}

@test "rejects missing file with no partial entries" {
    printf 'x' > "$MANIFEST_ROOT/present"
    run cli --file present --file missing
    assert_refused
}

@test "rejects a directory selected as a file" {
    mkdir "$MANIFEST_ROOT/not-regular"
    run cli --file not-regular
    assert_refused
}

@test "rejects a file above the per-file limit" {
    python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"x" * (1024*1024+1))' "$MANIFEST_ROOT/large"
    run cli --file large
    assert_refused
}

@test "rejects aggregate bytes above the total limit" {
    python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b"x" * (8*1024*1024)); pathlib.Path(sys.argv[2]).write_bytes(b"y" * (8*1024*1024)); pathlib.Path(sys.argv[3]).write_bytes(b"z")' "$MANIFEST_ROOT/a" "$MANIFEST_ROOT/b" "$MANIFEST_ROOT/c"
    run cli --file a --file b --file c
    assert_refused
}

@test "rejects more than the selected-file count limit" {
    local args=() i
    for ((i = 0; i < 65; i++)); do
        : > "$MANIFEST_ROOT/file-$i"
        args+=(--file "file-$i")
    done
    run cli "${args[@]}"
    assert_refused
}
