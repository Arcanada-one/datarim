#!/usr/bin/env bash
# fleet_concurrency.sh — basic concurrency control for fleet spawn (design 3b).
#
# Two orthogonal controls:
#   1. Per-task lock (mkdir-atomic) — prevents a second spawn racing the same
#      task. `flock` is NOT assumed (absent on macOS); mkdir is atomic on every
#      POSIX filesystem, matching the plugin-system locking precedent.
#   2. Cap enforcement — a role's active fleet sessions may not exceed its
#      roles.yaml `max_parallel`, nor the global `global_max_parallel`.
#
# Full DEV-server provisioning (port registry, schema-per-project, Redis
# DB-per-project) is OUT OF SCOPE here — that is a separate infrastructure task.
#
# Usage:
#   fleet_concurrency.sh fleet_acquire_lock <task-id>
#   fleet_concurrency.sh fleet_release_lock <task-id>
#   fleet_concurrency.sh fleet_cap_check    <role> <active-count>
#
# Exit codes: 0 ok | 1 denied (lock held / cap reached / unknown role) | 2 usage.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_FLEET_REPO:=$(cd "$DR_ORCH_DIR/../.." && pwd)}"
: "${DR_FLEET_LOCK_DIR:=$HOME/.local/share/dr-orchestrate/fleet-locks}"
: "${DR_FLEET_ROLES:=$DR_FLEET_REPO/config/roles.yaml}"

_valid_id() {
  # Task IDs and roles: conservative slug to keep them safe as path components.
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

fleet_acquire_lock() {
  local task="${1:-}"
  _valid_id "$task" || { echo "ERROR: invalid task id" >&2; return 2; }
  mkdir -p "$DR_FLEET_LOCK_DIR"
  # mkdir is atomic: succeeds only if the lock dir did not already exist.
  if mkdir "$DR_FLEET_LOCK_DIR/$task.lock" 2>/dev/null; then
    return 0
  fi
  echo "ERROR: fleet lock already held for task: $task" >&2
  return 1
}

fleet_release_lock() {
  local task="${1:-}"
  _valid_id "$task" || { echo "ERROR: invalid task id" >&2; return 2; }
  rmdir "$DR_FLEET_LOCK_DIR/$task.lock" 2>/dev/null || true
}

# fleet_cap_check <role> <active-count> — allow (0) iff active < role max_parallel
# AND active < global_max_parallel. Unknown role fails closed (1).
fleet_cap_check() {
  local role="${1:-}" active="${2:-}"
  _valid_id "$role" || { echo "ERROR: invalid role" >&2; return 2; }
  [[ "$active" =~ ^[0-9]+$ ]] || { echo "ERROR: active-count must be an integer" >&2; return 2; }
  [ -f "$DR_FLEET_ROLES" ] || { echo "ERROR: roles file not found: $DR_FLEET_ROLES" >&2; return 1; }

  local caps
  caps="$(python3 - "$DR_FLEET_ROLES" "$role" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
role = sys.argv[2]
g = doc.get("global_max_parallel")
rc = None
for r in (doc.get("roles") or []):
    if r.get("id") == role:
        rc = r.get("max_parallel"); break
if rc is None or g is None:
    sys.exit(3)   # unknown role or missing global cap → fail closed
print(f"{rc} {g}")
PY
  )" || { echo "ERROR: unknown role or malformed roles.yaml: $role" >&2; return 1; }

  local role_cap global_cap
  role_cap="${caps%% *}"; global_cap="${caps##* }"
  if [ "$active" -ge "$role_cap" ]; then
    echo "ERROR: role '$role' at cap ($active >= max_parallel $role_cap)" >&2
    return 1
  fi
  if [ "$active" -ge "$global_cap" ]; then
    echo "ERROR: global fleet cap reached ($active >= global_max_parallel $global_cap)" >&2
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [ -n "$fn" ] || { echo "usage: fleet_concurrency.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
