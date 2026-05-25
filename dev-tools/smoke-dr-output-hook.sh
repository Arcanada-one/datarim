#!/usr/bin/env bash
# smoke-dr-output-hook.sh — live transcript smoke for TUNE-0264.
#
# Picks the most recently modified session JSONL under
# $HOME/.claude/projects/<encoded-cwd>/ and runs it through the Stop hook,
# printing a one-line verdict:
#
#   header_found:{y|n}; human_summary:{ok|<finding>|skipped}
#
# Operator-facing manual probe — fail-soft, exit 0 regardless of verdict.

set +e

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
HOOK="${HOOK_DIR}/hooks/dr-output-stop.sh"

PROJECTS_DIR="${HOME}/.claude/projects"
if [ ! -d "$PROJECTS_DIR" ]; then
    printf 'smoke: no projects dir at %s\n' "$PROJECTS_DIR"
    exit 0
fi

latest_jsonl="$(find "$PROJECTS_DIR" -type f -name '*.jsonl' -print0 \
    | xargs -0 ls -1t 2>/dev/null | head -1)"

if [ -z "$latest_jsonl" ]; then
    printf 'smoke: no session jsonl found under %s\n' "$PROJECTS_DIR"
    exit 0
fi

payload="$(printf '{"session_id":"smoke","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}\n' "$latest_jsonl")"
out="$(printf '%s\n' "$payload" | bash "$HOOK" 2>/tmp/dr-output-stop-smoke.stderr)"

header="y"
if printf '%s' "$out" | grep -q 'Stage Header missing'; then
    header="n"
fi

human="skipped"
if printf '%s' "$out" | grep -q 'human-summary'; then
    # Extract first finding code from the JSON reason (lower-case slug-ish token).
    human="$(printf '%s' "$out" | grep -oE 'missing_section|missing_preamble|missing_subheading_[0-9]|fifth_subheading|wrong_order' | head -1)"
    [ -z "$human" ] && human="violation"
elif [ -z "$out" ]; then
    human="ok"
fi

printf 'header_found:%s; human_summary:%s (transcript: %s)\n' "$header" "$human" "$latest_jsonl"
exit 0
