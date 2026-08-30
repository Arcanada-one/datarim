#!/usr/bin/env bats

CAPTURE="$BATS_TEST_DIRNAME/../dev-tools/capture-framework-version-baseline.sh"
CHECKER="$BATS_TEST_DIRNAME/../dev-tools/check-framework-version-accountability.sh"
TASK_ID="TUNE-9001"

setup() {
  export GIT_AUTHOR_DATE='2026-07-20T00:00:00Z'
  export GIT_COMMITTER_DATE='2026-07-20T00:00:00Z'
  export HOME="$BATS_TEST_TMPDIR/home"
  export WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$HOME" "$WORKSPACE/datarim/tasks" "$WORKSPACE/datarim/prd" \
    "$WORKSPACE/datarim/plans" "$REPO"
  chmod 755 "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.name "Test Agent"
  git -C "$REPO" config user.email "test@example.invalid"
  printf '%s\n' '1.0.0' > "$REPO/VERSION"
  printf '%s\n' '# Changelog' '' '## [Unreleased]' '' '## [1.0.0]' > "$REPO/CHANGELOG.md"
  mkdir -p "$REPO/tests"
  printf '%s\n' 'baseline' > "$REPO/tests/baseline.txt"
  printf '%s\n' '---' "task_id: $TASK_ID" 'artifact: init-task' \
    'schema_version: 1' 'captured_at: 2026-07-20T00:00:00Z' \
    'captured_by: /dr-init' 'operator: local-test' 'status: canonical' '---' \
    '' '# Test brief' > "$WORKSPACE/datarim/tasks/$TASK_ID-init-task.md"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm baseline
  export BASE_SHA
  BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
}

capture_baseline() {
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ]
}

commit_file() {
  local path="$1" body="${2:-changed}"
  mkdir -p "$(dirname "$REPO/$path")"
  printf '%s\n' "$body" > "$REPO/$path"
  git -C "$REPO" add -- "$path"
  git -C "$REPO" commit -qm "change $path"
}

append_unreleased() {
  local task="$1"
  awk -v task="$task" '
    { print }
    /^## \[Unreleased\]$/ && !done { print ""; print "- Added accountability (" task ")"; done=1 }
  ' "$REPO/CHANGELOG.md" > "$REPO/CHANGELOG.md.new"
  mv "$REPO/CHANGELOG.md.new" "$REPO/CHANGELOG.md"
}

checker_digest() {
  "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO" 2>/dev/null \
    | sed -n 's/.*scope_digest=\([a-f0-9]\{64\}\).*/\1/p'
}

write_deferral() {
  local digest="$1" init_digest recorded_at
  init_digest="$(sed -n 's/^init-task-sha256: //p' "$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID/baseline.record")"
  recorded_at='2026-07-20T00:00:01Z'
  mkdir -p "$REPO/.datarim/version-deferrals"
  printf '%s\n' \
    'schema-version: 1' \
    "task-id: $TASK_ID" \
    "base-commit: $BASE_SHA" \
    "shipped-diff-digest: $digest" \
    'decision: defer' \
    'reason-code: batch-accumulation' \
    'reason: Operator requested this change join a coordinated release.' \
    'delivery-kind: release-train' \
    'delivery-target: next-consolidated-release' \
    'source-kind: init-task' \
    "source-digest: $init_digest" \
    'recorded-by: agent' \
    "recorded-at: $recorded_at" \
    > "$REPO/.datarim/version-deferrals/$TASK_ID.record"
  git -C "$REPO" add ".datarim/version-deferrals/$TASK_ID.record"
  git -C "$REPO" commit -qm 'add deferral'
}

@test "capture creates the closed mode-600 INIT baseline" {
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] \
    && [ "$(stat -c '%a' "$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID/baseline.record")" = 600 ] \
    && grep -qF "base-commit: $BASE_SHA" "$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID/baseline.record"
}

@test "capture is idempotent for an identical baseline" {
  capture_baseline
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"baseline_reused"* ]]
}

