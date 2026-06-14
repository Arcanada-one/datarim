#!/usr/bin/env bash
# check-deferral-prose.sh — anti-deferral prose scanner for QA / compliance reports.
#
# Detects the failure mode where an agent labels its OWN incomplete work
# ("out of scope / informational / not a blocker / I'll fix later") and ships it.
# A deferral-tell phrase is a BLOCK only when it co-occurs (same paragraph) with a
# file the agent itself touched AND no traceable legitimate-deferral artefact is
# present. A deferral phrase about an untouched (genuinely foreign) area, a clean
# report, or a phrase backed by a verified follow-up ID / blocked_by reference is
# allowed. The touched-file discriminator is what keeps the gate targeted and the
# false-positive rate low.
#
# Legitimate-deferral artefact (the only escape): a follow-up backlog ID present in
# the backlog, OR a `blocked_by:` reference resolvable in the tasks index. Prose
# without such an ID is not an artefact.
#
# Contract:
#   exit 0  → PASS (no self-inflicted deferral, or fail-open advisory)
#   exit 1  → BLOCKED (stdout: file:line: phrase | touched=<f> | no verified artefact)
#   exit 2  → usage error
#
# Fail-open-with-warning: if the touched-file set cannot be computed (no
# --touched-files and git merge-base unavailable — detached HEAD, no origin/main,
# git absent), the scanner WARNS loudly to stderr and PASSES rather than blocking
# an otherwise-clean archive on its own infrastructure failure. The seed phrase
# list is a FLOOR, not a ceiling — rephrasings are caught structurally by the
# artefact requirement, FB-5a, and the compliance human-summary.
#
# API:
#   check-deferral-prose.sh --file <report.md> [--touched-files <list>]
#       [--root <repo-root>] [--backlog <path>] [--tasks <path>]
#       [--phrases <path>] [--report]

set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: check-deferral-prose.sh --file <report.md> [--touched-files <list>]
       [--root <repo-root>] [--backlog <path>] [--tasks <path>]
       [--phrases <path>] [--report]
  --file           markdown report to scan (required; ^[A-Za-z0-9._/-]+\.md$)
  --touched-files  newline list of files the task touched (else derived from git)
  --root           repo root for git-derived touched set + KB lookups (default: .)
  --backlog        backlog index for artefact verification (default: <root>/datarim/backlog.md)
  --tasks          tasks index for blocked_by verification (default: <root>/datarim/tasks.md)
  --phrases        override the seed deferral-phrase floor (one pattern per line)
  --extra-repo     nested git repo whose merge-base..HEAD touched-set is added
                   to the scope (repeatable; for dual-repo framework tasks where
                   the report and the touched code live in different repos)
  --report         print machine-readable findings even when clean
exit codes:
  0 PASS (clean or fail-open advisory), 1 BLOCKED (findings on stdout), 2 usage error
USAGE
    exit 2
}

FILE=""
TOUCHED_FILES=""
ROOT="."
BACKLOG=""
TASKS=""
PHRASES=""
REPORT=0
EXTRA_REPOS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --file)           [ $# -ge 2 ] || usage; FILE="$2"; shift 2 ;;
        --touched-files)  [ $# -ge 2 ] || usage; TOUCHED_FILES="$2"; shift 2 ;;
        --root)           [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --backlog)        [ $# -ge 2 ] || usage; BACKLOG="$2"; shift 2 ;;
        --tasks)          [ $# -ge 2 ] || usage; TASKS="$2"; shift 2 ;;
        --phrases)        [ $# -ge 2 ] || usage; PHRASES="$2"; shift 2 ;;
        --extra-repo)     [ $# -ge 2 ] || usage; EXTRA_REPOS+=("$2"); shift 2 ;;
        --report)         REPORT=1; shift ;;
        -h|--help)        usage ;;
        *)                usage ;;
    esac
done

[ -n "$FILE" ] || usage

