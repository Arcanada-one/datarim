#!/usr/bin/env bats
# check-release-env-policy.bats — regression suite for the release
# environment policy declaration + drift check
# (dev-tools/check-release-env-policy.sh + .github/environments-policy.yml).
#
# Contract pinned here:
#   - the shipped .github/environments-policy.yml validates clean
#   - missing file / missing env / missing v* tag pattern / missing
#     custom_branch_policies all FAIL --check
#   - --live is fail-soft: no gh binary or no repo slug → NOTE + exit 0
#   - --live with a stubbed API: matching live policy → PASS; missing tag
#     policy → DRIFT advisory exit 0; --strict turns drift into exit 1

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/dev-tools/check-release-env-policy.sh"
  FIX="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIX"
}

write_valid_policy() {
  cat > "$FIX/policy.yml" <<'YAML'
schema_version: 1

environments:
  release-auto:
    deployment_branch_policy:
      custom_branch_policies: true
      tag_patterns:
        - "v*"
    required_reviewers: false
  release-manual:
    deployment_branch_policy:
      custom_branch_policies: true
      tag_patterns:
        - "v*"
    required_reviewers: true
YAML
}

# gh-api stub factory: $1 = mode (with-tag | without-tag | fail)
write_gh_stub() {
  local mode="$1"
  cat > "$FIX/gh-stub" <<STUB
#!/usr/bin/env bash
case "$mode" in
  with-tag)
    echo '{"total_count":1,"branch_policies":[{"id":1,"name":"v*","type":"tag"}]}'
    ;;
  without-tag)
    echo '{"total_count":1,"branch_policies":[{"id":1,"name":"main","type":"branch"}]}'
    ;;
  fail)
    exit 1
    ;;
esac
STUB
  chmod +x "$FIX/gh-stub"
}

@test "shipped .github/environments-policy.yml validates clean" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "missing policy file fails" {
  run bash "$SCRIPT" --check --file "$FIX/nope.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"policy file missing"* ]]
}

@test "missing release-manual environment fails" {
  write_valid_policy
  grep -v 'release-manual' "$FIX/policy.yml" > "$FIX/p2.yml" || true
  # crude cut: rebuild without the manual env block
  awk '/^  release-manual:/{skip=1} skip && /^  [a-zA-Z]/ && !/^  release-manual:/{skip=0} !skip' \
    "$FIX/policy.yml" > "$FIX/p2.yml"
  run bash "$SCRIPT" --check --file "$FIX/p2.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'release-manual' not declared"* ]]
}

@test "missing v* tag pattern fails" {
  write_valid_policy
  sed 's/- "v\*"/- "release-only"/' "$FIX/policy.yml" > "$FIX/p2.yml"
  run bash "$SCRIPT" --check --file "$FIX/p2.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tag_patterns must include the v* pattern"* ]]
}

@test "custom_branch_policies false fails" {
  write_valid_policy
  sed 's/custom_branch_policies: true/custom_branch_policies: false/' \
    "$FIX/policy.yml" > "$FIX/p2.yml"
  run bash "$SCRIPT" --check --file "$FIX/p2.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"custom_branch_policies must be true"* ]]
}

@test "missing schema_version fails" {
  write_valid_policy
  grep -v '^schema_version:' "$FIX/policy.yml" > "$FIX/p2.yml"
  run bash "$SCRIPT" --check --file "$FIX/p2.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema_version"* ]]
}

@test "--live is fail-soft when gh is unavailable" {
  write_valid_policy
  run env GH_API_CMD="$FIX/definitely-not-a-binary api" \
    bash "$SCRIPT" --check --live --repo owner/name --file "$FIX/policy.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping live drift comparison"* ]]
}

@test "--live is fail-soft when no repo slug is available" {
  write_valid_policy
  write_gh_stub with-tag
  run env GH_API_CMD="$FIX/gh-stub" GITHUB_REPOSITORY= \
    bash "$SCRIPT" --check --live --file "$FIX/policy.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping live drift comparison"* ]]
}

@test "--live PASS when live policy carries the v* tag pattern" {
  write_valid_policy
  write_gh_stub with-tag
  run env GH_API_CMD="$FIX/gh-stub" \
    bash "$SCRIPT" --check --live --repo owner/name --file "$FIX/policy.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"live OK: release-auto"* ]]
  [[ "$output" == *"live OK: release-manual"* ]]
  [[ "$output" != *"DRIFT"* ]]
}

@test "--live drift is ADVISORY by default (exit 0, DRIFT reported)" {
  write_valid_policy
  write_gh_stub without-tag
  run env GH_API_CMD="$FIX/gh-stub" \
    bash "$SCRIPT" --check --live --repo owner/name --file "$FIX/policy.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRIFT: release-auto"* ]]
  [[ "$output" == *"advisory"* ]]
}

@test "--live --strict turns drift into exit 1" {
  write_valid_policy
  write_gh_stub without-tag
  run env GH_API_CMD="$FIX/gh-stub" \
    bash "$SCRIPT" --check --live --strict --repo owner/name --file "$FIX/policy.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"strict mode"* ]]
}

@test "--live API failure is an advisory skip, not a failure" {
  write_valid_policy
  write_gh_stub fail
  run env GH_API_CMD="$FIX/gh-stub" \
    bash "$SCRIPT" --check --live --repo owner/name --file "$FIX/policy.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"advisory skip"* ]]
}

@test "invalid repo slug is a usage error" {
  write_valid_policy
  write_gh_stub with-tag
  run env GH_API_CMD="$FIX/gh-stub" \
    bash "$SCRIPT" --check --live --repo 'owner/name;rm -rf /' --file "$FIX/policy.yml"
  [ "$status" -eq 2 ]
}
