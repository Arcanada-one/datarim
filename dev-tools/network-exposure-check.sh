#!/usr/bin/env bash
# network-exposure-check.sh — TUNE-0109 secure-by-default network exposure linter.
#
# Verifies that bind targets across docker-compose / redis.conf / postgresql.conf
# / systemd .socket files conform to Datarim Tier model 0–3:
#   Tier 0: no ports entry            (allowed)
#   Tier 1: 127.0.0.1 / ::1           (allowed)
#   Tier 2: 100.64.0.0/10 (Tailscale) (allowed)
#   Tier 3: 0.0.0.0 / [::] / public   (allowed iff x-exposure-justification + x-exposure-expires <= 90d)
#
# Source-of-truth contract: skills/network-exposure-baseline.md.
#
# Exit codes:
#   0 — clean
#   1 — at least one violation found
#   2 — usage error / missing dependency
#
set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="network-exposure-check.sh"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--compose PATH]... [--redis-conf PATH]... \\
                    [--postgres-conf PATH]... [--systemd-socket PATH]... \\
                    [--strict] [--format text|sarif] [--today YYYY-MM-DD]

Options:
  --compose PATH         Docker compose file to lint (repeatable).
  --redis-conf PATH      Redis configuration file (repeatable).
  --postgres-conf PATH   PostgreSQL configuration file (repeatable).
  --systemd-socket PATH  systemd .socket unit (repeatable).
  --strict               Treat warnings as failures (default ON).
  --format FMT           text (default) | sarif.
  --today YYYY-MM-DD     Override "today" date for TTL test fixtures.
  --version              Print version and exit.
  -h, --help             Show this help.
EOF
}

# ---------------------------------------------------------------------------
# Tier classification primitives.
# ---------------------------------------------------------------------------

# Allowlist regexes (POSIX-extended).
readonly RX_LOOPBACK_V4='^127\.0\.0\.1$'
readonly RX_LOOPBACK_V6='^(::1|::ffff:127\.0\.0\.1)$'
readonly RX_TAILSCALE_V4='^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+$'
readonly RX_TAILSCALE_V6_MAPPED='^::ffff:100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+$'

# Blocklist regexes.
readonly RX_PUBLIC_V4='^0\.0\.0\.0$'
readonly RX_UNSPECIFIED_V6='^(::|0:0:0:0:0:0:0:0)$'

# classify_bind <bind-string-without-brackets>
# Echoes one of: tier1 | tier2 | tier3_public | malformed
classify_bind() {
    local raw="$1"
    [[ -z "$raw" ]] && { echo malformed; return; }
    if [[ "$raw" =~ $RX_LOOPBACK_V4 ]] || [[ "$raw" =~ $RX_LOOPBACK_V6 ]]; then
        echo tier1; return
    fi
    if [[ "$raw" =~ $RX_TAILSCALE_V4 ]] || [[ "$raw" =~ $RX_TAILSCALE_V6_MAPPED ]]; then
        echo tier2; return
    fi
    if [[ "$raw" =~ $RX_PUBLIC_V4 ]] || [[ "$raw" =~ $RX_UNSPECIFIED_V6 ]]; then
        echo tier3_public; return
    fi
    # Any other IPv6 in [::ffff:...] form mapping a non-loopback v4 → public.
    if [[ "$raw" =~ ^::ffff:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        local mapped="${BASH_REMATCH[1]}"
        if [[ "$mapped" == "127.0.0.1" ]]; then echo tier1; return; fi
        echo tier3_public; return
    fi
    # Any other IPv6 (global unicast, link-local, ULA) → treat as public, demand justification.
    if [[ "$raw" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$raw" == *:* ]]; then
        echo tier3_public; return
    fi
    echo malformed
}

# ---------------------------------------------------------------------------
# TTL / justification primitives.
# ---------------------------------------------------------------------------

today_iso() {
    if [[ -n "${TODAY_OVERRIDE:-}" ]]; then
        echo "$TODAY_OVERRIDE"
    else
        date -u +%Y-%m-%d
    fi
}

# date_diff_days <YYYY-MM-DD> <YYYY-MM-DD>
# Echo signed integer (later − earlier).
date_diff_days() {
    python3 -c "
from datetime import date
a = date.fromisoformat('$1')
b = date.fromisoformat('$2')
print((b - a).days)
"
}

# ---------------------------------------------------------------------------
# Docker compose linter.
# ---------------------------------------------------------------------------

lint_compose() {
    local file="$1"
    [[ -f "$file" ]] || { emit_error "$file" 0 "file not found"; return 1; }
    command -v yq >/dev/null 2>&1 || { emit_error "$file" 0 "yq not installed"; return 2; }

    local services
    services="$(yq -r '.services // {} | keys | .[]' "$file" 2>/dev/null)" || {
        emit_error "$file" 0 "yq failed to parse"
        return 1
    }

    local rc=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local justification expires
        justification="$(yq -r ".services.\"$svc\".\"x-exposure-justification\" // \"\"" "$file" 2>/dev/null)"
        expires="$(yq -r ".services.\"$svc\".\"x-exposure-expires\" // \"\"" "$file" 2>/dev/null)"

        local has_justification=0 ttl_ok=0 ttl_reason="missing"
        if [[ -n "$justification" ]]; then has_justification=1; fi
        if [[ -n "$expires" ]]; then
            local diff today
            today="$(today_iso)"
            if diff="$(date_diff_days "$today" "$expires" 2>/dev/null)"; then
                if (( diff >= 0 )) && (( diff <= 90 )); then
                    ttl_ok=1; ttl_reason="ok"
                elif (( diff < 0 )); then
                    ttl_reason="expired($diff days)"
                else
                    ttl_reason="too-long($diff days >90)"
                fi
            else
                ttl_reason="malformed-date"
            fi
        fi

        local idx=0
        local ports_count
        ports_count="$(yq -r ".services.\"$svc\".ports // [] | length" "$file" 2>/dev/null)"
        while (( idx < ports_count )); do
            local raw line
            raw="$(yq -r ".services.\"$svc\".ports[$idx]" "$file" 2>/dev/null)"
            line="$(grep -nF -- "$raw" "$file" | head -1 | cut -d: -f1)"
            line="${line:-0}"
            check_compose_port "$file" "$line" "$svc" "$raw" "$has_justification" "$ttl_ok" "$ttl_reason" || rc=1
            idx=$((idx+1))
        done
    done <<< "$services"

    return "$rc"
}

