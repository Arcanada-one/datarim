#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup() {
  D5_OWN_CLONE="${D5_OWN_CLONE:-$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)}"
  D5_CAPTURE_DIR="${D5_CAPTURE_DIR:-$BATS_FILE_TMPDIR/capture}"
  TEST_TMPDIR="$(mktemp -d)"
  chmod 700 "$TEST_TMPDIR"
  export TEST_TMPDIR
  if [[ ! -e "$D5_CAPTURE_DIR" ]]; then
    (umask 077 && mkdir -m 700 -p -- "$D5_CAPTURE_DIR")
  fi
  if [[ -n "${D5_CAPTURE_HELPER:-}" ]]; then
    mkdir -p "$D5_CAPTURE_DIR/direct"
    chmod 700 "$D5_CAPTURE_DIR/direct"
  fi
}

teardown() {
  rm -rf -- "$TEST_TMPDIR"
}

write_complete() {
  if [[ -n "${D5_COMPLETE_SPECIMEN:-}" ]]; then
    cp -- "$D5_COMPLETE_SPECIMEN" "$TEST_TMPDIR/input.json"
  else
    python3 - "$TEST_TMPDIR/input.json" <<'PY'
import hashlib
import json
import pathlib
import sys

rows = [
    {"relative_path": "a-abc", "sha256": hashlib.sha256(b"abc").hexdigest(), "byte_count": 3},
    {"relative_path": "z-empty", "sha256": hashlib.sha256(b"").hexdigest(), "byte_count": 0},
]
value = {
    "schema": "DatarimCliInputManifest/v1",
    "result": "COMPLETE",
    "exit_code": 0,
    "diagnostic_codes": [],
    "file_count": len(rows),
    "file_count_status": "MEASURED",
    "files": rows,
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(value, separators=(",", ":")) + "\n", encoding="utf-8")
PY
  fi
  chmod 600 "$TEST_TMPDIR/input.json"
}

make_case() {
  python3 - "$TEST_TMPDIR/input.json" "$1" <<'PY'
import hashlib, json, sys
from decimal import Decimal
path, case = sys.argv[1:]
sha_empty = hashlib.sha256(b"").hexdigest()
sha_abc = hashlib.sha256(b"abc").hexdigest()
rows = [
    {"relative_path":"a-abc","sha256":sha_abc,"byte_count":3},
    {"relative_path":"z-empty","sha256":sha_empty,"byte_count":0},
]
obj = {"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,
       "diagnostic_codes":[],"file_count":2,"file_count_status":"MEASURED","files":rows}
if case == "unknown-integral":
    obj["future_metadata"] = {"ignored": True}
    obj["files"][0]["byte_count"] = Decimal("3.0")
elif case == "unavailable":
    obj.update(result="INPUT_REFUSED", exit_code=2, diagnostic_codes=["OTHER"],
               file_count=None, file_count_status="NOT_MEASURED", files=[])
elif case == "empty":
    obj["files"] = []
    obj["file_count"] = 0
elif case == "count-mismatch":
    obj["file_count"] = 1
elif case == "bool-size":
    obj["files"][0]["byte_count"] = True
elif case == "fraction-size":
    obj["files"][0]["byte_count"] = Decimal("3.5")
elif case == "nonfinite-size":
    obj["files"][0]["byte_count"] = Decimal("NaN")
elif case == "duplicate-path":
    obj["files"].append(dict(obj["files"][0]))
    obj["file_count"] = 3
elif case == "absolute-path":
    obj["files"][0]["relative_path"] = "/tmp/private"
elif case == "dotdot-path":
    obj["files"][0]["relative_path"] = "a/../b"
elif case == "file-limit":
    obj["files"][0]["byte_count"] = 1048577
elif case == "total-limit":
    obj["files"] = [{"relative_path":f"p{i}","sha256":sha_empty,"byte_count":1048576} for i in range(17)]
    obj["file_count"] = 17
elif case == "sixty-four-files":
    obj["files"] = [{"relative_path":f"p{i:02d}","sha256":sha_empty,"byte_count":0} for i in range(64)]
    obj["file_count"] = 64
elif case == "count-overflow":
    obj["files"] = [{"relative_path":f"p{i:02d}","sha256":sha_empty,"byte_count":0} for i in range(65)]
    obj["file_count"] = 65
elif case == "hostile-literal":
    obj["files"][0]["relative_path"] = "folder/line\nnext\\$(touch marker)-雪"
elif case == "existing-path-declaration":
    obj["files"] = [{"relative_path":"README.md","sha256":"0"*64,"byte_count":999}]
    obj["file_count"] = 1
elif case != "complete":
    raise SystemExit("unknown fixture case")
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, ensure_ascii=True, separators=(",", ":"), default=lambda x: float(x))
    f.write("\n")
