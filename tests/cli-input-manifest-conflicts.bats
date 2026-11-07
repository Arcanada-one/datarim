#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  INSPECTOR="$REPO_ROOT/dev-tools/inspect-cli-input-manifest-conflicts.py"
  CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/d5-manifest-conflicts.XXXXXX")"
  chmod 700 "$CASE_DIR"
}

teardown() {
  rm -rf -- "$CASE_DIR"
}

build_case() {
  python3 - "$CASE_DIR" "$1" <<'PY'
import json
import os
import pathlib
import sys

case = pathlib.Path(sys.argv[1])
scenario = sys.argv[2]
schema = "DatarimCliInputManifest/v1"
output_schema = "DatarimCliInputManifestConflicts/v1"
input_limit = 2 * 1024 * 1024
max_file_bytes = 1024 * 1024
hash_a = "a" * 64
hash_b = "b" * 64
hash_c = "c" * 64


def row(path, digest=hash_a, size=0):
    return {"relative_path": path, "sha256": digest, "byte_count": size}


def manifest(rows, **extra):
    value = {
        "schema": schema,
        "result": "COMPLETE",
        "exit_code": 0,
        "diagnostic_codes": [],
        "file_count": len(rows),
        "file_count_status": "MEASURED",
        "files": rows,
    }
    value.update(extra)
    return value


def compact(value, *, ascii_only=False):
    return (json.dumps(value, ensure_ascii=ascii_only, separators=(",", ":")) + "\n").encode("utf-8", "strict")


def success(manifest_count, conflict_rows):
    return {
        "schema": output_schema,
        "result": "CONFLICTS" if conflict_rows else "CONSISTENT",
        "exit_code": 1 if conflict_rows else 0,
        "diagnostic_codes": ["INPUT_MANIFEST_CONFLICTS"] if conflict_rows else [],
        "manifest_count": manifest_count,
        "manifest_count_status": "MEASURED",
        "conflict_count": len(conflict_rows),
        "conflict_count_status": "MEASURED",
        "conflicts": conflict_rows,
    }


def declaration(index, digest, size):
    return {"manifest_index": index, "sha256": digest, "byte_count": size}


def refusal():
    return {
        "schema": output_schema,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": ["INPUT_MANIFEST_CONFLICT_INSPECTION_REFUSED"],
        "manifest_count": None,
        "manifest_count_status": "NOT_MEASURED",
        "conflict_count": None,
        "conflict_count_status": "NOT_MEASURED",
        "conflicts": [],
    }


docs = None
raw = None
expected = refusal()

if scenario == "single_manifest":
    docs = [manifest([row("a.txt", hash_a, 23)], producer_note={"ignored": True})]
    expected = success(1, [])
elif scenario == "identical_overlap":
    docs = [manifest([row("same.txt", hash_a, 4)]), manifest([row("same.txt", hash_a, 4)])]
    expected = success(2, [])
elif scenario == "hash_conflict":
    docs = [manifest([row("same.txt", hash_a, 4)]), manifest([row("same.txt", hash_b, 4)])]
    expected = success(2, [{
        "relative_path": "same.txt",
        "declarations": [declaration(0, hash_a, 4), declaration(1, hash_b, 4)],
    }])
elif scenario == "size_conflict":
    docs = [manifest([row("same.txt", hash_a, 4)]), manifest([row("same.txt", hash_a, 5)])]
    expected = success(2, [{
        "relative_path": "same.txt",
        "declarations": [declaration(0, hash_a, 4), declaration(1, hash_a, 5)],
    }])
elif scenario == "all_sources_sorted":
    docs = [
        manifest([row("z.txt", hash_a, 1), row("a.txt", hash_a, 1)]),
        manifest([row("z.txt", hash_b, 1), row("a.txt", hash_c, 1)]),
        manifest([row("z.txt", hash_a, 2)]),
    ]
    expected = success(3, [
        {
            "relative_path": "a.txt",
            "declarations": [declaration(0, hash_a, 1), declaration(1, hash_c, 1)],
        },
        {
            "relative_path": "z.txt",
            "declarations": [declaration(0, hash_a, 1), declaration(1, hash_b, 1), declaration(2, hash_a, 2)],
        },
    ])
elif scenario == "integral_decimal":
    raw = f'[{json.dumps(manifest([row("bytes.bin", hash_a, 23)]), separators=(",", ":"))}]\n'.encode("utf-8")
    raw = raw.replace(b'"byte_count":23', b'"byte_count":23.0', 1)
    expected = success(1, [])
elif scenario == "max_manifests":
    docs = [manifest([row(f"m{i:02d}.txt", hash_a, 0)]) for i in range(16)]
    expected = success(16, [])
elif scenario == "too_many_manifests":
    docs = [manifest([row(f"m{i:02d}.txt", hash_a, 0)]) for i in range(17)]
elif scenario == "max_rows":
    docs = [manifest([row(f"f{i:02d}.bin", hash_a, 0) for i in range(64)])]
    expected = success(1, [])
elif scenario == "too_many_rows":
    docs = [manifest([row(f"f{i:02d}.bin", hash_a, 0) for i in range(65)])]
elif scenario == "exact_manifest_total":
    docs = [manifest([row(f"f{i:02d}.bin", hash_a, max_file_bytes) for i in range(16)])]
    expected = success(1, [])
elif scenario == "manifest_total_over":
    docs = [manifest([row(f"f{i:02d}.bin", hash_a, max_file_bytes) for i in range(17)])]
elif scenario == "union_over":
    docs = [manifest([row(f"f{i:02d}.bin", hash_a, 0) for i in range(64)]), manifest([row("extra.bin", hash_a, 0)])]
elif scenario == "profile_object":
    docs = manifest([row("a.txt", hash_a, 0)])
elif scenario == "empty_array":
    docs = []
elif scenario in ("wrong_schema", "refused_profile", "bad_exit", "bad_diagnostics", "bad_status", "count_mismatch", "decimal_core_count", "extra_row_key"):
    doc = manifest([row("a.txt", hash_a, 0)])
    if scenario == "wrong_schema":
        doc["schema"] = "DatarimCliInputManifest/v0"
    elif scenario == "refused_profile":
        doc.update(result="INPUT_REFUSED", exit_code=2, diagnostic_codes=["INPUT_MANIFEST_REFUSED"], file_count=None, file_count_status="NOT_MEASURED", files=[])
    elif scenario == "bad_exit":
        doc["exit_code"] = 0.0
    elif scenario == "bad_diagnostics":
        doc["diagnostic_codes"] = ["OTHER"]
    elif scenario == "bad_status":
        doc["file_count_status"] = "NOT_MEASURED"
    elif scenario == "count_mismatch":
        doc["file_count"] = 2
    elif scenario == "decimal_core_count":
        doc["file_count"] = 1.0
    elif scenario == "extra_row_key":
        doc["files"][0]["note"] = "unexpected"
    docs = [doc]
elif scenario in ("path_empty", "path_absolute", "path_trailing_slash", "path_empty_component", "path_dot", "path_dotdot", "path_nul", "path_surrogate"):
    invalid_paths = {
        "path_empty": "",
        "path_absolute": "/absolute.txt",
        "path_trailing_slash": "dir/",
        "path_empty_component": "dir//file",
        "path_dot": "./file",
        "path_dotdot": "dir/../file",
        "path_nul": "name\x00suffix",
        "path_surrogate": "bad\ud800name",
    }
    docs = [manifest([row(invalid_paths[scenario], hash_a, 0)])]
elif scenario == "bad_digest":
    docs = [manifest([row("a.txt", "A" * 64, 0)])]
elif scenario in ("byte_boolean", "byte_fraction", "byte_negative", "byte_over_limit", "huge_integer"):
    value = {
        "byte_boolean": True,
        "byte_fraction": 0.5,
        "byte_negative": -1,
        "byte_over_limit": max_file_bytes + 1,
        "huge_integer": 0,
    }[scenario]
    docs = [manifest([row("a.bin", hash_a, value)])]
    if scenario == "huge_integer":
        raw = compact(docs).replace(b'"byte_count":0', b'"byte_count":' + b"9" * 5000, 1)
elif scenario == "duplicate_row_path":
    docs = [manifest([row("same.txt", hash_a, 0), row("same.txt", hash_b, 0)])]
elif scenario == "duplicate_json_key":
    raw = (f'[[{{"schema":"{schema}","schema":"{schema}","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{{"relative_path":"a.txt","sha256":"{hash_a}","byte_count":0}}]}}]]\n').encode()
elif scenario == "nonfinite":
    raw = (f'[[{{"schema":"{schema}","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{{"relative_path":"a.txt","sha256":"{hash_a}","byte_count":NaN}}]}}]]\n').encode()
elif scenario == "invalid_utf8":
    raw = b"\xff\xfe\n"
elif scenario == "deep_json":
    raw = b"[" * 1200 + b"0" + b"]" * 1200
elif scenario in ("input_exact", "input_over"):
    doc = manifest([row("a.txt", hash_a, 0)], ignored="")
    base = compact([doc])
    target_size = input_limit if scenario == "input_exact" else input_limit + 1
    doc["ignored"] = "x" * (target_size - len(base))
    raw = compact([doc])
    if len(raw) != target_size:
        raise RuntimeError("input limit fixture length mismatch")
    if scenario == "input_exact":
        expected = success(1, [])
elif scenario == "output_over":
    path = "😀" * 180000
    docs = [manifest([row(path, hash_a, 0)]), manifest([row(path, hash_b, 0)])]
    raw = compact(docs, ascii_only=False)
    if len(raw) >= input_limit:
        raise RuntimeError("output limit fixture must remain within the input limit")
elif scenario == "hostile_literal":
    marker = case / "must-not-be-created"
    literal = f"$(touch {marker});back\\slash\nline"
    docs = [manifest([row(literal, hash_a, 0)]), manifest([row(literal, hash_b, 0)])]
    expected = success(2, [{
        "relative_path": literal,
        "declarations": [declaration(0, hash_a, 0), declaration(1, hash_b, 0)],
    }])
elif scenario == "invalid_args":
    docs = [manifest([row("a.txt", hash_a, 0)])]
else:
    raise SystemExit("unknown synthetic scenario")

if raw is None:
    raw = compact(docs, ascii_only=(scenario == "path_surrogate"))
if len(raw) > input_limit and scenario not in ("input_over",):
    raise RuntimeError("unexpected oversized synthetic input")
if scenario == "output_over" and len(raw) >= input_limit:
    raise RuntimeError("output-limit input exceeded input cap")


def save(name, content):
    fd = os.open(case / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())

# A single Bats test may generate several scenarios in the same private directory.
for name in ("input.raw", "expected.raw"):
    try:
        (case / name).unlink()
    except FileNotFoundError:
        pass

save("input.raw", raw)
save("expected.raw", compact(expected, ascii_only=True))
PY
}

