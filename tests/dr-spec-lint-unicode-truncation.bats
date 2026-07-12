#!/usr/bin/env bats
# dr-spec-lint-unicode-truncation.bats — TUNE-0482
#
# dr-spec-lint.sh's internal short() helper truncated finding excerpts with
# `cut -c1-120`. Under a byte-oriented locale (LC_ALL=C) — and even under a
# UTF-8 locale once the sliced bytes are re-passed through bash argv to the
# emit_finding python3 heredoc — a 120-BYTE cut into a run of multibyte
# Cyrillic characters produces an invalid UTF-8 fragment. That fragment is
# then handed to python3 via argv, decoded with surrogateescape, and crashes
# with UnicodeEncodeError on print/json.dumps, which trips the script's own
# "finding count mismatch" invariant and exits 2 — a false NON-COMPLIANT
# result in advisory mode for any task whose PRD/AC text contains Russian.
#
# The fix truncates by CHARACTER (python3 slicing) instead of by byte, and
# adds encoding="utf-8" + errors="replace" to the FAIL-text heredoc's file
# read/stdout write for defense in depth.

setup() {
    ROOT_DIR="$BATS_TEST_DIRNAME/.."
    LINT="$ROOT_DIR/dev-tools/dr-spec-lint.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
}

teardown() {
    rm -rf "$WORK"
}

# Build a PRD whose Requirements section has a malformed D-REQ heading (single
# letter id, so it fails D_REQ_ID_RE and falls into the short()-truncated
# dreq-id-format finding path) followed by a long run of Cyrillic characters.
_write_cyrillic_fixture() {
    local ascii_prefix_len="$1"
    python3 - "$WORK/datarim/prd/PRD-FAKE-0002.md" "$ascii_prefix_len" <<'PYEOF'
import sys
path, n = sys.argv[1], int(sys.argv[2])
ascii_part = "x" * n
cyr_part = "ж" * 80
with open(path, "w", encoding="utf-8") as fh:
    fh.write("# PRD-FAKE-0002\n\n## Requirements\n\n")
    fh.write("#### D-REQ-x: " + ascii_part + cyr_part + "\n")
PYEOF
}

# ---------- (a) Cyrillic AC/heading >120 chars: gate returns valid findings-JSON, no traceback ----------

@test "Cyrillic malformed D-REQ heading >120 chars: no traceback, valid JSON, rc 0 under --advisory" {
    _write_cyrillic_fixture 0
    run "$LINT" --task FAKE-0002 --root "$WORK" --format json --advisory
    [ "$status" -eq 0 ]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"UnicodeEncodeError"* ]]
    [[ "$output" != *"finding count mismatch"* ]]
    # Every emitted line must parse as JSON.
    run bash -c "printf '%s\n' \"\$1\" | python3 -c 'import json,sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    json.loads(line)
print(\"ALL_LINES_VALID_JSON\")'" _ "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL_LINES_VALID_JSON"* ]]
}

@test "Cyrillic malformed D-REQ heading >120 chars: text/FAIL path (heredoc #2) has no traceback" {
    _write_cyrillic_fixture 0
    run "$LINT" --task FAKE-0002 --root "$WORK" --format text --advisory
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL:"* ]]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"UnicodeEncodeError"* ]]
}

@test "Cyrillic malformed D-REQ heading >120 chars: no crash under LC_ALL=C" {
    _write_cyrillic_fixture 0
    run env LC_ALL=C "$LINT" --task FAKE-0002 --root "$WORK" --format json --advisory
    [ "$status" -eq 0 ]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"finding count mismatch"* ]]
}

# ---------- (b) ASCII control case still works ----------

@test "ASCII-only malformed D-REQ heading >120 chars: still produces one clean finding" {
    {
        printf '# PRD-FAKE-0003\n\n## Requirements\n\n'
        printf -- '#### D-REQ-x: %s\n' "$(python3 -c 'print("a" * 150)')"
    } > "$WORK/datarim/prd/PRD-FAKE-0003.md"

    run "$LINT" --task FAKE-0003 --root "$WORK" --format json --advisory
    [ "$status" -eq 0 ]
    [[ "$output" != *"Traceback"* ]]
    run bash -c "printf '%s\n' \"\$1\" | python3 -c 'import json,sys
n=0
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    f=json.loads(line)
    n+=1
    assert len(f[\"evidence\"][\"excerpt\"]) <= 200
print(n)'" _ "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

# ---------- (c) exact boundary: char 120 is the START of a 2-byte Cyrillic char ----------

@test "exact byte-120 boundary lands mid-codepoint (regression trigger) but truncation is still valid UTF-8" {
    # "malformed D-REQ heading: " prefix is 26 chars; with a 0-char ascii filler
    # the cyrillic run starts immediately at char 26, so byte offset 120 (the
    # historic cut -c1-120 boundary) falls inside a 2-byte cyrillic codepoint,
    # not on a character boundary. This is the exact scenario that produced
    # invalid UTF-8 with the old byte-oriented cut(1).
    _write_cyrillic_fixture 0
    run "$LINT" --task FAKE-0002 --root "$WORK" --format json --advisory
    [ "$status" -eq 0 ]

    # Extract the excerpt field and confirm it round-trips through UTF-8
    # encode/decode without error (i.e. no lone surrogates, no truncated
    # multibyte sequence).
    run bash -c "printf '%s\n' \"\$1\" | python3 -c 'import json,sys
line = sys.stdin.readline().strip()
f = json.loads(line)
excerpt = f[\"evidence\"][\"excerpt\"]
excerpt.encode(\"utf-8\")
print(\"ROUNDTRIP_OK\", len(excerpt))'" _ "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ROUNDTRIP_OK"* ]]
}
