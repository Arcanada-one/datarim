#!/usr/bin/env bash
#
# resolve-peer-provider.sh — 6-step resolution chain for /dr-verify Layer 2
# peer-review provider. Replaces hardcoded `--peer-provider deepseek` default
# with declarative chain producing zero-flag UX.
#
# Resolution chain (D-1):
#   1. --peer-provider CLI flag         → cli_flag
#   2. --project-config <yaml>          → per_project_config
#                                         (caller-supplied; suggested ./datarim/config.yaml)
#   3. --user-config <yaml>             → per_user_config
#                                         (caller-supplied; suggested ~/.config/datarim/config.yaml)
#   4. coworker --profile code default  → coworker_default
#   5. cross-Claude-family subagent     → fallback_subagent (Claude runtime only)
#   6. same-model isolated last resort  → fallback_isolated
#
# Output (stdout, 3 lines):
#   line 1: provider_name      (deepseek | moonshot | openrouter | sonnet | haiku | opus | none)
#   line 2: peer_review_mode   (cross_vendor | cross_claude_family | same_model_isolated)
#   line 3: source_layer       (cli_flag | per_project_config | per_user_config |
#                               coworker_default | fallback_subagent | fallback_isolated)
#
# Exit codes:
#   0 — resolution successful
#   1 — invalid provider value (validation against whitelist failed)
#   2 — cost cap breach (--estimate-cost > $PEER_REVIEW_COST_THRESHOLD; default $0.10)
#
# Stderr: warnings on Codex degraded mode, on per-user/per-project conflict.
#
# See: skills/self-verification.md § Peer Review Provider Resolution
#
# strict-mode rationale: -e omitted intentionally. The chain MUST always emit a
# resolution (or explicit exit 1/2) — under -e an awk parse error would kill the
# whole chain mid-step and skip downstream fallback. Explicit if/[ guards on
# every parser call handle non-zero. -u and pipefail are kept.
set -uo pipefail

PROVIDER_WHITELIST="deepseek moonshot openrouter sonnet haiku opus none"
PEER_REVIEW_COST_THRESHOLD="${PEER_REVIEW_COST_THRESHOLD:-0.10}"

PROJECT_CFG=""
USER_CFG=""
CLI_PROVIDER=""
ESTIMATE_COST=""
NO_CONFIG=0

# --- argparse ----------------------------------------------------------------

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --peer-provider)
            shift
            [ $# -gt 0 ] || { echo "resolve-peer-provider: --peer-provider requires value" >&2; exit 1; }
            CLI_PROVIDER="$1"; shift ;;
        --project-config)
            shift
            [ $# -gt 0 ] || { echo "resolve-peer-provider: --project-config requires value" >&2; exit 1; }
            PROJECT_CFG="$1"; shift ;;
        --user-config)
            shift
            [ $# -gt 0 ] || { echo "resolve-peer-provider: --user-config requires value" >&2; exit 1; }
            USER_CFG="$1"; shift ;;
        --estimate-cost)
            shift
            [ $# -gt 0 ] || { echo "resolve-peer-provider: --estimate-cost requires value" >&2; exit 1; }
            ESTIMATE_COST="$1"; shift ;;
        --no-config)
            NO_CONFIG=1; shift ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            echo "resolve-peer-provider: unknown arg: $1" >&2
            exit 1 ;;
    esac
done

# --- helpers -----------------------------------------------------------------

# is_valid_provider <name> → 0 if whitelisted, 1 otherwise
is_valid_provider() {
    local p="$1"
    local w
    for w in $PROVIDER_WHITELIST; do
        [ "$p" = "$w" ] && return 0
    done
    return 1
}

# infer_mode <provider> → emits cross_vendor|cross_claude_family|same_model_isolated
infer_mode() {
    case "$1" in
        deepseek|moonshot|openrouter) printf 'cross_vendor\n' ;;
        sonnet|haiku)                 printf 'cross_claude_family\n' ;;
        opus|none)                    printf 'same_model_isolated\n' ;;
        *)                            printf 'same_model_isolated\n' ;;
    esac
}

