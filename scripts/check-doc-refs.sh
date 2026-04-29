#!/usr/bin/env bash
# check-doc-refs.sh — markdown reference integrity linter (TUNE-0054)
#
# Recursively scans markdown files under --root for broken references:
#   1. Markdown inline links: `[text](relative/path.md)` and `[text](path.md#anchor)`
#   2. Bare-path mentions:    `(skills|agents|commands|templates|docs)/.../*.md`
#
# For each reference, the resolved target must exist on disk relative to:
#   - markdown link form  → dirname(file) (RFC 7e standard)
#   - bare-path form      → ROOT
#
# Whitelist precedence (highest first):
#   1. Inline same-line marker `<!-- doc-ref:allow path=<target> -->`
#   2. `.docrefignore` glob pattern at ROOT (gitignore-style)
#   3. Otherwise → orphan reported on stderr
#
# Skip rules:
#   - External links: `http://`, `https://`, `mailto:`, `ftp://`, `#anchor-only`
#   - Fenced code blocks (``` toggling) and inline backtick code
#   - Auto-generated/binary files (none currently)
#
# Exit codes:
#   0  clean — every non-whitelisted reference resolves
#   1  orphans found
#   2  usage error / path-traversal rejection / ROOT not a directory
#
# Source: TUNE-0054 plan in datarim/tasks.md.
# Recurrence-prevention pattern: «Memory Rule → Executable Gate at Apply Step»
# (TUNE-0044/0056/0058/0059/0060/0061 — 7th iteration).

set -u

print_usage() {
    cat >&2 <<'EOF'
Usage:
  check-doc-refs.sh [--root <DIR>] [--baseline <FILE>] [--no-baseline] [--quiet]

Options:
  --root <DIR>          Tree to scan. Default: . (current dir).
  --baseline <FILE>     Path to .docrefignore. Default: <root>/.docrefignore.
  --no-baseline         Ignore baseline (paranoid CI mode).
  --quiet               Suppress OK summary; orphans still printed.

Exit codes:
  0 - clean
  1 - orphans found
  2 - usage error / path-traversal / bad root
EOF
}

# --- arg parsing --------------------------------------------------------------
ROOT="."
BASELINE_OVERRIDE=""
NO_BASELINE=0
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)         ROOT="${2:-}"; shift 2 ;;
        --baseline)     BASELINE_OVERRIDE="${2:-}"; shift 2 ;;
        --no-baseline)  NO_BASELINE=1; shift ;;
        --quiet)        QUIET=1; shift ;;
        -h|--help)      print_usage; exit 0 ;;
        *)              echo "Error: unknown arg: $1" >&2; print_usage; exit 2 ;;
    esac
done

if [ ! -d "$ROOT" ]; then
    echo "Error: --root '$ROOT' is not a directory" >&2
    exit 2
fi

# Canonicalise ROOT for path-traversal guard.
ROOT_ABS="$(cd "$ROOT" && pwd -P)"

# Baseline location.
if [ "$NO_BASELINE" -eq 1 ]; then
    BASELINE=""
elif [ -n "$BASELINE_OVERRIDE" ]; then
    BASELINE="$BASELINE_OVERRIDE"
else
    BASELINE="$ROOT/.docrefignore"
fi

# --- baseline glob loading ----------------------------------------------------
# Load non-comment, non-blank lines from baseline into BASELINE_PATTERNS array.
BASELINE_PATTERNS=()
if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ''|'#'*) continue ;;
            *)       BASELINE_PATTERNS+=("$_line") ;;
        esac
    done < "$BASELINE"
fi

# Test if a given relative path matches any baseline glob.
matches_baseline() {
    local rel="$1"
    local pat
    for pat in "${BASELINE_PATTERNS[@]+"${BASELINE_PATTERNS[@]}"}"; do
        # SC2053 + SC2254: glob match is intentional (gitignore-style patterns).
        # shellcheck disable=SC2053,SC2254
        case "$rel" in
            $pat) return 0 ;;
        esac
    done
    return 1
}

# --- file enumeration ---------------------------------------------------------
# We scan ROOT/CLAUDE.md plus ROOT/{skills,agents,commands,templates,docs}/**/*.md.
# Other dirs (tests/, scripts/, documentation/) are out-of-scope per plan.
SCAN_TARGETS=()
[ -f "$ROOT/CLAUDE.md" ] && SCAN_TARGETS+=("$ROOT/CLAUDE.md")
for _sub in skills agents commands templates docs; do
    if [ -d "$ROOT/$_sub" ]; then
        while IFS= read -r _f; do
            SCAN_TARGETS+=("$_f")
        done < <(find "$ROOT/$_sub" -type f -name '*.md' 2>/dev/null)
    fi
done

# --- orphan accumulator -------------------------------------------------------
ORPHAN_COUNT=0
TRAVERSAL_HIT=0

emit_orphan() {
    local file="$1" line="$2" target="$3" resolved="${4:-}"
    if [ -n "$resolved" ] && [ "$resolved" != "$target" ]; then
        echo "ORPHAN: $file:$line: $target  (resolved: $resolved)" >&2
    else
        echo "ORPHAN: $file:$line: $target" >&2
    fi
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
}

