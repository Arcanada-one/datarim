#!/usr/bin/env bash
# Shared validation and persistence primitives for learned-rule lifecycle state.

readonly LEARNED_RULE_PROPOSAL_TTL=900
readonly LEARNED_RULE_LIFETIME=604800
readonly LEARNED_RULE_REVALIDATE_AFTER=86400
readonly LEARNED_RULE_PROPOSAL_CAP=128
readonly LEARNED_RULE_RULE_CAP=256
readonly LEARNED_RULE_TOMBSTONE_CAP=512
readonly LEARNED_RULE_TOMBSTONE_BYTES_CAP=1048576
readonly LEARNED_RULE_QUEUE_CAP=128
readonly LEARNED_RULE_QUEUE_BYTES_CAP=65536
export LEARNED_RULE_PROPOSAL_TTL LEARNED_RULE_LIFETIME LEARNED_RULE_REVALIDATE_AFTER
export LEARNED_RULE_PROPOSAL_CAP LEARNED_RULE_RULE_CAP LEARNED_RULE_TOMBSTONE_CAP
export LEARNED_RULE_TOMBSTONE_BYTES_CAP LEARNED_RULE_QUEUE_CAP LEARNED_RULE_QUEUE_BYTES_CAP

LEARNED_RULES_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=portable-stat.sh
source "$LEARNED_RULES_COMMON_LIB_DIR/portable-stat.sh"

learned_rules_error() {
    printf 'learned-rules: %s\n' "$*" >&2
}

learned_rules_now() {
    local now=${DR_ORCH_NOW_EPOCH:-}
    if [[ -z "$now" ]]; then
        now=$(date +%s)
    fi
    [[ "$now" =~ ^[0-9]+$ ]] || {
        learned_rules_error 'invalid current time'
        return 2
    }
    printf '%s\n' "$now"
}

learned_rules_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        learned_rules_error 'SHA-256 implementation unavailable'
        return 2
    fi
}

learned_rules_random_id() {
    local value=''
    if [[ "${DR_ORCH_TEST_ENTROPY_FAIL:-0}" == 1 ]]; then
        learned_rules_error 'cryptographic entropy source unavailable'
        return 2
    elif [[ -n "${DR_ORCH_TEST_ENTROPY_HEX:-}" ]]; then
        value="$DR_ORCH_TEST_ENTROPY_HEX"
    elif command -v openssl >/dev/null 2>&1; then
        value=$(openssl rand -hex 32) || value=''
    elif [[ -r /dev/urandom ]] && command -v od >/dev/null 2>&1; then
        value=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n') || value=''
    fi
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] || {
        learned_rules_error 'cryptographic entropy source unavailable'
        return 2
    }
    printf '%s\n' "$value"
}

learned_rules_validate_utf8() {
    local value=${1-}
    printf '%s' "$value" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || {
        learned_rules_error 'invalid UTF-8'
        return 2
    }
}

learned_rules_has_forbidden_controls() {
    local value=${1-} allow_tab=${2:-0}
    printf '%s' "$value" | iconv -f UTF-8 -t UTF-32LE 2>/dev/null | od -An -tu4 | \
        awk -v allow_tab="$allow_tab" '
            { for (i = 1; i <= NF; i++) {
                cp = $i
                if ((cp <= 31 && !(allow_tab == 1 && cp == 9)) || (cp >= 127 && cp <= 159)) { bad = 1; exit }
            }}
            END { exit bad }
        '
}

