#!/usr/bin/env bash
# dr-output-stop.sh — bash wrapper around dr-output-stop.py.
#
# Claude Code Stop hook entry point. Forwards stdin JSON to the Python
# helper which runs two validators (Stage Header + Human Summary contract).
# Fail-soft: any unexpected error from the wrapper or the helper degrades to
# exit 0 (allow) — the text contract (skills/cta-format/SKILL.md +
# skills/human-summary/SKILL.md) is the canonical surface, this hook is the final
# defensive layer per TUNE-0264.
#
# Usage (registered in ~/.claude/settings.json):
#   {"hooks": {"Stop": [{"hooks": [{
#     "type": "command",
#     "command": "bash $HOME/.claude/dev-tools/hooks/dr-output-stop.sh",
#     "timeout": 5
#   }]}]}}
#
# Spec: code/datarim/docs/how-to/dr-output-hook.md

set +e
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
HELPER="${SCRIPT_DIR}/dr-output-stop.py"

if [ ! -f "$HELPER" ]; then
    exit 0
fi

python3 "$HELPER" --stdin
exit 0
