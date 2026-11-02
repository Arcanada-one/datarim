#!/usr/bin/env bats

setup_file() {
  [ -n "${SUMMARY_CATALOG_OUTER_RECEIPT:-}" ] || return 0
  local attempt=0
  while [ ! -s "$SUMMARY_CATALOG_OUTER_RECEIPT" ] && [ "$attempt" -lt 100 ]; do
    sleep 0.05
    attempt=$((attempt + 1))
  done
  [ -s "$SUMMARY_CATALOG_OUTER_RECEIPT" ] || return 1
}

setup() {
  umask 077
  SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/list-summary-schemas.py"
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/repo"
  EVIDENCE_DIR="${SUMMARY_CATALOG_DIRECT_EVIDENCE:-$BATS_TEST_TMPDIR/direct}"
  mkdir -m 700 -p "$EVIDENCE_DIR"
  mkdir -m 700 "$EVIDENCE_DIR/$BATS_TEST_NUMBER"
  CASE_NUMBER=0
}

make_root() {
  mkdir -p "$1/documentation/reference/schemas"
}

write_schema() {
  python3 - "$1" "$2" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(json.loads(sys.argv[2]), ensure_ascii=False), encoding="utf-8")
PY
}

fixture_digest() {
  python3 - "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
target = root / "documentation" / "reference" / "schemas"
h = hashlib.sha256()
for component in (root, root / "documentation", root / "documentation" / "reference", target):
    try:
        info = component.lstat()
    except FileNotFoundError:
        h.update(b"missing\0" + os.fsencode(component.name) + b"\0")
        break
    h.update(b"component\0" + os.fsencode(component.name) + b"\0")
    h.update(str(stat.S_IFMT(info.st_mode)).encode("ascii") + b"\0")
    if stat.S_ISLNK(info.st_mode):
        h.update(os.fsencode(os.readlink(component)) + b"\0")
        break
if not target.is_symlink() and target.is_dir():
    for path in sorted(target.iterdir(), key=lambda item: os.fsencode(item.name)):
        if not path.name.endswith(".schema.json"):
            continue
        info = path.lstat()
        h.update(b"entry\0" + os.fsencode(path.name) + b"\0")
        h.update(str(stat.S_IFMT(info.st_mode)).encode("ascii") + b"\0")
        if stat.S_ISREG(info.st_mode):
            payload = path.read_bytes()
            h.update(len(payload).to_bytes(8, "big") + payload)
        elif stat.S_ISLNK(info.st_mode):
            h.update(os.fsencode(os.readlink(path)) + b"\0")
        else:
            h.update(str(info.st_size).encode("ascii") + b"\0")
print(h.hexdigest())
PY
}

run_catalog() {
  local root="$1"
  local label="$2"
  local case_dir start end source_before source_after input_before input_after pid rc
  CASE_NUMBER=$((CASE_NUMBER + 1))
  case_dir="$EVIDENCE_DIR/${BATS_TEST_NUMBER}/${CASE_NUMBER}-${label}"
  mkdir -m 700 "$case_dir"
  source_before="$(sha256sum "$SCRIPT" | cut -d ' ' -f 1)"
  input_before="$(fixture_digest "$root")"
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  (
    cd "$BATS_TEST_TMPDIR" || exit 91
    exec python3 "$SCRIPT" --root "$root"
  ) >"$case_dir/stdout.raw" 2>"$case_dir/stderr.raw" &
  pid=$!
  if wait "$pid"; then rc=0; else rc=$?; fi
  end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  source_after="$(sha256sum "$SCRIPT" | cut -d ' ' -f 1)"
  input_after="$(fixture_digest "$root")"
  chmod 600 "$case_dir/stdout.raw" "$case_dir/stderr.raw"
  python3 - "$case_dir/receipt.json" "$pid" "$start" "$end" "$rc" "$SCRIPT" "$root" "$BATS_TEST_TMPDIR" "$source_before" "$source_after" "$input_before" "$input_after" <<'PY'
import json
import os
import sys

path, pid, started, ended, status, script, root, cwd, source_before, source_after, input_before, input_after = sys.argv[1:]
record = {
    "direct_pid": int(pid),
    "started_utc": started,
    "ended_utc": ended,
    "argv": ["python3", script, "--root", root],
    "cwd": cwd,
    "exit_code": int(status),
    "stdout_raw": "stdout.raw",
    "stderr_raw": "stderr.raw",
    "source_sha256_before": source_before,
    "source_sha256_after": source_after,
    "fixture_manifest_sha256_before": input_before,
    "fixture_manifest_sha256_after": input_after,
}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(record, stream, sort_keys=True)
    stream.write("\n")
PY
  chmod 600 "$case_dir/receipt.json"
  LAST_CASE_DIR="$case_dir"
  LAST_STATUS="$rc"
}

