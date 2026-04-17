#!/usr/bin/env bats
# utilities-decomposition.bats — T2 structural tests for utilities.md decomposition (TUNE-0005)
#
# Validates that utilities.md was correctly decomposed into skills/utilities/ directory
# following the same pattern as visual-maps/ and datarim-system/.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "T1: stub file exists with correct frontmatter name" {
  [ -f "$REPO_DIR/skills/utilities.md" ]
  grep -q '^name: utilities$' "$REPO_DIR/skills/utilities.md"
}

@test "T2: stub file has model: haiku in frontmatter" {
  grep -q '^model: haiku$' "$REPO_DIR/skills/utilities.md"
}

@test "T3: utilities/ directory exists with 12 fragment files" {
  [ -d "$REPO_DIR/skills/utilities" ]
  local count
  count=$(ls "$REPO_DIR/skills/utilities/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 12 ]
}

@test "T4: all 12 expected fragment files exist" {
  local fragments=(
    datetime.md system-info.md crypto.md encoding.md
    text-transform.md validation.md json.md formatting.md
    datarim-sync.md ga4-admin.md ssh-deploy.md recovery.md
  )
  for f in "${fragments[@]}"; do
    [ -f "$REPO_DIR/skills/utilities/$f" ]
  done
}

@test "T5: no fragment file has YAML frontmatter" {
  for f in "$REPO_DIR/skills/utilities/"*.md; do
    local first_line
    first_line=$(head -1 "$f")
    [ "$first_line" != "---" ]
  done
}

@test "T6: stub references all 12 fragment paths" {
  local fragments=(
    datetime.md system-info.md crypto.md encoding.md
    text-transform.md validation.md json.md formatting.md
    datarim-sync.md ga4-admin.md ssh-deploy.md recovery.md
  )
  for f in "${fragments[@]}"; do
    grep -q "utilities/$f" "$REPO_DIR/skills/utilities.md"
  done
}

@test "T7: total fragment line count >= 400 (content preserved)" {
  local total
  total=$(cat "$REPO_DIR/skills/utilities/"*.md | wc -l | tr -d ' ')
  [ "$total" -ge 400 ]
}

@test "T8: evolution.md references utilities/recovery.md (not utilities.md §)" {
  grep -q 'utilities/recovery.md' "$REPO_DIR/skills/evolution.md"
  ! grep -q 'utilities\.md §' "$REPO_DIR/skills/evolution.md"
}

@test "T9: docs/skills.md mentions fragment count" {
  grep -q 'fragment' "$REPO_DIR/docs/skills.md"
}
