#!/usr/bin/env bash
# check-dr-auto-reassert-wiring.sh — assert that commands/dr-auto.md Step 5
# carries an imperative, non-skippable pre-dispatch invocation of
# auto-mode-marker.sh reassert (the wiring that makes the marker re-assert
# self-enforcing for an LLM-executed spec).
#
# Why this exists:
#   The /dr-auto command spec is executed by an LLM orchestrator, not a
#   shell script. "Self-enforcing" for an LLM-executed spec means:
#     (1) Step 5 carries a mandatory MUST-gate with the executable call, and
#     (2) a deterministic CI lint FAILS (exit 1) the moment that call decays
#         back to advisory prose only.
#   Without this lint, prose-only regression is silent — no CI gate fires.
#
# Detection algorithm:
#   Scans <root>/commands/dr-auto.md for the co-occurrence of:
#     (a) a mandatory/imperative cue (MUST / mandatory / must-run / pre-dispatch /
#         Before spawning / before spawning / non-skippable / you MUST) present
#         on a prose line outside a fenced block, AND
#     (b) the executable invocation  auto-mode-marker.sh reassert  present on
#         any line (prose or inside a fenced block) within 8 lines of a
#         matched cue.
#
#   A prose-only advisory mentions only the invocation without any mandatory
#   cue nearby — the lint emits exit 1 + offence line.
#   If neither the cue nor the invocation is found — exit 1.
#   Fenced code blocks are excluded from the CUE scan only (so an illustrative
#   fenced block that mentions the helper but has no adjacent imperative framing
#   does not cause a false-pass). The INVOCATION scan includes fenced blocks
#   because the invocation is deliberately placed in a copyable code block
#   immediately below the imperative prose.
#
# API:
#   check-dr-auto-reassert-wiring.sh [--root <runtime-path>] [--quiet]
#     --root   scan root (default: script-dir/..); reads <root>/commands/dr-auto.md
#     --quiet  exit code only, no offence lines printed
#
# Exit codes:
#   0 — wired (imperative cue + invocation co-located)
#   1 — prose-only regression (invocation absent, or invocation present but no
#       nearby mandatory cue)
#   2 — usage / IO error (bad args, missing root, missing file)

set -uo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: check-dr-auto-reassert-wiring.sh [--root <runtime-path>] [--quiet]
  --root   scan root (default: script-dir/..)
  --quiet  exit code only, no offence lines
exit codes: 0 wired | 1 prose-only regression | 2 usage/IO
USAGE
    exit 2
}

ROOT=""
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || usage
            ROOT="$2"
            shift 2
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "[check-dr-auto-reassert-wiring] unknown flag: $1" >&2
            usage
            ;;
    esac
done

if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ ! -d "$ROOT" ]; then
    echo "[check-dr-auto-reassert-wiring] root does not exist: $ROOT" >&2
    exit 2
fi

TARGET="$ROOT/commands/dr-auto.md"

if [ ! -f "$TARGET" ]; then
    echo "[check-dr-auto-reassert-wiring] file not found: $TARGET" >&2
    exit 2
fi

# Use awk to scan the file.
# Returns one of:
#   "wired"       — imperative cue present (outside fence) AND invocation
#                   present (within 8 lines of last seen cue, any context)
#   "prose-only"  — invocation found but not within 8 lines of an imperative cue
#   "missing"     — invocation not found at all
result="$(LC_ALL=C awk '
    BEGIN {
        in_fence      = 0
        found_call    = 0
        found_wired   = 0
        last_cue_line = -99
        WINDOW        = 8
    }

    # Fence tracking: toggle on ``` lines
    /^[[:space:]]*```/ {
        in_fence = (in_fence == 0) ? 1 : 0
        next
    }

    {
        lineno = NR

        # CUE scan — prose lines only (outside fences)
        if (in_fence == 0) {
            if ($0 ~ /MUST|mandatory|must-run|pre-dispatch|Before spawning|before spawning|non-skippable|you MUST/) {
                last_cue_line = lineno
            }
        }

        # INVOCATION scan — any line (prose or inside fence)
        if ($0 ~ /auto-mode-marker\.sh[[:space:]]+reassert/) {
            found_call = 1
            # Check if this invocation is within WINDOW lines of the last cue
            if (lineno - last_cue_line <= WINDOW && last_cue_line >= 0) {
                found_wired = 1
            }
        }
    }

    END {
        if (found_wired == 1) {
            print "wired"
        } else if (found_call == 1) {
            print "prose-only"
        } else {
            print "missing"
        }
    }
' "$TARGET")"

case "$result" in
    wired)
        exit 0
        ;;
    prose-only)
        if [ "$QUIET" -eq 0 ]; then
            echo "commands/dr-auto.md: Step 5 carries auto-mode-marker.sh reassert but it is framed as advisory prose only — promote to a mandatory MUST pre-dispatch gate" >&2
        fi
        exit 1
        ;;
    missing)
        if [ "$QUIET" -eq 0 ]; then
            echo "commands/dr-auto.md: auto-mode-marker.sh reassert invocation is absent from Step 5 (prose-only regression)" >&2
        fi
        exit 1
        ;;
    *)
        echo "[check-dr-auto-reassert-wiring] unexpected awk result: $result" >&2
        exit 2
        ;;
esac
