#!/usr/bin/env bash
set -euo pipefail
case "$STACK" in
  typescript_pnpm) required="node corepack" ;;
  rust_cargo)      required="cargo" ;;
  python)          required="python3" ;;
  framework)       required="shellcheck" ;;
  *) echo "ERROR: unknown stack profile: $STACK" >&2; exit 1 ;;
esac
missing=""
for bin in $required; do
  command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
  echo "ERROR: stack '$STACK' requires:$missing" >&2
  echo "       runner '${RUNNER_NAME:-unknown}' does not provide them, and the" >&2
  echo "       provisioning step above did not supply them either." >&2
  echo "       This gate must never pass without actually auditing." >&2
  exit 1
fi
echo "toolchain OK for '$STACK' on runner '${RUNNER_NAME:-unknown}':$(for b in $required; do printf ' %s=%s' "$b" "$(command -v "$b")"; done)"
