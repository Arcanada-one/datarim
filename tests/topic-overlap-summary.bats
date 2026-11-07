#!/usr/bin/env bats

BASE_SHA=6d270261a000df0f339dbe5c4d139a78066f2d41

setup() {
    REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P) || return 1
    SCRIPT="$REPO/dev-tools/check-topic-overlap.py"
    TMP="$BATS_TEST_TMPDIR/topic-overlap-summary-inputs"
    BASE_SCRIPT="$BATS_TEST_TMPDIR/topic-overlap-parent.py"

    local test_name=${BATS_TEST_NAME//[^A-Za-z0-9_.-]/_}
    if [ -n "${TOPIC_OVERLAP_EVIDENCE_DIR:-}" ]; then
        TEST_EVIDENCE_DIR="$TOPIC_OVERLAP_EVIDENCE_DIR/$test_name"
    else
        TEST_EVIDENCE_DIR="$BATS_TEST_TMPDIR/topic-overlap-summary-evidence"
    fi
    mkdir -p "$TMP" "$TEST_EVIDENCE_DIR/raw" || return 1
    chmod 700 "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/raw" || return 1

    printf 'project architecture overlap shared\n' > "$TMP/task.md" || return 1
    printf '%s\n' '- TST-9001 · pending · P2 · L2 · project architecture overlap shared' > "$TMP/backlog.md" || return 1
    : > "$TMP/empty.md" || return 1
    printf '# synthetic private stopwords\n' > "$TMP/stopwords.txt" || return 1
    git -C "$REPO" show "$BASE_SHA:dev-tools/check-topic-overlap.py" > "$BASE_SCRIPT" || return 1
}

run_cli() {
    local label=$1 source=$2
    shift 2
    python3 - "$source" "$TEST_EVIDENCE_DIR" "$label" "$REPO" "$TMP" "$@" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
import stat
from datetime import datetime, timezone
from unittest import mock

source, evidence_root, label, cwd, fixture_root, *cli_args = sys.argv[1:]

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(131072), b""):
            h.update(chunk)
    return h.hexdigest()

def fixture_fingerprint(root):
    h = hashlib.sha256()
    file_count = 0
    byte_count = 0
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(base, name)
            relative = os.path.relpath(path, root).encode("utf-8")
            with open(path, "rb") as stream:
                data = stream.read()
            h.update(len(relative).to_bytes(8, "big"))
            h.update(relative)
            h.update(len(data).to_bytes(8, "big"))
            h.update(data)
            file_count += 1
            byte_count += len(data)
    return h.hexdigest(), file_count, byte_count

argv = [sys.executable, source, *cli_args]
test_source = os.path.join(cwd, "tests/topic-overlap-summary.bats")
source_before = sha256_file(source)
test_before = sha256_file(test_source)
fixture_before, fixture_files_before, fixture_bytes_before = fixture_fingerprint(fixture_root)
started = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
child = {}
original_popen = subprocess.Popen

class DirectChildPopen(original_popen):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        child["pid"] = self.pid

with mock.patch.object(subprocess, "Popen", DirectChildPopen):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, check=False)
ended = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
source_after = sha256_file(source)
test_after = sha256_file(test_source)
fixture_after, fixture_files_after, fixture_bytes_after = fixture_fingerprint(fixture_root)

raw_dir = os.path.join(evidence_root, "raw")
os.makedirs(raw_dir, mode=0o700, exist_ok=True)
os.chmod(raw_dir, 0o700)
for suffix, payload in (("stdout.raw", result.stdout), ("stderr.raw", result.stderr)):
    path = os.path.join(raw_dir, label + "." + suffix)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(payload)
    os.chmod(path, 0o600)

receipt = {
    "pid": child.get("pid"),
    "started_utc": started,
    "ended_utc": ended,
    "argv": argv,
    "cwd": os.path.abspath(cwd),
    "exit_code": result.returncode,
    "source_path": os.path.abspath(source),
    "source_sha256_before": source_before,
    "source_sha256_after": source_after,
    "test_source_sha256_before": test_before,
    "test_source_sha256_after": test_after,
    "fixture_root": os.path.abspath(fixture_root),
    "fixture_sha256_before": fixture_before,
    "fixture_sha256_after": fixture_after,
    "fixture_files_before": fixture_files_before,
    "fixture_files_after": fixture_files_after,
    "fixture_bytes_before": fixture_bytes_before,
    "fixture_bytes_after": fixture_bytes_after,
}
meta_path = os.path.join(raw_dir, label + ".process.json")
fd = os.open(meta_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(receipt, stream, sort_keys=True)
    stream.write("\n")
os.chmod(meta_path, 0o600)
sys.exit(result.returncode)
PY
}

