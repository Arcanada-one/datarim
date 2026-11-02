#!/usr/bin/env bats

set -o pipefail

setup_file() {
  if [ "${D5_MERGE_EVIDENCE_DIR+x}" = x ]; then
    [ -n "$D5_MERGE_EVIDENCE_DIR" ] \
      && [ -d "$D5_MERGE_EVIDENCE_DIR" ] \
      && [ -f "$D5_MERGE_EVIDENCE_DIR/preflight.json" ] \
      && [ "$(stat -c '%a' "$D5_MERGE_EVIDENCE_DIR")" = "700" ] \
      && [ "$(stat -c '%a' "$D5_MERGE_EVIDENCE_DIR/preflight.json")" = "600" ] \
      && D5_MERGE_EVIDENCE_MODE=external \
      && export D5_MERGE_EVIDENCE_MODE
  else
    [ -n "$BATS_FILE_TMPDIR" ] \
      && D5_MERGE_EVIDENCE_DIR="$BATS_FILE_TMPDIR/merge-evidence" \
      && (umask 077 && mkdir -m 700 "$D5_MERGE_EVIDENCE_DIR") \
      && D5_MERGE_EVIDENCE_MODE=bats-default \
      && export D5_MERGE_EVIDENCE_DIR D5_MERGE_EVIDENCE_MODE
  fi
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  MERGE_CLI="$REPO_ROOT/dev-tools/merge-cli-input-manifests.py"
  CASE_SLUG="$(printf '%s' "$BATS_TEST_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_' '_')"
  CASE_DIR="$D5_MERGE_EVIDENCE_DIR/$CASE_SLUG"
  FIXTURE_DIR="$CASE_DIR/fixture"
  mkdir -m 700 "$CASE_DIR"
  mkdir -m 700 "$FIXTURE_DIR"
  printf 'private synthetic canary; declaration-only merge must not read it\n' > "$FIXTURE_DIR/canary"
  chmod 400 "$FIXTURE_DIR/canary"
}

build_input() {
  python3 - "$CASE_DIR" "$1" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

case = pathlib.Path(sys.argv[1])
scenario = sys.argv[2]
schema = "DatarimCliInputManifest/v1"
limit = 2 * 1024 * 1024
hash_a = "a" * 64
hash_b = "b" * 64
canary = b"private synthetic canary; declaration-only merge must not read it\n"
canary_hash = hashlib.sha256(canary).hexdigest()

def row(path="canary", digest=canary_hash, size=len(canary)):
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

def complete(rows):
    return {
        "schema": schema,
        "result": "COMPLETE",
        "exit_code": 0,
        "diagnostic_codes": [],
        "file_count": len(rows),
        "file_count_status": "MEASURED",
        "files": rows,
    }

def refused():
    return {
        "schema": schema,
        "result": "INPUT_REFUSED",
        "exit_code": 2,
        "diagnostic_codes": ["INPUT_MANIFEST_REFUSED"],
        "file_count": None,
        "file_count_status": "NOT_MEASURED",
        "files": [],
    }

def compact(value, ascii_only=False):
    return (json.dumps(value, ensure_ascii=ascii_only, separators=(",", ":")) + "\n").encode("utf-8")

def save(raw, expected, argv=None):
    values = {
        "input.raw": raw,
        "expected.raw": compact(expected, ascii_only=True),
        "argv.json": compact(argv or [], ascii_only=True),
    }
    for name, content in values.items():
        path = case / name
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())

if scenario == "single_metadata":
    rows = [row()]
    doc = manifest(rows, producer_note="not copied into merged output")
    save(compact([doc]), complete(rows))
elif scenario == "union":
    rows = [row("z.txt", hash_a, 2), row("b.txt", hash_b, 3), row("a.txt", hash_a, 1)]
    docs = [manifest(rows[:2]), manifest([rows[1], rows[2]])]
    expected = complete([rows[2], rows[1], rows[0]])
    save(compact(docs), expected)
elif scenario == "hash_conflict":
    save(compact([manifest([row("same.txt", hash_a, 3)]), manifest([row("same.txt", hash_b, 3)])]), refused())
elif scenario == "size_conflict":
    save(compact([manifest([row("same.txt", hash_a, 3)]), manifest([row("same.txt", hash_a, 4)])]), refused())
