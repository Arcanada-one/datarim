#!/usr/bin/env bash
# cross-kb-evolution-digest.sh — surface framework-relevant evolution lessons
# from every managed knowledge base into ONE operator-facing digest.
#
# Datarim self-evolution runs per-KB: each managed KB keeps its own
# datarim/history/evolution-log.md. When a task in a non-framework KB evolves
# the shared runtime, the log entry lands in that KB's log and the operator —
# who watches the framework KB — never sees it; project-local feedback-memory
# lessons decay entirely. This tool reads the per-KB evolution-log across an
# operator-configured set of KB roots and emits a merged, source-tagged digest
# with two buckets: framework EVOLUTION (shared-runtime changes) and PROMOTION
# candidates (project-local lessons that may warrant framework evolution).
#
# It is strictly READ-ONLY over every KB. Rows are untrusted (they may be
# synced from other machines): every cell is handled as inert data — never
# eval'd, never sourced, and the Target column is classified by string prefix
# ONLY, never opened as a path. No KB is ever silently absent: each configured
# root renders an explicit status (OK / MISSING-ROOT / NO-LOG / EMPTY /
# PARSE-ERR / SYNC-STALE) so a typo'd or unsynced root is never mistaken for
# "that KB had no evolution".
#
# Inputs (KB roots — union of all that are given):
#   --kb <root>          a workspace root (parent of datarim/); repeatable
#   --config <file>      file of roots, one per line ('#' comments, blanks ok);
#                        read line-by-line, NEVER sourced
#   --discover <dir>     glob KB roots by locating */datarim/history/evolution-log.md
#   (default when none given: $CROSS_KB_EVOLUTION_CONF or
#    ~/.claude/local/config/managed-kbs.conf, if present)
# Options:
#   --since <YYYY-MM-DD> keep rows on/after this date
#   --sync-stale <S>     flag a log SYNC-STALE when its mtime age >= S seconds
#   --now <EPOCH>        test hook for freshness comparison (default: date +%s)
#   --json               emit machine-readable JSON instead of text
#   --out <file>         write the digest to <file> atomically (default: stdout)
#
# Exit codes:
#   0  aggregation completed (including all-degraded inputs — a digest never
#      fails on bad DATA)
#   2  usage error (unknown flag, malformed --since, missing/unreadable --config)
#   3  --out write failure (environment/operator error — never swallowed)
#
# Identifier-free, English-only — shipped framework surface.
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

_usage() { echo "cross-kb-evolution-digest: $*" >&2; exit 2; }

# ── args ─────────────────────────────────────────────────────────────────────
declare -a KB_ROOTS=()
config=""; discover=""; since=""; sync_stale=""; now_override=""; as_json=0; out=""
default_conf="${CROSS_KB_EVOLUTION_CONF:-$HOME/.claude/local/config/managed-kbs.conf}"

while [ $# -gt 0 ]; do
    case "$1" in
        --kb)         [ $# -ge 2 ] || _usage "--kb needs a value"; KB_ROOTS+=("$2"); shift 2 ;;
        --config)     [ $# -ge 2 ] || _usage "--config needs a value"; config="$2"; shift 2 ;;
        --discover)   [ $# -ge 2 ] || _usage "--discover needs a value"; discover="$2"; shift 2 ;;
        --since)      [ $# -ge 2 ] || _usage "--since needs a value"; since="$2"; shift 2 ;;
        --sync-stale) [ $# -ge 2 ] || _usage "--sync-stale needs a value"; sync_stale="$2"; shift 2 ;;
        --now)        [ $# -ge 2 ] || _usage "--now needs a value"; now_override="$2"; shift 2 ;;
        --json)       as_json=1; shift ;;
        --out)        [ $# -ge 2 ] || _usage "--out needs a value"; out="$2"; shift 2 ;;
        -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
        --) shift; break ;;
        *) _usage "unknown arg: $1" ;;
    esac
done

case "$since" in
    '') ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) _usage "--since must be YYYY-MM-DD" ;;
esac
case "$sync_stale" in ''|*[!0-9]*) [ -z "$sync_stale" ] || _usage "--sync-stale must be an integer" ;; esac
case "$now_override" in ''|*[!0-9]*) [ -z "$now_override" ] || _usage "--now must be an integer" ;; esac

now="${now_override:-$(date +%s)}"

# ── helpers ──────────────────────────────────────────────────────────────────
_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Strip a leading runtime prefix + surrounding backticks from one token.
_strip_prefix() {
    local t="$1"
    t="${t#\`}"; t="${t%\`}"
    t="${t#\~/.claude/}"
    t="${t#\$HOME/.claude/}"
    t="${t#./}"
    printf '%s' "$t"
}