learned_rules_validate_context() {
    local value=${1-} label=${2:-context}
    learned_rules_validate_utf8 "$value" || return
    [[ -n "$value" && ${#value} -le 256 ]] || {
        learned_rules_error "invalid $label"
        return 2
    }
    if ! learned_rules_has_forbidden_controls "$value" 0; then
        learned_rules_error "invalid $label"
        return 2
    fi
}

learned_rules_normalize_match() {
    local raw=${1-} normalized bytes
    learned_rules_validate_utf8 "$raw" || return
    if ! learned_rules_has_forbidden_controls "$raw" 1; then
        learned_rules_error 'control character in match'
        return 2
    fi
    normalized=$(printf '%s' "$raw" | sed $'s/^[ \t]*//; s/[ \t]*$//; s/[ \t][ \t]*/ /g')
    bytes=$(LC_ALL=C printf '%s' "$normalized" | wc -c | tr -d ' ')
    [[ "$bytes" -ge 1 && "$bytes" -le 256 ]] || {
        learned_rules_error 'match must be 1..256 bytes'
        return 2
    }
    [[ "$normalized" != -* ]] || {
        learned_rules_error 'leading option form is forbidden'
        return 2
    }
    case "$normalized" in
        *'/'*|*\\*|*'..'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'$'*|*'`'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'*'*|*'?'*|*'!'*)
            learned_rules_error 'path or shell syntax is forbidden in match'
            return 2
            ;;
    esac
    printf '%s\n' "$normalized"
}

learned_rules_validate_confidence() {
    local value=${1-}
    jq -en --arg value "$value" '($value | tonumber?) as $n | $n != null and $n >= 0 and $n <= 1' >/dev/null || {
        learned_rules_error 'confidence must be numeric in [0,1]'
        return 2
    }
}

learned_rules_init_paths() {
    LEARNED_RULES_STATE_DIR=${DR_ORCH_STATE_DIR:-${STATE_DIR:-${HOME}/.local/share/dr-orchestrate/state}}
    LEARNED_RULES_FILE=${DR_ORCH_RULES_LEARNED:-"$LEARNED_RULES_STATE_DIR/learned-rules.yaml"}
    LEARNED_RULES_PROPOSALS_DIR=${DR_ORCH_PROPOSALS_DIR:-"$LEARNED_RULES_STATE_DIR/learned-rule-proposals"}
    LEARNED_RULES_TOMBSTONES_DIR=${DR_ORCH_TOMBSTONES_DIR:-"$LEARNED_RULES_STATE_DIR/learned-rule-tombstones"}
    LEARNED_RULES_DELIVERY_DIR=${DR_ORCH_DELIVERY_DIR:-"$LEARNED_RULES_STATE_DIR/learned-rule-delivery"}
    LEARNED_RULES_AUDIT_DIR=${AUDIT_DIR:-${HOME}/.local/share/datarim-orchestrate}
    LEARNED_RULES_AUDIT_FILE=${DR_ORCH_LEARNED_AUDIT:-${DR_ORCH_AUDIT_FILE:-"$LEARNED_RULES_AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"}}
    LEARNED_RULES_LOCK_FILE="$LEARNED_RULES_STATE_DIR/.learned-rules.lock"
    LEARNED_RULES_KEY_FILE="$LEARNED_RULES_STATE_DIR/.learned-rules-capability-key"
    export LEARNED_RULES_STATE_DIR LEARNED_RULES_FILE LEARNED_RULES_PROPOSALS_DIR
    export LEARNED_RULES_TOMBSTONES_DIR LEARNED_RULES_DELIVERY_DIR
    export LEARNED_RULES_AUDIT_DIR LEARNED_RULES_AUDIT_FILE
    export LEARNED_RULES_LOCK_FILE LEARNED_RULES_KEY_FILE
}

learned_rules_assert_contained() {
    local path=$1 root_abs path_abs
    root_abs=$(realpath -m -- "$LEARNED_RULES_STATE_DIR") || return 2
    path_abs=$(realpath -m -- "$path") || return 2
    [[ "$path_abs" == "$root_abs" || "$path_abs" == "$root_abs/"* ]] || {
        learned_rules_error "state path escapes configured root: $path"
        return 2
    }
}

learned_rules_assert_not_symlink() {
    local path=$1 cursor
    [[ "$path" == /* ]] || path="$PWD/$path"
    cursor=$path
    while :; do
        [[ ! -L "$cursor" ]] || {
            learned_rules_error "symlink state path rejected: $cursor"
            return 2
        }
        [[ "$cursor" != / ]] || break
        cursor=$(dirname -- "$cursor")
    done
}

learned_rules_check_owner_mode() {
    local path=$1 expected=$2 kind=${3:-file} legacy_mode=${4:-} mode owner
    [[ -e "$path" ]] || return 0
    [[ ! -L "$path" ]] || return 2
    owner=$(portable_uid "$path") || return 2
    mode=$(portable_mode "$path") || return 2
    [[ "$owner" = "$(id -u)" ]] || {
        learned_rules_error "unsafe owner or mode for $path"
        return 2
    }
    if [[ "$kind" = dir ]]; then
        [[ -d "$path" ]] || return 2
    else
        [[ -f "$path" ]] || return 2
    fi
    if [[ "$mode" = "$legacy_mode" ]]; then
        chmod "0$expected" "$path" || return 2
        mode=$(portable_mode "$path") || return 2
    fi
    [[ "$mode" = "$expected" ]] || {
        learned_rules_error "unsafe owner or mode for $path"
        return 2
    }
}

learned_rules_read_secure() {
    local path=$1 fd path_identity fd_identity
    learned_rules_assert_not_symlink "$path" || return
    learned_rules_check_owner_mode "$path" 600 file || return
    exec {fd}<"$path" || return 2
    path_identity=$(portable_identity "$path") || { exec {fd}>&-; return 2; }
    fd_identity=$(portable_identity "/dev/fd/$fd") || { exec {fd}>&-; return 2; }
    [[ ! -L "$path" && -f "/dev/fd/$fd" && "$path_identity" = "$fd_identity" ]] || {
        exec {fd}>&-
        learned_rules_error "state path changed during open: $path"
        return 2
    }
    cat <&"$fd"
    exec {fd}>&-
}

learned_rules_validate_state_directory() {
    local dir=$1 entry
    while IFS= read -r -d '' entry; do
        [[ ! -L "$entry" && -f "$entry" && "$entry" == *.json ]] || {
            learned_rules_error "invalid state directory entry: $entry"
            return 2
        }
        learned_rules_check_owner_mode "$entry" 600 file || return
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

learned_rules_prepare_state() {
    local path
    learned_rules_init_paths
    umask 077
    for path in "$LEARNED_RULES_FILE" "$LEARNED_RULES_PROPOSALS_DIR" \
        "$LEARNED_RULES_TOMBSTONES_DIR" "$LEARNED_RULES_DELIVERY_DIR" \
        "$LEARNED_RULES_LOCK_FILE" "$LEARNED_RULES_KEY_FILE"; do
        learned_rules_assert_contained "$path" || return
    done
    learned_rules_assert_not_symlink "$LEARNED_RULES_STATE_DIR" || return
    if [[ ! -e "$LEARNED_RULES_STATE_DIR" ]]; then
        mkdir -p -- "$LEARNED_RULES_STATE_DIR" || return 2
        chmod 0700 "$LEARNED_RULES_STATE_DIR" || return 2
    fi
    learned_rules_check_owner_mode "$LEARNED_RULES_STATE_DIR" 700 dir || return
    for path in "$LEARNED_RULES_PROPOSALS_DIR" "$LEARNED_RULES_TOMBSTONES_DIR" "$LEARNED_RULES_DELIVERY_DIR"; do
        learned_rules_assert_not_symlink "$path" || return
        if [[ ! -e "$path" ]]; then
            mkdir -m 0700 -- "$path" || return 2
        fi
        learned_rules_check_owner_mode "$path" 700 dir || return
        learned_rules_validate_state_directory "$path" || return
    done
    for path in "$LEARNED_RULES_FILE" "$LEARNED_RULES_LOCK_FILE" "$LEARNED_RULES_KEY_FILE"; do
        learned_rules_assert_not_symlink "$path" || return
        learned_rules_check_owner_mode "$path" 600 file || return
    done
    learned_rules_assert_not_symlink "$LEARNED_RULES_AUDIT_FILE" || return
    learned_rules_check_owner_mode "$LEARNED_RULES_AUDIT_FILE" 600 file 644 || return
}

learned_rules_atomic_write() {
    local path=$1 payload=$2 tmp
    learned_rules_assert_contained "$path" || return
    if [[ -n "${DR_ORCH_TEST_ATOMIC_FAIL_BASENAME:-}" \
      && "$(basename -- "$path")" == "$DR_ORCH_TEST_ATOMIC_FAIL_BASENAME" ]]; then
        return 2
    fi
    learned_rules_assert_not_symlink "$path" || return
    if [[ -e "$path" ]]; then
        learned_rules_check_owner_mode "$path" 600 file || return
    fi
    tmp=$(mktemp "$(dirname -- "$path")/.learned-rules.tmp.XXXXXX") || return 2
    chmod 0600 "$tmp" || { rm -f -- "$tmp"; return 2; }
    if ! printf '%s\n' "$payload" > "$tmp"; then
        rm -f -- "$tmp"
        return 2
    fi
    mv -f -- "$tmp" "$path" || { rm -f -- "$tmp"; return 2; }
    chmod 0600 "$path"
}

learned_rules_sync_file() {
    local path=$1
    if sync -f "$path" >/dev/null 2>&1; then
        return 0
    fi
    sync >/dev/null 2>&1 || true
}