@test "capture re-entry preserves the INIT base after commit and append-log growth" {
  capture_baseline
  printf '%s\n' '' '## Append-log' '- 2026-07-20: later clarification.' \
    >> "$WORKSPACE/datarim/tasks/$TASK_ID-init-task.md"
  commit_file 'commands/dr-sample.md'
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *"disposition=baseline_reused"* ]] \
    && [[ "$output" == *"base=$BASE_SHA"* ]]
}

@test "capture refuses late creation after PRD exists" {
  printf '%s\n' '# late' > "$WORKSPACE/datarim/prd/PRD-$TASK_ID.md"
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"late_capture"* ]]
}

@test "checker fails closed when the INIT baseline is missing" {
  mkdir -p "$REPO/commands" "$REPO/skills/example"
  printf '%s\n' '# command' > "$REPO/commands/dr-example.md"
  printf '%s\n' '# skill' > "$REPO/skills/example/SKILL.md"
  git -C "$REPO" add commands skills
  git -C "$REPO" commit -qm 'add current Datarim identity markers'
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"error=missing_baseline"* ]]
}

@test "checker returns not_applicable without a baseline for a consumer repository" {
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=not_applicable"* ]]
}

@test "checker fails closed without a baseline for a historical Datarim repository" {
  mkdir -p "$REPO/commands" "$REPO/skills/example"
  printf '%s\n' '# command' > "$REPO/commands/dr-example.md"
  printf '%s\n' '# skill' > "$REPO/skills/example/SKILL.md"
  git -C "$REPO" add commands skills
  git -C "$REPO" commit -qm 'add historical Datarim identity markers'
  git -C "$REPO" rm -qr commands skills
  git -C "$REPO" commit -qm 'remove Datarim identity markers'
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"error=missing_baseline"* ]]
}

@test "checker fails closed on a malformed baseline for a consumer repository" {
  capture_baseline
  printf '%s\n' 'malformed' \
    > "$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID/baseline.record"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"error=baseline_schema"* ]]
}

@test "checker fails closed on a symlink baseline for a consumer repository" {
  local record real_record
  capture_baseline
  record="$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID/baseline.record"
  real_record="$(dirname "$record")/real.record"
  mv "$record" "$real_record"
  ln -s "$(basename "$real_record")" "$record"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"error=missing_baseline"* ]]
}

@test "checker fails closed when committed history cannot be classified" {
  printf '%040d\n' 0 | tr '0' 'f' > "$REPO/.git/refs/heads/unreadable-history"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] \
    && [[ "$output" == *"error=identity_history_unreadable"* ]] \
    && [[ "$output" != *"disposition=not_applicable"* ]]
}

@test "tests-only diff is not applicable" {
  capture_baseline
  commit_file 'tests/new-case.bats' '@test "x" { true; }'
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=not_applicable"* ]]
}

@test "shipped diff without accounting blocks and still emits digest" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 1 ] \
    && [[ "$output" == *"disposition=accountability_missing"* ]] \
    && [[ "$output" =~ scope_digest=[a-f0-9]{64} ]]
}

@test "scope digest matches the golden serialization fixture" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  local digest
  digest="$(checker_digest)"
  [ "$digest" = '08788ebbdb8a7f643cbe3c2f464ef26b4efdfb81252c772cd61e93a732c8701e' ]
}

@test "shipped diff with strict bump and new task bullet passes" {
  capture_baseline
  mkdir -p "$REPO/commands"
  printf '%s\n' changed > "$REPO/commands/dr-sample.md"
  printf '%s\n' '1.1.0' > "$REPO/VERSION"
  append_unreleased "$TASK_ID"
  git -C "$REPO" add . && git -C "$REPO" commit -qm bump
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=satisfied_by_version"* ]]
}

@test "VERSION-only strict bump with new task bullet passes" {
  capture_baseline
  printf '%s\n' '1.1.0' > "$REPO/VERSION"
  append_unreleased "$TASK_ID"
  git -C "$REPO" add VERSION CHANGELOG.md && git -C "$REPO" commit -qm version-only
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=satisfied_by_version"* ]]
}