assert_result() {
  python3 - "$LAST_CASE_DIR" "$1" "$FIXTURE_ROOT" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys

case_dir = pathlib.Path(sys.argv[1])
case = sys.argv[2]
fixture_root = pathlib.Path(sys.argv[3])
receipt = json.loads((case_dir / "receipt.json").read_text(encoding="utf-8"))
stdout = (case_dir / "stdout.raw").read_text(encoding="utf-8")
stderr = (case_dir / "stderr.raw").read_text(encoding="utf-8")
obj = json.loads(stdout)
assert receipt["direct_pid"] > 0
assert receipt["started_utc"] <= receipt["ended_utc"]
assert receipt["argv"][0] == "python3" and receipt["argv"][1].endswith("/dev-tools/list-summary-schemas.py")
assert receipt["argv"][2:] == ["--root", str(fixture_root)]
assert receipt["cwd"] == str(fixture_root.parent)
assert receipt["exit_code"] == obj["exit_code"]
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["fixture_manifest_sha256_before"] == receipt["fixture_manifest_sha256_after"]
assert stat.S_IMODE((case_dir / "stdout.raw").stat().st_mode) == 0o600
assert stat.S_IMODE((case_dir / "stderr.raw").stat().st_mode) == 0o600
assert stat.S_IMODE((case_dir / "receipt.json").stat().st_mode) == 0o600
assert str(fixture_root) not in stdout + stderr
assert set(obj) == {"schema", "result", "exit_code", "diagnostic_codes", "entry_count", "entry_count_status", "entries"}
assert obj["schema"] == "DatarimSummarySchemaCatalog/v1"

if case == "sorted":
    files = [
        fixture_root / "documentation/reference/schemas/a.schema.json",
        fixture_root / "documentation/reference/schemas/z.schema.json",
    ]
    entries = obj["entries"]
    assert obj["result"] == "COMPLETE" and receipt["exit_code"] == 0
    assert obj["entry_count"] == 2 and obj["entry_count_status"] == "MEASURED"
    assert [entry["relative_path"] for entry in entries] == [
        "documentation/reference/schemas/a.schema.json",
        "documentation/reference/schemas/z.schema.json",
    ]
    assert [entry["sha256"] for entry in entries] == [hashlib.sha256(path.read_bytes()).hexdigest() for path in files]
    assert entries[0]["title"] == "Alpha" and entries[0]["dialect"].endswith("/schema")
    assert entries[0]["summary_schema"] == "SummaryAlpha/v1"
    assert all(set(entry) == {"relative_path", "sha256", "title", "dialect", "summary_schema"} for entry in entries)
    assert obj["diagnostic_codes"] == []
elif case == "boolean":
    entries = obj["entries"]
    assert obj["result"] == "COMPLETE" and obj["entry_count"] == 2
    assert entries[0]["relative_path"].endswith("/boolean.schema.json")
    assert entries[0]["title"] is None and entries[0]["dialect"] is None and entries[0]["summary_schema"] is None
    assert entries[1]["summary_schema"] is None
elif case == "empty":
    assert obj["result"] == "COMPLETE" and obj["exit_code"] == 0
    assert obj["entry_count"] == 0 and obj["entry_count_status"] == "MEASURED" and obj["entries"] == []
elif case == "absent":
    assert obj["result"] == "INPUT_REFUSED" and obj["exit_code"] == 2
    assert obj["diagnostic_codes"] == ["SCHEMA_DIRECTORY_UNAVAILABLE"]
    assert obj["entry_count"] is None and obj["entry_count_status"] == "NOT_MEASURED" and obj["entries"] == []
elif case in {"malformed", "symlink_file", "symlink_dir"}:
    assert obj["result"] == "INPUT_REFUSED" and obj["exit_code"] == 2
    expected = "SCHEMA_DIRECTORY_UNAVAILABLE" if case == "symlink_dir" else "SCHEMA_INPUT_REFUSED"
    assert obj["diagnostic_codes"] == [expected]
    assert obj["entry_count"] is None and obj["entry_count_status"] == "NOT_MEASURED" and obj["entries"] == []
elif case in {"oversize", "too_many"}:
    assert obj["result"] == "INPUT_REFUSED" and obj["exit_code"] == 2
    assert obj["diagnostic_codes"] == ["SCHEMA_CATALOG_LIMIT"]
    assert obj["entry_count"] is None and obj["entry_count_status"] == "NOT_MEASURED" and obj["entries"] == []
elif case == "hostile":
    canary = pathlib.Path(receipt["cwd"]) / "catalog-canary"
    entry = obj["entries"][0]
    assert obj["result"] == "COMPLETE" and obj["entry_count"] == 1
    assert entry["relative_path"].endswith("/$(touch catalog-canary).schema.json")
    assert entry["title"] == 'Quoted " title $(touch catalog-canary)'
    def assert_canary_absent():
        assert not canary.exists(), f"hostile input created {canary}"

    assert_canary_absent()
    canary.write_text("intentional assertion self-check\n", encoding="utf-8")
    try:
        try:
            assert_canary_absent()
        except AssertionError:
            pass
        else:
            raise AssertionError("canary absence assertion accepted a present canary")
    finally:
        canary.unlink(missing_ok=True)
    assert str(fixture_root) not in stdout + stderr
else:
    raise AssertionError(f"unknown test case: {case}")
PY
}

