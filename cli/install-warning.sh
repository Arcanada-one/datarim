#!/usr/bin/env bash
# cli/install-warning.sh — bilingual AAL 3 install warning (TUNE-0271 D-E).
# Canonical text from PRD-TUNE-0271 § Bilingual Install Warning Text.
# Printed every install run (no "already seen" skip).

set -u

print_aal3_warning() {
    cat <<'WARN'
─── Datarim CLI — AAL 3 autonomous-agent surface ───
EN: This CLI lets external agents drive Datarim WITHOUT interactive
EN: confirmation, including /dr-* dispatch, task moves, plugin changes,
EN: and tmux new/kill. The AAL 3 mandate-override
EN: has no active acceptance; install and mutating commands fail closed
EN: until a current entry is approved in accepted-risk-aal.yml.
EN: Kill-switch: `datarim audit halt` (sentinel file ~/.config/datarim-cli/HALT).

RU: CLI позволяет внешним агентам управлять Datarim БЕЗ интерактивного
RU: подтверждения, включая /dr-* вызовы, смену стадий, плагины,
RU: создание/удаление tmux. AAL 3 mandate-override действует
RU: только при актуальной записи; сейчас нет действующего принятия риска,
RU: поэтому установка и изменяющие команды блокируются.
RU: Kill-switch: `datarim audit halt` (sentinel-файл ~/.config/datarim-cli/HALT).
─── audit log: datarim/audit/cli-audit-{YYYY-MM-DD}.jsonl (retention 90d) ───
WARN
}

case "${BASH_SOURCE[0]:-$0}" in
    "$0") print_aal3_warning ;;
esac
