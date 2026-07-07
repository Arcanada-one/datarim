#!/usr/bin/env bash
# datarim-stage-probe-coworker-echo.sh — probe coworker datarim profile awareness.
#
# Sends a fixed question to coworker (`List 3 Datarim conventions you must
# follow when editing this file.`) using the active profile, captures the
# response, counts mandate keywords, and appends a journal entry.
#
# Refuses if the task-description contains sensitive markers (T1 mitigation):
# passwords, API keys, SSH paths, vault tokens, client secrets. In that case
# the journal records `skipped:sensitive-markers` and exits 0 — the absence
# of coworker exposure is the desired outcome.
#
# Usage:
#   dev-tools/datarim-stage-probe-coworker-echo.sh <TASK-ID>
#
# Exit codes:
#   0  probe executed (success OR sensitive-markers refusal)
#   1  harness dir missing / coworker CLI absent / task-description not found
#   2  TASK-ID regex fail

set -euo pipefail

TASK_ID="${1:-}"

if ! [[ "$TASK_ID" =~ ^[A-Z]+-[0-9]{4,}$ ]]; then
    printf 'coworker-echo: bad TASK-ID %q\n' "$TASK_ID" >&2
    exit 2
fi

DIR="/tmp/datarim-test-${TASK_ID}"

if [ ! -d "$DIR" ] || [ -L "$DIR" ]; then
    printf 'coworker-echo: harness dir missing or symlink — run init first\n' >&2
    exit 1
fi

if ! command -v coworker >/dev/null 2>&1; then
    printf 'coworker-echo: coworker CLI not in PATH\n' >&2
    exit 1
fi

# Walk up from cwd to find the task-description file.
TASK_DESC=""
cur="$(pwd)"
while [ "$cur" != "/" ]; do
    cand="${cur}/datarim/tasks/${TASK_ID}-task-description.md"
    if [ -f "$cand" ]; then
        TASK_DESC="$cand"
        break
    fi
    cur="$(dirname "$cur")"
done

if [ -z "$TASK_DESC" ]; then
    printf 'coworker-echo: task-description for %s not found in any ancestor datarim/tasks/\n' "$TASK_ID" >&2
    exit 1
fi

# T1 mitigation — refuse if description names sensitive markers.
if grep -qiE '(password|secret|api[_-]?key|/etc/shadow|vault token|client_secret|private[_-]?key)' "$TASK_DESC"; then
    printf 'coworker-echo: sensitive markers detected in %s — refusing (T1 mitigation)\n' "$TASK_DESC" >&2
    printf 'coworker · %s · skipped:sensitive-markers\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${DIR}/journal.md"
    exit 0
fi

OUT="${DIR}/coworker-echo.txt"
# --max-tokens 4096 — listing 3 rules with brief explanations against the
# doc-read profile consumes enough prompt budget that lower caps
# truncate mid-sentence and reduce keyword recall.
coworker ask --profile doc-read --paths "$TASK_DESC" \
    --question "List 3 Datarim conventions you must follow when editing this file." \
    --max-tokens 4096 > "$OUT" 2>&1 || true

# Score mandate keywords (case-insensitive). Each unique keyword counts once.
KEYWORDS_FOUND=0
for kw in \
    "stage header" \
    "append-log" \
    "append log" \
    "expectations checklist" \
    "snapshot frontmatter" \
    "yaml frontmatter" \
    "frontmatter" \
    "mandate" \
    "supreme directive" \
    "diataxis" \
    "diátaxis" \
    "wish_id" \
    "history-agnostic" \
    "history agnostic"
do
    if grep -qi "$kw" "$OUT"; then
        KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))
    fi
done

printf 'coworker · %s · keywords-found:%d\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$KEYWORDS_FOUND" >> "${DIR}/journal.md"
printf 'ok: keywords=%d (response saved to %s)\n' "$KEYWORDS_FOUND" "$OUT"