# Parse one compose port string, classify, emit verdict.
check_compose_port() {
    local file="$1" line="$2" svc="$3" raw="$4"
    local has_just="$5" ttl_ok="$6" ttl_reason="$7"
    local host=""

    # Strip outer quotes.
    raw="${raw#\"}"; raw="${raw%\"}"
    raw="${raw#\'}"; raw="${raw%\'}"

    if [[ "$raw" =~ ^\[([0-9a-fA-F:.%]+)\]:[0-9]+(:[0-9]+)?$ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$raw" =~ ^([0-9.]+):[0-9]+:[0-9]+$ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$raw" =~ ^[0-9]+:[0-9]+$ ]] || [[ "$raw" =~ ^[0-9]+$ ]]; then
        host=""  # short-form ⇒ implicit 0.0.0.0
    else
        emit_warn "$file" "$line" "compose:$svc unrecognized port form: '$raw'"
        return 1
    fi

    if [[ -z "$host" ]]; then
        emit_violation "$file" "$line" "compose:$svc short-form port '$raw' implicitly binds 0.0.0.0 (Tier 3) — use 127.0.0.1: prefix or justify"
        return 1
    fi

    local tier
    tier="$(classify_bind "$host")"
    case "$tier" in
        tier1|tier2)
            emit_ok "$file" "$line" "compose:$svc $host ($tier)"
            return 0
            ;;
        tier3_public)
            if (( has_just == 1 )) && (( ttl_ok == 1 )); then
                emit_ok "$file" "$line" "compose:$svc $host (Tier 3 justified, ttl=$ttl_reason)"
                return 0
            fi
            emit_violation "$file" "$line" "compose:$svc $host (Tier 3 public) — justification=${has_just} ttl=$ttl_reason"
            return 1
            ;;
        malformed|*)
            emit_violation "$file" "$line" "compose:$svc malformed bind '$host'"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Redis / Postgres / systemd linters.
# ---------------------------------------------------------------------------

lint_redis() {
    local file="$1"
    [[ -f "$file" ]] || { emit_error "$file" 0 "file not found"; return 1; }
    local rc=0 line=0
    while IFS= read -r raw; do
        line=$((line+1))
        local stripped="${raw%%#*}"
        [[ "$stripped" =~ ^[[:space:]]*bind[[:space:]]+(.*)$ ]] || continue
        local addrs="${BASH_REMATCH[1]}"
        addrs="${addrs%%[[:space:]]}"
        local addr all_pass=1
        for addr in $addrs; do
            local tier; tier="$(classify_bind "$addr")"
            case "$tier" in
                tier1|tier2) ;;
                *) all_pass=0; emit_violation "$file" "$line" "redis bind '$addr' is $tier"; rc=1 ;;
            esac
        done
        (( all_pass == 1 )) && emit_ok "$file" "$line" "redis bind '$addrs'"
    done < "$file"
    return "$rc"
}