@test "VERSION downgrade blocks even with a shipped diff" {
  capture_baseline
  printf '%s\n' '0.9.0' > "$REPO/VERSION"
  mkdir -p "$REPO/commands"
  printf '%s\n' changed > "$REPO/commands/dr-sample.md"
  git -C "$REPO" add VERSION commands/dr-sample.md && git -C "$REPO" commit -qm downgrade
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 1 ] && [[ "$output" == *"disposition=invalid_version_transition"* ]]
}

@test "valid committed deferral passes and record-only commit keeps digest stable" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  local before after
  before="$(checker_digest)"
  [ "${#before}" -eq 64 ]
  write_deferral "$before"
  after="$(checker_digest)"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$before" = "$after" ] \
    && [ "$status" -eq 0 ] \
    && [[ "$output" == *"disposition=satisfied_by_deferral"* ]]
}

@test "later init-task append-log growth preserves the captured deferral source" {
  capture_baseline
  printf '%s\n' '' '## Append-log' '- 2026-07-20: clarification retained.' \
    >> "$WORKSPACE/datarim/tasks/$TASK_ID-init-task.md"
  commit_file 'commands/dr-sample.md'
  local digest
  digest="$(checker_digest)"
  write_deferral "$digest"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=satisfied_by_deferral"* ]]
}

@test "bump plus deferral is contradictory" {
  capture_baseline
  mkdir -p "$REPO/commands"
  printf '%s\n' changed > "$REPO/commands/dr-sample.md"
  printf '%s\n' '1.1.0' > "$REPO/VERSION"
  append_unreleased "$TASK_ID"
  git -C "$REPO" add . && git -C "$REPO" commit -qm bump
  local digest
  digest="$(checker_digest)"
  write_deferral "$digest"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 1 ] && [[ "$output" == *"disposition=contradictory_evidence"* ]]
}

@test "unstaged shipped dirt is untrustworthy" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  printf '%s\n' dirty >> "$REPO/commands/dr-sample.md"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"disposition=untrustworthy_evidence"* ]]
}

@test "unstaged rename from shipped to excluded path remains relevant" {
  mkdir -p "$REPO/commands"
  printf '%s\n' original > "$REPO/commands/original.md"
  git -C "$REPO" add commands/original.md && git -C "$REPO" commit -qm fixture
  capture_baseline
  git -C "$REPO" mv commands/original.md tests/moved.md
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"disposition=untrustworthy_evidence"* ]]
}

@test "unrelated tests dirt is ignored" {
  capture_baseline
  printf '%s\n' dirty >> "$REPO/tests/baseline.txt"
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ] && [[ "$output" == *"disposition=not_applicable"* ]]
}

@test "malformed deferral record fails closed" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  local digest
  digest="$(checker_digest)"
  write_deferral "$digest"
  git -C "$REPO" show "HEAD:.datarim/version-deferrals/$TASK_ID.record" \
    | sed '/^decision:/d' > "$REPO/.datarim/version-deferrals/$TASK_ID.record"
  git -C "$REPO" add . && git -C "$REPO" commit -qm malformed
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"disposition=untrustworthy_evidence"* ]]
}

@test "deferral record with a NUL byte fails closed" {
  capture_baseline
  commit_file 'commands/dr-sample.md'
  local digest record bad
  digest="$(checker_digest)"
  write_deferral "$digest"
  record="$REPO/.datarim/version-deferrals/$TASK_ID.record"
  bad="$REPO/.datarim/version-deferrals/bad.record"
  {
    head -n 6 "$record"
    printf 'reason: Operator requested this change\0 join a coordinated release.\n'
    tail -n +8 "$record"
  } > "$bad"
  mv "$bad" "$record"
  git -C "$REPO" add ".datarim/version-deferrals/$TASK_ID.record"
  git -C "$REPO" commit -qm nul-record
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ] && [[ "$output" == *"error=deferral_encoding"* ]]
}

