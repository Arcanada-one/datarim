#!/usr/bin/env bats
# Synthetic-only CLI contract tests for the opt-in module-manifest summary.

setup() {
    umask 077
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    VALIDATOR="$REPO/dev-tools/check-module-manifest.sh"
    EVIDENCE="${ROLE_MODULE_MANIFEST_EVIDENCE_DIR:-$BATS_TEST_TMPDIR/module-manifest-summary}"
    INVOKE_CWD="$REPO"
    mkdir -p "$EVIDENCE"
}

write_fixture() {
    local root="$1" scenario="${2:-valid}"
    local schema_version=1
    mkdir -p "$root/pack"
    if [ "$scenario" = "invalid-version" ]; then
        schema_version=2
    fi
    cat > "$root/pack/module.yaml" <<EOF
schema_version: $schema_version
module:
  id: synthetic-pack
  title: Synthetic pack
  version: 1.2.3
  description: Synthetic fixture only.
skills:
EOF

    if [ "$scenario" != "empty-skills" ]; then
        cat >> "$root/pack/module.yaml" <<'EOF'
  - name: alpha
    version: 1.0.0
    summary: Synthetic skill.
EOF
    fi

    case "$scenario" in
        undeclared-requires)
            cat >> "$root/pack/module.yaml" <<'EOF'
    requires:
      - missing-dependency
EOF
            ;;
        valid|invalid-version|empty-skills|missing-skill) ;;
        *) return 2 ;;
    esac

    if [ "$scenario" != "missing-skill" ]; then
        mkdir -p "$root/pack/skills/alpha"
        cat > "$root/pack/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: Synthetic fixture only.
---
# Synthetic skill
EOF
    fi
}

source_manifest() {
    python3 - "$REPO" <<'PY'
import hashlib, json, pathlib, sys
repo = pathlib.Path(sys.argv[1])
rows = []
for rel in ("dev-tools/check-module-manifest.sh", "tests/module-manifest-summary.bats", "documentation/reference/module-manifest-summary.md"):
    path = repo / rel
    data = path.read_bytes()
    rows.append({"path": rel, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "mode": format(path.stat().st_mode & 0o777, "04o")})
print(json.dumps(rows, sort_keys=True, separators=(",", ":")))
PY
}