@test "catalog sorts literal metadata and hashes the loaded fixture bytes" {
  make_root "$FIXTURE_ROOT"
  write_schema "$FIXTURE_ROOT/documentation/reference/schemas/z.schema.json" '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Zulu"}'
  write_schema "$FIXTURE_ROOT/documentation/reference/schemas/a.schema.json" '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Alpha","properties":{"schema":{"const":"SummaryAlpha/v1"}}}'
  run_catalog "$FIXTURE_ROOT" sorted
  assert_result sorted
}

@test "Boolean and object schemas preserve unsupported metadata as null" {
  make_root "$FIXTURE_ROOT"
  printf 'true\n' >"$FIXTURE_ROOT/documentation/reference/schemas/boolean.schema.json"
  write_schema "$FIXTURE_ROOT/documentation/reference/schemas/object.schema.json" '{"properties":{"schema":{"$ref":"#/$defs/schema"}},"$defs":{"schema":{"const":"Not-resolved"}}}'
  run_catalog "$FIXTURE_ROOT" boolean
  assert_result boolean
}

@test "a present empty schema directory is a measured empty catalog" {
  make_root "$FIXTURE_ROOT"
  run_catalog "$FIXTURE_ROOT" empty
  assert_result empty
}

@test "an absent schema directory is refused with an unavailable count" {
  run_catalog "$FIXTURE_ROOT" absent
  assert_result absent
}

@test "malformed JSON and symlink inputs are refused without partial entries" {
  make_root "$FIXTURE_ROOT"
  printf '{not json}\n' >"$FIXTURE_ROOT/documentation/reference/schemas/bad.schema.json"
  run_catalog "$FIXTURE_ROOT" malformed
  assert_result malformed

  rm "$FIXTURE_ROOT/documentation/reference/schemas/bad.schema.json"
  printf '{"title":"outside"}\n' >"$BATS_TEST_TMPDIR/outside.schema.json"
  ln -s "$BATS_TEST_TMPDIR/outside.schema.json" "$FIXTURE_ROOT/documentation/reference/schemas/link.schema.json"
  run_catalog "$FIXTURE_ROOT" symlink_file
  assert_result symlink_file

  rm "$FIXTURE_ROOT/documentation/reference/schemas/link.schema.json"
  rm -r "$FIXTURE_ROOT/documentation/reference/schemas"
  ln -s "$BATS_TEST_TMPDIR" "$FIXTURE_ROOT/documentation/reference/schemas"
  run_catalog "$FIXTURE_ROOT" symlink_dir
  assert_result symlink_dir
}

@test "oversize files and a catalog over the file cap are explicit limit refusals" {
  make_root "$FIXTURE_ROOT"
  python3 - "$FIXTURE_ROOT/documentation/reference/schemas/large.schema.json" <<'PY'
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_bytes(b" " * (1024 * 1024 + 1))
PY
  run_catalog "$FIXTURE_ROOT" oversize
  assert_result oversize

  rm "$FIXTURE_ROOT/documentation/reference/schemas/large.schema.json"
  python3 - "$FIXTURE_ROOT/documentation/reference/schemas" <<'PY'
import pathlib
import sys
directory = pathlib.Path(sys.argv[1])
for number in range(257):
    (directory / f"{number:03}.schema.json").write_text("{}", encoding="utf-8")
PY
  run_catalog "$FIXTURE_ROOT" too_many
  assert_result too_many
}

@test "quoted hostile filename and title remain literal JSON and inert" {
  make_root "$FIXTURE_ROOT"
  python3 - "$FIXTURE_ROOT/documentation/reference/schemas" <<'PY'
import json
import pathlib
import sys
directory = pathlib.Path(sys.argv[1])
document = {"title": 'Quoted " title $(touch catalog-canary)'}
(directory / "$(touch catalog-canary).schema.json").write_text(json.dumps(document), encoding="utf-8")
PY
  run_catalog "$FIXTURE_ROOT" hostile
  assert_result hostile
}