PY
  chmod 600 "$TEST_TMPDIR/input.json"
}

invoke() {
  local label="$1" input="$2"; shift 2
  local cli="$D5_OWN_CLONE/dev-tools/select-cli-input-manifest.py" rc
  if [[ -n "${D5_CAPTURE_HELPER:-}" ]]; then
    if "$D5_CAPTURE_HELPER" --capture-dir "$D5_CAPTURE_DIR/direct" --cwd "$D5_OWN_CLONE" \
      --source "$cli" --test "$BATS_TEST_NAME" \
      --fixture "$input" --timeout 15 -- /bin/bash -c \
      'input=$1; shift; exec "$@" < "$input"' _ "$input" "$cli" "$@"; then
      rc=0
    else
      rc=$?
    fi
    cp -- "$D5_CAPTURE_DIR/direct/latest.stdout" "$TEST_TMPDIR/$label.stdout"
    cp -- "$D5_CAPTURE_DIR/direct/latest.stderr" "$TEST_TMPDIR/$label.stderr"
  else
    if "$cli" "$@" <"$input" >"$TEST_TMPDIR/$label.stdout" 2>"$TEST_TMPDIR/$label.stderr"; then
      rc=0
    else
      rc=$?
    fi
  fi
  return "$rc"
}

@test "selects requested declarations and sorts output without opening paths" {
  write_complete
  run invoke selected "$TEST_TMPDIR/input.json" --file z-empty --file a-abc
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/selected.stderr")" = "" ]
  python3 - "$TEST_TMPDIR/selected.stdout" <<'PY'
import json, sys
x=json.load(open(sys.argv[1], encoding="utf-8"))
assert x["result"] == "COMPLETE" and x["exit_code"] == 0
assert [r["relative_path"] for r in x["files"]] == ["a-abc","z-empty"]
PY
}

@test "ignores unknown producer metadata and accepts exact integral decimal counts" {
  write_complete; make_case unknown-integral
  run invoke selected "$TEST_TMPDIR/input.json" --file a-abc
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMPDIR/selected.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["files"][0]["byte_count"] == 3
PY
}

@test "preserves hostile POSIX path characters as data" {
  write_complete; make_case hostile-literal
  local hostile=$'folder/line\nnext\\$(touch marker)-雪'
  run invoke selected "$TEST_TMPDIR/input.json" --file "$hostile"
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMPDIR/selected.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["files"][0]["relative_path"] == "folder/line\nnext\\$(touch marker)-雪"
PY
  [ ! -e "$TEST_TMPDIR/marker" ]
}

@test "refuses missing duplicate and noncanonical requested paths" {
  write_complete
  run invoke missing "$TEST_TMPDIR/input.json" --file absent
  [ "$status" -eq 2 ]
  run invoke duplicate "$TEST_TMPDIR/input.json" --file a-abc --file a-abc
  [ "$status" -eq 2 ]
  run invoke traversal "$TEST_TMPDIR/input.json" --file ../a-abc
  [ "$status" -eq 2 ]
  for name in missing duplicate traversal; do
    [ "$(cat "$TEST_TMPDIR/$name.stderr")" = "INPUT_MANIFEST_SELECTION_REFUSED" ]
    python3 - "$TEST_TMPDIR/$name.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["result"]=="INPUT_REFUSED" and x["file_count"] is None and x["files"]==[]
PY
  done
}