# parse_yaml_provider <config-path> → emits provider value or empty
# Reads `peer_review:` block, extracts `provider:` field. awk token-equality.
parse_yaml_provider() {
    local cfg="$1"
    [ -f "$cfg" ] || return 0
    awk '
        /^peer_review:[[:space:]]*$/ { in_block = 1; next }
        in_block && /^[^[:space:]]/  { in_block = 0 }
        in_block && /^[[:space:]]+provider:[[:space:]]*/ {
            sub(/^[[:space:]]+provider:[[:space:]]*/, "", $0)
            sub(/[[:space:]]*#.*$/, "", $0)
            gsub(/[[:space:]]/, "", $0)
            print $0
            exit
        }
    ' "$cfg"
}

# coworker_default_provider → emits provider for `code` profile, or empty
coworker_default_provider() {
    local cfg="$HOME/.config/coworker/profiles.yaml"
    [ -f "$cfg" ] || return 0
    awk -v p="^code:" '
        /^[a-z]+:/         { cur = $0 }
        cur ~ p && /recommended_provider/ {
            sub(/^[[:space:]]+recommended_provider:[[:space:]]*/, "", $0)
            gsub(/[[:space:]]/, "", $0)
            print $0
            exit
        }
    ' "$cfg"
}

# emit <provider> <source_layer> → prints 3 lines, exits 0
emit() {
    local provider="$1"
    local source_layer="$2"
    if ! is_valid_provider "$provider"; then
        echo "resolve-peer-provider: invalid provider '$provider' (whitelist: $PROVIDER_WHITELIST)" >&2
        exit 1
    fi
    printf '%s\n' "$provider"
    infer_mode "$provider"
    printf '%s\n' "$source_layer"
    exit 0
}

# cost_breach_check — exit 2 if --estimate-cost > threshold
cost_breach_check() {
    [ -z "$ESTIMATE_COST" ] && return 0
    awk -v est="$ESTIMATE_COST" -v thr="$PEER_REVIEW_COST_THRESHOLD" \
        'BEGIN { if (est+0 > thr+0) exit 2; else exit 0 }' || {
        echo "resolve-peer-provider: cost cap breach: estimated $ESTIMATE_COST > threshold $PEER_REVIEW_COST_THRESHOLD" >&2
        exit 2
    }
}

# --- chain -------------------------------------------------------------------

# Step 0. cost-cap probe (precedes all chain logic — fail-fast)
cost_breach_check

# Step 1. CLI flag override
if [ -n "$CLI_PROVIDER" ]; then
    emit "$CLI_PROVIDER" "cli_flag"
fi

# Step 2 + 3 — config files (only when not in --no-config mode)
if [ "$NO_CONFIG" -eq 0 ]; then
    # Step 2. Per-project config wins over per-user (D-5)
    if [ -n "$PROJECT_CFG" ] && [ -f "$PROJECT_CFG" ]; then
        v="$(parse_yaml_provider "$PROJECT_CFG")"
        if [ -n "$v" ]; then
            emit "$v" "per_project_config"
        fi
    fi

    # Step 3. Per-user config
    if [ -n "$USER_CFG" ] && [ -f "$USER_CFG" ]; then
        v="$(parse_yaml_provider "$USER_CFG")"
        if [ -n "$v" ]; then
            emit "$v" "per_user_config"
        fi
    fi
fi

# Step 4. Coworker default (--profile code per D-6)
v="$(coworker_default_provider)"
if [ -n "$v" ] && [ "$v" != "none" ]; then
    emit "$v" "coworker_default"
fi

# Step 5. Cross-Claude-family fallback (Claude runtime only)
if [ -z "${CODEX_RUNTIME:-}" ]; then
    emit "sonnet" "fallback_subagent"
fi

# Step 6. Same-model isolated last resort (Codex degraded mode)
echo "WARN: Codex runtime detected, falling back to same_model_isolated mode" >&2
emit "opus" "fallback_isolated"