elif scenario == "refused_input":
    rejected = {
        "schema": schema, "result": "INPUT_REFUSED", "exit_code": 2,
        "diagnostic_codes": ["INPUT_MANIFEST_REFUSED"], "file_count": None,
        "file_count_status": "NOT_MEASURED", "files": [],
    }
    save(compact([manifest([row("safe.txt", hash_a, 1)]), rejected]), refused())
elif scenario == "empty_array":
    save(b"[]\n", refused())
elif scenario in ("max_manifests", "too_many_manifests"):
    count = 16 if scenario == "max_manifests" else 17
    docs = [manifest([row("m%02d.txt" % i, hash_a, 0)]) for i in range(count)]
    expected = complete([row("m%02d.txt" % i, hash_a, 0) for i in range(count)]) if count == 16 else refused()
    save(compact(docs), expected)
elif scenario == "count_mismatch":
    doc = manifest([row("x.txt", hash_a, 0)])
    doc["file_count"] = 2
    save(compact([doc]), refused())
elif scenario == "boolean_count":
    doc = manifest([row("x.txt", hash_a, 0)])
    doc["file_count"] = True
    save(compact([doc]), refused())
elif scenario == "status_mismatch":
    doc = manifest([row("x.txt", hash_a, 0)])
    doc["file_count_status"] = "NOT_MEASURED"
    save(compact([doc]), refused())
elif scenario in ("path_dotdot", "path_absolute", "path_empty", "path_empty_component", "path_surrogate"):
    paths = {
        "path_dotdot": "a/../b",
        "path_absolute": "/absolute",
        "path_empty": "",
        "path_empty_component": "a//b",
        "path_surrogate": "\ud800",
    }
    save(compact([manifest([row(paths[scenario], hash_a, 0)])], ascii_only=scenario == "path_surrogate"), refused())
elif scenario == "bad_digest":
    save(compact([manifest([row("x.txt", "A" * 64, 0)])]), refused())
elif scenario == "huge_integer_token":
    doc = manifest([row("x.txt", hash_a, 0)])
    raw = compact([doc]).replace(b'"byte_count":0', b'"byte_count":' + b"9" * 5000, 1)
    if raw == compact([doc]):
        raise RuntimeError("large integer token fixture substitution failed")
    save(raw, refused())
elif scenario == "bounded_integer_token":
    rows = [row("x.txt", hash_a, 23)]
    save(compact([manifest(rows)]), complete(rows))
elif scenario == "bounded_integral_decimal":
    raw = ('[{"schema":"%s","result":"COMPLETE","exit_code":0,'
           '"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED",'
           '"files":[{"relative_path":"x.txt","sha256":"%s","byte_count":23.0}]}]\n') % (schema, hash_a)
    save(raw.encode("utf-8"), complete([row("x.txt", hash_a, 23)]))
elif scenario in ("byte_boolean", "byte_fraction", "decimal_integral", "file_over_limit"):
    sizes = {
        "byte_boolean": True,
        "byte_fraction": 0.5,
        "decimal_integral": 0.0,
        "file_over_limit": 1024 * 1024 + 1,
    }
    rows = [row("x.txt", hash_a, sizes[scenario])]
    expected = complete([row("x.txt", hash_a, 0)]) if scenario == "decimal_integral" else refused()
    save(compact([manifest(rows)], ascii_only=False), expected)
elif scenario == "duplicate_keys":
    raw = ('[{"schema":"%s","schema":"%s","result":"COMPLETE","exit_code":0,'
           '"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED",'
           '"files":[{"relative_path":"x","sha256":"%s","byte_count":0}]}]\n') % (schema, schema, hash_a)
    save(raw.encode("utf-8"), refused())
elif scenario == "nonfinite":
    raw = ('[{"schema":"%s","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],'
           '"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"x",'
           '"sha256":"%s","byte_count":NaN}]}]\n') % (schema, hash_a)
    save(raw.encode("utf-8"), refused())
elif scenario == "invalid_utf8":
    save(b"\xff", refused())
elif scenario == "deep_json":
    save(b"[" * 1200 + b"0" + b"]" * 1200, refused())
elif scenario == "input_over_limit":
    doc = manifest([row("x.txt", hash_a, 0)], future_metadata="")
    raw = compact([doc])
    extra = limit + 1 - len(raw)
    doc["future_metadata"] = "x" * extra
    raw = compact([doc])
    if len(raw) != limit + 1:
        raise RuntimeError("oversize fixture length preflight mismatch")
    save(raw, refused())
