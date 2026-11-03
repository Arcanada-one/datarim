#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-topic-overlap.py"
TMP="$BATS_TEST_TMPDIR/topic-overlap-summary"
BASE_SCRIPT="$BATS_TEST_TMPDIR/topic-overlap-parent.py"

setup() {
    mkdir -p "$TMP"
    printf 'project architecture overlap shared\n' > "$TMP/task.md"
    printf '%s\n' '- TST-9001 · pending · P2 · L2 · project architecture overlap shared' > "$TMP/backlog.md"
    : > "$TMP/empty.md"
    printf '# synthetic private stopwords\n' > "$TMP/stopwords.txt"
    git -C "$BATS_TEST_DIRNAME/.." show 6d270261a000df0f339dbe5c4d139a78066f2d41:dev-tools/check-topic-overlap.py > "$BASE_SCRIPT"
}

summary() {
    python3 "$SCRIPT" --summary-json --task-description "$1" --backlog "$2" \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
}

@test "summary reports an overlap without exposing dynamic identifiers or text" {
    run summary "$TMP/task.md" "$TMP/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(jq -r .schema <<<"$output")" = DatarimTopicOverlapSummary/v1 ]
    [ "$(jq -r .result <<<"$output")" = ADVISORY ]
    [ "$(jq -r .selected_count <<<"$output")" = 1 ]
    [ "$(jq -r .match_count <<<"$output")" = 1 ]
    [[ "$output" != *TST-9001* ]]
    [[ "$output" != *architecture* ]]
}

@test "summary measures zero matches for a completed non-overlap calculation" {
    printf 'quantum lattice migration roadmap\n' > "$TMP/task.md"
    run summary "$TMP/task.md" "$TMP/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result+":"+(.match_count|tostring)+":"+.match_count_status' <<<"$output")" = ADVISORY:0:MEASURED ]
}

@test "missing task description is explicitly unavailable with unmeasured counts" {
    run summary "$TMP/missing.md" "$TMP/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result+":"+(.selected_count_status)+":"+(.match_count_status)' <<<"$output")" = INPUT_UNAVAILABLE:NOT_MEASURED:NOT_MEASURED ]
}

@test "empty and absent backlog both report zero measured candidates" {
    for backlog in "$TMP/empty.md" "$TMP/absent.md"; do
        run summary "$TMP/task.md" "$backlog"
        [ "$status" -eq 0 ]
        [ "$(jq -r '.result+":"+(.selected_count|tostring)+":"+(.match_count|tostring)' <<<"$output")" = NO_CANDIDATES:0:0 ]
    done
}

@test "empty task description completes with measured zero matches" {
    run summary "$TMP/empty.md" "$TMP/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result+":"+(.selected_count|tostring)+":"+(.match_count|tostring)' <<<"$output")" = ADVISORY:1:0 ]
}

@test "legacy JSON output remains byte-identical with hostile synthetic input" {
    printf 'private project architecture shared\n' > "$TMP/task.md"
    printf '%s\n' '- SECRET-1234 · pending · P2 · L2 · private project architecture shared' > "$TMP/backlog.md"
    run python3 "$BASE_SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --format json --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    [ "$status" -eq 0 ]
    expected="$output"
    run python3 "$SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --format json --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    run python3 "$SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --format json --summary-json --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result+":"+(.match_count|tostring)' <<<"$output")" = ADVISORY:1 ]
    [[ "$output" != *SECRET-1234* ]]
    [[ "$output" != *private* ]]
}

@test "omitting summary flag preserves default text output and silent no-match behavior" {
    run python3 "$BASE_SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    baseline_status=$status
    baseline_output="$output"
    run python3 "$SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    [ "$status" -eq 0 ]
    [ "$status" -eq "$baseline_status" ]
    [ "$output" = "$baseline_output" ]
    [[ "$output" == *"TST-9001"* ]]
    printf 'quantum lattice migration\n' > "$TMP/task.md"
    run python3 "$SCRIPT" --task-description "$TMP/task.md" --backlog "$TMP/backlog.md" \
        --stopwords-en "$TMP/stopwords.txt" --stopwords-ru "$TMP/stopwords.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
