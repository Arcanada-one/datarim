#!/usr/bin/env bats

# TUNE-0017: Tests for seo-launch+marketing → go-to-market merge and description shortening

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "go-to-market.md exists" {
  [ -f "$REPO_ROOT/skills/go-to-market.md" ]
}

@test "seo-launch.md does NOT exist" {
  [ ! -f "$REPO_ROOT/skills/seo-launch.md" ]
}

@test "marketing.md does NOT exist" {
  [ ! -f "$REPO_ROOT/skills/marketing.md" ]
}

@test "CLAUDE.md says 24 skills" {
  grep -q "24 skills" "$REPO_ROOT/CLAUDE.md"
}

@test "go-to-market.md has name: go-to-market in frontmatter" {
  grep -q "^name: go-to-market$" "$REPO_ROOT/skills/go-to-market.md"
}

@test "no skill description exceeds 155 chars" {
  over=0
  for f in "$REPO_ROOT"/skills/*.md; do
    desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description: */, ""); print; exit}' "$f")
    len=${#desc}
    if [ "$len" -gt 155 ]; then
      echo "OVER $len $(basename "$f"): $desc"
      over=$((over + 1))
    fi
  done
  [ "$over" -eq 0 ]
}
