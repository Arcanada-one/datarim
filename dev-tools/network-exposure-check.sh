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
# Source-of-truth contract: skills/network-exposure-baseline/SKILL.md.
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
                    [--runtime-bind addr:port]... \\
                    [--strict] [--format text|sarif] [--today YYYY-MM-DD]

Options:
  --compose PATH         Docker compose file to lint (repeatable).
  --redis-conf PATH      Redis configuration file (repeatable).
  --postgres-conf PATH   PostgreSQL configuration file (repeatable).
  --systemd-socket PATH  systemd .socket unit (repeatable).
  --runtime-bind ADDR:PORT  Classify a runtime listener bind directly
                          (TUNE-0295 — for socat / dr_orchestrate_server).
                          Exit 0 = tier1/tier2, 1 = tier3, 2 = malformed.
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

# Dotted-quad IPv4 shape (any specific address). A static linter cannot read
# the host routing table, so a non-loopback, non-mesh specific IPv4 — public
# OR RFC1918 private OR link-local — is block-by-default (tier3_public): it
# requires an explicit justification + TTL. Loopback / Tailscale branches run
# ahead of this and short-circuit; only genuinely unparseable strings fall
# through to "malformed".
readonly RX_IPV4_DOTTED_QUAD='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

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
    # Any other specific IPv4 — public, RFC1918 private (10/8, 172.16/12,
    # 192.168/16), or link-local (169.254/16) — is block-by-default. The linter
    # cannot prove a private bind is mesh-only the way loopback is safe-by-
    # construction, so it demands a justification + TTL (tier3_public) instead
    # of failing as malformed. Loopback / Tailscale already returned above.
    if [[ "$raw" =~ $RX_IPV4_DOTTED_QUAD ]]; then
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
            local raw line ptype
            # docker-compose `config` expands ports into long-form mapping
            # objects ({mode, host_ip, target, published, protocol}); yq dumps
            # them as multi-line YAML, which check_compose_port cannot parse.
            # Detect the mapping (yq prints "!!map") and reconstruct the
            # canonical host:port:port[/proto] string before classification.
            ptype="$(yq -r ".services.\"$svc\".ports[$idx] | type" "$file" 2>/dev/null)"
            if [[ "$ptype" == "!!map" || "$ptype" == "map" ]]; then
                local host_ip published target proto
                host_ip="$(yq -r ".services.\"$svc\".ports[$idx].host_ip // \"\"" "$file" 2>/dev/null)"
                published="$(yq -r ".services.\"$svc\".ports[$idx].published // \"\"" "$file" 2>/dev/null)"
                target="$(yq -r ".services.\"$svc\".ports[$idx].target // \"\"" "$file" 2>/dev/null)"
                proto="$(yq -r ".services.\"$svc\".ports[$idx].protocol // \"\"" "$file" 2>/dev/null)"
                [[ "$host_ip" == "null" ]] && host_ip=""
                [[ "$proto" == "null" || "$proto" == "tcp" ]] && proto=""
                if [[ -n "$host_ip" ]]; then
                    raw="${host_ip}:${published}:${target}"
                else
                    raw="${published}:${target}"
                fi
                [[ -n "$proto" ]] && raw="${raw}/${proto}"
            else
                raw="$(yq -r ".services.\"$svc\".ports[$idx]" "$file" 2>/dev/null)"
            fi
            line="$(grep -nF -- "$raw" "$file" | head -1 | cut -d: -f1)"
            line="${line:-0}"
            check_compose_port "$file" "$line" "$svc" "$raw" "$has_justification" "$ttl_ok" "$ttl_reason" || rc=1
            idx=$((idx+1))
        done
    done <<< "$services"

    return "$rc"
}

