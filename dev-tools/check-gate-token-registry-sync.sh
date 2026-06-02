#!/usr/bin/env bash
# check-gate-token-registry-sync.sh — cross-check task-description frontmatter
# values against the network-exposure gate's recognised value-sets.
#
# Why: the tiered gate (network-exposure-gate.sh) hard-codes (a) a SEC_INFRA_TYPES
# token set matched with exact `==` for P1 escalation, and (b) a set of priority
# tokens recognised by decide()'s `case` arms. A `type:` or `priority:` value used
# in real task-descriptions but absent from the corresponding gate set is silently
# mishandled: an unhandled `type:` never escalates a genuine sec/infra task; an
# unhandled `priority:` fall-closes to hard_block as "malformed" (a latent false
# positive). Both are the same value-set-omission defect class. This checker greps
# the real corpus and flags any value the gate does not consciously handle, so the
# next gap is caught mechanically instead of by manual audit.
#
# Scope of the type: check (precision, not noise). `type:` is a free-form field,
# so most distinct values (feature, bug, docs, foundation, …) are routine and have
# nothing to do with the gate's sec/infra escalation. Flagging every value absent
# from the set would drown the real signal. The defect class this catches is the
# short-form-gap one: a SHORT-FORM / morphological VARIANT of a token already in the
# gate set, that is itself absent — e.g. `infra` vs `infrastructure`, `sec` vs
# `security-incident`. A corpus `type:` value V is flagged iff V is NOT in the set
# and V is in a PREFIX relation with some gate token G (G starts with V, or V starts
# with G), min length 3 — i.e. V is a plausible short/long sibling of a gating token
# that the gate would silently fail to match. Arbitrary unrelated values are ignored.
#
# A priority: value is flagged whenever it is not one the gate's decide() case arms
# recognise (the gate fail-closes any other to hard_block — the P4 latent-FP class).
#
# The optional --allowlist file suppresses specific type: values from the flag.
#
# API:
#   check-gate-token-registry-sync.sh [--root <path>] [--corpus-dir <path>]
#       [--gate <path>] [--allowlist <file>] [--quiet]
#     --root        repo root (default: script-dir/..)
#     --corpus-dir  task-description corpus (default: <root>/datarim/tasks)
#     --gate        gate script to parse (default: <root>/dev-tools/network-exposure-gate.sh)
#     --allowlist   extra conscious-out type: values, one per line (# comments)
#     --quiet       exit code only (suppress the per-finding report)
#
# Exit codes:
#   0 — clean (every corpus type:/priority: value is handled) OR empty/absent corpus
#   1 — at least one unhandled type: or priority: value found
#   2 — usage / IO error (unreadable gate, unknown flag)

set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="check-gate-token-registry-sync.sh"

# Built-in conscious allowlist: type: values deliberately NOT in the gate's
# hard_block set (routine, non-sec/infra work). Sync with the corpus audit in the
# task record; extend per-consumer via --allowlist.
TYPE_ALLOWLIST=(
    feature bugfix content research refactor chore tooling ops
    framework framework-feature framework-maintenance framework-enhancement
    framework-bugfix framework-hardening migration legacy-migrated spawn task
    verification testing project-init documentation web fixtures tech-debt
    smoke-target test-flake
)

usage() {
    cat >&2 <<USAGE
usage: $SCRIPT_NAME [--root <path>] [--corpus-dir <path>] [--gate <path>] [--allowlist <file>] [--quiet]
  --root        repo root (default: script-dir/..)
  --corpus-dir  corpus of task-descriptions (default: <root>/datarim/tasks)
  --gate        gate script to parse (default: <root>/dev-tools/network-exposure-gate.sh)
  --allowlist   extra conscious-out type: values (one per line, # comments)
  --quiet       exit code only
exit codes: 0 clean/empty | 1 unhandled value found | 2 usage/IO
USAGE
    exit 2
}

# in_list <needle> <element...> -> exit 0 if needle equals any element
in_list() {
    local needle="$1"; shift
    local e
    for e in "$@"; do
        [ "$needle" = "$e" ] && return 0
    done
    return 1
}

# prefix_related <value> <gate-token...> -> exit 0 if <value> is a short/long
# sibling of any gate token: one is a prefix of the other and the shorter is
# >= 3 chars. Catches infra<->infrastructure, sec<->security-*; ignores unrelated
# free-form values. The value is assumed NOT already equal to a gate token
# (callers check in_list first).
prefix_related() {
    local v="$1"; shift
    [ "${#v}" -ge 3 ] || return 1
    local g
    for g in "$@"; do
        case "$g" in "$v"*) return 0 ;; esac   # g starts with v (v is short form)
        case "$v" in "$g"*) return 0 ;; esac   # v starts with g (v is long form)
    done
    return 1
}