# Lexical path canonicalisation (no I/O — parent dirs need not exist).
# Collapses './' and resolves '../' against the prior component. Preserves
# leading '/' for absolute inputs. Used for path-traversal detection.
canonicalise_path() {
    local input="$1"
    local lead=""
    case "$input" in
        /*) lead="/" ;;
    esac
    local IFS='/'
    # shellcheck disable=SC2206
    local parts=( $input )
    local out=()
    local seg
    for seg in "${parts[@]}"; do
        case "$seg" in
            ''|'.') ;;
            '..')
                if [ "${#out[@]}" -gt 0 ] && [ "${out[$((${#out[@]}-1))]}" != ".." ]; then
                    unset 'out[${#out[@]}-1]'
                    out=("${out[@]}")
                elif [ -z "$lead" ]; then
                    out+=("..")
                fi
                ;;
            *) out+=("$seg") ;;
        esac
    done
    if [ "${#out[@]}" -eq 0 ]; then
        printf '%s' "${lead:-.}"
    else
        printf '%s%s' "$lead" "$(IFS=/; echo "${out[*]}")"
    fi
}

# --- per-file scan ------------------------------------------------------------
# AWK script handles fenced/inline-code stripping in one pass and emits records:
#   <lineno>\t<form>\t<target>\t<allow_marker_target_or_empty>
# where form ∈ {link, bare}.
# Fenced blocks are ``` toggling at start of line.
# Inline code `…` on the same line is removed before extraction.
AWK_EXTRACT='
BEGIN { fenced = 0 }
{
    line = $0
    # Fenced toggle: leading ``` (after optional whitespace)
    if (match(line, /^[[:space:]]*```/)) {
        fenced = 1 - fenced
        next
    }
    if (fenced) next

    # Strip inline backtick code spans `…`
    while (match(line, /`[^`]*`/)) {
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
    }

    # Capture inline allow marker target on this line (if any).
    allow = ""
    if (match(line, /<!--[[:space:]]*doc-ref:allow[[:space:]]+path=[^[:space:]]+[[:space:]]*-->/)) {
        m = substr(line, RSTART, RLENGTH)
        if (match(m, /path=[^[:space:]]+/)) {
            allow = substr(m, RSTART + 5, RLENGTH - 5)
        }
    }

    # Extract markdown inline links: [text](target)
    rest = line
    while (match(rest, /\[[^]]*\]\(([^)]+)\)/)) {
        chunk = substr(rest, RSTART, RLENGTH)
        if (match(chunk, /\(([^)]+)\)/)) {
            tgt = substr(chunk, RSTART + 1, RLENGTH - 2)
            print NR "\tlink\t" tgt "\t" allow
        }
        rest = substr(rest, RSTART + RLENGTH)
    }

    # Extract bare-path mentions: <prefix>/.../*.md (no surrounding markdown brackets)
    # Operate on backtick-stripped + bracketed-form-stripped variant.
    bare_line = line
    while (match(bare_line, /\[[^]]*\]\([^)]+\)/)) {
        bare_line = substr(bare_line, 1, RSTART - 1) substr(bare_line, RSTART + RLENGTH)
    }
    while (match(bare_line, /(skills|agents|commands|templates|docs)\/[-A-Za-z0-9_.\/]+\.md/)) {
        tgt = substr(bare_line, RSTART, RLENGTH)
        print NR "\tbare\t" tgt "\t" allow
        bare_line = substr(bare_line, RSTART + RLENGTH)
    }
}
'

scan_file() {
    local file="$1"
    local file_dir
    file_dir="$(cd "$(dirname "$file")" && pwd -P)"

    while IFS=$'\t' read -r lineno form target allow; do
        [ -z "$target" ] && continue

        # Skip externals/anchors.
        case "$target" in
            http://*|https://*|mailto:*|ftp://*|'#'*) continue ;;
        esac

        # Strip URL fragment (#anchor).
        target_no_anchor="${target%%#*}"
        [ -z "$target_no_anchor" ] && continue

        # Resolve.
        if [ "$form" = "link" ]; then
            base_dir="$file_dir"
        else
            base_dir="$ROOT_ABS"
        fi

        # Absolute path of the candidate.
        if [ "${target_no_anchor:0:1}" = "/" ]; then
            candidate="$target_no_anchor"
        else
            candidate="$base_dir/$target_no_anchor"
        fi

        # Path-traversal guard: manual lexical canonicalisation (parent dirs may not exist).
        # Splits on '/', collapses '.', resolves '..', preserving leading '/' for absolute paths.
        cand_abs="$(canonicalise_path "$candidate")"

        case "$cand_abs" in
            "$ROOT_ABS"|"$ROOT_ABS"/*) ;;  # within ROOT
            *)
                echo "Error: path traversal outside ROOT in $file:$lineno → $target" >&2
                TRAVERSAL_HIT=1
                continue
                ;;
        esac

        # Allow marker: matches when --allow path== resolves to same relative target.
        rel_from_root="${cand_abs#"$ROOT_ABS"/}"
        if [ -n "$allow" ]; then
            if [ "$allow" = "$rel_from_root" ] || [ "$allow" = "$target_no_anchor" ]; then
                continue
            fi
        fi

        # Existence check.
        if [ -e "$cand_abs" ]; then
            continue
        fi

        # Baseline whitelist.
        if matches_baseline "$rel_from_root"; then
            continue
        fi

        emit_orphan "$file" "$lineno" "$target" "$rel_from_root"
    done < <(LC_ALL=C awk "$AWK_EXTRACT" "$file" 2>/dev/null)
}

# --- main loop ----------------------------------------------------------------
for _f in "${SCAN_TARGETS[@]+"${SCAN_TARGETS[@]}"}"; do
    scan_file "$_f"
done

# --- exit ---------------------------------------------------------------------
if [ "$TRAVERSAL_HIT" -eq 1 ]; then
    exit 2
fi

if [ "$ORPHAN_COUNT" -gt 0 ]; then
    echo "FAIL: $ORPHAN_COUNT orphan reference(s)" >&2
    exit 1
fi

if [ "$QUIET" -ne 1 ]; then
    echo "OK: doc references clean (${#SCAN_TARGETS[@]} files scanned)" >&2
fi
exit 0