# ---------------------------------------------------------------------------
# Compose ${VAR} interpolation (B3 hybrid).
#
# A compose port string may carry shell-style parameter expansions in any of its
# colon-separated segments — host slot and/or port slots — that the linter sees
# verbatim (yq does not interpolate). B3 strategy, per segment, in order:
#   1. env-resolve   — if the named env var is set, use its value
#   2. default-extract — ${VAR:-D} / ${VAR-D} → use the default literal D
#   3. unresolved ${VAR:?} / bare ${VAR} in the HOST slot →
#        3a. Tailscale-mesh var-name (${TAILSCALE_IP} etc.) → Tier 2 pass (TUNE-0123)
#        3b. otherwise → WARN-but-PASS, naming var + file:line
# Segments 1–2 apply to host AND port slots (TUNE-0122: ${PORT:-3700}:3700 and
# 127.0.0.1:${PORT:-3700}:3700 both resolve); step 3 applies to the host slot.
# Security (Mandate S1/S5): the ${...} body is untrusted compose input. The var
# name is regex-validated as the trust boundary; resolution reads the value with
# printenv exclusively — no shell expansion, no indirect expansion, no dynamic
# code execution. Anything failing the gate is a violation, never resolved. A
# token whose body carries command-substitution metacharacters is rejected
# outright as an injection attempt.
RX_VAR_NAME='^[A-Za-z_][A-Za-z0-9_]*$'
# Metacharacters that have no place in a compose bind host and signal an
# injection attempt inside a ${...} body: command substitution, chaining, pipes,
# redirection, backgrounding.
RX_VAR_DANGEROUS='[`;&|<>]|\$\('

# _compose_var_name <full-expansion> → echoes the var name, returns 0 if the
# token is a well-formed ${NAME...} with a regex-valid NAME, else returns 1.
_compose_var_name() {
    local expansion="$1" inner name
    [[ "$expansion" =~ ^\$\{(.*)\}$ ]] || return 1
    inner="${BASH_REMATCH[1]}"
    # NAME is everything up to the first modifier char (: - ? + =) or end.
    name="${inner%%[:?=+-]*}"
    [[ "$name" =~ $RX_VAR_NAME ]] || return 1
    echo "$name"
}

