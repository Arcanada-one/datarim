#!/usr/bin/env bash
# personal-id-lint workflow body (static bash invocation from the workflow).
set -euo pipefail
chmod +x scripts/personal-id-gate.sh
if [ -n "${PERSONAL_ID_OVERLAY_B64:-}" ]; then
  overlay="$(mktemp)"
  trap 'rm -f "$overlay"' EXIT
  printf '%s' "$PERSONAL_ID_OVERLAY_B64" | base64 --decode > "$overlay"
  export DATARIM_PERSONAL_ID_OVERLAY="$overlay"
  python3 scripts/verify-personal-id-overlay-revision.py --overlay "$overlay"
else
  echo "::notice::private overlay: absent - shipped patterns only"
fi
# Findings are printed as path:line only; the matched text could be
# the very identifier the gate exists to keep out of public logs.
bash scripts/personal-id-gate.sh --report | sed -E 's/^([^:]+:[0-9]+):.*/\1/'
