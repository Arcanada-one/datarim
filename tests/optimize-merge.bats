#!/usr/bin/env bats

# TUNE-0017: Tests for seo-launch+marketing → go-to-market merge and description shortening
# TUNE-0034: removed 3 stale assertions on go-to-market.md (artifact removed pre-2026)
# and "24 skills" snapshot count in CLAUDE.md (count is volatile, not an invariant).
# Surviving tests cover live invariants: removed legacy skills stay removed, and
# no skill description exceeds the 155-char discovery cap.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "seo-launch.md does NOT exist" {
  [ ! -f "$REPO_ROOT/skills/seo-launch.md" ]
}

@test "marketing.md does NOT exist" {
  [ ! -f "$REPO_ROOT/skills/marketing.md" ]
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
