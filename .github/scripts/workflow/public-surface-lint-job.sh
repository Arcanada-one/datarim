#!/usr/bin/env bash
# public-surface-lint reusable workflow body.
# Checks out Arcanada-one/datarim into .datarim and runs the linter.
set -euo pipefail
DATARIM_REF="${DATARIM_REF:-main}"
PATHS_INPUT="${PATHS_INPUT:-README.md CHANGELOG.md CONTRIBUTING.md docs packages}"
CONSUMER_REGEX="${CONSUMER_REGEX:-}"
REPORT="${REPORT:-true}"

rm -rf .datarim
git clone --depth 1 https://github.com/Arcanada-one/datarim.git .datarim
git -C .datarim fetch --depth 1 origin "$DATARIM_REF"
git -C .datarim checkout --force FETCH_HEAD

if [ -n "$CONSUMER_REGEX" ] && [ -f "$CONSUMER_REGEX" ]; then
  REGEX_PATH="$CONSUMER_REGEX"
else
  REGEX_PATH=".datarim/dev-tools/public-surface-forbidden.regex"
fi

set -uo pipefail
args=(--regex "$REGEX_PATH" --paths)
# shellcheck disable=SC2086
for p in $PATHS_INPUT; do [ -n "$p" ] && args+=("$p"); done
[ "$REPORT" = "true" ] && args+=(--report)
./.datarim/dev-tools/public-surface-lint.sh "${args[@]}"
