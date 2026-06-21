# shellcheck shell=bash
# backlog-sink.sh — shared backlog-sink resolver + append helper for the
# site-drift auto-task generators (level 2 dr-archive sub-step and level 3
# cron sweep). Sourced library: no shebang, no top-level side-effects.
#
# Public API:
#   resolve_backlog_sink [--root <dir>]
#       stdout: absolute backlog path; exit 0 = file sink resolved,
#       exit 1 = no file sink (caller no-ops — NOT an error).
#
#   append_site_update_task <backlog> <product> <severity> <detail>
#       Idempotent, atomic, injection-gated append of one site-update task.
#       exit 0 = appended or already-present (dedup); exit 2 = rejected input.
#
# Dependency floor: pure bash + awk + grep + realpath/readlink. No yq, no jq,
# no python — must run on any Datarim consumer. Backend resolution mirrors the
# awk precedent in check-repo-site-sync.sh.
#
# Security (Mandate S1/S5/S9): every space.yml / registry scalar is untrusted.
#   - product id: ^[a-z][a-z0-9-]*$ allowlist (rejects leading dash, regex-meta,
#     path-traversal).
#   - severity: ^(HIGH|MEDIUM)$ allowlist.
#   - detail: must be single-line, [[:print:]]-only (anti backlog-line-injection).
#   - resolved backlog path: realpath-contained within the resolved KB root,
#     component-wise `..` rejection.
#   - append is temp-file + atomic rename under an mkdir-based lock.

# Anchor token is the id-independent dedup key per product.
_bs_anchor() { printf 'drift-site-update-%s' "$1"; }

# ---- field allowlists ---------------------------------------------------

_bs_valid_product() {  # $1=product id
    case "$1" in
        -*) return 1 ;;                       # no leading dash
    esac
    printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9-]*$'
}

_bs_valid_severity() {  # $1=severity
    case "$1" in HIGH|MEDIUM) return 0 ;; *) return 1 ;; esac
}

# Reject multi-line or control-char detail (backlog-line-injection gate).
# Printable UTF-8 (Cyrillic, ↔ arrows, em-dashes — all common in the backlog)
# is allowed; the gate blocks only C0/C1 control bytes and newlines, which are
# the actual injection vectors (forged backlog lines, ANSI escapes).
_bs_valid_detail() {  # $1=detail
    [ -n "$1" ] || return 1
    case "$1" in *$'\n'*|*$'\r'*) return 1 ;; esac    # no embedded line break
    # Reject any C0 control (0x00-0x1F except space-class already excluded by
    # the line-break test above) or DEL (0x7F). Multibyte UTF-8 lead/continuation
    # bytes are >= 0x80 and pass.
    printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]' && return 1
    return 0
}

# ---- backend resolution -------------------------------------------------

