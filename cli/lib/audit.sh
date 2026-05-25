#!/usr/bin/env bash
# cli/lib/audit.sh — JSONL audit log appender (Phase 3, TUNE-0271).
# Source: TUNE-0271 plan § Detailed Design 4.2.
#
# Schema (schema_version: 1, 10 required keys):
#   schema_version, ts, session_id, calling_agent, subcommand, args_hash,
#   reversibility, outcome, duration_ms, exit_code.
#
# Atomic append via python3 fcntl.flock (portable across Linux + macOS; macOS
# does not ship flock(1)). See TUNE-0271 gap-discovery note.
#
# Output path: $AUDIT_DIR/cli-audit-{YYYY-MM-DD}.jsonl (UTC date).
# Override: DATARIM_CLI_AUDIT_DIR.

set -u

cli_audit_dir() {
    printf '%s' "${DATARIM_CLI_AUDIT_DIR:-${DATARIM_ROOT:-$PWD}/datarim/audit}"
}

# audit_append <subcommand> <args_hash> <reversibility> <outcome> <duration_ms> <exit_code>
# session_id + ts + calling_agent + schema_version derived from env/wall clock.
audit_append() {
    local subcommand="$1" args_hash="$2" reversibility="$3"
    local outcome="$4" duration_ms="$5" exit_code="$6"
    local audit_dir audit_file ts session_id calling_agent
    audit_dir="$(cli_audit_dir)"
    mkdir -p "$audit_dir"
    audit_file="$audit_dir/cli-audit-$(date -u +%F).jsonl"
    ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || python3 -c "import datetime; print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.')+f'{datetime.datetime.utcnow().microsecond//1000:03d}Z')")"
    session_id="${DATARIM_CLI_SESSION_ID:-$(_audit_random_id)}"
    calling_agent="${DATARIM_CLI_AGENT_ID:-unknown}"

    # Validate enums before write (fail-loud is better than poisoning JSONL).
    case "$reversibility" in reversible|irreversible) ;; *)
        printf '[audit] invalid reversibility=%s\n' "$reversibility" >&2; return 1 ;;
    esac
    case "$outcome" in success|abort|error|kill_switched) ;; *)
        printf '[audit] invalid outcome=%s\n' "$outcome" >&2; return 1 ;;
    esac

    # Build JSON via python3 to get correct escaping for free.
    python3 - "$audit_file" "$ts" "$session_id" "$calling_agent" "$subcommand" \
              "$args_hash" "$reversibility" "$outcome" "$duration_ms" "$exit_code" <<'PY'
import fcntl, json, os, sys
(audit_file, ts, session_id, calling_agent, subcommand, args_hash,
 reversibility, outcome, duration_ms, exit_code) = sys.argv[1:11]
line = json.dumps({
    "schema_version": 1,
    "ts": ts,
    "session_id": session_id,
    "calling_agent": calling_agent,
    "subcommand": subcommand,
    "args_hash": args_hash,
    "reversibility": reversibility,
    "outcome": outcome,
    "duration_ms": int(duration_ms),
    "exit_code": int(exit_code),
}, separators=(',', ':'), ensure_ascii=False)
fd = os.open(audit_file, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    os.write(fd, (line + "\n").encode("utf-8"))
finally:
    fcntl.flock(fd, fcntl.LOCK_UN)
    os.close(fd)
PY
}

_audit_random_id() {
    python3 -c "import secrets; print(secrets.token_hex(8))"
}

# args_hash <arg1> <arg2> ... → sha256:<64hex>
audit_args_hash() {
    local joined
    joined="$(printf '%s\0' "$@")"
    local sha
    sha=$(printf '%s' "$joined" | shasum -a 256 2>/dev/null | awk '{print $1}')
    if [ -z "$sha" ]; then
        sha=$(printf '%s' "$joined" | sha256sum 2>/dev/null | awk '{print $1}')
    fi
    printf 'sha256:%s' "$sha"
}

# Stub for Phase 5+ remote audit mirror (Vault / Loki). Returns 99 by contract.
opsbot_emit() {
    return 99
}

# Local-only retention purge:
#   files < 90 d untouched
#   90 d ≤ age < 180 d → gzip into $AUDIT_DIR/archive/
#   age ≥ 180 d → unlink
# Caller: dev-tools/check-cli-audit-schema.sh --purge-older-than 90d
audit_purge() {
    local audit_dir today_epoch file
    audit_dir="$(cli_audit_dir)"
    [ -d "$audit_dir" ] || return 0
    mkdir -p "$audit_dir/archive"
    today_epoch=$(date -u +%s)
    for file in "$audit_dir"/cli-audit-*.jsonl; do
        [ -f "$file" ] || continue
        local fname age_days file_epoch
        fname="$(basename "$file")"
        # cli-audit-YYYY-MM-DD.jsonl
        local datepart="${fname#cli-audit-}"; datepart="${datepart%.jsonl}"
        file_epoch=$(python3 -c "import datetime,sys; d=sys.argv[1]; print(int(datetime.datetime.strptime(d,'%Y-%m-%d').replace(tzinfo=datetime.timezone.utc).timestamp()))" "$datepart" 2>/dev/null || echo 0)
        [ "$file_epoch" -eq 0 ] && continue
        age_days=$(( (today_epoch - file_epoch) / 86400 ))
        if [ "$age_days" -ge 180 ]; then
            rm -f "$file"
            # Also clean the archived gz if present
            rm -f "$audit_dir/archive/$fname.gz"
        elif [ "$age_days" -ge 90 ]; then
            if [ ! -f "$audit_dir/archive/$fname.gz" ]; then
                gzip -c "$file" > "$audit_dir/archive/$fname.gz"
                rm -f "$file"
            fi
        fi
    done
}