# classify <category> <target> -> evolution | promotion | other
# Target is tokenized (whitespace , +) and matched by prefix ONLY; it is never
# opened as a path. Globbing is disabled so a '*' in a cell cannot expand.
_classify() {
    local cat="$1" tgt="$2" tok stripped lc
    local IFS=' ,+'
    set -f
    for tok in $tgt; do
        stripped="$(_strip_prefix "$tok")"
        case "$stripped" in
            skills/*|agents/*|commands/*|templates/*|CLAUDE.md) set +f; printf 'evolution'; return ;;
        esac
    done
    set +f
    lc="$(printf '%s' "$cat" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in *memory*) printf 'promotion'; return ;; esac
    case "$tgt" in *memory/*) printf 'promotion'; return ;; esac
    printf 'other'
}

# Sanitize a field for single-line text output: drop C0 control bytes + DEL
# (neutralizes ANSI/OSC terminal-injection); keep printable + UTF-8 high bytes.
_sanitize_text() { printf '%s' "$1" | tr -d '\000-\037\177'; }

# JSON-escape a string (dependency-free, byte-wise under LC_ALL=C).
_json_escape() {
    local s="$1" out="" i c code esc len="${#1}"
    for (( i=0; i<len; i++ )); do
        c="${s:i:1}"
        case "$c" in
            '\') out+='\\' ;;
            '"') out+='\"' ;;
            $'\n') out+='\n' ;;
            $'\t') out+='\t' ;;
            $'\r') out+='\r' ;;
            *)
                printf -v code '%d' "'$c" 2>/dev/null || code=32
                if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]; then
                    printf -v esc '\\u%04x' "$code"; out+="$esc"
                else
                    out+="$c"
                fi ;;
        esac
    done
    printf '%s' "$out"
}

# ── resolve KB roots ─────────────────────────────────────────────────────────
if [ -n "$config" ]; then
    [ -r "$config" ] || _usage "--config file not readable: $config"
    while IFS= read -r cline || [ -n "$cline" ]; do
        cline="$(_trim "$cline")"
        case "$cline" in ''|'#'*) continue ;; esac
        KB_ROOTS+=("$cline")
    done < "$config"
fi

if [ -n "$discover" ]; then
    while IFS= read -r logf; do
        [ -n "$logf" ] || continue
        KB_ROOTS+=("${logf%/datarim/history/evolution-log.md}")
    done < <(find "$discover" -maxdepth 6 -type f -path '*/datarim/history/evolution-log.md' 2>/dev/null | LC_ALL=C sort)
fi

# Fall back to the default config only when no source was specified at all.
if [ "${#KB_ROOTS[@]}" -eq 0 ] && [ -z "$config" ] && [ -z "$discover" ] && [ -r "$default_conf" ]; then
    while IFS= read -r cline || [ -n "$cline" ]; do
        cline="$(_trim "$cline")"
        case "$cline" in ''|'#'*) continue ;; esac
        KB_ROOTS+=("$cline")
    done < "$default_conf"
fi

# ── labels (disambiguate basename collisions) ────────────────────────────────
declare -a LABELS=()
declare -A LABEL_SEEN=()
_label_for() {
    local root="$1" base twoseg lbl
    base="$(basename "$root")"
    lbl="$base"
    if [ -n "${LABEL_SEEN[$base]+x}" ]; then
        twoseg="$(basename "$(dirname "$root")")/$base"
        lbl="$twoseg"
    fi
    LABEL_SEEN["$base"]=1
    printf '%s' "$lbl"
}
for r in "${KB_ROOTS[@]:-}"; do
    [ -n "$r" ] || continue
    LABELS+=("$(_label_for "$r")")
done

# ── parse each KB ────────────────────────────────────────────────────────────
# Parallel row arrays; a sort permutation is computed over (date,label,lineno).
declare -a R_date=() R_kb=() R_line=() R_bucket=() R_cat=() R_tgt=() R_change=() R_task=()
declare -a STAT_LABEL=() STAT_STATUS=() STAT_DETAIL=()
n_evo=0; n_promo=0; n_other=0