# Walk up from cwd (or --root) to find spaces/*/space.yml; awk-parse the
# knowledge_base block for current_backend + datarim_path.
_bs_find_space_yml() {  # $1=start dir → stdout path or empty
    local d="$1"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        local hit
        hit="$(find "$d/spaces" -maxdepth 2 -name space.yml 2>/dev/null | head -1)"
        [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
        d="$(dirname "$d")"
    done
    return 1
}

# Extract a scalar under the knowledge_base: block. Two-space-indent contract
# matching space.yml; the block may sit under a parent (e.g. infra:) at any
# depth, so we key off the `knowledge_base:` line and the relative indent of
# the wanted key, not an absolute column.
_bs_kb_field() {  # $1=space.yml $2=key → stdout value
    awk -v key="$2" '
        function strip(s){ sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
        BEGIN { inkb=0; kbindent=-1 }
        /^[[:space:]]*#/ { next }
        {
            line=$0
            # current indent = leading spaces
            n=match(line, /[^ ]/); indent=(n>0?n-1:0)
            if (line ~ /knowledge_base:[[:space:]]*$/) { inkb=1; kbindent=indent; next }
            if (inkb && indent <= kbindent && strip(line) != "") { inkb=0 }
            if (inkb && line ~ ("^[[:space:]]+" key ":[[:space:]]")) {
                v=line; sub(/^[^:]*:[[:space:]]*/,"",v); v=strip(v)
                if (v ~ /^".*"$/ || v ~ /^'\''.*'\''$/) v=substr(v,2,length(v)-2)
                print v; exit
            }
        }
    ' "$1" 2>/dev/null
}

resolve_backlog_sink() {
    local root=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 1. Env override — operator/CI explicit sink.
    if [ -n "${DATARIM_BACKLOG_PATH:-}" ]; then
        printf '%s' "$DATARIM_BACKLOG_PATH"; return 0
    fi

    local start="${root:-$PWD}"

    # 2. space.yml backend resolution.
    local space_yml
    space_yml="$(_bs_find_space_yml "$start")"
    if [ -n "$space_yml" ]; then
        local backend dpath
        backend="$(_bs_kb_field "$space_yml" current_backend)"
        if [ "$backend" = "file-based-datarim" ]; then
            dpath="$(_bs_kb_field "$space_yml" datarim_path)"
            if [ -n "$dpath" ] && [ -d "$dpath" ]; then
                printf '%s/backlog.md' "$dpath"; return 0
            fi
        elif [ -n "$backend" ]; then
            # Known non-file backend (e.g. future muneral): no file sink.
            return 1
        fi
    fi

    # 3. Bare datarim/backlog.md under root.
    if [ -d "$start/datarim" ]; then
        printf '%s/datarim/backlog.md' "$start"; return 0
    fi

    # 4. Nothing resolvable.
    return 1
}

# ---- anti-flap note -----------------------------------------------------
#
# There is intentionally NO post-close cooldown. The drift signal is sticky —
# it does not self-clear; only an operator fixing the deployed site clears it.
# A sticky signal cannot flap, so open-task dedup (the anchor grep below) is
# the complete idempotency contract. If a product whose task was closed still
# drifts, the next sweep re-spawns exactly one task — that is a true positive
# (premature close or regression), not noise to suppress. (Verdict: researcher
# survey of Alertmanager repeat_interval / PagerDuty dedup-key / Nagios flap
# detection + architect/sre/security consilium — all converged on "no
# cooldown".) Any future anti-flap work is gated on observed re-spawn churn,
# not speculation — see the backlog follow-up.

# ---- atomic, idempotent append ------------------------------------------

append_site_update_task() {  # $1=backlog $2=product $3=severity $4=detail
    local backlog="$1" product="$2" severity="$3" detail="$4"

    _bs_valid_product  "$product"  || { echo "backlog-sink: invalid product id '$product'" >&2; return 2; }
    _bs_valid_severity "$severity" || { echo "backlog-sink: invalid severity '$severity'" >&2; return 2; }
    _bs_valid_detail   "$detail"   || { echo "backlog-sink: detail rejected (multi-line or non-printable)" >&2; return 2; }
    [ -n "$backlog" ] || { echo "backlog-sink: empty backlog path" >&2; return 2; }

    local anchor; anchor="$(_bs_anchor "$product")"

    # Dedup: anchor already present → no-op success.
    if [ -f "$backlog" ] && grep -qF "$anchor" -- "$backlog"; then
        return 0
    fi

    # mkdir-based lock around read-modify-write. Explicit cleanup before every
    # return — `trap ... RETURN` is avoided (unsupported in zsh, and fires on
    # every nested-function return, releasing the lock prematurely).
    local lock="${backlog}.lock"
    local i=0
    until mkdir "$lock" 2>/dev/null; do
        i=$((i+1)); [ "$i" -ge 50 ] && { echo "backlog-sink: lock timeout" >&2; return 2; }
        sleep 0.1
    done

    # Re-check under lock (TOCTOU).
    if [ -f "$backlog" ] && grep -qF "$anchor" -- "$backlog"; then
        rmdir "$lock" 2>/dev/null
        return 0
    fi

    local line tmp
    line="- TASK-XXXX · pending · P2 · L1 · Site-update ${product}: repo↔site drift (${severity}) — ${detail}. Anchor: ${anchor}. (Source: drift-sweep)"

    tmp="$(mktemp "${backlog}.XXXXXX")" || { echo "backlog-sink: mktemp failed" >&2; rmdir "$lock" 2>/dev/null; return 2; }
    [ -f "$backlog" ] && cat -- "$backlog" > "$tmp"
    printf '%s\n' "$line" >> "$tmp"
    mv -f -- "$tmp" "$backlog"
    rmdir "$lock" 2>/dev/null
    return 0
}