# _compose_var_default <full-expansion> → echoes the default literal for the
# :-/- forms (${VAR:-D}, ${VAR-D}); returns 1 when there is no default form.
_compose_var_default() {
    local expansion="$1" inner
    [[ "$expansion" =~ ^\$\{[^}]*\}$ ]] || return 1
    inner="${expansion#\$\{}"; inner="${inner%\}}"
    if [[ "$inner" =~ ^[A-Za-z_][A-Za-z0-9_]*:?-(.*)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# TUNE-0123: Tailscale-mesh variable-name allowlist.
# A bare/required ${VAR} host token with an unset env and no default cannot be
# resolved to a literal, but a variable *named* after the tailnet interface is a
# strong, greppable signal of a mesh-only bind (Observability Stack compose uses
# `${TAILSCALE_IP}:PORT:PORT` for 6 services). When such a token would otherwise
# fall through to the anonymous B3 residual WARN, we instead classify it Tier 2
# (Tailscale-bound) — no WARN, no unrecognized-form. This is name-only intent
# recognition; it never reads or executes the variable value. A different tier
# at runtime (someone points TAILSCALE_IP at a public IP) is the same residual
# accepted risk the B3 WARN already carries — but here it is folded into an
# explicit, documented Tier-2 pass rather than a WARN.
RX_MESH_VAR_NAME='(^|_)(TAILSCALE|TAILNET|TSNET|MESH)_?(IP|ADDR|HOST|BIND)$'

# _compose_var_is_mesh <var-name> → returns 0 if the name matches the
# Tailscale-mesh allowlist, else 1. Matching is case-insensitive.
_compose_var_is_mesh() {
    local name_uc="${1^^}"
    [[ "$name_uc" =~ $RX_MESH_VAR_NAME ]]
}

# _resolve_var_silent <full-${...}-token> <file> <line> <svc>
# Env / default-extract resolver used by the segment walk. Same trust boundary
# as resolve_compose_host (dangerous-token reject, regex-validated NAME,
# printenv-only) but it does NOT emit the B3 residual WARN — an unresolved token
# is reported to the caller so the host-position logic can choose between a
# Tier-2 mesh-name pass (TUNE-0123) and the residual WARN. Echoes the resolved
# literal on stdout when resolved. Returns:
#   0 + literal echoed  — env value or default-extract
#   10 (no stdout)      — unresolved (bare ${VAR} / ${VAR:?}, env unset, no default)
#   1  (no stdout)      — unsafe / malformed token (violation emitted)
_resolve_var_silent() {
    local token="$1" file="$2" line="$3" svc="$4"
    local name def
    if [[ "$token" =~ $RX_VAR_DANGEROUS ]]; then
        emit_violation "$file" "$line" "compose:$svc rejected unsafe variable token '$token' (command-substitution / shell metacharacters)"
        return 1
    fi
    if ! name="$(_compose_var_name "$token")"; then
        emit_violation "$file" "$line" "compose:$svc malformed/invalid variable token '$token'"
        return 1
    fi
    if printenv -- "$name" >/dev/null 2>&1; then
        printenv -- "$name"; return 0
    fi
    if def="$(_compose_var_default "$token")"; then
        echo "$def"; return 0
    fi
    return 10
}

# TUNE-0122: interpolate ${VAR...} tokens in ANY port segment.
# Docker-compose long/short-form port strings put a ${VAR} not only in the host
# slot (${HOST:-127.0.0.1}:8080:8080) but also in the published/target port slot
# (127.0.0.1:${PORT:-3700}:3700, or the Transcribator dev form ${PORT:-3700}:3700).
# The original parser only resolved a leading ${...} host token, so a variable in
# a port position fell through to "unrecognized port form". This walks each
# colon-separated segment of the host:port[:port] body (the optional /proto
# suffix is split off first and re-attached), resolving env-set and default
# (${VAR:-D}/${VAR-D}) tokens in place. Unresolved residual tokens (bare ${VAR} /
# ${VAR:?}) are LEFT verbatim so the host-position logic in check_compose_port
# can still emit the B3 WARN or a Tier-2 mesh-name pass. Resolution is
# printenv-only / default-literal only — no dynamic code execution, no shell
# expansion.
# Echoes the interpolated string. Returns:
#   0 — interpolation done (string may still hold unresolved host token(s))
#   1 — an unsafe/malformed token was found (violation emitted by resolver)
_interpolate_compose_ports() {
    local raw="$1" file="$2" line="$3" svc="$4"
    local proto="" body="$raw"
    # Split a trailing /proto suffix so the ':' walk sees only host:port[:port].
    if [[ "$body" =~ ^(.*)(/(udp|tcp|sctp))$ ]]; then
        body="${BASH_REMATCH[1]}"; proto="${BASH_REMATCH[2]}"
    fi
    # Bracketed IPv6 hosts ([::1]:8080) contain ':' inside the brackets; leave
    # any such host untouched by the segment walk and only interpolate the tail.
    local prefix=""
    if [[ "$body" =~ ^(\[[0-9a-fA-F:.%]+\])(:.*)?$ ]]; then
        prefix="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"
    fi
    # Split the body on ':' — but a ':' inside a ${...} expansion (the modifier
    # colon of ${VAR:-D} / ${VAR:?msg}) is NOT a segment separator. Walk char by
    # char, tracking ${...} depth, so ${PORT:-3700} stays one segment.
    local out="" seg first=1
    local -a segs=()
    local cur="" i ch depth=0 n=${#body}
    for (( i=0; i<n; i++ )); do
        ch="${body:i:1}"
        if [[ "$ch" == '$' && "${body:i+1:1}" == '{' ]]; then
            depth=$((depth+1)); cur+="$ch"; continue
        fi
        if (( depth > 0 )) && [[ "$ch" == '}' ]]; then
            depth=$((depth-1)); cur+="$ch"; continue
        fi
        if (( depth == 0 )) && [[ "$ch" == ':' ]]; then
            segs+=("$cur"); cur=""; continue
        fi
        cur+="$ch"
    done
    segs+=("$cur")
    for seg in "${segs[@]}"; do
        if [[ "$seg" =~ ^\$\{[^}]*\}$ ]]; then
            local resolved rrc=0
            resolved="$(_resolve_var_silent "$seg" "$file" "$line" "$svc")" || rrc=$?
            case "$rrc" in
                0)  seg="$resolved" ;;   # env or default-extract → literal
                10) : ;;                 # unresolved → keep verbatim for residual
                *)  return 1 ;;          # unsafe/malformed token → violation emitted
            esac
        fi
        if (( first == 1 )); then out="$seg"; first=0; else out="${out}:${seg}"; fi
    done
    printf '%s%s%s\n' "$prefix" "$out" "$proto"
    return 0
}