fixture_manifest() {
    python3 - "$1" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in sorted(root.rglob("*")):
    rel = path.relative_to(root).as_posix()
    st = path.lstat()
    row = {"path": rel, "mode": format(st.st_mode & 0o777, "04o")}
    if path.is_symlink():
        row.update(kind="symlink", target_sha256=hashlib.sha256(path.readlink().as_posix().encode()).hexdigest())
    elif path.is_file():
        data = path.read_bytes()
        row.update(kind="file", bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    elif path.is_dir():
        row["kind"] = "directory"
    else:
        row["kind"] = "special"
    rows.append(row)
print(json.dumps(rows, sort_keys=True, separators=(",", ":")))
PY
}

invoke_cli() {
    local case_name="$1" fixture="$2"
    shift 2
    local case_dir="$EVIDENCE/$case_name"
    mkdir -m 700 "$case_dir" || return 1
    CASE_DIR="$case_dir"
    CASE_MANIFEST="${1:-}"
    CASE_STDOUT="$case_dir/stdout.bin"
    CASE_STDERR="$case_dir/stderr.bin"
    CASE_EXIT=""
    local argv_nul="$case_dir/argv.nul"
    local source_before="$case_dir/source-before.json"
    local fixture_before="$case_dir/fixture-before.json"
    local source_after="$case_dir/source-after.json"
    local fixture_after="$case_dir/fixture-after.json"
    local started cwd

    printf '%s\0' "$VALIDATOR" "$@" > "$argv_nul"
    source_manifest > "$source_before" || return 1
    fixture_manifest "$fixture" > "$fixture_before" || return 1
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cwd="$(cd "$INVOKE_CWD" && pwd -P)" || return 1
    python3 - "$case_dir/start.json" "$case_name" "$started" "$cwd" "$argv_nul" "$VALIDATOR" "$@" <<'PY'
import json, os, sys
path, name, started, cwd, argv_nul, *argv = sys.argv[1:]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump({"case": name, "start_utc": started, "cwd": cwd, "argv": argv, "argv_nul_path": argv_nul}, stream, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
PY
    : > "$CASE_STDOUT"
    : > "$CASE_STDERR"
    chmod 600 "$CASE_STDOUT" "$CASE_STDERR"
    (
        cd "$cwd" || exit 125
        exec "$VALIDATOR" "$@"
    ) > "$CASE_STDOUT" 2> "$CASE_STDERR" &
    local child_pid=$!
    printf '%s\n' "$child_pid" > "$case_dir/child.pid"
    if wait "$child_pid"; then
        CASE_EXIT=0
    else
        CASE_EXIT=$?
    fi

    source_manifest > "$source_after" || return 1
    fixture_manifest "$fixture" > "$fixture_after" || return 1
    local ended
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 - "$case_dir/result.json" "$case_name" "$started" "$ended" "$cwd" "$child_pid" "$CASE_EXIT" "$argv_nul" "$CASE_STDOUT" "$CASE_STDERR" "$source_before" "$source_after" "$fixture_before" "$fixture_after" <<'PY'
import hashlib, json, os, pathlib, sys
(dest, name, started, ended, cwd, pid, exit_code, argv_nul, stdout, stderr,
 source_before, source_after, fixture_before, fixture_after) = sys.argv[1:]
def load(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
def file_record(path):
    data = pathlib.Path(path).read_bytes()
    return {"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "mode": format(pathlib.Path(path).stat().st_mode & 0o777, "04o")}
start = load(str(pathlib.Path(dest).with_name("start.json")))
sb, sa, fb, fa = (load(p) for p in (source_before, source_after, fixture_before, fixture_after))
record = {
    "case": name, "start_utc": started, "end_utc": ended, "cwd": cwd,
    "pid": int(pid), "argv": start["argv"], "argv_nul": file_record(argv_nul),
    "exit_code": int(exit_code), "stdout": file_record(stdout), "stderr": file_record(stderr),
    "source_before": sb, "source_after": sa, "source_unchanged": sb == sa,
    "fixture_before": fb, "fixture_after": fa, "fixture_unchanged": fb == fa,
}
fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(record, stream, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
PY
}

assert_record_integrity() {
    python3 - "$CASE_DIR/result.json" "$REPO" "$INVOKE_CWD" <<'PY'
import hashlib, json, pathlib, stat, sys
result_path = pathlib.Path(sys.argv[1])
repo, expected_cwd = sys.argv[2:]
record = json.loads(result_path.read_text(encoding="utf-8"))
if type(record.get("pid")) is not int or record["pid"] < 1 or type(record.get("exit_code")) is not int:
    raise SystemExit(1)
if not record.get("start_utc") or not record.get("end_utc") or not record.get("argv") or record.get("cwd") != str(pathlib.Path(expected_cwd).resolve()):
    raise SystemExit(1)
if len(record.get("source_before", [])) != 3 or record["source_before"] != record.get("source_after") or record.get("source_unchanged") is not True:
    raise SystemExit(1)
if record.get("fixture_before") != record.get("fixture_after") or record.get("fixture_unchanged") is not True:
    raise SystemExit(1)
if record.get("argv_nul", {}).get("path") is None or pathlib.Path(record["argv_nul"]["path"]).read_bytes() != b"".join(arg.encode() + b"\0" for arg in record["argv"]):
    raise SystemExit(1)
for key in ("stdout", "stderr", "argv_nul"):
    row = record[key]
    path = pathlib.Path(row["path"])
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != row["sha256"] or len(data) != row["bytes"] or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise SystemExit(1)
for name in ("start.json", "result.json", "source-before.json", "source-after.json", "fixture-before.json", "fixture-after.json", "child.pid"):
    path = result_path.with_name(name)
    if not path.is_file() or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise SystemExit(1)
if result_path.with_name("child.pid").read_text(encoding="ascii").strip() != str(record["pid"]):
    raise SystemExit(1)
PY
}

assert_summary() {
    local result="$1" exit_code="$2" diagnostic="$3" skill_count="$4" warning_count="$5" forbidden="$6"
    python3 - "$CASE_STDOUT" "$CASE_EXIT" "$result" "$exit_code" "$diagnostic" "$skill_count" "$warning_count" "$forbidden" <<'PY'
import json, pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
actual_exit, expected_result, expected_exit, diagnostic, skills, warnings, forbidden = sys.argv[2:]
if not raw.endswith(b"\n") or raw.count(b"\n") != 1:
    raise SystemExit(1)
try:
    value = json.loads(raw)
except Exception:
    raise SystemExit(1)
expected_keys = {"schema", "result", "exit_code", "diagnostic_codes", "skill_count", "skill_count_status", "warning_count", "warning_count_status"}
if not isinstance(value, dict) or set(value) != expected_keys:
    raise SystemExit(1)
if value["schema"] != "DatarimModuleManifestSummary/v1" or value["result"] != expected_result:
    raise SystemExit(1)
if type(value["exit_code"]) is not int or value["exit_code"] != int(expected_exit) or int(actual_exit) != int(expected_exit):
    raise SystemExit(1)
expected_codes = [] if diagnostic == "" else [diagnostic]
if value["diagnostic_codes"] != expected_codes:
    raise SystemExit(1)
for key, expected in (("skill_count", skills), ("warning_count", warnings)):
    status_key = key + "_status"
    if expected == "null":
        if value[key] is not None or value[status_key] != "NOT_MEASURED":
            raise SystemExit(1)
    elif type(value[key]) is not int or value[key] != int(expected) or value[status_key] != "MEASURED":
        raise SystemExit(1)
if forbidden and forbidden.encode() in raw:
    raise SystemExit(1)
PY
}

assert_summary_has_no_handled_diagnostics() {
    [ ! -s "$CASE_STDERR" ]
}

assert_default_valid() {
    local expected="$CASE_DIR/default.expected"
    printf 'RESULT: VALID (%s) — schema_version=1, module=synthetic-pack@1.2.3, skills=1\n' "$CASE_MANIFEST" > "$expected"
    chmod 600 "$expected"
    [ "$CASE_EXIT" -eq 0 ] && cmp -s "$CASE_STDOUT" "$expected" && [ ! -s "$CASE_STDERR" ]
}

assert_default_invalid_version() {
    local expected="$CASE_DIR/default.expected"
    printf 'FAIL: unsupported schema_version '\''2'\'' (this validator handles 1)\nRESULT: INVALID (%s)\n' "$CASE_MANIFEST" > "$expected"
    chmod 600 "$expected"
    [ "$CASE_EXIT" -eq 1 ] && [ ! -s "$CASE_STDOUT" ] && cmp -s "$CASE_STDERR" "$expected"
}

assert_default_missing_skill() {
    local expected_out="$CASE_DIR/default.stdout.expected" expected_err="$CASE_DIR/default.stderr.expected"
    printf 'RESULT: VALID (%s) — schema_version=1, module=synthetic-pack@1.2.3, skills=1\n' "$CASE_MANIFEST" > "$expected_out"
    printf 'WARN: skills entry '\''alpha'\'' has no matching skills/alpha/SKILL.md near the manifest (may be authored ahead of the file)\n' > "$expected_err"
    chmod 600 "$expected_out" "$expected_err"
    [ "$CASE_EXIT" -eq 0 ] && cmp -s "$CASE_STDOUT" "$expected_out" && cmp -s "$CASE_STDERR" "$expected_err"
}

assert_default_undeclared_requirement() {
    local expected_out="$CASE_DIR/default.stdout.expected" expected_err="$CASE_DIR/default.stderr.expected"
    printf 'RESULT: VALID (%s) — schema_version=1, module=synthetic-pack@1.2.3, skills=1\n' "$CASE_MANIFEST" > "$expected_out"
    printf 'WARN: skills entry '\''alpha'\'' requires '\''missing-dependency'\'' which is not declared in this pack (may be satisfied by core or another plugin)\n' > "$expected_err"
    chmod 600 "$expected_out" "$expected_err"
    [ "$CASE_EXIT" -eq 0 ] && cmp -s "$CASE_STDOUT" "$expected_out" && cmp -s "$CASE_STDERR" "$expected_err"
}

assert_path_refusal() {
    local expected="$CASE_DIR/refusal.expected"
    printf '%s\n' 'ERROR: manifest path contains a control character' > "$expected"
    chmod 600 "$expected"
    [ "$CASE_EXIT" -eq 2 ] && [ ! -s "$CASE_STDOUT" ] && cmp -s "$CASE_STDERR" "$expected"
}

assert_usage_error() {
    [ "$CASE_EXIT" -eq 2 ] && [ -s "$CASE_STDOUT" ] && grep -Fxq 'ERROR: no manifest path given' "$CASE_STDERR" && grep -q '^# Usage: check-module-manifest\.sh <path-to-module\.yaml>$' "$CASE_STDOUT" && grep -q '^# Read-only: no writes, no network\.$' "$CASE_STDOUT"
}

@test "valid summary counts a nearby synthetic skill and default output stays exact" {
    local root="$BATS_TEST_TMPDIR/valid"
    write_fixture "$root" valid
    invoke_cli valid-summary "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary VALID 0 '' 1 0 "$root" && assert_summary_has_no_handled_diagnostics || return 1
    invoke_cli valid-default "$root" "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_default_valid
}

@test "unsupported schema version is invalid with measured count and unchanged default streams" {
    local root="$BATS_TEST_TMPDIR/hard-invalid"
    write_fixture "$root" invalid-version
    invoke_cli invalid-summary "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary INVALID 1 MODULE_MANIFEST_INVALID 1 0 synthetic-pack && assert_summary_has_no_handled_diagnostics || return 1
    invoke_cli invalid-default "$root" "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_default_invalid_version
}

@test "empty skills remains invalid with a measured zero skill count" {
    local root="$BATS_TEST_TMPDIR/empty-skills"
    write_fixture "$root" empty-skills
    invoke_cli empty-skills "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary INVALID 1 MODULE_MANIFEST_INVALID 0 0 synthetic-pack && assert_summary_has_no_handled_diagnostics
}

@test "missing nearby skill is warning-only and counted once" {
    local root="$BATS_TEST_TMPDIR/missing-skill"
    write_fixture "$root" missing-skill
    invoke_cli missing-skill-summary "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary VALID 0 '' 1 1 synthetic-pack && assert_summary_has_no_handled_diagnostics || return 1
    invoke_cli missing-skill-default "$root" "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_default_missing_skill
}

@test "undeclared dependency warning is counted without changing valid status" {
    local root="$BATS_TEST_TMPDIR/undeclared-requirement"
    write_fixture "$root" undeclared-requires
    invoke_cli undeclared-summary "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary VALID 0 '' 1 1 missing-dependency && assert_summary_has_no_handled_diagnostics || return 1
    invoke_cli undeclared-default "$root" "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_default_undeclared_requirement
}

@test "missing manifest returns unavailable with both counts unmeasured" {
    local root="$BATS_TEST_TMPDIR/missing-manifest"
    mkdir -p "$root/pack"
    invoke_cli unavailable "$root" --summary-json "$root/pack/missing.yaml" || return 1
    assert_record_integrity && assert_summary INPUT_UNAVAILABLE 2 MODULE_MANIFEST_UNAVAILABLE null null "$root" && assert_summary_has_no_handled_diagnostics
}

@test "Unicode space and TAB path is accepted and does not enter the summary" {
    local root
    root="$BATS_TEST_TMPDIR/pack café$(printf '\t') space"
    write_fixture "$root" valid
    invoke_cli unicode-tab-summary "$root" --summary-json "$root/pack/module.yaml" || return 1
    assert_record_integrity && assert_summary VALID 0 '' 1 0 "$root" && assert_summary_has_no_handled_diagnostics
}

@test "leading-dash relative path is accepted after the argument separator" {
    local root="$BATS_TEST_TMPDIR/dash-path"
    write_fixture "$root" valid
    mv "$root/pack/module.yaml" "$root/pack/-module.yaml"
    INVOKE_CWD="$root/pack"
    invoke_cli dash-path "$root" --summary-json -- -module.yaml || return 1
    assert_record_integrity && assert_summary VALID 0 '' 1 0 '-module.yaml' && assert_summary_has_no_handled_diagnostics
}

@test "C0 newline ESC DEL and C1 manifest paths receive fixed parser refusals" {
    local root="$BATS_TEST_TMPDIR/control-paths"
    write_fixture "$root" valid
    local c0=$'bad\001path' lf=$'bad\npath' esc=$'bad\033path' del=$'bad\177path' c1=$'bad\u0085path'
    invoke_cli control-c0 "$root" --summary-json "$root/pack/$c0" || return 1
    assert_record_integrity && assert_path_refusal || return 1
    invoke_cli control-lf "$root" --summary-json "$root/pack/$lf" || return 1
    assert_record_integrity && assert_path_refusal || return 1
    invoke_cli control-esc "$root" --summary-json "$root/pack/$esc" || return 1
    assert_record_integrity && assert_path_refusal || return 1
    invoke_cli control-del "$root" --summary-json "$root/pack/$del" || return 1
    assert_record_integrity && assert_path_refusal || return 1
    invoke_cli control-c1 "$root" --summary-json "$root/pack/$c1" || return 1
    assert_record_integrity && assert_path_refusal
}

@test "missing or empty positional manifest remains a usage error outside JSON" {
    local root="$BATS_TEST_TMPDIR/missing-argument"
    mkdir -p "$root"
    invoke_cli no-path "$root" --summary-json || return 1
    assert_record_integrity && assert_usage_error || return 1
    invoke_cli empty-path "$root" --summary-json '' || return 1
    assert_record_integrity && assert_usage_error
}