elif scenario == "exact_total":
    rows = [row("f%02d.bin" % i, hash_a, 1024 * 1024) for i in range(16)]
    save(compact([manifest(rows)]), complete(rows))
elif scenario == "exact_file_count":
    rows = [row("f%02d.bin" % i, hash_a, 0) for i in range(64)]
    save(compact([manifest(rows)]), complete(rows))
elif scenario == "manifest_total_over":
    rows = [row("f%02d.bin" % i, hash_a, 1024 * 1024) for i in range(17)]
    save(compact([manifest(rows)]), refused())
elif scenario == "union_count_over":
    first = [row("f%02d.bin" % i, hash_a, 0) for i in range(64)]
    save(compact([manifest(first), manifest([row("extra.bin", hash_a, 0)])]), refused())
elif scenario == "union_total_over":
    first = [row("f%02d.bin" % i, hash_a, 1024 * 1024) for i in range(16)]
    save(compact([manifest(first), manifest([row("extra.bin", hash_a, 1)])]), refused())
elif scenario == "hostile_literal":
    literal = "$(touch marker);back\\slash\nline"
    rows = [row(literal, hash_a, 0), row("-leading-name", hash_b, 0)]
    expected = complete(sorted(rows, key=lambda item: item["relative_path"]))
    save(compact([manifest(rows)], ascii_only=False), expected)
elif scenario == "output_over_limit":
    path = "\U0001f600" * 175000
    save(compact([manifest([row(path, hash_a, 0)])], ascii_only=False), refused())
elif scenario == "invalid_args":
    save(compact([manifest([row("x.txt", hash_a, 0)])]), refused(), ["--root", "/never/open"])
else:
    raise SystemExit("unknown fixture scenario")
PY
}

capture_cli() {
  run python3 - "$CASE_DIR" "$MERGE_CLI" "$BATS_TEST_FILENAME" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import stat
import subprocess
import sys

case = pathlib.Path(sys.argv[1])
cli = pathlib.Path(sys.argv[2])
test_file = pathlib.Path(sys.argv[3])
fixture = case / "fixture"
input_path = case / "input.raw"
stdout_path = case / "stdout.raw"
stderr_path = case / "stderr.raw"
receipt_path = case / "receipt.json"

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    return sha(path.read_bytes())

def fixture_snapshot(root):
    records = []
    for current, dirs, files in os.walk(root):
        dirs.sort()
        files.sort()
        for name in files:
            path = pathlib.Path(current) / name
            rel = path.relative_to(root).as_posix()
            data = path.read_bytes()
            records.append((rel, stat.S_IMODE(path.stat().st_mode), len(data), sha(data)))
    return sha(json.dumps(records, ensure_ascii=True, separators=(",", ":")).encode("utf-8"))

def write_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())