main() {
    local script_dir root="" corpus_dir="" gate="" allowlist_file="" quiet=0
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    while [ $# -gt 0 ]; do
        case "$1" in
            --root)       shift; [ $# -gt 0 ] || usage; root="$1" ;;
            --corpus-dir) shift; [ $# -gt 0 ] || usage; corpus_dir="$1" ;;
            --gate)       shift; [ $# -gt 0 ] || usage; gate="$1" ;;
            --allowlist)  shift; [ $# -gt 0 ] || usage; allowlist_file="$1" ;;
            --quiet)      quiet=1 ;;
            --version)    echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
            -h|--help)    usage ;;
            *)            echo "ERROR: unknown flag '$1'" >&2; usage ;;
        esac
        shift
    done

    [ -n "$root" ] || root="$(cd "$script_dir/.." && pwd)"
    [ -n "$corpus_dir" ] || corpus_dir="$root/datarim/tasks"
    [ -n "$gate" ] || gate="$root/dev-tools/network-exposure-gate.sh"

    if [ ! -r "$gate" ]; then
        echo "ERROR: cannot read gate script: $gate" >&2
        exit 2
    fi

    # --- Parse the gate's recognised value-sets -------------------------------

    # GATE_TYPE_SET: the SEC_INFRA_TYPES array block.
    local gate_type_set=()
    while IFS= read -r tok; do
        [ -n "$tok" ] && gate_type_set+=("$tok")
    done < <(
        sed -n '/SEC_INFRA_TYPES=(/,/^)/p' "$gate" \
            | sed -e 's/#.*$//' -e 's/SEC_INFRA_TYPES=(//' -e 's/)//' \
            | tr -d ' \t' | grep -v '^$'
    )

    # GATE_PRIO_SET: literal Pn tokens named in decide()'s case arms (excludes the
    # empty "" arm and the *) malformed catch-all). Pattern: lines like `P0)` or
    # `P2|P3|P4)` inside the case. Split on `|`, keep tokens matching ^P[0-9]+$.
    local gate_prio_set=()
    while IFS= read -r tok; do
        [ -n "$tok" ] && gate_prio_set+=("$tok")
    done < <(
        grep -oE '^[[:space:]]*P[0-9]+(\|P[0-9]+)*\)' "$gate" \
            | tr -d ' \t)' | tr '|' '\n' | grep -E '^P[0-9]+$' | sort -u
    )

    # Extra type allowlist from file (optional).
    local extra_allow=()
    if [ -n "$allowlist_file" ]; then
        if [ ! -r "$allowlist_file" ]; then
            echo "ERROR: cannot read --allowlist file: $allowlist_file" >&2
            exit 2
        fi
        while IFS= read -r line; do
            line="${line%%#*}"
            line="$(printf '%s' "$line" | tr -d ' \t')"
            [ -n "$line" ] && extra_allow+=("$line")
        done < "$allowlist_file"
    fi

    # --- Empty / absent corpus is clean ---------------------------------------
    if [ ! -d "$corpus_dir" ]; then
        [ "$quiet" -eq 1 ] || echo "note: corpus dir absent ($corpus_dir) — nothing to check"
        exit 0
    fi
    local md_count
    md_count="$(find "$corpus_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$md_count" -eq 0 ]; then
        [ "$quiet" -eq 1 ] || echo "note: corpus empty ($corpus_dir) — nothing to check"
        exit 0
    fi

    # --- Scan the corpus and flag unhandled values ----------------------------
    local unhandled=0 f val
    local seen_type=" " seen_prio=" "

    # frontmatter <file> <key> — echo the value of <key> from the first YAML
    # frontmatter block (between the first two `---` fences). Strips surrounding
    # quotes/whitespace. Empty output => key absent. Scoping to the frontmatter
    # block avoids matching prose lines that happen to start with the key word.
    extract() {
        awk -v key="$1" '
            BEGIN { in_fm = 0 }
            /^---[[:space:]]*$/ { if (in_fm) exit; in_fm = 1; next }
            in_fm && $0 ~ "^"key":[[:space:]]" {
                sub("^"key":[[:space:]]+", "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                gsub(/^["\047]|["\047]$/, "")
                print
                exit
            }
        ' "$2"
    }

    for f in "$corpus_dir"/*.md; do
        # type:
        val="$(extract type "$f")"
        if [ -n "$val" ]; then
            case "$seen_type" in
                *" $val "*) : ;;
                *)
                    seen_type="$seen_type$val "
                    if in_list "$val" "${gate_type_set[@]}"; then
                        : # already a gate token — handled
                    elif in_list "$val" "${TYPE_ALLOWLIST[@]}"; then
                        : # explicitly conscious-out (built-in allowlist)
                    elif [ "${#extra_allow[@]}" -gt 0 ] && in_list "$val" "${extra_allow[@]}"; then
                        : # explicitly conscious-out (--allowlist file)
                    elif prefix_related "$val" "${gate_type_set[@]}"; then
                        # short/long sibling of a gating token but itself absent —
                        # the short-form-gap defect class (e.g. `sec` vs `security-*`).
                        unhandled=$((unhandled + 1))
                        [ "$quiet" -eq 1 ] || echo "UNHANDLED type: $val  (e.g. ${f#"$corpus_dir"/})  — sibling of a gating token, absent from SEC_INFRA_TYPES"
                    else
                        : # unrelated free-form type — out of the gate's concern
                    fi
                    ;;
            esac
        fi

        # priority:
        val="$(extract priority "$f")"
        if [ -n "$val" ]; then
            case "$seen_prio" in
                *" $val "*) : ;;
                *)
                    seen_prio="$seen_prio$val "
                    if in_list "$val" "${gate_prio_set[@]}"; then
                        :
                    else
                        unhandled=$((unhandled + 1))
                        [ "$quiet" -eq 1 ] || echo "UNHANDLED priority: $val  (e.g. ${f#"$corpus_dir"/})  — would fail-close to hard_block"
                    fi
                    ;;
            esac
        fi
    done

    if [ "$unhandled" -gt 0 ]; then
        [ "$quiet" -eq 1 ] || echo "FAIL: $unhandled unhandled value(s) — gate set or allowlist must consciously cover them"
        exit 1
    fi
    [ "$quiet" -eq 1 ] || echo "OK: all corpus type:/priority: values are consciously handled by the gate"
    exit 0
}

main "$@"
