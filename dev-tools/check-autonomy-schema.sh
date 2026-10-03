#!/usr/bin/env bash
# Validate one or more space.yml autonomy blocks.
set -euo pipefail

(( $# > 0 )) || { echo "usage: check-autonomy-schema.sh <space.yml> [...]" >&2; exit 2; }

failed=0
for file in "$@"; do
  if ! yq eval -e '
    .autonomy.schema_version == 1 and
    (.autonomy.policy | type == "!!map") and
    ([.autonomy.policy[] | (. == "auto" or . == "operator")] | all)
  ' "$file" >/dev/null 2>&1; then
    echo "FAIL: invalid autonomy block: $file" >&2
    failed=1
  fi
done
exit "$failed"
