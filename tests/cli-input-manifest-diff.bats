#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup() {
    REPO="${D5_OWN_CLONE:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
    CLI="$REPO/dev-tools/compare-cli-input-manifests.py"
    TEST_FILE="$REPO/tests/cli-input-manifest-diff.bats"
    BEFORE="$BATS_TEST_TMPDIR/before.json"
    AFTER="$BATS_TEST_TMPDIR/after.json"
    BASE_BEFORE="$BATS_TEST_TMPDIR/retained-before.json"
    BASE_AFTER="$BATS_TEST_TMPDIR/retained-after.json"

    if [[ -n "${D5_BEFORE_SPECIMEN:-}" && -n "${D5_AFTER_SPECIMEN:-}" ]]; then
        cp -- "$D5_BEFORE_SPECIMEN" "$BASE_BEFORE"
        cp -- "$D5_AFTER_SPECIMEN" "$BASE_AFTER"
    else
        printf '%s\n' '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":2,"file_count_status":"MEASURED","files":[{"relative_path":"a-abc","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","byte_count":3},{"relative_path":"z-empty","sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","byte_count":0}]}' > "$BASE_BEFORE"
        printf '%s\n' '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"Ω $(touch manifest-canary).txt","sha256":"829f8d848b44fa3098194754af5b60e2fb1517b0195956841beb6cac9bc68067","byte_count":7}]}' > "$BASE_AFTER"
    fi

    cp -- "$BASE_BEFORE" "$BEFORE"
    cp -- "$BASE_AFTER" "$AFTER"
}

