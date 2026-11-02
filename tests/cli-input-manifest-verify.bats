#!/usr/bin/env bats

setup_file() {
  local base=${BATS_TEST_DIRNAME}/../.cli-input-manifest-verify-evidence
  export CLI_INPUT_MANIFEST_EVIDENCE_DIR=${CLI_INPUT_MANIFEST_EVIDENCE_DIR:-$base}
  mkdir -p "$CLI_INPUT_MANIFEST_EVIDENCE_DIR"
  [[ -d "$CLI_INPUT_MANIFEST_EVIDENCE_DIR" && -w "$CLI_INPUT_MANIFEST_EVIDENCE_DIR" ]] || return 1
  chmod 700 "$CLI_INPUT_MANIFEST_EVIDENCE_DIR"
  [[ "$CLI_INPUT_MANIFEST_EVIDENCE_DIR" == /* ]] || return 1
  local mode
  mode=$(stat -c '%a' "$CLI_INPUT_MANIFEST_EVIDENCE_DIR")
  [[ "$mode" == 700 ]]
}

setup() {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/sub"
  printf 'alpha\n' > "$root/a.txt"
  printf '\000\377payload' > "$root/sub/b.bin"
  chmod 600 "$root/a.txt" "$root/sub/b.bin"
  export FIXTURE_ROOT="$root"
  export FIXTURE_SHA_A
  export FIXTURE_SHA_B
  export FIXTURE_SIZE_A
  export FIXTURE_SIZE_B
  FIXTURE_SHA_A=$(sha256sum "$root/a.txt" | cut -d' ' -f1)
  FIXTURE_SHA_B=$(sha256sum "$root/sub/b.bin" | cut -d' ' -f1)
  FIXTURE_SIZE_A=$(wc -c < "$root/a.txt" | tr -d ' ')
  FIXTURE_SIZE_B=$(wc -c < "$root/sub/b.bin" | tr -d ' ')
  export MANIFEST=''
}

manifest_one() {
  printf '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"a.txt","sha256":"%s","byte_count":%s}]}\n' "$FIXTURE_SHA_A" "$FIXTURE_SIZE_A"
}

run_verify() {
  local name=$1 manifest=$2
  local case_dir="$CLI_INPUT_MANIFEST_EVIDENCE_DIR/$name"
  local raw="$case_dir/stdout.raw"
  local err="$case_dir/stderr.raw"
  local input="$case_dir/manifest.stdin"
  local marker="$case_dir/recursion-injected.marker"
  mkdir -p "$case_dir/fixture"
  cp -a "$FIXTURE_ROOT/." "$case_dir/fixture/"
  printf '%s\n' "$manifest" > "$input"
  chmod 600 "$input"
  local source="$BATS_TEST_DIRNAME/../dev-tools/verify-cli-input-manifest.py"
  local test_source="$BATS_TEST_DIRNAME/cli-input-manifest-verify.bats"
  local started pid ended exit_code fixture_before source_before test_before input_sha
  local fixture_after source_after test_after input_after fixture_copy_before fixture_copy_after
  local read_counter='' read_counter_sha='' marker_sha=''
  fixture_before=$(cd "$FIXTURE_ROOT" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  fixture_copy_before=$(cd "$case_dir/fixture" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  [[ "$fixture_before" == "$fixture_copy_before" ]]
  source_before=$(sha256sum "$source" | cut -d' ' -f1)
  test_before=$(sha256sum "$test_source" | cut -d' ' -f1)
  input_sha=$(sha256sum "$input" | cut -d' ' -f1)
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  : > "$raw"; : > "$err"; chmod 600 "$raw" "$err"
  if [[ -f "$case_dir/instrument/sitecustomize.py" ]]; then
    read_counter="$case_dir/read-counts.raw"
    : > "$read_counter"; chmod 600 "$read_counter"
    if [[ "${D5_FORCE_RECURSION:-}" == 1 ]]; then
      D5_READ_ROOT="$FIXTURE_ROOT" D5_READ_COUNTER_FILE="$read_counter" D5_GROW_PATH="${D5_GROW_PATH:-}" D5_RECURSION_MARKER="$marker" PYTHONPATH="$case_dir/instrument" \
        python3 "$source" --root "$FIXTURE_ROOT" < "$input" >"$raw" 2>"$err" &
    else
      D5_READ_ROOT="$FIXTURE_ROOT" D5_READ_COUNTER_FILE="$read_counter" D5_GROW_PATH="${D5_GROW_PATH:-}" PYTHONPATH="$case_dir/instrument" \
        python3 "$source" --root "$FIXTURE_ROOT" < "$input" >"$raw" 2>"$err" &
    fi
  else
    python3 "$source" --root "$FIXTURE_ROOT" < "$input" >"$raw" 2>"$err" &
  fi
  pid=$!
  if wait "$pid"; then exit_code=0; else exit_code=$?; fi
  ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fixture_after=$(cd "$FIXTURE_ROOT" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  fixture_copy_after=$(cd "$case_dir/fixture" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  source_after=$(sha256sum "$source" | cut -d' ' -f1)
  test_after=$(sha256sum "$test_source" | cut -d' ' -f1)
  input_after=$(sha256sum "$input" | cut -d' ' -f1)
  if [[ -n "$read_counter" ]]; then read_counter_sha=$(sha256sum "$read_counter" | cut -d' ' -f1); fi
  if [[ -f "$marker" ]]; then marker_sha=$(sha256sum "$marker" | cut -d' ' -f1); fi
  python3 - "$case_dir/receipt.json" "$name" "$pid" "$started" "$ended" "$exit_code" "$PWD" "$FIXTURE_ROOT" "$source" "$source_before" "$source_after" "$test_source" "$test_before" "$test_after" "$input" "$input_sha" "$input_after" "$fixture_before" "$fixture_after" "$case_dir/fixture" "$fixture_copy_before" "$fixture_copy_after" "$read_counter" "$read_counter_sha" "${D5_GROW_PATH:-}" "$marker" "$marker_sha" <<'PY'
import json,os,sys
(out,name,pid,start,end,code,cwd,root,source,source_before,source_after,test,test_before,test_after,input_path,input_sha,input_after,fixture_before,fixture_after,fixture_copy,fixture_copy_before,fixture_copy_after,read_counter,read_counter_sha,grow_path,marker,marker_sha)=sys.argv[1:]
value={"case":name,"pid":int(pid),"started_utc":start,"ended_utc":end,"argv":["python3",source,"--root",root],"cwd":cwd,"exit":int(code),"input_path":input_path,"input_sha256_before":input_sha,"input_sha256_after":input_after,"source_path":source,"source_sha256_before":source_before,"source_sha256_after":source_after,"test_path":test,"test_sha256_before":test_before,"test_sha256_after":test_after,"fixture_root":root,"fixture_sha256_before":fixture_before,"fixture_sha256_after":fixture_after,"fixture_evidence_path":fixture_copy,"fixture_evidence_sha256_before":fixture_copy_before,"fixture_evidence_sha256_after":fixture_copy_after,"controlled_growth_path":grow_path or None,"read_counter_path":read_counter or None,"read_counter_sha256":read_counter_sha or None,"recursion_injection_marker":marker if marker_sha else None,"recursion_marker_sha256":marker_sha or None}
with open(out,"w",encoding="utf-8") as f: json.dump(value,f,sort_keys=True); f.write("\n")
os.chmod(out,0o600)
assert value["pid"] > 0 and value["started_utc"] and value["ended_utc"]
assert value["input_sha256_before"] == value["input_sha256_after"]
assert value["source_sha256_before"] == value["source_sha256_after"]
assert value["test_sha256_before"] == value["test_sha256_after"]
assert value["fixture_evidence_sha256_before"] == value["fixture_evidence_sha256_after"]
assert value["fixture_sha256_before"] == value["fixture_evidence_sha256_before"]
if not grow_path:
    assert value["fixture_sha256_before"] == value["fixture_sha256_after"]
PY
  [[ "$(stat -c '%a' "$raw")" == 600 && "$(stat -c '%a' "$err")" == 600 && "$(stat -c '%a' "$input")" == 600 ]]
  [[ -z "$read_counter" || "$(stat -c '%a' "$read_counter")" == 600 ]]
  export VERIFY_EXIT=$exit_code VERIFY_RAW=$raw VERIFY_ERR=$err
  export VERIFY_RECEIPT="$case_dir/receipt.json" VERIFY_COUNTER="$read_counter"
}

write_read_instrumentation() {
  local case_dir="$CLI_INPUT_MANIFEST_EVIDENCE_DIR/$1"
  mkdir -p "$case_dir/instrument"
  cat > "$case_dir/instrument/sitecustomize.py" <<'PY'
import atexit
import json
import os

_root = os.path.realpath(os.environ["D5_READ_ROOT"]) + os.sep
_target = os.environ["D5_READ_COUNTER_FILE"]
_recursion_marker = os.environ.get("D5_RECURSION_MARKER", "")
_original_read = os.read
_original_fstat = os.fstat
_original_json_loads = json.loads
_grow_path = os.environ.get("D5_GROW_PATH", "")
_counts = {}
_grew = False
_recursion_calls = 0

def _controlled_json_loads(*args, **kwargs):
    global _recursion_calls
    if _recursion_marker:
        _recursion_calls += 1
        fd = os.open(_recursion_marker, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, (str(_recursion_calls) + "\n").encode("ascii"))
        finally:
            os.close(fd)
        raise RecursionError("controlled JSON decoder exhaustion")
    return _original_json_loads(*args, **kwargs)

json.loads = _controlled_json_loads

def _counted_read(fd, size):
    data = _original_read(fd, size)
    try:
        path = os.readlink(f"/proc/self/fd/{fd}")
    except OSError:
        return data
    if path.startswith(_root):
        _counts[path] = _counts.get(path, 0) + len(data)
    return data

os.read = _counted_read

def _grow_after_snapshot(fd):
    global _grew
    snapshot = _original_fstat(fd)
    if _grow_path and not _grew:
        try:
            path = os.readlink(f"/proc/self/fd/{fd}")
        except OSError:
            return snapshot
        if path == _root + _grow_path:
            with open(path, "ab") as stream:
                stream.write(b"\x00")
            _grew = True
    return snapshot

os.fstat = _grow_after_snapshot

@atexit.register
def _persist_counts():
    fd = os.open(_target, os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump({"reads": _counts, "total_bytes": sum(_counts.values()), "grew_after_fstat": _grew, "growth_path": _grow_path or None}, stream, sort_keys=True)
        stream.write("\n")
PY
  chmod 600 "$case_dir/instrument/sitecustomize.py"
}

prepare_aggregate_fixture() {
  rm -f "$FIXTURE_ROOT/a.txt" "$FIXTURE_ROOT/sub/b.bin"
  rmdir "$FIXTURE_ROOT/sub"
  for index in $(seq 1 16); do
    local name
    printf -v name 'part-%02d.bin' "$index"
    head -c 1048576 /dev/zero > "$FIXTURE_ROOT/$name"
    chmod 600 "$FIXTURE_ROOT/$name"
  done
}

manifest_all() {
  python3 - "$FIXTURE_ROOT" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
entries=[]
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    data=path.read_bytes()
    entries.append({"relative_path":path.relative_to(root).as_posix(),"sha256":hashlib.sha256(data).hexdigest(),"byte_count":len(data)})
print(json.dumps({"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":len(entries),"file_count_status":"MEASURED","files":entries},separators=(",",":")))
PY
}

assert_profile() {
  local expected_result=$1 expected_exit=$2 expected_status=$3
  if [[ "$VERIFY_EXIT" != "$expected_exit" ]]; then
    python3 - "${VERIFY_EXIT:-}" "$expected_exit" "${VERIFY_RECEIPT:-}" "${VERIFY_RAW:-}" "${VERIFY_ERR:-}" >&2 <<'PY' || true
import hashlib,json,pathlib,sys
actual,expected,receipt_path,stdout_path,stderr_path=sys.argv[1:]
def numeric(value):
    return value if value.isascii() and value.isdigit() else "NOT_RETAINED"
def stream(path):
    try:
        data=pathlib.Path(path).read_bytes()
    except (OSError,ValueError):
        return "NOT_RETAINED","NOT_RETAINED"
    return str(len(data)),hashlib.sha256(data).hexdigest()
try:
    receipt=json.loads(pathlib.Path(receipt_path).read_text(encoding="utf-8"))
    raw_pid=receipt.get("pid") if isinstance(receipt,dict) else None
    raw_exit=receipt.get("exit") if isinstance(receipt,dict) else None
    pid=str(raw_pid) if type(raw_pid) is int and raw_pid > 0 and type(raw_exit) is int and numeric(actual) != "NOT_RETAINED" and raw_exit == int(actual) else "NOT_RETAINED"
except (OSError,ValueError,TypeError):
    pid="NOT_RETAINED"
out_bytes,out_sha=stream(stdout_path)
err_bytes,err_sha=stream(stderr_path)
line=(f"F4_TEST_FAILURE actual_exit={numeric(actual)} expected_exit={numeric(expected)} "
      f"child_pid={pid} stdout_bytes={out_bytes} stdout_sha256={out_sha} "
      f"stderr_bytes={err_bytes} stderr_sha256={err_sha}")
if len(line.encode("ascii")) > 1024:
    line="F4_TEST_FAILURE actual_exit=NOT_RETAINED expected_exit=NOT_RETAINED child_pid=NOT_RETAINED stdout_bytes=NOT_RETAINED stdout_sha256=NOT_RETAINED stderr_bytes=NOT_RETAINED stderr_sha256=NOT_RETAINED"
sys.stderr.write(line+"\n")
PY
    return 1
  fi
  python3 - "$VERIFY_RAW" "$expected_result" "$expected_exit" "$expected_status" <<'PY'
import json,sys
p, result, code, status = sys.argv[1:]
with open(p, encoding="utf-8") as f: value=json.load(f)
assert set(value) == {"schema","result","exit_code","diagnostic_codes","file_count","file_count_status","changed_paths"}
assert value["schema"] == "DatarimCliInputManifestVerification/v1"
assert value["result"] == result and value["exit_code"] == int(code)
assert value["file_count_status"] == status
if status == "NOT_MEASURED":
    assert value["file_count"] is None and value["changed_paths"] == []
PY
}

@test "matching selected bytes produce MATCHED without exposing file content" {
  local before after
  before=$(sha256sum "$FIXTURE_ROOT/a.txt" "$FIXTURE_ROOT/sub/b.bin")
  run_verify matched "$(manifest_one)"
  assert_profile MATCHED 0 MEASURED
  [[ ! -s "$VERIFY_ERR" ]]
  ! grep -q 'alpha' "$VERIFY_RAW"
  after=$(sha256sum "$FIXTURE_ROOT/a.txt" "$FIXTURE_ROOT/sub/b.bin")
  [[ "$before" == "$after" ]]
}

@test "changed bytes are measured only after a complete safe read" {
  printf 'changed\n' > "$FIXTURE_ROOT/a.txt"
  run_verify changed "$(manifest_one)"
  assert_profile CHANGED 1 MEASURED
  python3 - "$VERIFY_RAW" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])); assert v["diagnostic_codes"] == ["INPUT_MANIFEST_BYTES_CHANGED"]
assert v["changed_paths"] == ["a.txt"] and v["file_count"] == 1
PY
}

@test "missing selected path is a fixed refusal with no partial result" {
  local sha size
  sha=$(printf x | sha256sum | cut -d' ' -f1); size=1
  run_verify missing "$(printf '{\"schema\":\"DatarimCliInputManifest/v1\",\"result\":\"COMPLETE\",\"exit_code\":0,\"diagnostic_codes\":[],\"file_count\":2,\"file_count_status\":\"MEASURED\",\"files\":[{\"relative_path\":\"a.txt\",\"sha256\":\"%s\",\"byte_count\":%s},{\"relative_path\":\"missing.txt\",\"sha256\":\"%s\",\"byte_count\":1}]}\n' "$FIXTURE_SHA_A" "$FIXTURE_SIZE_A" "$sha")"
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  python3 - "$VERIFY_RAW" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])); assert v["diagnostic_codes"] == ["INPUT_MANIFEST_VERIFICATION_REFUSED"]
PY
}

@test "duplicate object keys are refused" {
  run_verify duplicate '{"schema":"DatarimCliInputManifest/v1","schema":"x"}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "boolean byte count is refused" {
  run_verify boolean '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"a.txt","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":true}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "integral decimal byte count is accepted" {
  run_verify decimal "$(printf '{\"schema\":\"DatarimCliInputManifest/v1\",\"result\":\"COMPLETE\",\"exit_code\":0,\"diagnostic_codes\":[],\"file_count\":1,\"file_count_status\":\"MEASURED\",\"files\":[{\"relative_path\":\"a.txt\",\"sha256\":\"%s\",\"byte_count\":%s.0}]}\n' "$FIXTURE_SHA_A" "$FIXTURE_SIZE_A")"
  assert_profile MATCHED 0 MEASURED
}

@test "non-finite numbers are refused" {
  run_verify nonfinite '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"a.txt","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":NaN}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "one mebibyte boundary matches and one byte over is refused" {
  head -c 1048576 /dev/zero > "$FIXTURE_ROOT/a.txt"
  FIXTURE_SHA_A=$(sha256sum "$FIXTURE_ROOT/a.txt" | cut -d' ' -f1)
  FIXTURE_SIZE_A=1048576
  run_verify maximum_file "$(manifest_one)"
  assert_profile MATCHED 0 MEASURED
  printf '\0' >> "$FIXTURE_ROOT/a.txt"
  run_verify oversized_file "$(manifest_one)"
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "huge integral decimal is refused before integer conversion" {
  run_verify huge_decimal '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"a.txt","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1e1000000000}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "canonical path boundaries and hostile control data are refused" {
  run_verify traversal '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"../a.txt","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  run_verify hostile '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"x\u0000secret","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
}

@test "aggregate actual-byte budget accepts an exact sixteen mebibyte snapshot" {
  prepare_aggregate_fixture
  write_read_instrumentation aggregate_exact
  run_verify aggregate_exact "$(manifest_all)"
  assert_profile MATCHED 0 MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_COUNTER" "$VERIFY_RECEIPT" <<'PY'
import json,sys
result=json.load(open(sys.argv[1],encoding="utf-8"))
counter=json.load(open(sys.argv[2],encoding="utf-8"))
receipt=json.load(open(sys.argv[3],encoding="utf-8"))
assert result["file_count"] == 16 and result["changed_paths"] == []
assert counter["total_bytes"] == 16 * 1024 * 1024
assert len(counter["reads"]) == 16 and all(n == 1024 * 1024 for n in counter["reads"].values())
assert receipt["read_counter_sha256"]
PY
}

@test "aggregate actual-byte budget refuses the next nonempty file without reading it" {
  prepare_aggregate_fixture
  printf 'z' > "$FIXTURE_ROOT/zz-after-budget.bin"
  write_read_instrumentation aggregate_over_budget
  local manifest
  manifest=$(manifest_all)
  manifest=$(python3 - "$manifest" <<'PY'
import hashlib,json,sys
value=json.loads(sys.argv[1])
extra=next(item for item in value["files"] if item["relative_path"] == "zz-after-budget.bin")
extra["byte_count"]=0
extra["sha256"]=hashlib.sha256(b"").hexdigest()
print(json.dumps(value,separators=(",",":")))
PY
)
  run_verify aggregate_over_budget "$manifest"
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_COUNTER" "$VERIFY_RECEIPT" "$FIXTURE_ROOT/zz-after-budget.bin" <<'PY'
import json,sys
result=json.load(open(sys.argv[1],encoding="utf-8"))
counter=json.load(open(sys.argv[2],encoding="utf-8"))
receipt=json.load(open(sys.argv[3],encoding="utf-8"))
extra=sys.argv[4]
assert result["diagnostic_codes"] == ["INPUT_MANIFEST_VERIFICATION_REFUSED"]
assert counter["total_bytes"] == 16 * 1024 * 1024
assert counter["reads"].get(extra,0) == 0
assert receipt["read_counter_sha256"] and receipt["fixture_evidence_path"]
PY
  [[ ! -s "$VERIFY_ERR" ]]
}

@test "F2 refuses post-fstat growth at the per-file payload cap after one detector byte" {
  head -c 1048576 /dev/zero > "$FIXTURE_ROOT/a.txt"
  FIXTURE_SHA_A=$(sha256sum "$FIXTURE_ROOT/a.txt" | cut -d' ' -f1)
  FIXTURE_SIZE_A=1048576
  write_read_instrumentation f2_per_file_growth
  export D5_GROW_PATH=a.txt
  run_verify f2_per_file_growth "$(manifest_one)"
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_COUNTER" "$VERIFY_RECEIPT" "$FIXTURE_ROOT/a.txt" "$CLI_INPUT_MANIFEST_EVIDENCE_DIR/f2_per_file_growth/fixture/a.txt" <<'PY'
import json,pathlib,sys
raw,counter_path,receipt_path,fixture,evidence=map(pathlib.Path,sys.argv[1:])
result=json.loads(raw.read_text())
counter=json.loads(counter_path.read_text())
receipt=json.loads(receipt_path.read_text())
assert result["diagnostic_codes"] == ["INPUT_MANIFEST_VERIFICATION_REFUSED"]
assert counter["grew_after_fstat"] is True and counter["growth_path"] == "a.txt"
assert counter["total_bytes"] == 1024 * 1024 + 1
assert sum(counter["reads"].values()) == counter["total_bytes"]
assert [n for path,n in counter["reads"].items() if path.endswith("/a.txt")] == [1024 * 1024 + 1]
assert evidence.read_bytes() == b"\x00" * (1024 * 1024)
assert fixture.read_bytes() == evidence.read_bytes() + b"\x00"
assert receipt["fixture_sha256_before"] == receipt["fixture_evidence_sha256_before"]
assert receipt["fixture_evidence_sha256_before"] == receipt["fixture_evidence_sha256_after"]
assert receipt["input_sha256_before"] == receipt["input_sha256_after"]
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["test_sha256_before"] == receipt["test_sha256_after"]
PY
  [[ ! -s "$VERIFY_ERR" ]]
}

@test "F2 refuses post-fstat growth at the aggregate payload cap after one detector byte" {
  prepare_aggregate_fixture
  write_read_instrumentation f2_aggregate_growth
  export D5_GROW_PATH=part-16.bin
  local manifest
  manifest=$(manifest_all)
  run_verify f2_aggregate_growth "$manifest"
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_COUNTER" "$VERIFY_RECEIPT" "$FIXTURE_ROOT/part-16.bin" "$CLI_INPUT_MANIFEST_EVIDENCE_DIR/f2_aggregate_growth/fixture/part-16.bin" <<'PY'
import json,pathlib,sys
raw,counter_path,receipt_path,fixture,evidence=map(pathlib.Path,sys.argv[1:])
result=json.loads(raw.read_text())
counter=json.loads(counter_path.read_text())
receipt=json.loads(receipt_path.read_text())
assert result["diagnostic_codes"] == ["INPUT_MANIFEST_VERIFICATION_REFUSED"]
assert counter["grew_after_fstat"] is True and counter["growth_path"] == "part-16.bin"
assert counter["total_bytes"] == 16 * 1024 * 1024 + 1
assert sum(counter["reads"].values()) == counter["total_bytes"]
assert [n for path,n in counter["reads"].items() if path.endswith("/part-16.bin")] == [1024 * 1024 + 1]
assert evidence.read_bytes() == b"\x00" * (1024 * 1024)
assert fixture.read_bytes() == evidence.read_bytes() + b"\x00"
assert receipt["fixture_sha256_before"] == receipt["fixture_evidence_sha256_before"]
assert receipt["fixture_evidence_sha256_before"] == receipt["fixture_evidence_sha256_after"]
assert receipt["input_sha256_before"] == receipt["input_sha256_after"]
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["test_sha256_before"] == receipt["test_sha256_after"]
PY
  [[ ! -s "$VERIFY_ERR" ]]
}

@test "F2 accepts an exact sixteen mebibyte payload and measures EOF at the boundary" {
  prepare_aggregate_fixture
  write_read_instrumentation f2_aggregate_exact
  unset D5_GROW_PATH
  run_verify f2_aggregate_exact "$(manifest_all)"
  assert_profile MATCHED 0 MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_COUNTER" "$VERIFY_RECEIPT" <<'PY'
import json,sys
result=json.load(open(sys.argv[1],encoding="utf-8"))
counter=json.load(open(sys.argv[2],encoding="utf-8"))
receipt=json.load(open(sys.argv[3],encoding="utf-8"))
assert result["file_count"] == 16 and result["changed_paths"] == []
assert counter["total_bytes"] == 16 * 1024 * 1024
assert len(counter["reads"]) == 16 and all(n == 1024 * 1024 for n in counter["reads"].values())
assert counter["grew_after_fstat"] is False
assert receipt["input_sha256_before"] == receipt["input_sha256_after"]
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["test_sha256_before"] == receipt["test_sha256_after"]
assert receipt["fixture_sha256_before"] == receipt["fixture_sha256_after"]
assert receipt["fixture_evidence_sha256_before"] == receipt["fixture_evidence_sha256_after"]
PY
  [[ ! -s "$VERIFY_ERR" ]]
}

@test "controlled JSON decoder RecursionError reaches the fixed refusal handler" {
  write_read_instrumentation recursion_oracle
  export D5_FORCE_RECURSION=1
  run_verify recursion_oracle '{"schema":"DatarimCliInputManifest/v1","result":"COMPLETE","exit_code":0,"diagnostic_codes":[],"file_count":1,"file_count_status":"MEASURED","files":[{"relative_path":"a.txt","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1}]}'
  assert_profile INPUT_REFUSED 2 NOT_MEASURED
  python3 - "$VERIFY_RAW" "$VERIFY_ERR" "$VERIFY_RECEIPT" "$CLI_INPUT_MANIFEST_EVIDENCE_DIR/recursion_oracle/recursion-injected.marker" <<'PY'
import hashlib,json,pathlib,sys
raw_path,err_path,receipt_path,marker_path=map(pathlib.Path,sys.argv[1:])
value=json.loads(raw_path.read_text(encoding="utf-8"))
receipt=json.loads(receipt_path.read_text(encoding="utf-8"))
marker=marker_path.read_bytes()
assert value == {"schema":"DatarimCliInputManifestVerification/v1","result":"INPUT_REFUSED","exit_code":2,"diagnostic_codes":["INPUT_MANIFEST_VERIFICATION_REFUSED"],"file_count":None,"file_count_status":"NOT_MEASURED","changed_paths":[]}
assert marker == b"1\n" and marker_path.stat().st_mode & 0o777 == 0o600
assert receipt["exit"] == 2 and receipt["recursion_injection_marker"] == str(marker_path)
assert receipt["recursion_marker_sha256"] == hashlib.sha256(marker).hexdigest()
assert receipt["source_sha256_before"] == receipt["source_sha256_after"]
assert receipt["test_sha256_before"] == receipt["test_sha256_after"]
assert receipt["input_sha256_before"] == receipt["input_sha256_after"]
assert receipt["fixture_sha256_before"] == receipt["fixture_sha256_after"]
assert receipt["fixture_evidence_sha256_before"] == receipt["fixture_evidence_sha256_after"]
assert not err_path.read_bytes()
assert raw_path.read_bytes().endswith(b"\n")
PY
}

@test "profile exit mismatch emits bounded typed child diagnostic" {
  local case_dir="$CLI_INPUT_MANIFEST_EVIDENCE_DIR/failure_diagnostic"
  local fixture="$case_dir/fixture"
  local source="$BATS_TEST_DIRNAME/../dev-tools/verify-cli-input-manifest.py"
  local test_source="$BATS_TEST_DIRNAME/cli-input-manifest-verify.bats"
  mkdir -p "$fixture"
  chmod 700 "$case_dir" "$fixture"
  printf 'F4 synthetic fixture\n' > "$fixture/input.txt"
  chmod 600 "$fixture/input.txt"
  python3 - "$case_dir" "$PWD" "$source" "$test_source" "$fixture/input.txt" <<'PY'
import datetime,hashlib,json,os,pathlib,subprocess,sys
case_dir,cwd,source,test_source,fixture=sys.argv[1:]
root=pathlib.Path(case_dir)
if root.stat().st_mode & 0o777 != 0o700:
    raise SystemExit("evidence directory mode preflight failed")
paths={name:root/name for name in ("stdout.raw","stderr.raw","receipt.json")}
for path in paths.values():
    fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    os.close(fd)
sample={"case":"failure_diagnostic","pid":1,"started_utc":"2000-01-01T00:00:00Z","ended_utc":"2000-01-01T00:00:01Z","argv":["synthetic"],"cwd":cwd,"exit":23,"stdout_bytes":1,"stdout_sha256":"0"*64,"stderr_bytes":1,"stderr_sha256":"1"*64,"source_sha256_before":"2"*64,"source_sha256_after":"2"*64,"test_sha256_before":"3"*64,"test_sha256_after":"3"*64,"fixture_sha256_before":"4"*64,"fixture_sha256_after":"4"*64}
probe=(json.dumps(sample,sort_keys=True,separators=(",",":"))+"\n").encode("utf-8")
if not probe.endswith(b"\n") or probe.endswith(b"\\n") or json.loads(probe)!=sample:
    raise SystemExit("JSON receipt serialization preflight failed")
def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
def write_durable(path,data):
    with open(path,"wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(path,0o600)
source_before=sha(source)
test_before=sha(test_source)
fixture_before=sha(fixture)
started=datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
child_code=("import sys; sys.stdout.buffer.write(b'F4_PRIVATE_PAYLOAD_SENTINEL\\n'); "
            "sys.stderr.buffer.write(b'F4_PRIVATE_PATH_SENTINEL '+sys.argv[1].encode()+b'\\n'); "
            "raise SystemExit(23)")
argv=[sys.executable,"-c",child_code,str(pathlib.Path(fixture).resolve())]
proc=subprocess.Popen(argv,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
stdout,stderr=proc.communicate()
ended=datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z")
write_durable(paths["stdout.raw"],stdout)
write_durable(paths["stderr.raw"],stderr)
source_after=sha(source)
test_after=sha(test_source)
fixture_after=sha(fixture)
record={"case":"failure_diagnostic","pid":proc.pid,"started_utc":started,"ended_utc":ended,"argv":argv,"cwd":cwd,"exit":proc.returncode,"stdout_path":str(paths["stdout.raw"]),"stdout_bytes":len(stdout),"stdout_sha256":hashlib.sha256(stdout).hexdigest(),"stderr_path":str(paths["stderr.raw"]),"stderr_bytes":len(stderr),"stderr_sha256":hashlib.sha256(stderr).hexdigest(),"source_path":source,"source_sha256_before":source_before,"source_sha256_after":source_after,"test_path":test_source,"test_sha256_before":test_before,"test_sha256_after":test_after,"fixture_path":fixture,"fixture_sha256_before":fixture_before,"fixture_sha256_after":fixture_after}
encoded=(json.dumps(record,sort_keys=True,separators=(",",":"))+"\n").encode("utf-8")
json.loads(encoded)
write_durable(paths["receipt.json"],encoded)
if proc.returncode != 23:
    raise SystemExit("synthetic process outcome was not the allocated nonzero code")
PY
  local receipt="$case_dir/receipt.json"
  export VERIFY_RECEIPT="$receipt" VERIFY_RAW="$case_dir/stdout.raw" VERIFY_ERR="$case_dir/stderr.raw"
  VERIFY_EXIT=$(python3 - "$receipt" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8"))["exit"])
PY
)
  export VERIFY_EXIT
  local assertion_stdout="$case_dir/assertion.stdout.raw"
  local assertion_stderr="$case_dir/assertion.stderr.raw"
  : > "$assertion_stdout"; : > "$assertion_stderr"
  chmod 600 "$assertion_stdout" "$assertion_stderr"
  local assertion_status=0
  if assert_profile MATCHED 0 MEASURED >"$assertion_stdout" 2>"$assertion_stderr"; then
    assertion_status=0
  else
    assertion_status=$?
  fi
  [[ "$assertion_status" -eq 1 ]]
  [[ ! -s "$assertion_stdout" ]]
  local pid stdout_bytes stdout_sha stderr_bytes stderr_sha diagnostic
  read -r pid stdout_bytes stdout_sha stderr_bytes stderr_sha < <(python3 - "$receipt" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding="utf-8"))
print(r["pid"],r["stdout_bytes"],r["stdout_sha256"],r["stderr_bytes"],r["stderr_sha256"])
PY
)
  diagnostic=$(cat "$assertion_stderr")
  [[ "$diagnostic" == "F4_TEST_FAILURE actual_exit=23 expected_exit=0 child_pid=$pid stdout_bytes=$stdout_bytes stdout_sha256=$stdout_sha stderr_bytes=$stderr_bytes stderr_sha256=$stderr_sha" ]]
  [[ "${#diagnostic}" -le 1024 ]]
  [[ "$diagnostic" != *F4_PRIVATE_PAYLOAD_SENTINEL* ]]
  [[ "$diagnostic" != *F4_PRIVATE_PATH_SENTINEL* ]]
  [[ "$diagnostic" != *"$fixture"* ]]
  [[ "$(stat -c '%a' "$case_dir/receipt.json")" == 600 ]]
  [[ "$(stat -c '%a' "$case_dir/stdout.raw")" == 600 ]]
  [[ "$(stat -c '%a' "$case_dir/stderr.raw")" == 600 ]]
  python3 - "$receipt" "$case_dir" "$source" "$test_source" "$fixture/input.txt" <<'PY'
import hashlib,json,pathlib,sys
receipt,case_dir,source,test_source,fixture=map(pathlib.Path,sys.argv[1:])
r=json.loads(receipt.read_text(encoding="utf-8"))
assert r["exit"] == 23 and type(r["pid"]) is int and r["pid"] > 0
for stream in ("stdout","stderr"):
    data=(pathlib.Path(case_dir)/(stream+".raw")).read_bytes()
    assert r[stream+"_bytes"] == len(data)
    assert r[stream+"_sha256"] == hashlib.sha256(data).hexdigest()
for key,path in (("source",source),("test",test_source),("fixture",fixture)):
    expected=r[key+"_sha256_before"]
    assert r[key+"_sha256_after"] == expected == hashlib.sha256(path.read_bytes()).hexdigest()
assert r["started_utc"] and r["ended_utc"] and r["argv"] and r["cwd"]
PY
}