# Path-traversal / shape guard (Security Mandate § S1/S5). Untrusted planner input.
if ! printf '%s' "$FILE" | grep -Eq '^[A-Za-z0-9._/-]+\.md$'; then
    echo "ERROR: --file must match ^[A-Za-z0-9._/-]+\\.md\$ (got: $FILE)" >&2
    exit 2
fi
if [ ! -f "$FILE" ]; then
    echo "ERROR: file not found: $FILE" >&2
    exit 2
fi

: "${BACKLOG:=$ROOT/datarim/backlog.md}"
: "${TASKS:=$ROOT/datarim/tasks.md}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_PHRASES="$SCRIPT_DIR/../skills/expectations-checklist/deferral-phrases.txt"
: "${PHRASES:=$DEFAULT_PHRASES}"

# ---------------------------------------------------------------------------
# Resolve the touched-file set. Precedence:
#   1. --touched-files <list>           (caller-supplied, authoritative)
#   2. git merge-base origin/main..HEAD (the ownership boundary)
#   3. staged + working diff            (fallback, warn)
#   4. empty                            (fail-open advisory, warn)
# ---------------------------------------------------------------------------
TOUCHED_SET=""
touched_source="none"

read_list() { tr -d '\r' < "$1" | grep -v '^[[:space:]]*$' || true; }

if [ -n "$TOUCHED_FILES" ]; then
    if [ -f "$TOUCHED_FILES" ]; then
        TOUCHED_SET="$(read_list "$TOUCHED_FILES")"
        touched_source="explicit"
    else
        echo "ERROR: --touched-files not found: $TOUCHED_FILES" >&2
        exit 2
    fi
elif git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    base="$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
    if [ -n "$base" ]; then
        TOUCHED_SET="$(git -C "$ROOT" diff "$base"..HEAD --name-only 2>/dev/null || true)"
        touched_source="merge-base"
    fi
    if [ -z "$TOUCHED_SET" ]; then
        # Fallback: staged + working diff. Loud warning — coverage may be partial.
        TOUCHED_SET="$(
            { git -C "$ROOT" diff --cached --name-only 2>/dev/null
              git -C "$ROOT" diff --name-only 2>/dev/null; } | sort -u || true
        )"
        echo "WARNING: merge-base unavailable, using staged+working diff. Touched-file scope may be incomplete." >&2
        touched_source="staged-working"
    fi
fi

# Dual-repo augmentation: for a framework (TUNE-*) task the report lives in the
# outer workspace repo while the touched code lives in a nested repo. Each
# --extra-repo contributes its own merge-base..HEAD touched-set (staged+working
# fallback) so a genuine self-deferral on nested code is not invisible. This is
# additive, never a replacement — the fail-open contract is preserved: an
# unreadable extra-repo warns and is skipped, it never hard-blocks.
for er in ${EXTRA_REPOS[@]+"${EXTRA_REPOS[@]}"}; do
    if ! git -C "$er" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "WARNING: --extra-repo not a git work tree, skipped: $er" >&2
        continue
    fi
    er_base="$(git -C "$er" merge-base HEAD origin/main 2>/dev/null || true)"
    er_set=""
    if [ -n "$er_base" ]; then
        er_set="$(git -C "$er" diff "$er_base"..HEAD --name-only 2>/dev/null || true)"
    fi
    if [ -z "$er_set" ]; then
        er_set="$(
            { git -C "$er" diff --cached --name-only 2>/dev/null
              git -C "$er" diff --name-only 2>/dev/null; } | sort -u || true
        )"
    fi
    if [ -n "$er_set" ]; then
        TOUCHED_SET="$(printf '%s\n%s\n' "$TOUCHED_SET" "$er_set" | grep -v '^[[:space:]]*$' | sort -u)"
        [ "$touched_source" = "none" ] && touched_source="extra-repo"
    fi
done

