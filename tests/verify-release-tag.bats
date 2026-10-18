#!/usr/bin/env bats
# Exercises the workflow's signed-tag ancestry and immutable identity helper
# with an isolated local origin; no GitHub ref or signing configuration changes.
setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  TEST_ROOT="$(mktemp -d)"
  REPO="$TEST_ROOT/repo"
  ORIGIN="$TEST_ROOT/origin.git"
  git init -q -b main "$REPO"
  git init -q --bare "$ORIGIN"
  git -C "$REPO" config user.name 'Release fixture'
  git -C "$REPO" config user.email release@example.test
  git -C "$REPO" config gpg.format ssh
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config tag.gpgsign false
  printf 'tagged-source-payload\n' > "$REPO/payload.txt"
  git -C "$REPO" add payload.txt
  git -C "$REPO" commit -q -m 'fix: tagged source'
  BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q origin main
  ssh-keygen -q -t ed25519 -N '' -f "$TEST_ROOT/signing-key"
  mkdir -p "$REPO/.github"
  printf 'release@example.test ' > "$TEST_ROOT/allowed-signers"
  cat "$TEST_ROOT/signing-key.pub" >> "$TEST_ROOT/allowed-signers"
  cp "$TEST_ROOT/allowed-signers" "$REPO/.github/ssh-signing-allowed-signers"
  git -C "$REPO" config user.signingkey "$TEST_ROOT/signing-key"
  git -C "$REPO" tag -s -m 'bump_level=patch' v1.2.3 "$BASE_SHA"
  git -C "$REPO" push -q origin refs/tags/v1.2.3
  git -C "$REPO" commit -q --allow-empty -m 'fix: protected main advances'
  MAIN_SHA="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" push -q origin main
  HELPER="${BATS_TEST_DIRNAME}/../dev-tools/verify-release-tag.sh"
}

teardown() { rm -rf -- "${TEST_ROOT:?}"; }

@test 'accepts a trusted signed ancestor tag and keeps its exact source payload' {
  run "$HELPER" classify --repo "$REPO" --tag v1.2.3 --workflow-ref refs/heads/main \
    --allowed-signers .github/ssh-signing-allowed-signers
  [ "$status" -eq 0 ]
  [[ "$output" == *"release_sha=$BASE_SHA"* ]]
  [[ "$output" == *'stamped_bump_level=patch'* ]]
  tag_object="$(git -C "$REPO" rev-parse refs/tags/v1.2.3)"
  [[ "$output" == *"release_tag_object=$tag_object"* ]]
  [ "$(git -C "$REPO" show "$BASE_SHA:payload.txt")" = 'tagged-source-payload' ]
}

@test 'rejects a signed tag whose target is not on protected main' {
  git -C "$REPO" checkout -q --orphan foreign
  git -C "$REPO" rm -q -rf .
  printf 'foreign-source\n' > "$REPO/foreign.txt"
  git -C "$REPO" add foreign.txt
  git -C "$REPO" commit -q -m 'fix: unrelated history'
  foreign_sha="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" tag -s -m 'bump_level=patch' v1.2.4 "$foreign_sha"
  git -C "$REPO" push -q origin refs/tags/v1.2.4
  git -C "$REPO" checkout -q main

  run "$HELPER" classify --repo "$REPO" --tag v1.2.4 --workflow-ref refs/heads/main \
    --allowed-signers .github/ssh-signing-allowed-signers
  [ "$status" -ne 0 ]
  [[ "$output" == *'not an ancestor'* ]]
}

@test 'rejects dispatch from any ref other than protected main' {
  run "$HELPER" classify --repo "$REPO" --tag v1.2.3 --workflow-ref refs/tags/v1.2.3 \
    --allowed-signers .github/ssh-signing-allowed-signers
  [ "$status" -ne 0 ]
  [[ "$output" == *'not dispatched from protected main'* ]]
}

@test 'rejects tag substitution after successful classification' {
  run "$HELPER" classify --repo "$REPO" --tag v1.2.3 --workflow-ref refs/heads/main \
    --allowed-signers .github/ssh-signing-allowed-signers
  [ "$status" -eq 0 ]
  pinned_sha="$(printf '%s\n' "$output" | sed -n 's/^release_sha=//p')"
  pinned_object="$(printf '%s\n' "$output" | sed -n 's/^release_tag_object=//p')"
  git -C "$REPO" tag -d v1.2.3 >/dev/null
  git -C "$REPO" tag -s -m 'bump_level=patch' v1.2.3 "$MAIN_SHA"
  git -C "$REPO" push -q --force origin refs/tags/v1.2.3

  run "$HELPER" recheck --repo "$REPO" --tag v1.2.3 --release-sha "$pinned_sha" \
    --tag-object "$pinned_object"
  [ "$status" -ne 0 ]
  [[ "$output" == *'tag object changed'* ]]
}