write_case() {
    python3 - "$BASE_BEFORE" "$BASE_AFTER" "$BEFORE" "$AFTER" "$1" <<'PY'
import copy
import json
import pathlib
import sys

base_before, base_after, before_path, after_path = map(pathlib.Path, sys.argv[1:5])
case = sys.argv[5]
before_raw = base_before.read_bytes()
after_raw = base_after.read_bytes()
before = json.loads(before_raw)
after = json.loads(after_raw)

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n", encoding="utf-8")

def row(path, digest="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", size=3):
    return {"relative_path": path, "sha256": digest, "byte_count": size}

if case == "retained-specimens":
    after_path.write_bytes(after_raw)
    before_path.write_bytes(before_raw)
elif case == "unchanged-reordered":
    after = copy.deepcopy(before)
    after["files"].reverse()
    dump(before_path, before)
    dump(after_path, after)
elif case == "mixed-change":
    after = copy.deepcopy(before)
    rows = {entry["relative_path"]: entry for entry in after["files"]}
    rows["a-abc"].update(sha256="f" * 64, byte_count=4)
    rows["z-empty"]["byte_count"] = 1
    rows["Ω $(touch manifest-canary).txt"] = json.loads(after_raw)["files"][0]
    after["files"] = [rows["Ω $(touch manifest-canary).txt"], rows["z-empty"], rows["a-abc"]]
    after["file_count"] = len(after["files"])
    dump(before_path, before)
    dump(after_path, after)
elif case == "size-only":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["byte_count"] = 4
    dump(before_path, before)
    dump(after_path, after)
elif case == "digest-only":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["sha256"] = "0" * 64
    dump(before_path, before)
    dump(after_path, after)
elif case == "refused-producer":
    after = {"schema": "DatarimCliInputManifest/v1", "result": "INPUT_REFUSED", "exit_code": 2,
             "diagnostic_codes": ["INPUT_MANIFEST_REFUSED"], "file_count": None,
             "file_count_status": "NOT_MEASURED", "files": []}
    dump(before_path, before)
    dump(after_path, after)
elif case == "duplicate-json-key":
    dump(before_path, before)
    after_path.write_text('{"schema":"DatarimCliInputManifest/v1","schema":"DatarimCliInputManifest/v1"}\n', encoding="utf-8")
elif case == "duplicate-path":
    after = copy.deepcopy(before)
    after["files"].append(copy.deepcopy(after["files"][0]))
    after["file_count"] = len(after["files"])
    dump(before_path, before)
    dump(after_path, after)
elif case == "boolean-size":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["byte_count"] = True
    dump(before_path, before)
    dump(after_path, after)
elif case == "integral-decimal":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["byte_count"] = 3.0
    dump(before_path, before)
    dump(after_path, after)
elif case == "fractional-decimal":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["byte_count"] = 3.5
    dump(before_path, before)
    dump(after_path, after)
elif case == "file-overflow":
    after = copy.deepcopy(before)
    next(entry for entry in after["files"] if entry["relative_path"] == "a-abc")["byte_count"] = 1024 * 1024 + 1
    dump(before_path, before)
    dump(after_path, after)
elif case == "total-overflow":
    after = copy.deepcopy(before)
    after["files"] = [row(f"file-{index:02d}", "a" * 64, 1024 * 1024) for index in range(17)]
    after["file_count"] = len(after["files"])
    dump(before_path, before)
    dump(after_path, after)
elif case == "count-overflow":
    after = copy.deepcopy(before)
    after["files"] = [row(f"file-{index:02d}") for index in range(65)]
    after["file_count"] = len(after["files"])
    dump(before_path, before)
    dump(after_path, after)
elif case == "traversal":
    after = copy.deepcopy(before)
    after["files"][0]["relative_path"] = "../escape"
    dump(before_path, before)
    dump(after_path, after)
elif case == "absolute-path":
    after = copy.deepcopy(before)
    after["files"][0]["relative_path"] = "/tmp/declared"
    dump(before_path, before)
    dump(after_path, after)
elif case == "empty-component":
    after = copy.deepcopy(before)
    after["files"][0]["relative_path"] = "a//b"
    dump(before_path, before)
    dump(after_path, after)
elif case == "uppercase-digest":
    after = copy.deepcopy(before)
    after["files"][0]["sha256"] = "A" * 64
    dump(before_path, before)
    dump(after_path, after)
elif case == "nonfinite":
    dump(before_path, before)
    after_path.write_text(after_raw.decode("utf-8").replace('"byte_count":7', '"byte_count":NaN', 1), encoding="utf-8")
elif case == "invalid-utf8":
    dump(before_path, before)
    after_path.write_bytes(b"\xff\n")
elif case == "oversized-input":
    dump(before_path, before)
    after_path.write_bytes(b" " * (2 * 1024 * 1024 + 1))
elif case == "hostile-literal":
    after = copy.deepcopy(before)
    after["files"].append(json.loads(after_raw)["files"][0])
    after["file_count"] = len(after["files"])
    dump(before_path, before)
    dump(after_path, after)
elif case == "unknown-top-level":
    after = copy.deepcopy(before)
    after["future_metadata"] = {"format_note": "ignored"}
    dump(before_path, before)
    dump(after_path, after)
elif case == "empty-files":
    after = copy.deepcopy(before)
    after["files"] = []
    after["file_count"] = 0
    dump(before_path, before)
    dump(after_path, after)
elif case == "extra-entry-field":
    after = copy.deepcopy(before)
    after["files"][0]["extra"] = "ignored?"
    dump(before_path, before)
    dump(after_path, after)
else:
    raise SystemExit("unknown synthetic fixture case")
PY
}

cli() {
    if [[ -n "${D5_CAPTURE_HELPER:-}" && -n "${D5_CAPTURE_DIR:-}" ]]; then
        "$D5_CAPTURE_HELPER" \
            --cwd "$REPO" \
            --source "$CLI" \
            --test "$TEST_FILE" \
            --fixture "$BATS_TEST_TMPDIR" \
            -- "$CLI" --before "$BEFORE" --after "$AFTER"
    else
        "$CLI" --before "$BEFORE" --after "$AFTER"
    fi
}

assert_exact() {
    local expected="$1"
    printf '%s\n' "$output" | EXPECTED="$expected" python3 -c 'import json,os,sys; got=json.loads(sys.stdin.read()); expected=json.loads(os.environ["EXPECTED"]); keys={"schema","result","exit_code","diagnostic_codes","added_count","removed_count","modified_count","counts_status","changes"}; assert isinstance(got,dict) and len(got)==9 and set(got)==keys and got==expected'
}