@test "deferral record requires every ordered key prefix" {
  local key digest record
  for key in reason-code reason delivery-kind delivery-target; do
    rm -rf "$WORKSPACE" "$REPO"
    setup
    capture_baseline
    commit_file 'commands/dr-sample.md'
    digest="$(checker_digest)"
    write_deferral "$digest"
    record="$REPO/.datarim/version-deferrals/$TASK_ID.record"
    sed "s/^${key}: //" "$record" > "$record.new"
    mv "$record.new" "$record"
    git -C "$REPO" add ".datarim/version-deferrals/$TASK_ID.record"
    git -C "$REPO" commit -qm "missing $key prefix"
    run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
    [ "$status" -eq 2 ] && [[ "$output" == *"error=deferral_schema"* ]] || return 1
  done
}

@test "representative shipped and excluded paths preserve classifier precedence" {
  local path
  for path in commands/x.md skills/x/SKILL.md agents/x.md templates/x.md plugins/x/run.sh cli/x.sh scripts/x.sh dev-tools/x.sh config/roles.yaml README.md SECURITY.md; do
    rm -rf "$WORKSPACE" "$REPO"
    setup
    capture_baseline
    commit_file "$path"
    run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
    [ "$status" -eq 1 ] && [[ "$output" == *"disposition=accountability_missing"* ]] || return 1
  done
}


@test "NUL-safe diff handles adversarial shipped filenames" {
  capture_baseline
  mkdir -p "$REPO/commands"
  printf '%s\n' changed > "$REPO/commands/name with spaces.md"
  printf '%s\n' changed > "$REPO/commands/"$'name\twith-tab.md'
  printf '%s\n' changed > "$REPO/commands/"$'name\nwith-newline.md'
  printf '%s\n' changed > "$REPO/commands/-leading-dash.md"
  printf '%s\n' changed > "$REPO/commands/"$'caf\303\251.md'
  git -C "$REPO" add -- commands && git -C "$REPO" commit -qm adversarial-paths
  run "$CHECKER" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 1 ] \
    && [[ "$output" == *"disposition=accountability_missing"* ]] \
    && [[ "$output" =~ scope_digest=[a-f0-9]{64} ]]
}

@test "a default-umask (775) repository root is accepted, not rejected as unsafe_repo" {
  # Regression: the repo-root precondition used the no-group-write predicate meant
  # for the record directory. With the common umask 0002 every checkout is mode 775,
  # so the baseline capture exited 2 (error=unsafe_repo) and, because
  # commands/dr-init.md Step 4.65 treats exit 2 as a hard INIT failure, /dr-init was
  # blocked outright for framework tasks on such a host. The repo root is only ever
  # READ through git; it needs the same guarantee as $workspace (owned, not a
  # symlink, not world-writable), not the stricter record-directory rule.
  chmod 775 "$REPO"
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" != *unsafe_repo* ]]
}

@test "a world-writable (777) repository root is still rejected as unsafe_repo" {
  # The relaxation must not extend to other-write: an attacker-writable repo root
  # would let a third party swap the tree the baseline is computed over.
  chmod 777 "$REPO"
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *unsafe_repo* ]]
}

@test "the record directory keeps the stricter no-group-write guarantee" {
  # trusted_directory() must still guard datarim/.auto/version-accountability/<task>/,
  # which the tool creates chmod 700 — the relaxation is scoped to the repo root only.
  chmod 775 "$REPO"
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 0 ]
  rec_dir="$WORKSPACE/datarim/.auto/version-accountability/$TASK_ID"
  [ -d "$rec_dir" ]
  [ "$(stat -c %a "$rec_dir")" = "700" ]
  chmod 770 "$rec_dir"
  run "$CAPTURE" --task "$TASK_ID" --workspace "$WORKSPACE" --repo "$REPO"
  [ "$status" -eq 2 ]
}
