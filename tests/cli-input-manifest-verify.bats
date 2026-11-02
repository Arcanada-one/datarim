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
  mkdir -p "$case_dir/fixture"
  cp -a "$FIXTURE_ROOT/." "$case_dir/fixture/"
  printf '%s\n' "$manifest" > "$input"
  chmod 600 "$input"
  local source="$BATS_TEST_DIRNAME/../dev-tools/verify-cli-input-manifest.py"
  local test_source="$BATS_TEST_DIRNAME/cli-input-manifest-verify.bats"
  local started pid ended exit_code fixture_before source_before test_before input_sha
  fixture_before=$(find "$FIXTURE_ROOT" -type f -print0 | sort -z | xargs -0 sha256sum)
  source_before=$(sha256sum "$source" | cut -d' ' -f1)
  test_before=$(sha256sum "$test_source" | cut -d' ' -f1)
  input_sha=$(sha256sum "$input" | cut -d' ' -f1)
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  : > "$raw"; : > "$err"; chmod 600 "$raw" "$err"
  python3 "$source" --root "$FIXTURE_ROOT" < "$input" >"$raw" 2>"$err" &
  pid=$!
  if wait "$pid"; then exit_code=0; else exit_code=$?; fi
  ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local fixture_after source_after test_after
  fixture_after=$(find "$FIXTURE_ROOT" -type f -print0 | sort -z | xargs -0 sha256sum)
  source_after=$(sha256sum "$source" | cut -d' ' -f1)
  test_after=$(sha256sum "$test_source" | cut -d' ' -f1)
  python3 - "$case_dir/receipt.json" "$name" "$pid" "$started" "$ended" "$exit_code" "$PWD" "$FIXTURE_ROOT" "$source" "$source_before" "$source_after" "$test_source" "$test_before" "$test_after" "$input" "$input_sha" "$fixture_before" "$fixture_after" <<'PY'
import json,os,sys
(out,name,pid,start,end,code,cwd,root,source,source_before,source_after,test,test_before,test_after,input_path,input_sha,fixture_before,fixture_after)=sys.argv[1:]
value={"case":name,"pid":int(pid),"started_utc":start,"ended_utc":end,"argv":["python3",source,"--root",root],"cwd":cwd,"exit":int(code),"input_path":input_path,"input_sha256":input_sha,"source_path":source,"source_sha256_before":source_before,"source_sha256_after":source_after,"test_path":test,"test_sha256_before":test_before,"test_sha256_after":test_after,"fixture_root":root,"fixture_sha256_before":fixture_before,"fixture_sha256_after":fixture_after}
assert value["pid"] > 0 and value["started_utc"] and value["ended_utc"]
assert value["source_sha256_before"] == value["source_sha256_after"]
assert value["test_sha256_before"] == value["test_sha256_after"]
assert value["fixture_sha256_before"] == value["fixture_sha256_after"]
with open(out,"w",encoding="utf-8") as f: json.dump(value,f,sort_keys=True); f.write("\n")
os.chmod(out,0o600)
PY
  [[ "$(stat -c '%a' "$raw")" == 600 && "$(stat -c '%a' "$err")" == 600 && "$(stat -c '%a' "$input")" == 600 ]]
  export VERIFY_EXIT=$exit_code VERIFY_RAW=$raw VERIFY_ERR=$err
}

assert_profile() {
  local expected_result=$1 expected_exit=$2 expected_status=$3
  [[ "$VERIFY_EXIT" == "$expected_exit" ]]
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