assert_process() {
    local label=$1 expected_exit=$2
    python3 - "$TEST_EVIDENCE_DIR/raw/$label.process.json" \
        "$TEST_EVIDENCE_DIR/raw/$label.stdout.raw" \
        "$TEST_EVIDENCE_DIR/raw/$label.stderr.raw" "$REPO" "$expected_exit" <<'PY'
import json
import os
import stat
import sys
meta_path, stdout_path, stderr_path, repo, expected_exit = sys.argv[1:]
meta = json.load(open(meta_path, encoding="utf-8"))
assert meta["pid"] and meta["started_utc"] and meta["ended_utc"]
assert meta["argv"] and meta["cwd"] == repo
assert meta["exit_code"] == int(expected_exit)
assert meta["source_sha256_before"] == meta["source_sha256_after"]
assert meta["test_source_sha256_before"] == meta["test_source_sha256_after"]
assert meta["fixture_sha256_before"] == meta["fixture_sha256_after"]
assert meta["fixture_files_before"] == meta["fixture_files_after"]
assert meta["fixture_bytes_before"] == meta["fixture_bytes_after"]
assert stat.S_IMODE(os.stat(os.path.dirname(meta_path)).st_mode) == 0o700
for path in (meta_path, stdout_path, stderr_path):
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
PY
    local result=$?
    [ "$result" -eq 0 ] || return 1
}

assert_summary() {
    local label=$1 expected_result=$2 expected_code=$3
    local expected_selected=$4 expected_selected_status=$5
    local expected_matches=$6 expected_match_status=$7
    python3 - "$TEST_EVIDENCE_DIR/raw/$label.stdout.raw" \
        "$TEST_EVIDENCE_DIR/raw/$label.stderr.raw" "$expected_result" \
        "$expected_code" "$expected_selected" "$expected_selected_status" \
        "$expected_matches" "$expected_match_status" <<'PY'
import json
import sys
stdout_path, stderr_path, result, code, selected, selected_status, matches, match_status = sys.argv[1:]
stdout = open(stdout_path, "rb").read()
stderr = open(stderr_path, "rb").read()
assert stdout.endswith(b"\n") and stdout.count(b"\n") == 1
summary = json.loads(stdout)
assert set(summary) == {
    "schema", "result", "exit_code", "diagnostic_codes", "selected_count",
    "selected_count_status", "match_count", "match_count_status",
}
assert summary["schema"] == "DatarimTopicOverlapSummary/v1"
assert summary["result"] == result
assert summary["exit_code"] == 0
assert summary["diagnostic_codes"] == ([] if code == "-" else [code])
assert summary["selected_count"] == (None if selected == "null" else int(selected))
assert summary["selected_count_status"] == selected_status
assert summary["match_count"] == (None if matches == "null" else int(matches))
assert summary["match_count_status"] == match_status
for private_text in (b"TST-9001", b"SECRET-1234", b"architecture", b"private"):
    assert private_text not in stdout and private_text not in stderr
assert stderr == b""
PY
    local result=$?
    [ "$result" -eq 0 ] || return 1
}

assert_same_process_output() {
    local parent_label=$1 current_label=$2
    cmp -s "$TEST_EVIDENCE_DIR/raw/$parent_label.stdout.raw" \
        "$TEST_EVIDENCE_DIR/raw/$current_label.stdout.raw" || return 1
    cmp -s "$TEST_EVIDENCE_DIR/raw/$parent_label.stderr.raw" \
        "$TEST_EVIDENCE_DIR/raw/$current_label.stderr.raw" || return 1
    python3 - "$TEST_EVIDENCE_DIR/raw/$parent_label.process.json" \
        "$TEST_EVIDENCE_DIR/raw/$current_label.process.json" <<'PY'
import json
import sys
parent, current = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
assert parent["exit_code"] == current["exit_code"]
assert parent["fixture_sha256_before"] == current["fixture_sha256_before"]
assert parent["fixture_sha256_after"] == current["fixture_sha256_after"]
PY
    local result=$?
    [ "$result" -eq 0 ] || return 1
}

