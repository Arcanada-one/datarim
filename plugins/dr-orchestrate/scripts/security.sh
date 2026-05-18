#!/usr/bin/env bash
# security.sh — whitelist + escape detection + cooldown + violation tracking
# Phase 1 (TUNE-0164). V-AC: 6 (escape block), 7 (micro-cooldown 500ms),
# 8 (5 violations/hour → 1h pane block). Fail-closed by design.
set -euo pipefail

: "${STATE_DIR:=/tmp/dr-orchestrate-state}"
mkdir -p "$STATE_DIR"

# Whitelist allowed input characters. Anything else → fail-closed.
# Source: INSIGHTS-TUNE-0104 CP-5 (CVE-2019-9535 mitigation).
WHITELIST_RE='^[a-zA-Z0-9 _./:=@-]+$'

# Portable millisecond clock. macOS `date +%s%N` returns literal "%N".
# Bash 5+ has $EPOCHREALTIME; older bash falls back to perl (always present
# on mac and Ubuntu base images).
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local r="$EPOCHREALTIME"
    local sec="${r%.*}"
    local frac="${r#*.}"
    frac="${frac:0:3}"
    while [[ ${#frac} -lt 3 ]]; do frac="${frac}0"; done
    echo "$(( 10#$sec * 1000 + 10#$frac ))"
  else
    perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
  fi
}

audit_block() {
  local reason="$1"; local input="$2"
  local h
  h="$(printf '%s' "$input" | shasum -a 256 | awk '{print $1}')"
  echo "SECURITY_BLOCK|reason=${reason}|input_hash=${h}" >&2
}

check_whitelist() {
  local text="$1"
  [[ "$text" =~ $WHITELIST_RE ]] || { audit_block "whitelist" "$text"; return 1; }
}

check_escape() {
  local text="$1"
  [[ "$text" != *$'\x1b'* ]] || { audit_block "escape" "$text"; return 1; }
}

# Two-layer cooldown (TUNE-0165 M4: flock-race-safe under concurrency):
#   micro    — 500 ms gate per send to the same pane.
#   decision — 60 s gate per autonomous decision to the same pane.
# Hits within window → record_violation + return 1. Misses update timestamp.
# Where `flock` is available (Linux util-linux) the read-write window is held
# inside a non-blocking exclusive lock so concurrent contenders fall through
# to "blocked" rather than racing the timestamp file. On macOS (no flock by
# default) the behavior degrades to Phase-1 non-atomic semantics with a one-
# time WARN; the V-AC-21 contract is Linux-gated.
_warn_flock_once() {
  local kind="$1"
  local sentinel="$STATE_DIR/.warned.flock-${kind}"
  [[ -f "$sentinel" ]] && return 0
  echo "WARN flock unavailable on this host — cooldown is not race-safe (kind=${kind})" >&2
  : > "$sentinel"
}

_cooldown_check_unlocked() {
  local pane="$1"; local kind="$2"; local floor="$3"
  local safe_pane="${pane//\//_}"; safe_pane="${safe_pane//:/_}"
  local state_file="$STATE_DIR/${safe_pane}.cooldown.${kind}"
  local now; now="$(now_ms)"
  if [[ -f "$state_file" ]]; then
    local last; last="$(cat "$state_file")"
    if (( now - last < floor )); then
      record_violation "$pane" "$kind"
      return 1
    fi
  fi
  echo "$now" > "$state_file"
}

check_cooldown() {
  local pane="$1"; local kind="${2:-micro}"
  local floor
  case "$kind" in
    micro)    floor=500 ;;
    decision) floor=60000 ;;
    *)        echo "ERR: unknown cooldown kind '$kind'" >&2; return 2 ;;
  esac
  if command -v flock >/dev/null 2>&1; then
    local safe_pane="${pane//\//_}"; safe_pane="${safe_pane//:/_}"
    local lock_file="$STATE_DIR/${safe_pane}.cooldown.${kind}.lock"
    (
      flock -n 200 || exit 1
      _cooldown_check_unlocked "$pane" "$kind" "$floor"
    ) 200>"$lock_file"
  else
    _warn_flock_once "$kind"
    _cooldown_check_unlocked "$pane" "$kind" "$floor"
  fi
}

# Violation ledger. 5 violations of any kind within 1 hour → pane blocked 1 h.
record_violation() {
  local pane="$1"; local kind="$2"
  local safe_pane="${pane//\//_}"; safe_pane="${safe_pane//:/_}"
  local v_file="$STATE_DIR/${safe_pane}.violations"
  local count
  count="$(grep -c '' "$v_file" 2>/dev/null || true)"
  count="${count:-0}"
  echo "$(date -u +%s)|${kind}" >> "$v_file"
  if (( count + 1 >= 5 )); then
    touch "$STATE_DIR/${safe_pane}.blocked"
  fi
}

# Pane-block test. Returns 0 if block file exists AND is < 1 h old.
# Stale block files are cleaned and return 1 (not blocked).
is_pane_blocked() {
  local pane="$1"
  local safe_pane="${pane//\//_}"; safe_pane="${safe_pane//:/_}"
  local b="$STATE_DIR/${safe_pane}.blocked"
  [[ -f "$b" ]] || return 1
  local mtime
  mtime="$(stat -f %m "$b" 2>/dev/null || stat -c %Y "$b" 2>/dev/null)"
  [[ -n "$mtime" ]] || return 1
  if (( $(date -u +%s) - mtime >= 3600 )); then
    rm -f "$b"
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: security.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
