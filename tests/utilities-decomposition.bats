#!/usr/bin/env bats
# utilities-decomposition.bats — T2 structural tests for utilities.md decomposition (TUNE-0005)
#
# Validates that utilities.md was correctly decomposed into skills/utilities/ directory
# following the same pattern as visual-maps/ and datarim-system/.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "T1: stub file exists with correct frontmatter name" {
  [ -f "$REPO_DIR/skills/utilities/SKILL.md" ]
  grep -q '^name: utilities$' "$REPO_DIR/skills/utilities/SKILL.md"
}

@test "T2: stub file has model frontmatter set" {
  grep -qE '^model: (haiku|inherit)$' "$REPO_DIR/skills/utilities/SKILL.md"
}

@test "T3: utilities/ directory exists with 14 fragment files" {
  # 12 original + keyword-linter.md (TUNE-0039 Class A) + git-diff-parsing.md
  [ -d "$REPO_DIR/skills/utilities" ]
  local count
  count=$(ls "$REPO_DIR/skills/utilities/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 15 ]
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
    # SKILL.md is the stub — it's expected to have frontmatter; only fragments must not.
    [ "$(basename "$f")" = "SKILL.md" ] && continue
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
    grep -qE "\`$f\`|utilities/$f" "$REPO_DIR/skills/utilities/SKILL.md"
  done
}

@test "T7: total fragment line count >= 400 (content preserved)" {
  local total
  total=$(cat "$REPO_DIR/skills/utilities/"*.md | wc -l | tr -d ' ')
  [ "$total" -ge 400 ]
}

@test "T8: evolution.md references utilities/recovery.md (not utilities.md §)" {
  grep -q 'utilities/recovery.md' "$REPO_DIR/skills/evolution/SKILL.md"
  ! grep -q 'utilities\.md §' "$REPO_DIR/skills/evolution/SKILL.md"
}

@test "T9: docs/skills.md mentions fragment count" {
  grep -q 'fragment' "$REPO_DIR/docs/skills.md"
}