lint_postgres() {
    local file="$1"
    [[ -f "$file" ]] || { emit_error "$file" 0 "file not found"; return 1; }
    local rc=0 line=0
    while IFS= read -r raw; do
        line=$((line+1))
        local stripped="${raw%%#*}"
        [[ "$stripped" =~ ^[[:space:]]*listen_addresses[[:space:]]*=[[:space:]]*[\'\"]?([^\'\"#]+)[\'\"]? ]] || continue
        local val="${BASH_REMATCH[1]}"
        val="${val%%[[:space:]]}"
        if [[ "$val" == "*" ]]; then
            emit_violation "$file" "$line" "postgres listen_addresses='*' (Tier 3 public, no justification possible inline)"
            rc=1; continue
        fi
        local addr all_pass=1
        IFS=',' read -ra addrs <<< "$val"
        for addr in "${addrs[@]}"; do
            addr="${addr#"${addr%%[![:space:]]*}"}"
            addr="${addr%"${addr##*[![:space:]]}"}"
            if [[ "$addr" == "localhost" ]]; then continue; fi
            local tier; tier="$(classify_bind "$addr")"
            case "$tier" in
                tier1|tier2) ;;
                *) all_pass=0; emit_violation "$file" "$line" "postgres listen_addresses '$addr' is $tier"; rc=1 ;;
            esac
        done
        (( all_pass == 1 )) && emit_ok "$file" "$line" "postgres listen_addresses='$val'"
    done < "$file"
    return "$rc"
}

lint_systemd_socket() {
    local file="$1"
    [[ -f "$file" ]] || { emit_error "$file" 0 "file not found"; return 1; }
    local rc=0 line=0
    while IFS= read -r raw; do
        line=$((line+1))
        local stripped="${raw%%#*}"
        [[ "$stripped" =~ ^[[:space:]]*ListenStream[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        local val="${BASH_REMATCH[1]}"
        val="${val%%[[:space:]]}"
        local host=""
        if [[ "$val" =~ ^\[([0-9a-fA-F:.%]+)\]:[0-9]+$ ]]; then
            host="${BASH_REMATCH[1]}"
        elif [[ "$val" =~ ^([0-9.]+):[0-9]+$ ]]; then
            host="${BASH_REMATCH[1]}"
        elif [[ "$val" =~ ^/ ]]; then
            emit_ok "$file" "$line" "systemd ListenStream=$val (unix socket)"
            continue
        else
            emit_violation "$file" "$line" "systemd ListenStream='$val' lacks explicit host"
            rc=1; continue
        fi
        local tier; tier="$(classify_bind "$host")"
        case "$tier" in
            tier1|tier2) emit_ok "$file" "$line" "systemd ListenStream=$val ($tier)" ;;
            *) emit_violation "$file" "$line" "systemd ListenStream=$val is $tier"; rc=1 ;;
        esac
    done < "$file"
    return "$rc"
}

# ---------------------------------------------------------------------------
# Output helpers.
# ---------------------------------------------------------------------------

emit_ok()        { (( VERBOSE == 1 )) && printf 'PASS  %s:%s: %s\n' "$1" "$2" "$3" >&2; return 0; }
emit_warn()      { printf 'WARN  %s:%s: %s\n' "$1" "$2" "$3" >&2; }
emit_violation() { printf 'FAIL  %s:%s: %s\n' "$1" "$2" "$3"; }
emit_error()     { printf 'ERROR %s:%s: %s\n' "$1" "$2" "$3" >&2; }

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

main() {
    local -a composes=() redises=() postgreses=() sockets=()
    local strict=1 format=text
    VERBOSE=0
    TODAY_OVERRIDE=""

    while (( $# > 0 )); do
        case "$1" in
            --compose)         composes+=("$2"); shift 2 ;;
            --redis-conf)      redises+=("$2"); shift 2 ;;
            --postgres-conf)   postgreses+=("$2"); shift 2 ;;
            --systemd-socket)  sockets+=("$2"); shift 2 ;;
            --strict)          strict=1; shift ;;
            --no-strict)       strict=0; shift ;;
            --format)          format="$2"; shift 2 ;;
            --today)           TODAY_OVERRIDE="$2"; shift 2 ;;
            --verbose|-v)      VERBOSE=1; shift ;;
            --version)         echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
            -h|--help)         usage; exit 0 ;;
            *)                 echo "unknown arg: $1" >&2; usage; exit 2 ;;
        esac
    done

    local rc=0 path
    for path in ${composes[@]+"${composes[@]}"};     do lint_compose         "$path" || rc=1; done
    for path in ${redises[@]+"${redises[@]}"};       do lint_redis           "$path" || rc=1; done
    for path in ${postgreses[@]+"${postgreses[@]}"}; do lint_postgres        "$path" || rc=1; done
    for path in ${sockets[@]+"${sockets[@]}"};       do lint_systemd_socket  "$path" || rc=1; done

    if [[ "$format" != "text" ]]; then
        echo "format '$format' not implemented (only 'text' supported)" >&2
        return 2
    fi

    (( strict == 0 )) && rc=0
    return "$rc"
}

main "$@"
