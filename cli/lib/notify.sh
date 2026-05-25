#!/usr/bin/env bash
# cli/lib/notify.sh — pluggable notifier with ≥1-success fail-closed contract.
# Source: TUNE-0271 plan § Detailed Design 4.5.
#
# Public:
#   notify_irreversible <severity> <title> <body>
#     Iterates over configured backends from $DATARIM_CLI_NOTIFIER_TARGETS
#     (comma-separated, e.g. "telegram,webhook"). Returns 0 if ≥1 backend
#     acknowledged within 3000ms; returns 18 (fail-closed) otherwise.
#
# Backends (functions named _notify_<type>) implemented in Phase 3:
#   _notify_telegram — POST sendMessage via @ArcanadaAssistantBot token.
#   _notify_stub     — test-only mock that succeeds.
#   _notify_stub_fail — test-only mock that fails.
#
# Backends contract: receive ($severity, $title, $body); return 0 on ACK, ≠0 on
# failure. Must finish within 3000ms (caller enforces).

set -u

CLI_NOTIFY_EXIT_FAILCLOSED=18

# Vault path for the operator-acknowledged bot.
CLI_NOTIFY_TG_VAULT_PATH="${DATARIM_CLI_TG_VAULT_PATH:-kv/arcanada/auth/arcanada-assistant-bot/api_token}"
CLI_NOTIFY_TG_CHAT_ID_ENV="${DATARIM_CLI_TG_CHAT_ID:-}"

# Backends list — comma-separated; defaults to "telegram".
_notifier_targets() {
    printf '%s' "${DATARIM_CLI_NOTIFIER_TARGETS:-telegram}"
}

_notify_telegram() {
    local severity="$1" title="$2" body="$3"
    local token chat_id endpoint payload
    if [ -n "${DATARIM_CLI_TG_TOKEN:-}" ]; then
        token="$DATARIM_CLI_TG_TOKEN"
    elif command -v vault >/dev/null 2>&1; then
        token=$(vault kv get -field=token "$CLI_NOTIFY_TG_VAULT_PATH" 2>/dev/null || true)
    else
        token=""
    fi
    chat_id="$CLI_NOTIFY_TG_CHAT_ID_ENV"
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        printf '[notify-telegram] missing token or chat_id (token_set=%s chat_set=%s)\n' \
            "$([ -n "$token" ] && echo 1 || echo 0)" \
            "$([ -n "$chat_id" ] && echo 1 || echo 0)" >&2
        return 1
    fi
    endpoint="${DATARIM_CLI_TG_API_BASE:-https://api.telegram.org}/bot${token}/sendMessage"
    payload=$(python3 -c "import json,sys; print(json.dumps({'chat_id':sys.argv[1],'text':f\"[{sys.argv[2]}] {sys.argv[3]}\n{sys.argv[4]}\"}))" \
        "$chat_id" "$severity" "$title" "$body")
    local http_code
    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        --max-time 3 \
        -H 'Content-Type: application/json' \
        -X POST -d "$payload" \
        "$endpoint" 2>/dev/null) || true
    case "$http_code" in
        2*) return 0 ;;
        *)  printf '[notify-telegram] HTTP %s from %s\n' "$http_code" "$endpoint" >&2
            return 1 ;;
    esac
}

# Test-only backends — only activated when env var present.
_notify_stub() {
    [ "${DATARIM_CLI_NOTIFY_STUB_RESULT:-0}" = "0" ]
}
_notify_stub_fail() {
    return 1
}

notify_irreversible() {
    local severity="$1" title="$2" body="$3"
    local targets IFS_BAK acked=0 target fn
    targets="$(_notifier_targets)"
    IFS_BAK="$IFS"
    IFS=',' read -ra arr <<<"$targets"
    IFS="$IFS_BAK"
    for target in "${arr[@]}"; do
        target="$(printf '%s' "$target" | tr -d '[:space:]')"
        [ -z "$target" ] && continue
        fn="_notify_$target"
        if declare -f "$fn" >/dev/null; then
            if "$fn" "$severity" "$title" "$body"; then
                acked=$((acked + 1))
            fi
        else
            printf '[notify] unknown backend: %s (no function %s)\n' "$target" "$fn" >&2
        fi
    done
    if [ "$acked" -ge 1 ]; then
        return 0
    fi
    printf '[notify] fail-closed: 0/%d backends acknowledged\n' "${#arr[@]}" >&2
    return $CLI_NOTIFY_EXIT_FAILCLOSED
}