if [ -z "$TOUCHED_SET" ]; then
    echo "WARNING: touched-file set empty (no --touched-files and git probe yielded nothing). Deferral scan is advisory only; not blocking." >&2
    touched_source="empty"
fi

# Reduce touched paths to basenames — reports cite files by name, not full path.
# Write to a temp file: BSD awk (macOS) rejects newlines inside a -v assignment,
# so the basename set is loaded via getline in BEGIN (same pattern as banlist).
BN_FILE="$(mktemp)"
trap 'rm -f "$BN_FILE"' EXIT
if [ -n "$TOUCHED_SET" ]; then
    while IFS= read -r p; do
        [ -n "$p" ] && basename "$p"
    done <<< "$TOUCHED_SET" > "$BN_FILE"
fi

# ---------------------------------------------------------------------------
# awk pass: emit candidate findings. For each line carrying a deferral-tell
# phrase, report the line number, the matched phrase, whether a touched-file
# basename appears in the SAME paragraph, and any candidate artefact ID token
# (FU/backlog ID or blocked_by ref) in the same paragraph. bash then verifies
# the artefact ID against the KB. A paragraph = run of non-blank lines.
# Output line shape:  <lineno>\t<phrase>\t<touched-basename-or->\t<artefact-id-or->
# ---------------------------------------------------------------------------
# Markdown fenced-code marker (three back-ticks), built from octal so no literal
# back-tick run appears in this file — a literal run inside the $(...) below
# would be mis-parsed by the shell as a nested command substitution.
FENCE_MARKER="$(printf '\140\140\140')"
candidates="$(
    awk -v PHRASES="$PHRASES" -v BN_FILE="$BN_FILE" -v FENCE="$FENCE_MARKER" '
    function lc(s) { return tolower(s) }
    BEGIN {
        np = 0
        while ((getline line < PHRASES) > 0) {
            sub(/#.*/, "", line)
            gsub(/^[ \t]+|[ \t\r]+$/, "", line)
            if (line == "") continue
            phrases[++np] = lc(line)
        }
        close(PHRASES)
        if (np == 0) {
            # Built-in floor (used when the phrase file is absent).
            split("out of scope|out-of-scope|вне scope|not a blocker|non-blocking|не блокер|не критично|informational|информационно|cosmetic|just cosmetic|косметика|will fix later|fix it later|fix later|доделаю позже|доделаем позже|post-archive|follow-up later|can revisit|next cycle|pre-existing|was already like this", arr, "|")
            for (i in arr) phrases[++np] = lc(arr[i])
        }
        nb = 0
        while ((getline line < BN_FILE) > 0) {
            gsub(/^[ \t]+|[ \t\r]+$/, "", line)
            if (line != "") bnames[++nb] = line
        }
        close(BN_FILE)
    }
    # Track paragraph boundaries by buffering; simpler: two-pass within awk.
    { lines[NR] = $0; ln = NR }
    END {
        total = ln
        # Mark quoted lines: a deferral-tell phrase inside a fenced code block
        # or a Markdown blockquote (leading ">") is a QUOTATION of the detection
        # target, not a self-deferral claim. A report ABOUT the anti-deferral
        # gate inevitably quotes the tell-phrases next to the gate own filenames;
        # those quotes must not BLOCK. Live prose on its own line still scans
        # normally. The fence marker (three back-ticks) is passed in via FENCE to
        # avoid embedding a literal back-tick run inside this $(...)-wrapped awk
        # program (a literal run would be parsed by the shell as a nested command
        # substitution). A fence line is one whose first non-space run equals the
        # marker (bare or marker+language). This pass runs in file order.
        fence_re = "^" FENCE
        in_fence = 0
        for (i = 1; i <= total; i++) {
            stripped = lines[i]; gsub(/^[ \t]+/, "", stripped)
            if (stripped ~ fence_re) { quoted[i] = 1; in_fence = !in_fence; continue }
            if (in_fence)            { quoted[i] = 1; continue }
            if (stripped ~ /^>/)     { quoted[i] = 1; continue }
            quoted[i] = 0
        }
        # Compute paragraph id per line (blank line separates paragraphs).
        pid = 0; prev_blank = 1
        for (i = 1; i <= total; i++) {
            if (lines[i] ~ /^[[:space:]]*$/) { prev_blank = 1; para[i] = 0; continue }
            if (prev_blank) pid++
            prev_blank = 0
            para[i] = pid
            # accumulate paragraph text (lowercased) for co-occurrence checks
            ptext[pid] = ptext[pid] " " lc(lines[i])
        }
        # For each paragraph, find a touched basename and an artefact id.
        for (p = 1; p <= pid; p++) {
            pbase[p] = "-"; partid[p] = "-"
            for (b = 1; b <= nb; b++) {
                if (bnames[b] != "" && index(ptext[p], lc(bnames[b])) > 0) { pbase[p] = bnames[b]; break }
            }
            # artefact id: blocked_by ref takes priority, else any FU/backlog id
            if (match(ptext[p], /blocked_by:[ \t]*[a-z]+-[0-9][0-9][0-9][0-9]/)) {
                tok = substr(ptext[p], RSTART, RLENGTH); sub(/blocked_by:[ \t]*/, "", tok)
                partid[p] = tok
            } else if (match(ptext[p], /[a-z]+-[0-9][0-9][0-9][0-9]/)) {
                partid[p] = substr(ptext[p], RSTART, RLENGTH)
            }
        }
        # Emit one candidate per LINE that contains a deferral phrase.
        for (i = 1; i <= total; i++) {
            if (para[i] == 0) continue
            if (quoted[i]) continue   # quoted phrase != self-deferral claim
            l = lc(lines[i])
            for (k = 1; k <= np; k++) {
                if (index(l, phrases[k]) > 0) {
                    p = para[i]
                    printf("%d\t%s\t%s\t%s\n", i, phrases[k], pbase[p], partid[p])
                    break
                }
            }
        }
    }
    ' "$FILE"
)"