expect_case() {
  local scenario="$1"
  local expected_exit="$2"
  shift 2
  build_case "$scenario"
  local actual_exit
  if python3 "$INSPECTOR" "$@" < "$CASE_DIR/input.raw" > "$CASE_DIR/stdout.raw" 2> "$CASE_DIR/stderr.raw"; then
    actual_exit=0
  else
    actual_exit=$?
  fi
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    printf 'scenario=%s expected_exit=%s actual_exit=%s\n' "$scenario" "$expected_exit" "$actual_exit" >&2
    return 1
  fi
  if ! cmp -s "$CASE_DIR/expected.raw" "$CASE_DIR/stdout.raw"; then
    printf 'scenario=%s stdout differs from the fixed expected JSON\n' "$scenario" >&2
    diff -u "$CASE_DIR/expected.raw" "$CASE_DIR/stdout.raw" >&2 || true
    return 1
  fi
  if [ "$expected_exit" -eq 2 ]; then
    printf 'INPUT_MANIFEST_CONFLICT_INSPECTION_REFUSED\n' > "$CASE_DIR/stderr.expected"
  else
    : > "$CASE_DIR/stderr.expected"
  fi
  cmp -s "$CASE_DIR/stderr.expected" "$CASE_DIR/stderr.raw"
}