assert_unchanged() {
    [ "$status" -eq 0 ] \
        && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"UNCHANGED","exit_code":0,"diagnostic_codes":[],"added_count":0,"removed_count":0,"modified_count":0,"counts_status":"MEASURED","changes":[]}'
}

assert_refused() {
    [ "$status" -eq 2 ] \
        && [ "$stderr" = "INPUT_MANIFEST_DIFF_REFUSED" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"INPUT_REFUSED","exit_code":2,"diagnostic_codes":["INPUT_MANIFEST_DIFF_REFUSED"],"added_count":null,"removed_count":null,"modified_count":null,"counts_status":"NOT_MEASURED","changes":[]}'
}

@test "retained complete specimens compare declared paths without reopening producer inputs" {
    write_case retained-specimens
    run --separate-stderr cli
    [ "$status" -eq 1 ] \
        && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":1,"removed_count":2,"modified_count":0,"counts_status":"MEASURED","changes":[{"relative_path":"a-abc","change":"REMOVED","before_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","after_sha256":null,"before_byte_count":3,"after_byte_count":null},{"relative_path":"z-empty","change":"REMOVED","before_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","after_sha256":null,"before_byte_count":0,"after_byte_count":null},{"relative_path":"Ω $(touch manifest-canary).txt","change":"ADDED","before_sha256":null,"after_sha256":"829f8d848b44fa3098194754af5b60e2fb1517b0195956841beb6cac9bc68067","before_byte_count":null,"after_byte_count":7}]}'
}

@test "entry ordering alone does not change a manifest" {
    write_case unchanged-reordered
    run --separate-stderr cli
    assert_unchanged
}

@test "diff output sorts additions and recognizes digest and size changes" {
    write_case mixed-change
    run --separate-stderr cli
    [ "$status" -eq 1 ] \
        && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":1,"removed_count":0,"modified_count":2,"counts_status":"MEASURED","changes":[{"relative_path":"a-abc","change":"MODIFIED","before_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","after_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","before_byte_count":3,"after_byte_count":4},{"relative_path":"z-empty","change":"MODIFIED","before_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","after_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","before_byte_count":0,"after_byte_count":1},{"relative_path":"Ω $(touch manifest-canary).txt","change":"ADDED","before_sha256":null,"after_sha256":"829f8d848b44fa3098194754af5b60e2fb1517b0195956841beb6cac9bc68067","before_byte_count":null,"after_byte_count":7}]}'
}

@test "byte count change alone is modified" {
    write_case size-only
    run --separate-stderr cli
    [ "$status" -eq 1 ] && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":0,"removed_count":0,"modified_count":1,"counts_status":"MEASURED","changes":[{"relative_path":"a-abc","change":"MODIFIED","before_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","after_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","before_byte_count":3,"after_byte_count":4}]}'
}

@test "digest change alone is modified" {
    write_case digest-only
    run --separate-stderr cli
    [ "$status" -eq 1 ] && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":0,"removed_count":0,"modified_count":1,"counts_status":"MEASURED","changes":[{"relative_path":"a-abc","change":"MODIFIED","before_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","after_sha256":"0000000000000000000000000000000000000000000000000000000000000000","before_byte_count":3,"after_byte_count":3}]}'
}

@test "a refused producer inventory is unavailable and never treated as empty" {
    write_case refused-producer
    run --separate-stderr cli
    assert_refused
}

@test "duplicate JSON keys are refused" {
    write_case duplicate-json-key
    run --separate-stderr cli
    assert_refused
}

@test "duplicate relative paths are refused" {
    write_case duplicate-path
    run --separate-stderr cli
    assert_refused
}

@test "boolean byte counts are not integers" {
    write_case boolean-size
    run --separate-stderr cli
    assert_refused
}

@test "exact integral decimal byte counts are accepted" {
    write_case integral-decimal
    run --separate-stderr cli
    assert_unchanged
}

@test "fractional decimal byte counts are refused" {
    write_case fractional-decimal
    run --separate-stderr cli
    assert_refused
}