# ---------------------------------------------------------------------------
# bash verdict pass. A candidate BLOCKS iff:
#   - it names a TOUCHED basename in its paragraph (self-inflicted), AND
#   - it has no verified legitimate-deferral artefact in that paragraph.
# Artefact verification: the candidate ID must literally appear in backlog/tasks.
# If the touched-file set is empty (fail-open), nothing blocks.
# ---------------------------------------------------------------------------
verify_artefact() {
    local id="$1"
    [ "$id" = "-" ] && return 1
    # Case-insensitive: reports may lower-case; KB stores upper-case IDs.
    if [ -f "$BACKLOG" ] && grep -qiE "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|$)" "$BACKLOG"; then return 0; fi
    if [ -f "$TASKS" ]   && grep -qiE "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|$)" "$TASKS";   then return 0; fi
    return 1
}

blocked=0
findings=""
while IFS=$'\t' read -r lineno phrase tbase artid; do
    [ -z "${lineno:-}" ] && continue
    # Not self-inflicted (phrase about an untouched / foreign area) → allow.
    [ "$tbase" = "-" ] && continue
    # Self-inflicted but a verified artefact backs the deferral → allow.
    if verify_artefact "$artid"; then continue; fi
    blocked=1
    findings="${findings}${FILE}:${lineno}: \"${phrase}\" on touched file '${tbase}' | no verified legitimate-deferral artefact"$'\n'
done <<< "$candidates"

if [ "$blocked" -eq 1 ]; then
    printf '%s' "$findings"
    echo "BLOCKED: self-inflicted deferral detected. Finish the work in this branch/cycle, or cite a verified follow-up ID / blocked_by reference. (touched-source: $touched_source)" >&2
    exit 1
fi

if [ "$REPORT" -eq 1 ]; then
    echo "PASS: no self-inflicted deferral (touched-source: $touched_source)"
fi
exit 0