_parse_kb() {
    local root="$1" label="$2"
    local log="$root/datarim/history/evolution-log.md"
    local kept=0 unparse=0 evo=0 promo=0 other=0 lineno=0 datarows=0
    local status detail age mt

    if [ ! -d "$root" ]; then
        STAT_LABEL+=("$label"); STAT_STATUS+=("MISSING-ROOT"); STAT_DETAIL+=("root not found")
        return
    fi
    if [ ! -f "$log" ]; then
        STAT_LABEL+=("$label"); STAT_STATUS+=("NO-LOG"); STAT_DETAIL+=("no datarim/history/evolution-log.md")
        return
    fi

    local line date task cat tgt change bucket
    declare -a cells
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in '|'*) ;; *) continue ;; esac
        set -f; IFS='|' read -ra cells <<< "$line"; set +f
        if [ "${#cells[@]}" -lt 6 ]; then unparse=$((unparse + 1)); continue; fi
        date="$(_trim "${cells[1]}")"
        case "$date" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
            Date|''|-*) continue ;;                 # header / separator / blank
            *) unparse=$((unparse + 1)); continue ;;
        esac
        datarows=$((datarows + 1))
        task="$(_trim "${cells[2]}")"
        cat="$(_trim "${cells[3]}")"
        tgt="$(_trim "${cells[4]}")"
        change="$(_trim "${cells[5]}")"
        if [ -n "$since" ] && [ "$date" \< "$since" ]; then continue; fi
        bucket="$(_classify "$cat" "$tgt")"
        case "$bucket" in
            other) other=$((other + 1)); continue ;;
            evolution) evo=$((evo + 1)) ;;
            promotion) promo=$((promo + 1)) ;;
        esac
        kept=$((kept + 1))
        R_date+=("$date"); R_kb+=("$label"); R_line+=("$lineno"); R_bucket+=("$bucket")
        R_cat+=("$cat"); R_tgt+=("$tgt"); R_change+=("$change"); R_task+=("$task")
    done < "$log"

    n_evo=$((n_evo + evo)); n_promo=$((n_promo + promo)); n_other=$((n_other + other))

    mt="$(_mtime "$log")"
    age=$(( now - mt )); [ "$age" -lt 0 ] && age=0
    detail="$kept row(s)"
    [ "$unparse" -gt 0 ] && detail="$detail, $unparse unparseable"
    detail="$detail, mtime age ${age}s"
    # PARSE-ERR only when the log yielded NO valid date-rows at all yet had
    # pipe-lines that failed to parse (a genuinely corrupt table) — not when a
    # healthy log simply has no framework rows in the requested window.
    if [ -n "$sync_stale" ] && [ "$age" -ge "$sync_stale" ]; then
        status="SYNC-STALE"
    elif [ "$kept" -gt 0 ]; then
        status="OK"
    elif [ "$datarows" -gt 0 ]; then
        status="EMPTY"
    elif [ "$unparse" -gt 0 ]; then
        status="PARSE-ERR"
    else
        status="EMPTY"
    fi
    STAT_LABEL+=("$label"); STAT_STATUS+=("$status"); STAT_DETAIL+=("$detail")
}

kb_count="${#KB_ROOTS[@]}"
for idx in "${!KB_ROOTS[@]}"; do
    [ -n "${KB_ROOTS[$idx]}" ] || continue
    _parse_kb "${KB_ROOTS[$idx]}" "${LABELS[$idx]}"
done

# ── sort permutation: date DESC, label ASC, lineno ASC ───────────────────────
declare -a ORDER=()
if [ "${#R_date[@]}" -gt 0 ]; then
    while IFS= read -r i; do ORDER+=("$i"); done < <(
        for i in "${!R_date[@]}"; do
            printf '%s\t%s\t%s\t%s\n' "${R_date[$i]}" "${R_kb[$i]}" "${R_line[$i]}" "$i"
        done | LC_ALL=C sort -t $'\t' -k1,1r -k2,2 -k3,3n | awk -F'\t' '{print $NF}'
    )
fi

