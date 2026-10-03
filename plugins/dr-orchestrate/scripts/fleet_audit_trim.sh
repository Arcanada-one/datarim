#!/usr/bin/env bash
# fleet_audit_trim.sh — Archive-before-XTRIM for fleet:audit-log stream.
#
# Reads all entries from stream:fleet:audit-log via XRANGE, writes them to a
# gzip-compressed JSONL archive file, then trims the stream to --max-len.
#
# Usage:
#   fleet_audit_trim.sh [--max-len N] [--dry-run] [--help]
#
# Options:
#   --max-len N    Keep this many entries after trim (default: 1000000)
#   --dry-run      Print what would happen; do NOT trim or archive
#
# Env:
#   DR_ORCH_REDIS_URL          Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_AUDIT_ARCHIVE_DIR Directory for archive files
#                              (default: var/fleet/audit-archive relative to plugin root)
#
# Archive filename: <archive-dir>/YYYY-MM-DD.jsonl.gz (date = UTC today)
# If the archive for today exists, new entries are appended before re-gzip.
#
# Cron recommendation: run once every 24h, e.g. 03:00 UTC

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_AUDIT_ARCHIVE_DIR:=$PLUGIN_DIR/var/fleet/audit-archive}"

STREAM_KEY="stream:fleet:audit-log"
MAX_LEN=1000000
DRY_RUN=0

_usage() {
  printf 'usage: fleet_audit_trim.sh [--max-len N] [--dry-run] [--help]\n'
  printf '  Archives stream:%s to JSONL.GZ before XTRIM.\n' "$STREAM_KEY"
  printf 'env: DR_ORCH_REDIS_URL, DR_FLEET_AUDIT_ARCHIVE_DIR\n'
}

# ── arg parser ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-len) MAX_LEN="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help)    _usage; exit 0 ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

# ── require redis-cli ─────────────────────────────────────────────────────────

if ! command -v redis-cli >/dev/null 2>&1; then
  printf 'ERR: redis-cli not found in PATH\n' >&2
  exit 1
fi

# ── redis connectivity ────────────────────────────────────────────────────────

if ! redis-cli -u "$DR_ORCH_REDIS_URL" ping 2>/dev/null | grep -q PONG; then
  printf 'ERR: cannot reach Redis at %s\n' "$DR_ORCH_REDIS_URL" >&2
  exit 1
fi

# ── stream length check ───────────────────────────────────────────────────────

stream_len=$(redis-cli -u "$DR_ORCH_REDIS_URL" XLEN "$STREAM_KEY" 2>/dev/null || echo 0)

if (( stream_len <= 0 )); then
  printf 'INFO: stream %s has 0 entries — nothing to archive\n' "$STREAM_KEY"
  exit 0
fi

printf 'INFO: stream %s has %d entries (max-len=%d)\n' "$STREAM_KEY" "$stream_len" "$MAX_LEN"

# ── dry-run early exit ────────────────────────────────────────────────────────

if (( DRY_RUN )); then
  printf 'DRY-RUN: would archive %d entries → %s/YYYY-MM-DD.jsonl.gz\n' \
    "$stream_len" "$DR_FLEET_AUDIT_ARCHIVE_DIR"
  printf 'DRY-RUN: would trim stream to max-len=%d\n' "$MAX_LEN"
  exit 0
fi

# ── archive ───────────────────────────────────────────────────────────────────

mkdir -p "$DR_FLEET_AUDIT_ARCHIVE_DIR"

today=$(date -u +%Y-%m-%d)
archive_file="$DR_FLEET_AUDIT_ARCHIVE_DIR/${today}.jsonl.gz"
tmp_jsonl=$(mktemp)

# Trap to clean up temp file on exit
trap 'rm -f "$tmp_jsonl"' EXIT

# XRANGE returns pairs: <id> <field> <val> <field> <val> ...
# We convert each entry to a JSON object line using awk.
redis-cli -u "$DR_ORCH_REDIS_URL" XRANGE "$STREAM_KEY" - + \
  | awk '
    /^[0-9]+-[0-9]+$/ {
      if (id != "") {
        printf "{\"_id\":\"%s\"", id
        for (k in fields) printf ",\"%s\":\"%s\"", k, fields[k]
        printf "}\n"
      }
      id = $0; delete fields
      next
    }
    /^[a-zA-Z_]/ && id != "" {
      last_key = $0; next
    }
    id != "" && last_key != "" {
      fields[last_key] = $0; last_key = ""
    }
    END {
      if (id != "") {
        printf "{\"_id\":\"%s\"", id
        for (k in fields) printf ",\"%s\":\"%s\"", k, fields[k]
        printf "}\n"
      }
    }
  ' > "$tmp_jsonl"

entry_count=$(wc -l < "$tmp_jsonl" | tr -d ' ')
printf 'INFO: archiving %d entries to %s\n' "$entry_count" "$archive_file"

# If archive for today exists, decompress + append + recompress
if [[ -f "$archive_file" ]]; then
  tmp_existing=$(mktemp)
  trap 'rm -f "$tmp_jsonl" "$tmp_existing"' EXIT
  gunzip -c "$archive_file" >> "$tmp_existing" 2>/dev/null || true
  cat "$tmp_jsonl" >> "$tmp_existing"
  gzip -c "$tmp_existing" > "${archive_file}.new"
  mv "${archive_file}.new" "$archive_file"
  rm -f "$tmp_existing"
else
  gzip -c "$tmp_jsonl" > "$archive_file"
fi

printf 'INFO: archive written: %s\n' "$archive_file"

# ── trim ──────────────────────────────────────────────────────────────────────

redis-cli -u "$DR_ORCH_REDIS_URL" XTRIM "$STREAM_KEY" MAXLEN "~" "$MAX_LEN" >/dev/null
printf 'INFO: trimmed %s to maxlen~%d\n' "$STREAM_KEY" "$MAX_LEN"

exit 0