@test "refuses unavailable empty and inconsistent producer results" {
  for kind in unavailable empty count-mismatch; do
    write_complete; make_case "$kind"
    run invoke "$kind" "$TEST_TMPDIR/input.json" --file a-abc
    [ "$status" -eq 2 ]
    [ "$(cat "$TEST_TMPDIR/$kind.stderr")" = "INPUT_MANIFEST_SELECTION_REFUSED" ]
    python3 - "$TEST_TMPDIR/$kind.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["result"]=="INPUT_REFUSED" and x["file_count_status"]=="NOT_MEASURED" and x["file_count"] is None
PY
  done
}

@test "refuses duplicate keys boolean fractions nonfinite values and duplicate rows" {
  for kind in bool-size fraction-size nonfinite-size duplicate-path; do
    write_complete; make_case "$kind"
    run invoke "$kind" "$TEST_TMPDIR/input.json" --file a-abc
    [ "$status" -eq 2 ]
  done
  printf '%s\n' '{"schema":"DatarimCliInputManifest/v1","schema":"DatarimCliInputManifest/v1"}' >"$TEST_TMPDIR/input.json"
  run invoke duplicate-key "$TEST_TMPDIR/input.json" --file a-abc
  [ "$status" -eq 2 ]
}

@test "refuses absolute traversal file-size and total-size violations" {
  for kind in absolute-path dotdot-path file-limit total-limit; do
    write_complete; make_case "$kind"
    run invoke "$kind" "$TEST_TMPDIR/input.json" --file a-abc
    [ "$status" -eq 2 ]
  done
}

@test "accepts all sixty-four bounded declarations and rejects count overflow" {
  write_complete; make_case sixty-four-files
  run invoke max-valid "$TEST_TMPDIR/input.json" --file p00 --file p01
  [ "$status" -eq 0 ]
  write_complete; make_case count-overflow
  run invoke overflow "$TEST_TMPDIR/input.json" --file p00
  [ "$status" -eq 2 ]
}

@test "refuses more than sixty-four exact path requests" {
  write_complete; make_case sixty-four-files
  local args=() index
  for ((index=0; index<65; index++)); do args+=(--file "p$index"); done
  run invoke selector-overflow "$TEST_TMPDIR/input.json" "${args[@]}"
  [ "$status" -eq 2 ]
  [ "$(cat "$TEST_TMPDIR/selector-overflow.stderr")" = "INPUT_MANIFEST_SELECTION_REFUSED" ]
}

@test "accepts exactly sixty-four requested paths" {
  write_complete; make_case sixty-four-files
  local args=() index
  for ((index=0; index<64; index++)); do args+=(--file "p$(printf '%02d' "$index")"); done
  run invoke selector-max-valid "$TEST_TMPDIR/input.json" "${args[@]}"
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMPDIR/selector-max-valid.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["file_count"]==64 and len(x["files"])==64
PY
}

@test "copies declarations for an existing path without refreshing them" {
  write_complete; make_case existing-path-declaration
  run invoke declared-only "$TEST_TMPDIR/input.json" --file README.md
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMPDIR/declared-only.stdout" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x["files"]==[{"relative_path":"README.md","sha256":"0"*64,"byte_count":999}]
PY
}

@test "refuses malformed UTF-8 oversized and excessively nested input" {
  write_complete
  printf '\377' >"$TEST_TMPDIR/input.json"
  run invoke invalid-utf8 "$TEST_TMPDIR/input.json" --file a-abc
  [ "$status" -eq 2 ]
  python3 - "$TEST_TMPDIR/input.json" <<'PY'
import sys
open(sys.argv[1],"wb").write(b" " * (2*1024*1024+1))
PY
  run invoke oversized "$TEST_TMPDIR/input.json" --file a-abc
  [ "$status" -eq 2 ]
  python3 - "$TEST_TMPDIR/input.json" <<'PY'
import sys
open(sys.argv[1],"w").write("["*1100+"0"+"]"*1100)
PY
  run invoke deeply-nested "$TEST_TMPDIR/input.json" --file a-abc
  [ "$status" -eq 2 ]
}
