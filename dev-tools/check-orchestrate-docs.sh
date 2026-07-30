#!/usr/bin/env bash
# Verify the six Phase 3 Class B shipped documentation surfaces.
set -euo pipefail

(( $# == 0 )) || { echo "usage: check-orchestrate-docs.sh" >&2; exit 2; }
ROOT="${DR_ORCH_DOCS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
# Baseline = where this work diverged from the canonical default branch.
# It was previously pinned to a hard-coded sha from the pre-re-root history;
# that commit is not reachable from origin/main, so every check below failed
# for any correct tree once the work was relanded. Deriving it keeps all three
# checks (plugin version, VERSION, release-claim scan) scoped to this branch's
# own additions, which is what they were always meant to assert.
BASE="${DR_ORCH_DOCS_BASE:-$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null \
        || git -C "$ROOT" rev-parse HEAD)}"
FRONTMATTER_CHECK="${DR_ORCH_FRONTMATTER_CHECK:-$ROOT/dev-tools/check-frontmatter-english.sh}"
BODY_CHECK="${DR_ORCH_BODY_CHECK:-$ROOT/dev-tools/check-body-english.sh}"
files=(
  commands/dr-orchestrate.md
  plugins/dr-orchestrate/plugin.yaml
  plugins/dr-orchestrate/README.md
  README.md
  CLAUDE.md
  CHANGELOG.md
)

for file in "${files[@]}"; do
  [[ -f "$ROOT/$file" ]] || { echo "FAIL: missing shipped surface: $file" >&2; exit 1; }
  grep -Eiq 'Phase[[:space:]]+3' "$ROOT/$file" || { echo "FAIL: $file lacks Phase 3" >&2; exit 1; }
  grep -Eiq 'confirm|Save[- ]as[- ]rule|Save as rule' "$ROOT/$file" || { echo "FAIL: $file lacks confirmation contract" >&2; exit 1; }
  grep -Eiq 'seven-day|7-day|604800' "$ROOT/$file" || { echo "FAIL: $file lacks seven-day TTL" >&2; exit 1; }
  grep -Eiq '24[- ]hour|24h|86400' "$ROOT/$file" || { echo "FAIL: $file lacks 24-hour window" >&2; exit 1; }
  grep -Eiq 're-validation|revalidation' "$ROOT/$file" || { echo "FAIL: $file lacks re-validation contract" >&2; exit 1; }
  grep -Eiq 'hard[- ]gat|immutable.*gate' "$ROOT/$file" || { echo "FAIL: $file lacks hard-gate contract" >&2; exit 1; }
done

corpus="$(mktemp)"
scan_root="$(mktemp -d)"
trap 'rm -f -- "$corpus"; rm -rf -- "$scan_root"' EXIT
for file in "${files[@]}"; do
  printf '\nFILE: %s\n' "$file" >>"$corpus"
  cat "$ROOT/$file" >>"$corpus"
done

git -C "$ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "FAIL: base commit unavailable: $BASE" >&2; exit 1; }
base_version="$(git -C "$ROOT" show "$BASE:plugins/dr-orchestrate/plugin.yaml" | yq -r '.version')"
current_version="$(yq -r '.version' "$ROOT/plugins/dr-orchestrate/plugin.yaml")"
[[ -n "$base_version" && "$base_version" == "$current_version" ]] || {
  echo "FAIL: plugin manifest version changed ($base_version -> $current_version)" >&2
  exit 1
}
git -C "$ROOT" diff --quiet "$BASE" -- VERSION || { echo "FAIL: VERSION changed in batch mode" >&2; exit 1; }

added_lines="$scan_root/added-lines.txt"
git -C "$ROOT" diff --unified=0 "$BASE" -- "${files[@]}" \
  | awk '/^\+\+\+/{next} /^\+/{sub(/^\+/, ""); print}' >"$added_lines"
if grep -Eiq '(^|[^[:alnum:]])v?[0-9]+\.[0-9]+\.[0-9]+([^[:alnum:]]|$)|(^|[[:space:]])released([[:space:]]|:)' "$added_lines"; then
  echo "FAIL: task-added documentation makes a release/version claim" >&2
  exit 1
fi

mkdir -p "$scan_root/repo/commands"
git -C "$scan_root/repo" init -q
index=0
for file in "${files[@]}"; do
  case "$file" in
    *.md)
      index=$((index + 1))
      git -C "$ROOT" diff --unified=0 "$BASE" -- "$file" \
        | awk '/^\+\+\+/{next} /^\+/{sub(/^\+/, ""); print}' \
        >"$scan_root/repo/commands/surface-$index.md"
      ;;
  esac
done
"$FRONTMATTER_CHECK" "$scan_root/repo" >/dev/null
"$BODY_CHECK" --root "$scan_root/repo" --scope commands >/dev/null
if LC_ALL=C grep -qE $'\xD0[\x80-\xBF]|\xD1[\x80-\xBF]|\xD2[\x80-\xBF]|\xD3[\x80-\xBF]' \
  "$ROOT/plugins/dr-orchestrate/plugin.yaml"; then
  echo "FAIL: plugin manifest contains non-English Cyrillic text" >&2
  exit 1
fi

echo "PASS: phase3_docs=6 confirmation=true ttl=604800 revalidation=86400 hard_gate=true version_unchanged=true english=true"