# Parse one compose port string, classify, emit verdict.
check_compose_port() {
    local file="$1" line="$2" svc="$3" raw="$4"
    local has_just="$5" ttl_ok="$6" ttl_reason="$7"
    local host=""

    # Strip outer quotes.
    raw="${raw#\"}"; raw="${raw%\"}"
    raw="${raw#\'}"; raw="${raw%\'}"

    # B3 interpolation: resolve ${VAR...} tokens in every port segment (host and
    # port positions) before classification (TUNE-0122). printenv / default-only
    # resolution, no shell expand. A leftover unresolved ${VAR} token is then a
    # host-position residual: either a Tier-2 Tailscale-mesh-named var (TUNE-0123)
    # or the anonymous B3 residual WARN-but-PASS.
    # shellcheck disable=SC2016  # single-quoted '${' is a deliberate literal match
    if [[ "$raw" == *'${'* ]]; then
        local interpolated irc=0
        interpolated="$(_interpolate_compose_ports "$raw" "$file" "$line" "$svc")" || irc=$?
        (( irc != 0 )) && return 1        # unsafe/malformed token → violation emitted
        raw="$interpolated"
        # If an unresolved ${VAR} token survived, it is the bind host (a port
        # slot never legitimately stays a bare variable). Classify by var NAME:
        # a tailnet-named var is Tier 2 (mesh-bound); anything else is the B3
        # residual WARN-but-PASS naming the variable + file:line.
        if [[ "$raw" =~ (\$\{[^}]*\}) ]]; then
            local host_token="${BASH_REMATCH[1]}" host_name
            if host_name="$(_compose_var_name "$host_token")"; then
                if _compose_var_is_mesh "$host_name"; then
                    emit_ok "$file" "$line" "compose:$svc \${$host_name} (tier2 Tailscale-mesh var-name)"
                    return 0
                fi
                emit_warn "$file" "$line" "compose:$svc unresolved \${$host_name} (env unset, no default) — accepted with WARN (B3 residual)"
                return 0
            fi
            emit_violation "$file" "$line" "compose:$svc malformed/invalid variable token '$host_token'"
            return 1
        fi
    fi

    # Optional /(udp|tcp|sctp) protocol suffix on long-form host:port:port
    # binds (compose ports may carry a protocol, e.g. "100.64.1.5:53:53/udp");
    # captured into a trailing group so BASH_REMATCH[1] (host) is unaffected.
    if [[ "$raw" =~ ^\[([0-9a-fA-F:.%]+)\]:[0-9]+(:[0-9]+)?(/(udp|tcp|sctp))?$ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$raw" =~ ^([0-9.]+):[0-9]+:[0-9]+(/(udp|tcp|sctp))?$ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$raw" =~ ^[0-9]+:[0-9]+(/(udp|tcp|sctp))?$ ]] || [[ "$raw" =~ ^[0-9]+(/(udp|tcp|sctp))?$ ]]; then
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

# TUNE-0295 V-AC-8: runtime-bind classifier
# Parse "<addr>:<port>" or "[<ipv6>]:<port>"; classify_bind on addr; emit
# verdict + tier; return 0 for tier1/tier2, 1 for tier3, 2 for malformed.
lint_runtime_bind() {
    local raw="$1"
    [[ -z "$raw" ]] && { echo "ERR: --runtime-bind requires <addr:port>" >&2; return 2; }
    local addr port
    if [[ "$raw" =~ ^\[([0-9a-fA-F:]+)\]:([0-9]+)$ ]]; then
        addr="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$raw" =~ ^([^:]+):([0-9]+)$ ]]; then
        addr="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        echo "runtime-bind '$raw' malformed (expected <addr:port>)" >&2
        return 2
    fi
    local tier
    tier="$(classify_bind "$addr")"
    case "$tier" in
        tier1)        echo "runtime-bind ${addr}:${port} classified tier1 loopback — PASS"; return 0 ;;
        tier2)        echo "runtime-bind ${addr}:${port} classified tier2 tailscale — PASS"; return 0 ;;
        tier3_public) echo "runtime-bind ${addr}:${port} classified tier3 public — FAIL (needs justification)"; return 1 ;;
        *)            echo "runtime-bind ${addr}:${port} malformed addr"; return 2 ;;
    esac
}

main() {
    local -a composes=() redises=() postgreses=() sockets=() runtime_binds=()
    local strict=1 format=text
    VERBOSE=0
    TODAY_OVERRIDE=""

    while (( $# > 0 )); do
        case "$1" in
            --compose)         composes+=("$2"); shift 2 ;;
            --redis-conf)      redises+=("$2"); shift 2 ;;
            --postgres-conf)   postgreses+=("$2"); shift 2 ;;
            --systemd-socket)  sockets+=("$2"); shift 2 ;;
            --runtime-bind)    runtime_binds+=("$2"); shift 2 ;;
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
    for path in ${runtime_binds[@]+"${runtime_binds[@]}"}; do
        local sub_rc=0
        lint_runtime_bind "$path" || sub_rc=$?
        (( sub_rc != 0 )) && rc=$sub_rc
    done

    if [[ "$format" != "text" ]]; then
        echo "format '$format' not implemented (only 'text' supported)" >&2
        return 2
    fi

    (( strict == 0 )) && rc=0
    return "$rc"
}

main "$@"
