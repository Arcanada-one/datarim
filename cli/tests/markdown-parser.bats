#!/usr/bin/env bats
# markdown-parser.bats — V-AC верификация thin-index одностроч-парсера.
# Format: `- {ID} · {status} · P{n} · L{n} · {title} → tasks/{ID}-task-description.md`

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$DATARIM_CLI_DIR/lib/markdown-parser.sh"
    [[ -f "$LIB" ]] || skip "lib/markdown-parser.sh not yet implemented"
}

@test "1: parse_thin_line extracts id/status/priority/complexity/title/pointer" {
    line='- TUNE-0268 · in_progress · P2 · L3 · Datarim CLI tool — нужно подробнее → tasks/TUNE-0268-init-task.md'
    run bash -c "source '$LIB' && parse_thin_line '$line'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.id == "TUNE-0268"' >/dev/null
    echo "$output" | jq -e '.status == "in_progress"' >/dev/null
    echo "$output" | jq -e '.priority == "P2"' >/dev/null
    echo "$output" | jq -e '.complexity == "L3"' >/dev/null
    echo "$output" | jq -e '.title | test("Datarim CLI tool")' >/dev/null
    echo "$output" | jq -e '.pointer == "tasks/TUNE-0268-init-task.md"' >/dev/null
}

@test "2: parse_thin_line returns exit 30 (STATE_MISMATCH) on malformed line" {
    line='this is not a thin one-liner'
    run bash -c "source '$LIB' && parse_thin_line '$line'"
    [ "$status" -eq 30 ]
}

@test "3: parse_thin_line handles complex titles with unicode + brackets + dashes" {
    line='- ARCA-0135 · in_progress · P1 · L4 · Comment engine [parent: ARCA-0001] — РУС текст → tasks/ARCA-0135-task-description.md'
    run bash -c "source '$LIB' && parse_thin_line '$line'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.id == "ARCA-0135"' >/dev/null
    echo "$output" | jq -e '.title | test("РУС текст")' >/dev/null
    echo "$output" | jq -e '.title | test("\\[parent: ARCA-0001\\]")' >/dev/null
}

@test "4: parse_thin_file streams all thin lines from input file as JSON array" {
    fixture="$BATS_TMPDIR/fixture.md"
    cat >"$fixture" <<'FIX'
# Tasks

## Active

- TUNE-0268 · in_progress · P2 · L3 · CLI tool → tasks/TUNE-0268-init-task.md
- ARCA-0001 · in_progress · P1 · L4 · Assistant Agent → tasks/ARCA-0001-task-description.md

Some narrative text that is not a thin line.

- DISK-0036 · blocked · P2 · L2 · Hermes sync → tasks/DISK-0036-task-description.md
FIX
    run bash -c "source '$LIB' && parse_thin_file '$fixture'"
    [ "$status" -eq 0 ]
    count="$(echo "$output" | jq '. | length')"
    [ "$count" -eq 3 ]
    echo "$output" | jq -e '.[0].id == "TUNE-0268"' >/dev/null
    echo "$output" | jq -e '.[2].id == "DISK-0036"' >/dev/null
    echo "$output" | jq -e '.[2].status == "blocked"' >/dev/null
}

@test "5: parse_thin_file returns empty array on file без thin lines" {
    fixture="$BATS_TMPDIR/empty.md"
    echo "# Just a header" > "$fixture"
    run bash -c "source '$LIB' && parse_thin_file '$fixture'"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "6: parse_thin_file exits 31 (NOT_FOUND) if file missing" {
    run bash -c "source '$LIB' && parse_thin_file '/tmp/nonexistent-$$.md'"
    [ "$status" -eq 31 ]
}