expect_group() {
  local scenario expected_exit
  while (($#)); do
    if (($# < 2)); then
      printf 'expect_group requires scenario/exit pairs\n' >&2
      return 2
    fi
    scenario="$1"
    expected_exit="$2"
    shift 2
    expect_case "$scenario" "$expected_exit" || return 1
  done
}

@test "one saved declaration is consistent and unknown producer metadata is not echoed" {
  expect_case single_manifest 0
}

@test "identical overlapping declarations are consistent" {
  expect_case identical_overlap 0
}

@test "a differing digest reports a conflict with every declaration" {
  expect_case hash_conflict 1
}

@test "a differing byte count reports a conflict with every declaration" {
  expect_case size_conflict 1
}

@test "conflict paths sort lexically and all source occurrences retain input order" {
  expect_case all_sources_sorted 1
}

@test "exact integral decimal byte counts are accepted" {
  expect_case integral_decimal 0
}

@test "the sixteen-manifest limit is inclusive" {
  expect_case max_manifests 0
}

@test "the sixty-four-row manifest limit is inclusive" {
  expect_case max_rows 0
}

@test "the per-manifest sixteen MiB declaration total is inclusive" {
  expect_case exact_manifest_total 0
}

@test "a non-array top level is refused" {
  expect_case profile_object 2
}

@test "an empty manifest array is refused" {
  expect_case empty_array 2
}

@test "more than sixteen manifests are refused" {
  expect_case too_many_manifests 2
}

@test "more than sixty-four rows are refused" {
  expect_case too_many_rows 2
}

@test "more than sixty-four unique union paths are refused" {
  expect_case union_over 2
}

@test "the saved producer schema, result, exit and core fields are exact" {
  expect_group \
    wrong_schema 2 \
    refused_profile 2 \
    bad_exit 2 \
    bad_diagnostics 2 \
    bad_status 2 || return 1
}

@test "core counters require integer tokens and exact row shape" {
  expect_group \
    count_mismatch 2 \
    decimal_core_count 2 \
    extra_row_key 2 \
    duplicate_row_path 2 || return 1
}

@test "noncanonical paths are refused" {
  expect_group \
    path_empty 2 \
    path_absolute 2 \
    path_trailing_slash 2 \
    path_empty_component 2 \
    path_dot 2 \
    path_dotdot 2 \
    path_nul 2 \
    path_surrogate 2 || return 1
}

@test "invalid digests and invalid byte-count numeric forms are refused" {
  expect_group \
    bad_digest 2 \
    byte_boolean 2 \
    byte_fraction 2 \
    byte_negative 2 \
    byte_over_limit 2 \
    huge_integer 2 || return 1
}

@test "duplicate JSON keys, nonfinite constants, malformed UTF-8 and deep JSON are refused" {
  expect_group \
    duplicate_json_key 2 \
    nonfinite 2 \
    invalid_utf8 2 \
    deep_json 2 || return 1
}

@test "a grouped case cannot hide its first failure behind a later success" {
  (
    seen=()
    expect_case() {
      seen+=("$1")
      [ "$1" != "forced_early_failure" ]
    }
    if expect_group forced_early_failure 2 later_success 0; then
      printf 'expect_group returned success after its first case failed\n' >&2
      exit 1
    fi
    [ "${#seen[@]}" -eq 1 ] && [ "${seen[0]}" = "forced_early_failure" ]
  )
}

@test "the two MiB input boundary is inclusive" {
  expect_case input_exact 0
}

@test "input larger than two MiB is refused" {
  expect_case input_over 2
}

@test "escaped Unicode output larger than two MiB is refused before writing a partial result" {
  expect_case output_over 2
}

@test "hostile path text remains literal and does not create its command marker" {
  expect_case hostile_literal 1 || return 1
  [ ! -e "$CASE_DIR/must-not-be-created" ] || return 1
}

@test "unexpected command-line arguments receive the fixed refusal result" {
  expect_case invalid_args 2 --unexpected
}
