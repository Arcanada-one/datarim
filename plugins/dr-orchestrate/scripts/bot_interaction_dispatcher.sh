#!/usr/bin/env bash
# bot_interaction_dispatcher.sh — reads the bot_interaction block from the
# user-config YAML and exports DR_ORCH_* env vars that gate the bot-interaction
# interface introduced in plugin v0.3.0+.
#
# Supported providers:
#   terminal  — no env mutations (default, existing behaviour preserved).
#   agent0017 — exports DR_ORCH_ESCALATION_BACKEND=dev-bot; if endpoint is set,
#               also exports DR_ORCH_ESCALATION_DEVBOT_URL; if outbound_backend=redis,
#               also exports DR_ORCH_OUTBOUND_BACKEND=redis + DR_ORCH_OUTBOUND_REDIS_URL.
#
# Usage (sourced): bot_interaction_load <config-yaml-path>
# Usage (direct):  bot_interaction_dispatcher.sh load <config-yaml-path>
set -euo pipefail

# bot_interaction_load <config-yaml-path>
# Returns 0 silently when:
#   - the file does not exist, OR
#   - the .bot_interaction block is absent (yq returns "null").
# Returns 2 with ERR message to stderr on unknown provider.
bot_interaction_load() {
  local config="$1"

  [[ -f "$config" ]] || return 0

  local provider
  provider="$(yq e '.bot_interaction.provider // "null"' "$config" 2>/dev/null)"
  [[ "$provider" != "null" ]] || return 0

  case "$provider" in
    terminal)
      # No env mutations — existing behaviour.
      return 0
      ;;
    agent0017)
      export DR_ORCH_ESCALATION_BACKEND="dev-bot"

      local endpoint
      endpoint="$(yq e '.bot_interaction.endpoint // ""' "$config" 2>/dev/null)"
      if [[ -n "$endpoint" ]]; then
        export DR_ORCH_ESCALATION_DEVBOT_URL="$endpoint"
      fi

      local outbound
      outbound="$(yq e '.bot_interaction.outbound_backend // ""' "$config" 2>/dev/null)"
      if [[ "$outbound" == "redis" ]]; then
        export DR_ORCH_OUTBOUND_BACKEND="redis"
        local redis_url
        redis_url="$(yq e '.bot_interaction.redis_url // ""' "$config" 2>/dev/null)"
        if [[ -n "$redis_url" ]]; then
          export DR_ORCH_OUTBOUND_REDIS_URL="$redis_url"
        fi
      fi

      return 0
      ;;
    *)
      echo "ERR: unknown bot_interaction.provider: $provider" >&2
      return 2
      ;;
  esac
}

# CLI dispatch — allows bats subprocess invocation:
#   bot_interaction_dispatcher.sh load <config>
# Maps the public verb "load" to the internal function name.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verb="${1:-}"
  shift || true
  case "$verb" in
    load) bot_interaction_load "$@" ;;
    "")   echo "usage: bot_interaction_dispatcher.sh load <config-yaml-path>" >&2; exit 2 ;;
    *)    echo "usage: bot_interaction_dispatcher.sh load <config-yaml-path>" >&2; exit 2 ;;
  esac
fi
