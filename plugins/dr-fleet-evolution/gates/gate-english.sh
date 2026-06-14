#!/usr/bin/env bash
# gates/gate-english.sh — English-only shipped-surface gate for a skill candidate.
#
# argv[1] = candidate file (SKILL.md), argv[2] = skill level (unused; uniform
# gate signature). exit 0 = pass, exit 1 = fail (non-Latin script found).
#
# NOT a naive non-ASCII grep: shipped fleet skills legitimately use typographic
# punctuation (em-dash, section sign, arrow) which does not violate the
# English-only mandate. This gate fails only on non-Latin *scripts* (Cyrillic,
# Greek, CJK, etc.) — the actual mandate target — and honours an inline
# `<!-- allow-non-ascii: <reason> -->` escape on the same line.

set -o pipefail

usage() { echo "Usage: $(basename "$0") <candidate-file> [skill-level]" >&2; }

main() {
    local candidate=${1:-}
    [ -n "$candidate" ] || { usage; exit 2; }
    [ -f "$candidate" ] || { echo "gate-english: file not found: $candidate" >&2; exit 2; }

    # Match any character in a non-Latin script the mandate forbids (Cyrillic,
    # Greek, Han, Hangul, Kana, Hebrew, Arabic). Typographic punctuation
    # (em-dash, section sign, arrow) is allowed. perl -CSD gives portable
    # Unicode script properties — `grep -P` is unavailable on BSD/macOS grep
    # (GNU/BSD divergence) so it is NOT used here.
    #
    # Lines carrying an `allow-non-ascii` escape are dropped before scanning.
    local offending
    offending=$(grep -vE 'allow-non-ascii' "$candidate" \
        | perl -CSD -ne 'print "$.: $_" if /[\p{Cyrillic}\p{Greek}\p{Han}\p{Hangul}\p{Hiragana}\p{Katakana}\p{Hebrew}\p{Arabic}]/' \
        || true)
    if [ -n "$offending" ]; then
        echo "gate-english: non-Latin script in shipped surface (English-only mandate):" >&2
        printf '%s\n' "$offending" | head -5 >&2
        exit 1
    fi
    exit 0
}

main "$@"