raw = input_path.read_bytes()
args = json.loads((case / "argv.json").read_text(encoding="utf-8"))
source_before = file_sha(cli)
test_before = file_sha(test_file)
input_before = sha(raw)
fixture_before = fixture_snapshot(fixture)
argv = [sys.executable, str(cli), *args]
started = utc()
proc = subprocess.Popen(argv, cwd=str(fixture), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
stdout, stderr = proc.communicate(raw)
ended = utc()
write_new(stdout_path, stdout)
write_new(stderr_path, stderr)
source_after = file_sha(cli)
test_after = file_sha(test_file)
input_after = file_sha(input_path)
fixture_after = fixture_snapshot(fixture)
receipt = {
    "process": "direct_merge_cli",
    "pid": proc.pid,
    "capture_pid": os.getpid(),
    "started_utc": started,
    "ended_utc": ended,
    "argv": argv,
    "cwd": str(fixture),
    "exit": proc.returncode,
    "input_path": str(input_path),
    "input_bytes": len(raw),
    "input_sha256_before": input_before,
    "input_sha256_after": input_after,
    "stdout_path": str(stdout_path),
    "stdout_bytes": len(stdout),
    "stdout_sha256": sha(stdout),
    "stdout_mode": format(stat.S_IMODE(stdout_path.stat().st_mode), "o"),
    "stderr_path": str(stderr_path),
    "stderr_bytes": len(stderr),
    "stderr_sha256": sha(stderr),
    "stderr_mode": format(stat.S_IMODE(stderr_path.stat().st_mode), "o"),
    "source_path": str(cli),
    "source_sha256_before": source_before,
    "source_sha256_after": source_after,
    "test_path": str(test_file),
    "test_sha256_before": test_before,
    "test_sha256_after": test_after,
    "fixture_path": str(fixture),
    "fixture_sha256_before": fixture_before,
    "fixture_sha256_after": fixture_after,
}
encoded = (json.dumps(receipt, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
if json.loads(encoded.decode("utf-8")) != receipt:
    raise RuntimeError("receipt serialization preflight mismatch")
write_new(receipt_path, encoded)
raise SystemExit(proc.returncode)
PY
  CLI_STATUS=$status
  return 0
}

assert_receipt() {
  python3 - "$CASE_DIR" "$1" "$MERGE_CLI" "$BATS_TEST_FILENAME" <<'PY'
import json
import pathlib
import stat
import sys

case = pathlib.Path(sys.argv[1])
expected_exit = int(sys.argv[2])
receipt = json.loads((case / "receipt.json").read_text(encoding="utf-8"))
assert receipt["exit"] == expected_exit
assert receipt["pid"] > 0
assert receipt["started_utc"].endswith("Z") and receipt["ended_utc"].endswith("Z")
assert receipt["argv"][1] == sys.argv[3]
assert receipt["test_path"] == sys.argv[4]
assert receipt["cwd"] == str(case / "fixture")
assert receipt["input_sha256_before"] == receipt["input_sha256_after"]
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["test_sha256_before"] == receipt["test_sha256_after"]
assert receipt["fixture_sha256_before"] == receipt["fixture_sha256_after"]
for name in ("stdout.raw", "stderr.raw", "receipt.json", "input.raw", "expected.raw"):
    assert stat.S_IMODE((case / name).stat().st_mode) == 0o600
assert receipt["stdout_mode"] == "600" and receipt["stderr_mode"] == "600"
PY
}

assert_output() {
  python3 - "$CASE_DIR" <<'PY'
import pathlib
import sys

case = pathlib.Path(sys.argv[1])
assert (case / "stdout.raw").read_bytes() == (case / "expected.raw").read_bytes()
expected = (case / "expected.raw").read_bytes()
refused = b'"result":"INPUT_REFUSED"' in expected
stderr = (case / "stderr.raw").read_bytes()
assert stderr == (b"INPUT_MANIFEST_MERGE_REFUSED\n" if refused else b"")
PY
}

@test "one complete saved manifest passes through without unknown metadata echo" {
  build_input single_metadata
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "disjoint rows merge, identical overlap coalesces, and output is sorted" {
  build_input union
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "same path with a different digest refuses without partial output" {
  build_input hash_conflict
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "same path with a different byte count refuses" {
  build_input size_conflict
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "one refused input prevents partial merge output" {
  build_input refused_input
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "empty manifest array is refused" {
  build_input empty_array
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "sixteen input manifests are accepted" {
  build_input max_manifests
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "more than sixteen input manifests are refused" {
  build_input too_many_manifests
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "producer file count must match row count" {
  build_input count_mismatch
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "boolean is not accepted as producer file count" {
  build_input boolean_count
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "only measured complete producer counts are mergeable" {
  build_input status_mismatch
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "dot dot path component is refused" {
  build_input path_dotdot
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "absolute path is refused" {
  build_input path_absolute
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "empty path is refused" {
  build_input path_empty
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "empty path component is refused" {
  build_input path_empty_component
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "unpaired surrogate path is refused as invalid UTF-8 data" {
  build_input path_surrogate
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "digest must be lowercase hexadecimal SHA-256" {
  build_input bad_digest
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "huge JSON integer token uses the fixed refusal profile" {
  build_input huge_integer_token
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "bounded JSON integer token is accepted" {
  build_input bounded_integer_token
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "bounded mathematically integral Decimal token is accepted" {
  build_input bounded_integral_decimal
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "boolean byte count is refused" {
  build_input byte_boolean
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "fractional byte count is refused" {
  build_input byte_fraction
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "mathematically integral Decimal byte count is accepted" {
  build_input decimal_integral
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "duplicate JSON keys are refused" {
  build_input duplicate_keys
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "nonfinite JSON number is refused" {
  build_input nonfinite
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "invalid UTF-8 input is refused" {
  build_input invalid_utf8
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "deep JSON recursion is refused without exception text" {
  build_input deep_json
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "input over two MiB is refused after bounded read" {
  build_input input_over_limit
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "one file above one MiB is refused" {
  build_input file_over_limit
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "one manifest above sixteen MiB declared total is refused" {
  build_input manifest_total_over
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "exactly sixty four unique files are accepted" {
  build_input exact_file_count
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "sixty five unique merged rows are refused" {
  build_input union_count_over
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "exact sixteen MiB unique declaration total is accepted" {
  build_input exact_total
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output
}

@test "union above sixteen MiB is refused" {
  build_input union_total_over
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "shell-looking, backslash, and newline path literals remain inert data" {
  build_input hostile_literal
  capture_cli
  [ "$CLI_STATUS" -eq 0 ] \
    && assert_receipt 0 \
    && assert_output \
    && [ ! -e "$FIXTURE_DIR/marker" ]
}

@test "oversized escaped output is refused before any partial stdout" {
  build_input output_over_limit
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "invalid arguments use fixed refusal output" {
  build_input invalid_args
  capture_cli
  [ "$CLI_STATUS" -eq 2 ] \
    && assert_receipt 2 \
    && assert_output
}

@test "F2 ordinary startup and valid external evidence mode both work" {
  if [ "${D5_MERGE_SETUP_PROBE:-}" = "1" ]; then
    if [ "$D5_MERGE_EVIDENCE_MODE" = "bats-default" ]; then
      [[ "$D5_MERGE_EVIDENCE_DIR" == "$BATS_FILE_TMPDIR/merge-evidence" ]] \
        && [ -d "$D5_MERGE_EVIDENCE_DIR" ] \
        && [ "$(stat -c '%a' "$D5_MERGE_EVIDENCE_DIR")" = "700" ] \
        && [ ! -e "$D5_MERGE_EVIDENCE_DIR/preflight.json" ]
    else
      [ "$D5_MERGE_EVIDENCE_MODE" = "external" ] \
        && [ "$D5_MERGE_EVIDENCE_DIR" = "$D5_MERGE_TEST_EXPECTED_DIR" ] \
        && [ "$(stat -c '%a' "$D5_MERGE_EVIDENCE_DIR")" = "700" ] \
        && [ "$(stat -c '%a' "$D5_MERGE_EVIDENCE_DIR/preflight.json")" = "600" ]
    fi
  else
    run env -u D5_MERGE_EVIDENCE_DIR D5_MERGE_SETUP_PROBE=1 \
      bats --filter '^F2 ordinary startup and valid external evidence mode both work$' \
        "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ] \
      && [[ "$output" == *"ok 1 F2 ordinary startup and valid external evidence mode both work"* ]] \
      && EXTERNAL_CASE_DIR="$CASE_DIR/valid-external" \
      && mkdir -m 700 "$EXTERNAL_CASE_DIR" \
      && (umask 077 && printf '{"preflight":"synthetic"}\n' > "$EXTERNAL_CASE_DIR/preflight.json") \
      && chmod 600 "$EXTERNAL_CASE_DIR/preflight.json" \
      && run env D5_MERGE_EVIDENCE_DIR="$EXTERNAL_CASE_DIR" \
        D5_MERGE_TEST_EXPECTED_DIR="$EXTERNAL_CASE_DIR" D5_MERGE_SETUP_PROBE=1 \
        bats --filter '^F2 ordinary startup and valid external evidence mode both work$' \
          "$BATS_TEST_FILENAME" \
      && [ "$status" -eq 0 ] \
      && [[ "$output" == *"ok 1 F2 ordinary startup and valid external evidence mode both work"* ]]
  fi
}

@test "F2 explicit invalid external evidence directory is refused" {
  run env D5_MERGE_EVIDENCE_DIR="$CASE_DIR/missing-external" \
    bats --filter 'F2 ordinary startup and valid external evidence mode both work' \
      "$BATS_TEST_FILENAME"
  [ "$status" -ne 0 ] \
    && [[ "$output" == *"setup_file"* ]] \
    && [ ! -e "$CASE_DIR/missing-external" ]
}