@test "summary reports an overlap without exposing dynamic identifiers or text" {
    run run_cli overlap "$SCRIPT" --summary-json --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process overlap 0 || return 1
    assert_summary overlap ADVISORY - 1 MEASURED 1 MEASURED || return 1
}

@test "summary measures zero matches for a completed non-overlap calculation" {
    printf 'quantum lattice migration roadmap\n' > "$TMP/task.md" || return 1
    run run_cli no-overlap "$SCRIPT" --summary-json --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process no-overlap 0 || return 1
    assert_summary no-overlap ADVISORY - 1 MEASURED 0 MEASURED || return 1
}

@test "missing task description is explicitly unavailable with unmeasured counts" {
    run run_cli missing-description "$SCRIPT" --summary-json \
        --task-description "$TMP/missing.md" --backlog "$TMP/backlog.md" \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    assert_process missing-description 0 || return 1
    assert_summary missing-description INPUT_UNAVAILABLE TASK_DESCRIPTION_UNAVAILABLE \
        null NOT_MEASURED null NOT_MEASURED || return 1
}

@test "empty and absent backlog both report zero measured candidates" {
    local index=0 backlog label
    for backlog in "$TMP/empty.md" "$TMP/absent.md"; do
        index=$((index + 1))
        label="no-candidates-$index"
        run run_cli "$label" "$SCRIPT" --summary-json --task-description "$TMP/task.md" \
            --backlog "$backlog" --stopwords-en "$TMP/stopwords.txt" \
            --stopwords-ru "$TMP/stopwords.txt"
        assert_process "$label" 0 || return 1
        assert_summary "$label" NO_CANDIDATES - 0 MEASURED 0 MEASURED || return 1
    done
}

@test "empty task description completes with measured zero matches" {
    run run_cli empty-task "$SCRIPT" --summary-json --task-description "$TMP/empty.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process empty-task 0 || return 1
    assert_summary empty-task ADVISORY - 1 MEASURED 0 MEASURED || return 1
}

@test "legacy JSON output remains byte-identical and summary wins with hostile synthetic input" {
    printf 'private project architecture shared\n' > "$TMP/task.md" || return 1
    printf '%s\n' '- SECRET-1234 · pending · P2 · L2 · private project architecture shared' > "$TMP/backlog.md" || return 1

    run run_cli legacy-parent "$BASE_SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --format json --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process legacy-parent 0 || return 1
    run run_cli legacy-current "$SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --format json --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process legacy-current 0 || return 1
    assert_same_process_output legacy-parent legacy-current || return 1

    run run_cli legacy-summary "$SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --format json --summary-json \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    assert_process legacy-summary 0 || return 1
    assert_summary legacy-summary ADVISORY - 1 MEASURED 1 MEASURED || return 1
}

@test "omitting summary flag preserves default text output and silent no-match behavior" {
    run run_cli default-parent-match "$BASE_SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process default-parent-match 0 || return 1
    run run_cli default-current-match "$SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process default-current-match 0 || return 1
    assert_same_process_output default-parent-match default-current-match || return 1
    grep -aF 'TST-9001' "$TEST_EVIDENCE_DIR/raw/default-current-match.stdout.raw" || return 1

    printf 'quantum lattice migration\n' > "$TMP/task.md" || return 1
    run run_cli default-parent-no-match "$BASE_SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process default-parent-no-match 0 || return 1
    run run_cli default-current-no-match "$SCRIPT" --task-description "$TMP/task.md" \
        --backlog "$TMP/backlog.md" --stopwords-en "$TMP/stopwords.txt" \
        --stopwords-ru "$TMP/stopwords.txt"
    assert_process default-current-no-match 0 || return 1
    assert_same_process_output default-parent-no-match default-current-no-match || return 1
    [ ! -s "$TEST_EVIDENCE_DIR/raw/default-current-no-match.stdout.raw" ] || return 1
}
