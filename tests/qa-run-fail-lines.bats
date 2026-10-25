#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-qa-run-fail-lines.py"
    RUN="$BATS_TEST_TMPDIR/run"
    mkdir -p "$RUN"
    printf 'FAIL: assertion one\n' > "$RUN/results.log"
}

@test "orphan FAIL line blocks certification" {
    printf '{"cases":{},"fail_lines":[]}\n' > "$RUN/manifest.json"
    run python3 "$SCRIPT" --run-dir "$RUN" --manifest "$RUN/manifest.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"orphan FAIL lines"* ]]
}

@test "FAIL line tied to a failing case is accounted for" {
    printf '{"cases":{"case-one":"fail"},"fail_lines":[{"path":"results.log","line":1,"disposition":"failing_case","case_id":"case-one"}]}\n' > "$RUN/manifest.json"
    run python3 "$SCRIPT" --run-dir "$RUN" --manifest "$RUN/manifest.json"
    [ "$status" -eq 0 ]
}

@test "harness fix requires replay of the recorded response" {
    printf 'original response\n' > "$RUN/response.txt"
    hash="$(sha256sum "$RUN/response.txt" | cut -d' ' -f1)"
    printf '{"response_sha256":"%s","result":"pass"}\n' "$hash" > "$RUN/replay.json"
    printf '{"cases":{},"fail_lines":[{"path":"results.log","line":1,"disposition":"harness_fixed","response_path":"response.txt","reevaluation_path":"replay.json"}]}\n' > "$RUN/manifest.json"
    run python3 "$SCRIPT" --run-dir "$RUN" --manifest "$RUN/manifest.json"
    [ "$status" -eq 0 ]
}
