#!/usr/bin/env bash
# cli/install-warning.sh — bilingual AAL 3 install warning (TUNE-0271 D-E).
# Canonical text from PRD-TUNE-0271 § Bilingual Install Warning Text.
# Printed every install run (no "already seen" skip).

set -u

print_aal3_warning() {
    cat <<'WARN'
─── Datarim CLI — AAL 3 autonomous-agent surface ───
EN: This CLI lets external agents drive Datarim WITHOUT interactive
EN: confirmation, including irreversible actions like /dr-archive,
EN: git push, deploy, tmux kill, config set. AAL 3 mandate-override
EN: was explicitly accepted by operator paxbeach on 2026-05-23 and
EN: expires 2026-08-21 unless renewed in accepted-risk-aal.yml.
EN: Kill-switch: `datarim audit halt` (sentinel file ~/.config/datarim-cli/HALT).

RU: CLI позволяет внешним агентам управлять Datarim БЕЗ интерактивного
RU: подтверждения, включая необратимые действия /dr-archive, git push,
RU: deploy, tmux kill, config set. AAL 3 mandate-override явно принят
RU: оператором paxbeach 2026-05-23, истекает 2026-08-21 без продления
RU: записи в accepted-risk-aal.yml.
RU: Kill-switch: `datarim audit halt` (sentinel-файл ~/.config/datarim-cli/HALT).
─── audit log: datarim/audit/cli-audit-{YYYY-MM-DD}.jsonl (retention 90d) ───
WARN
}

case "${BASH_SOURCE[0]:-$0}" in
    "$0") print_aal3_warning ;;
esac