# ── render ───────────────────────────────────────────────────────────────────
render_text() {
    if [ "$kb_count" -eq 0 ]; then
        echo "Cross-KB evolution digest — no managed KBs configured."
        echo "  (supply --kb/--config/--discover, or seed ${default_conf})"
        return
    fi
    echo "Cross-KB evolution digest — ${kb_count} KB(s): ${n_evo} evolution, ${n_promo} promotion row(s)"
    echo ""
    echo "## Framework evolution surfaced from other KBs"
    local shown=0 i tgt change
    for i in "${ORDER[@]:-}"; do
        [ -n "${i:-}" ] || continue
        [ "${R_bucket[$i]}" = "evolution" ] || continue
        tgt="$(_sanitize_text "${R_tgt[$i]}")"
        change="$(_sanitize_text "${R_change[$i]:0:220}")"
        printf '%s  [%s]  %s  %s\n' "${R_date[$i]}" "${R_kb[$i]}" "${R_cat[$i]}" "$tgt"
        [ -n "$change" ] && printf '    %s\n' "$change"
        shown=1
    done
    [ "$shown" -eq 0 ] && echo "  (none)"
    echo ""
    echo "## Promotion candidates (project-local lessons that may warrant framework evolution)"
    shown=0
    for i in "${ORDER[@]:-}"; do
        [ -n "${i:-}" ] || continue
        [ "${R_bucket[$i]}" = "promotion" ] || continue
        tgt="$(_sanitize_text "${R_tgt[$i]}")"
        change="$(_sanitize_text "${R_change[$i]:0:220}")"
        printf '%s  [%s]  %s  %s\n' "${R_date[$i]}" "${R_kb[$i]}" "${R_cat[$i]}" "$tgt"
        [ -n "$change" ] && printf '    %s\n' "$change"
        shown=1
    done
    [ "$shown" -eq 0 ] && echo "  (none)"
    echo ""
    echo "## Per-KB status"
    for i in "${!STAT_LABEL[@]}"; do
        printf '  [%s]  %s  (%s)\n' "$(_sanitize_text "${STAT_LABEL[$i]}")" "${STAT_STATUS[$i]}" "${STAT_DETAIL[$i]}"
    done
}

render_json() {
    local i first tgt
    printf '{"kb_count":%s,"other_count":%s,"evolution":[' "$kb_count" "$n_other"
    first=1
    for i in "${ORDER[@]:-}"; do
        [ -n "${i:-}" ] || continue
        [ "${R_bucket[$i]}" = "evolution" ] || continue
        [ "$first" -eq 1 ] || printf ','; first=0
        printf '{"date":"%s","kb":"%s","task_id":"%s","category":"%s","target":"%s","change":"%s"}' \
            "$(_json_escape "${R_date[$i]}")" "$(_json_escape "${R_kb[$i]}")" \
            "$(_json_escape "${R_task[$i]}")" "$(_json_escape "${R_cat[$i]}")" \
            "$(_json_escape "${R_tgt[$i]}")" "$(_json_escape "${R_change[$i]}")"
    done
    printf '],"promotion":['
    first=1
    for i in "${ORDER[@]:-}"; do
        [ -n "${i:-}" ] || continue
        [ "${R_bucket[$i]}" = "promotion" ] || continue
        [ "$first" -eq 1 ] || printf ','; first=0
        printf '{"date":"%s","kb":"%s","task_id":"%s","category":"%s","target":"%s","change":"%s"}' \
            "$(_json_escape "${R_date[$i]}")" "$(_json_escape "${R_kb[$i]}")" \
            "$(_json_escape "${R_task[$i]}")" "$(_json_escape "${R_cat[$i]}")" \
            "$(_json_escape "${R_tgt[$i]}")" "$(_json_escape "${R_change[$i]}")"
    done
    printf '],"kbs":['
    first=1
    for i in "${!STAT_LABEL[@]}"; do
        [ "$first" -eq 1 ] || printf ','; first=0
        printf '{"kb":"%s","status":"%s","detail":"%s"}' \
            "$(_json_escape "${STAT_LABEL[$i]}")" "$(_json_escape "${STAT_STATUS[$i]}")" \
            "$(_json_escape "${STAT_DETAIL[$i]}")"
    done
    printf ']}\n'
}

if [ "$as_json" -eq 1 ]; then
    rendered="$(render_json)"
else
    rendered="$(render_text)"
fi

# ── emit ─────────────────────────────────────────────────────────────────────
if [ -n "$out" ]; then
    if [ -L "$out" ]; then echo "cross-kb-evolution-digest: --out refuses a symlink target: $out" >&2; exit 3; fi
    out_dir="$(dirname "$out")"
    [ -d "$out_dir" ] || { echo "cross-kb-evolution-digest: --out parent dir missing: $out_dir" >&2; exit 3; }
    umask 077
    tmp="$(mktemp "$out_dir/.cke-digest.XXXXXX")" || { echo "cross-kb-evolution-digest: mktemp failed" >&2; exit 3; }
    if ! printf '%s\n' "$rendered" > "$tmp"; then rm -f "$tmp"; echo "cross-kb-evolution-digest: write failed" >&2; exit 3; fi
    if ! mv -f "$tmp" "$out"; then rm -f "$tmp"; echo "cross-kb-evolution-digest: atomic move failed" >&2; exit 3; fi
else
    printf '%s\n' "$rendered"
fi
exit 0
