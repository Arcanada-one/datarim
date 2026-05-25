#!/usr/bin/env bash
# exit-codes.sh — canonical exit code registry для Datarim CLI.
# Source: creative-TUNE-0268-architecture-subcommand-output-shape.md § IP-3
#         (foundation; patched 2026-05-24 после reconciliation с Phase 3 baseline).
#
# 0/1/2          — POSIX
# 17,18,21-27    — Phase 3 baseline (immutable as committed code в `cli/datarim` entry)
# 19,20,28-34    — new in Phase 1/2/4/5 per TUNE-0268
#
# Sourced by lib/output.sh и каждым Phase 1+ subcommand.
# Bash 3.2-compatible (case statements; no associative arrays — matches Phase 3 baseline).

# Guard against double-source.
[[ -n "${_EXIT_CODES_LOADED:-}" ]] && return 0
_EXIT_CODES_LOADED=1

# Resolve symbolic name → numeric exit code.
# Usage: exit "$(exit_code_of NOT_FOUND)"
exit_code_of() {
    local name="${1:?exit_code_of: name required}"
    case "$name" in
        SUCCESS)                          echo 0 ;;
        CATCHALL)                         echo 1 ;;
        MISUSE)                           echo 2 ;;
        HALT_ENGAGED)                     echo 17 ;;
        NOTIFIER_DOWN)                    echo 18 ;;
        TMUX_NOTIFIER_OFF)                echo 19 ;;
        AAL_LOCKED_KEY)                   echo 20 ;;
        HTTP_CONNECT_FAIL)                echo 21 ;;
        AGENT_ID_INVALID)                 echo 22 ;;
        ACCEPTED_RISK_EXPIRED)            echo 23 ;;
        HTTP_4XX)                         echo 24 ;;
        HTTP_5XX)                         echo 25 ;;
        NON_IDEMPOTENT_ON_SYNC)           echo 26 ;;
        ASYNC_TIMEOUT)                    echo 27 ;;
        ID_COLLISION_DETECTED)            echo 28 ;;
        COLLISION_TIMEOUT)                echo 29 ;;
        STATE_MISMATCH)                   echo 30 ;;
        NOT_FOUND)                        echo 31 ;;
        INVALID_COMMAND)                  echo 32 ;;
        DEPENDENCY_MISSING)               echo 33 ;;
        WORKSPACE_DISCIPLINE_VIOLATION)   echo 34 ;;
        *)
            echo "ERR: unknown exit code name '$name'" >&2
            return 1
            ;;
    esac
}

# Reverse: numeric code → symbolic name.
# Usage: name=$(exit_name_of 20)  # → "AAL_LOCKED_KEY"
exit_name_of() {
    local code="${1:?exit_name_of: numeric code required}"
    case "$code" in
        0)  echo SUCCESS ;;
        1)  echo CATCHALL ;;
        2)  echo MISUSE ;;
        17) echo HALT_ENGAGED ;;
        18) echo NOTIFIER_DOWN ;;
        19) echo TMUX_NOTIFIER_OFF ;;
        20) echo AAL_LOCKED_KEY ;;
        21) echo HTTP_CONNECT_FAIL ;;
        22) echo AGENT_ID_INVALID ;;
        23) echo ACCEPTED_RISK_EXPIRED ;;
        24) echo HTTP_4XX ;;
        25) echo HTTP_5XX ;;
        26) echo NON_IDEMPOTENT_ON_SYNC ;;
        27) echo ASYNC_TIMEOUT ;;
        28) echo ID_COLLISION_DETECTED ;;
        29) echo COLLISION_TIMEOUT ;;
        30) echo STATE_MISMATCH ;;
        31) echo NOT_FOUND ;;
        32) echo INVALID_COMMAND ;;
        33) echo DEPENDENCY_MISSING ;;
        34) echo WORKSPACE_DISCIPLINE_VIOLATION ;;
        *)
            echo "ERR: unknown exit code '$code'" >&2
            return 1
            ;;
    esac
}