@test "per-file byte count overflow is refused" {
    write_case file-overflow
    run --separate-stderr cli
    assert_refused
}

@test "aggregate byte count overflow is refused" {
    write_case total-overflow
    run --separate-stderr cli
    assert_refused
}

@test "file count overflow is refused" {
    write_case count-overflow
    run --separate-stderr cli
    assert_refused
}

@test "traversal paths are refused without echoing the input" {
    write_case traversal
    run --separate-stderr cli
    assert_refused
}

@test "absolute paths are refused" {
    write_case absolute-path
    run --separate-stderr cli
    assert_refused
}

@test "empty path components are refused" {
    write_case empty-component
    run --separate-stderr cli
    assert_refused
}

@test "uppercase digests are refused" {
    write_case uppercase-digest
    run --separate-stderr cli
    assert_refused
}

@test "non-finite JSON numbers are refused" {
    write_case nonfinite
    run --separate-stderr cli
    assert_refused
}

@test "invalid UTF-8 is refused" {
    write_case invalid-utf8
    run --separate-stderr cli
    assert_refused
}

@test "input byte limit is enforced with one detection byte" {
    write_case oversized-input
    run --separate-stderr cli
    assert_refused
}

@test "hostile-looking declared path is escaped data and never executed" {
    write_case hostile-literal
    [ ! -e "$REPO/manifest-canary" ] \
        && run --separate-stderr cli \
        && [ "$status" -eq 1 ] \
        && [ -z "$stderr" ] \
        && [ ! -e "$REPO/manifest-canary" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":1,"removed_count":0,"modified_count":0,"counts_status":"MEASURED","changes":[{"relative_path":"Ω $(touch manifest-canary).txt","change":"ADDED","before_sha256":null,"after_sha256":"829f8d848b44fa3098194754af5b60e2fb1517b0195956841beb6cac9bc68067","before_byte_count":null,"after_byte_count":7}]}'
}

@test "unknown top-level metadata is ignored for forward compatibility" {
    write_case unknown-top-level
    run --separate-stderr cli
    assert_unchanged
}

@test "empty input inventory is refused" {
    write_case empty-files
    run --separate-stderr cli
    assert_refused
}

@test "entry objects reject unknown fields" {
    write_case extra-entry-field
    run --separate-stderr cli
    assert_refused
}

@test "missing input file is a fixed refusal" {
    write_case retained-specimens
    rm -- "$AFTER"
    run --separate-stderr cli
    assert_refused
}

@test "non-regular input is a fixed refusal" {
    write_case retained-specimens
    rm -- "$AFTER"
    mkdir -- "$AFTER"
    run --separate-stderr cli
    assert_refused
}

@test "missing O_NONBLOCK refuses before opening either saved manifest" {
    write_case retained-specimens
    local hook_dir="$BATS_TEST_TMPDIR/no-nonblock-hook"
    local open_count="$BATS_TEST_TMPDIR/os-open-count"
    mkdir -- "$hook_dir"
    cat > "$hook_dir/sitecustomize.py" <<'PY'
import atexit
import os
import sys

if os.path.basename(sys.argv[0]) == "compare-cli-input-manifests.py":
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
    export D5_NONBLOCK_OPEN_COUNT="$open_count"
    export PYTHONPATH="$hook_dir${PYTHONPATH:+:$PYTHONPATH}"
    export PYTHONDONTWRITEBYTECODE=1
    run --separate-stderr cli
    [ -f "$open_count" ] \
        && [ "$(cat -- "$open_count")" = "0" ] \
        && assert_refused
}

@test "required O_NONBLOCK still compares two saved manifests" {
    write_case size-only
    run --separate-stderr cli
    [ "$status" -eq 1 ] \
        && [ -z "$stderr" ] \
        && assert_exact '{"schema":"DatarimCliInputManifestDiff/v1","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":0,"removed_count":0,"modified_count":1,"counts_status":"MEASURED","changes":[{"relative_path":"a-abc","change":"MODIFIED","before_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","after_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","before_byte_count":3,"after_byte_count":4}]}'
}
