#!/usr/bin/env bash
#
# check-skill-frontmatter.sh — TUNE-0114 AC-8 gate.
#
# Validates that every top-level skill (skills/*.md) declares:
#   - runtime:      list (must include claude or codex)
#   - current_aal:  integer 1..5
#   - target_aal:   integer 1..5
#
# Also verifies AGENTS.md → CLAUDE.md symlink integrity (AC-7 companion check).
#
# Exit 0 on PASS, 1 on FAIL. No mutation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail=0
checked=0
missing_runtime=0
missing_current_aal=0
missing_target_aal=0
bad_aal=0

extract_fm() {
  awk '
    BEGIN { in_fm = 0; line_count = 0 }
    /^---$/ {
      if (line_count == 0) { in_fm = 1; line_count++; next }
      if (in_fm == 1) { exit }
    }
    in_fm == 1 { print }
  ' "$1"
}

is_int_1_5() {
  case "$1" in
    1|2|3|4|5) return 0 ;;
    *) return 1 ;;
  esac
}

for skill in skills/*.md; do
  [[ -f "$skill" ]] || continue
  checked=$((checked + 1))

  fm=$(extract_fm "$skill")

  runtime=$(echo "$fm" | awk -F': ' '/^runtime:/ {print $2; exit}')
  current_aal=$(echo "$fm" | awk -F': ' '/^current_aal:/ {print $2; exit}')
  target_aal=$(echo "$fm" | awk -F': ' '/^target_aal:/ {print $2; exit}')

  if [[ -z "$runtime" ]]; then
    echo "MISS runtime: $skill"
    missing_runtime=$((missing_runtime + 1))
    fail=1
  elif ! echo "$runtime" | grep -qE 'claude|codex'; then
    echo "BAD runtime ($runtime) — must include claude or codex: $skill"
    fail=1
  fi

  if [[ -z "$current_aal" ]]; then
    echo "MISS current_aal: $skill"
    missing_current_aal=$((missing_current_aal + 1))
    fail=1
  elif ! is_int_1_5 "$current_aal"; then
    echo "BAD current_aal ($current_aal) — must be 1..5: $skill"
    bad_aal=$((bad_aal + 1))
    fail=1
  fi

  if [[ -z "$target_aal" ]]; then
    echo "MISS target_aal: $skill"
    missing_target_aal=$((missing_target_aal + 1))
    fail=1
  elif ! is_int_1_5 "$target_aal"; then
    echo "BAD target_aal ($target_aal) — must be 1..5: $skill"
    bad_aal=$((bad_aal + 1))
    fail=1
  fi
done

# Companion check: AC-7 AGENTS.md symlink integrity.
if [[ ! -L AGENTS.md ]]; then
  echo "FAIL AGENTS.md not a symlink"
  fail=1
elif [[ "$(readlink AGENTS.md)" != "CLAUDE.md" ]]; then
  echo "FAIL AGENTS.md target != CLAUDE.md (got: $(readlink AGENTS.md))"
  fail=1
fi

echo ""
echo "=== Summary ==="
echo "checked=$checked"
echo "missing runtime=$missing_runtime, current_aal=$missing_current_aal, target_aal=$missing_target_aal"
echo "bad aal values=$bad_aal"
echo ""

if [[ $fail -eq 0 ]]; then
  echo "RESULT: PASS (AC-8 + AC-7)"
  exit 0
else
  echo "RESULT: FAIL"
  exit 1
fi
