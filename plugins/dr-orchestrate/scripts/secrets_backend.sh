#!/usr/bin/env bash
# secrets_backend.sh — pluggable secrets backend (Phase 1: YAML; Vault stub).
# V-AC: 9 (YAML get + mode 0600 enforcement).
set -euo pipefail

# yaml_get <file> <key> — print value of top-level scalar key. Mode MUST be 0600.
# Exit codes: 0 ok, 1 file missing, 2 mode wrong, 3 key missing.
yaml_get() {
  local file="$1"; local key="$2"
  [[ -f "$file" ]] || { echo "ERR: $file missing" >&2; return 1; }
  local mode
  mode="$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null)"
  [[ -n "$mode" ]] || { echo "ERR: cannot stat $file" >&2; return 1; }
  if [[ "$mode" != "600" ]]; then
    echo "ERR: $file mode $mode (need 600)" >&2
    return 2
  fi
  local value
  value="$(awk -v k="$key" '
    BEGIN { found = 0 }
    $0 ~ "^[[:space:]]*"k"[[:space:]]*:" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      # strip matching surrounding quotes
      if (match($0, /^".*"$/) || match($0, /^'\''.*'\''$/)) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      found = 1
      exit
    }
    END { exit (found ? 0 : 3) }
  ' "$file")" || return 3
  printf '%s\n' "$value"
}

vault_get() {
  echo "ERR: Vault backend deferred to Phase 2 (TUNE-0165)" >&2
  return 99
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: secrets_backend.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
