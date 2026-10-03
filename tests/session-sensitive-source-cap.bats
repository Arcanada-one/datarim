#!/usr/bin/env bats

setup() {
  FRAMEWORK_ROOT="${BATS_TEST_DIRNAME}/.."
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/repo"
  BODY_FILE="$BATS_TEST_TMPDIR/body.md"
  SESSION_ID="SESSION-20260615-120000"
  SESSION_FILE="$FIXTURE_ROOT/datarim/sessions/$SESSION_ID.session.md"
  mkdir -p "$FIXTURE_ROOT/datarim"
}

write_fixture() {
  bash "$FRAMEWORK_ROOT/dev-tools/session-handoff-writer-wrapper.sh" \
    --root "$FIXTURE_ROOT" --session "$SESSION_ID" --captured-by agent \
    --recommended-next '/dr-continue' --next-action 'Inspect saved state.' \
    --body-file "$BODY_FILE" "$@"
}

@test "sensitive binding survives real middle-layer truncation and validates" {
  {
    printf '## Layer 1 — Git State\nHEAD: abc123\n'
    printf '### Sensitive source bindings\n'
    printf 'classification: sensitive; approved sanitized path: safe/source.txt\n'
    printf 'original source pin: abc123; sanitized digest: sha256:0123456789\n'
    printf 'omission/redaction constraints: preserve protected region; no raw context\n'
    printf '## Layer 2 — Active Tasks\n'
    printf '%40000s\n' ''
    printf '## Layer 3 — Related Files\nlarge-source-list\n'
    printf '## Layer 5 — Failed Approaches\nNone.\n'
  } > "$BODY_FILE"
  run write_fixture
  [ "$status" -eq 0 ] \
    && grep -qF 'session-truncated:' "$SESSION_FILE" \
    && grep -qF 'classification: sensitive; approved sanitized path: safe/source.txt' "$SESSION_FILE" \
    && grep -qF 'original source pin: abc123; sanitized digest: sha256:0123456789' "$SESSION_FILE" \
    && grep -qF 'omission/redaction constraints: preserve protected region; no raw context' "$SESSION_FILE" \
    && [ "$(wc -c < "$SESSION_FILE")" -le 32768 ]
  run bash "$FRAMEWORK_ROOT/dev-tools/check-session-handoff.sh" \
    --validate-frontmatter --session "$SESSION_ID" --root "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "protected metadata exceeding cap fails without publishing an invalid session" {
  {
    printf '## Layer 1 — Git State\n### Sensitive source bindings\n'
    printf 'classification: sensitive; omission/redaction constraints: '
    printf '%40000s\n' ''
    printf '## Layer 5 — Failed Approaches\nNone.\n'
  } > "$BODY_FILE"
  run write_fixture
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'protected layers exceed available session capacity'* ]] \
    && [ ! -e "$SESSION_FILE" ] \
    && [ ! -d "$FIXTURE_ROOT/datarim/sessions/.lock.$SESSION_ID" ]
}

@test "full existing session rejects new binding without changing previous bytes" {
  mkdir -p "$FIXTURE_ROOT/datarim/sessions"
  printf '%32768s' '' > "$SESSION_FILE"
  cp "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md"
  printf '## Layer 1 — Git State\nclassification: sensitive\n## Layer 5\nNone.\n' > "$BODY_FILE"
  run write_fixture
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'session file at capacity'* ]] \
    && cmp -s "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md" \
    && [ ! -d "$FIXTURE_ROOT/datarim/sessions/.lock.$SESSION_ID" ]
}

@test "ordinary handoff does not require a sensitive source binding" {
  printf '## Layer 1 — Git State\nHEAD: abc123\n## Layer 5\nNone.\n' > "$BODY_FILE"
  run write_fixture
  [ "$status" -eq 0 ] && [ -f "$SESSION_FILE" ]
}

@test "oversized frontmatter with an empty body cannot publish an over-cap session" {
  : > "$BODY_FILE"
  local large_action
  large_action="$(printf '%40000s' '')"
  run write_fixture --next-action "$large_action"
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'serialized session exceeds capacity'* ]] \
    && [ ! -e "$SESSION_FILE" ] \
    && [ ! -d "$FIXTURE_ROOT/datarim/sessions/.lock.$SESSION_ID" ]
}

@test "frontmatter exceeding remaining append capacity preserves existing bytes" {
  mkdir -p "$FIXTURE_ROOT/datarim/sessions"
  printf '%32000s' '' > "$SESSION_FILE"
  cp "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md"
  : > "$BODY_FILE"
  local large_action
  large_action="$(printf '%1000s' '')"
  run write_fixture --next-action "$large_action"
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'serialized session exceeds capacity'* ]] \
    && cmp -s "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md" \
    && [ ! -d "$FIXTURE_ROOT/datarim/sessions/.lock.$SESSION_ID" ]
}

@test "protected metadata overflow on append preserves existing bytes" {
  printf '## Layer 1 — Git State\nHEAD: abc123\n## Layer 5\nNone.\n' > "$BODY_FILE"
  write_fixture
  cp "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md"
  {
    printf '## Layer 1 — Git State\nclassification: sensitive\n'
    printf '%40000s\n' ''
    printf '## Layer 5 — Failed Approaches\nNone.\n'
  } > "$BODY_FILE"
  run write_fixture
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'protected layers exceed available session capacity'* ]] \
    && cmp -s "$SESSION_FILE" "$BATS_TEST_TMPDIR/before.md" \
    && [ ! -d "$FIXTURE_ROOT/datarim/sessions/.lock.$SESSION_ID" ]
}

@test "session capacity regression suite runs in the macOS portability job" {
  local suites
  suites="$(sed -n '/name: Run portability-sensitive suites/,/name: Run CI dependency and portability contracts/p' "$FRAMEWORK_ROOT/.github/workflows/bats.yml")"
  [[ "$suites" == *'tests/session-sensitive-source-cap.bats'* ]]
}
