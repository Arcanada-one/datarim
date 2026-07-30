#!/usr/bin/env bash
# Locked, bounded persistence for learned-rule proposals and rule records.

LEARNED_RULES_STORE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$LEARNED_RULES_STORE_LIB_DIR/learned-rules-common.sh"

learned_rules_lock() {
    local path_identity fd_identity timeout="${DR_ORCH_LOCK_TIMEOUT_S:-5}"
    [[ "$timeout" =~ ^[1-9][0-9]*$ && "$timeout" -le 30 ]] || return 2
    learned_rules_prepare_state || return
    if [[ ! -e "$LEARNED_RULES_LOCK_FILE" ]]; then
        ( set -o noclobber; umask 077; : >"$LEARNED_RULES_LOCK_FILE" ) 2>/dev/null || true
    fi
    learned_rules_assert_not_symlink "$LEARNED_RULES_LOCK_FILE" || return
    learned_rules_check_owner_mode "$LEARNED_RULES_LOCK_FILE" 600 file || return
    exec 9>>"$LEARNED_RULES_LOCK_FILE" || return 2
    path_identity=$(portable_identity "$LEARNED_RULES_LOCK_FILE") || { exec 9>&-; return 2; }
    fd_identity=$(portable_identity /dev/fd/9) || { exec 9>&-; return 2; }
    [[ ! -L "$LEARNED_RULES_LOCK_FILE" && -f /dev/fd/9 \
       && "$path_identity" = "$fd_identity" ]] || { exec 9>&-; return 2; }
    flock -w "$timeout" -x 9 || { exec 9>&-; return 2; }
}

learned_rules_unlock() {
    flock -u 9 2>/dev/null || true
    exec 9>&-
}

learned_rules_ensure_key_locked() {
    local key
    if [[ ! -e "$LEARNED_RULES_KEY_FILE" ]]; then
        key=$(learned_rules_random_id) || return
        learned_rules_atomic_write "$LEARNED_RULES_KEY_FILE" "$key" || return
    fi
    learned_rules_check_owner_mode "$LEARNED_RULES_KEY_FILE" 600 file || return
    key=$(learned_rules_read_secure "$LEARNED_RULES_KEY_FILE") || return
    [[ "$key" =~ ^[0-9a-f]{64}$ ]] || {
        learned_rules_error 'invalid capability key'
        return 2
    }
}

learned_rules_capability_for_record_locked() {
    local record=$1 key payload output
    learned_rules_ensure_key_locked || return
    key=$(learned_rules_read_secure "$LEARNED_RULES_KEY_FILE") || return
    payload=$(jq -cS '{nonce,actor,session,space,match,action,action_kind,confidence,
        created_at,expires_at,generation}' <<<"$record") || return 2
    output=$(printf '%s' "$payload" | openssl dgst -sha256 -mac HMAC \
        -macopt "hexkey:$key" 2>/dev/null | awk '{print $NF}') || return 2
    [[ "$output" =~ ^[0-9a-f]{64}$ ]] || return 2
    printf '%s\n' "$output"
}

learned_rules_validate_proposal_record_locked() {
    local record=$1 expected_id=${2:-} expected_hash=${3:-}
    local match action derived derived_hash
    jq -e --argjson ttl "$LEARNED_RULE_PROPOSAL_TTL" '
        def epoch: type=="number" and floor==. and .>=0 and .<=253402300799;
        type=="object" and
        (.proposal_hash|type=="string" and test("^[0-9a-f]{64}$")) and
        (.nonce|type=="string" and test("^[0-9a-f]{64}$")) and
        (.actor|type=="string") and (.session|type=="string") and (.space|type=="string") and
        (.match|type=="string") and (.action|type=="string") and
        .action_kind=="framework_command" and
        (.confidence|type=="number" and .>=0 and .<=1) and
        (.created_at|epoch) and (.expires_at|epoch) and .expires_at==(.created_at+$ttl) and
        (.generation|type=="string" and test("^[0-9a-f]{64}$")) and
        (.status=="pending" or .status=="delivered")' >/dev/null <<<"$record" || return 2
    learned_rules_validate_context "$(jq -r '.actor' <<<"$record")" actor || return
    learned_rules_validate_context "$(jq -r '.session' <<<"$record")" session || return
    learned_rules_validate_context "$(jq -r '.space' <<<"$record")" space || return
    match=$(learned_rules_normalize_match "$(jq -r '.match' <<<"$record")") || return
    [[ "$match" = "$(jq -r '.match' <<<"$record")" ]] || return 2
    action=$(learned_rules_canonical_action "$(jq -r '.action' <<<"$record")") || return
    [[ "$action" = "$(jq -r '.action' <<<"$record")" ]] || return 2
    derived=$(learned_rules_capability_for_record_locked "$record") || return
    derived_hash=$(printf '%s' "$derived" | learned_rules_sha256) || return
    [[ "$derived_hash" = "$(jq -r '.proposal_hash' <<<"$record")" ]] || return 2
    [[ -z "$expected_id" || "$derived" = "$expected_id" ]] || return 2
    [[ -z "$expected_hash" || "$derived_hash" = "$expected_hash" ]] || return 2
}

learned_rules_load_rules_locked() {
    local yaml json
    if [[ ! -e "$LEARNED_RULES_FILE" ]]; then
        printf '{"patterns":[]}\n'
        return 0
    fi
    yaml=$(learned_rules_read_secure "$LEARNED_RULES_FILE") || return
    json=$(printf '%s\n' "$yaml" | yq -o=json '.' 2>/dev/null) || {
        learned_rules_error 'corrupt learned rules state'
        return 2
    }
    jq -e --argjson rule_cap "$LEARNED_RULE_RULE_CAP" '
        def epoch: type=="number" and floor==. and .>=0 and .<=253402300799;
        type == "object" and (.patterns | type == "array") and
        (.patterns | length <= $rule_cap) and
        all(.patterns[];
            (.match | type == "string" and utf8bytelength>=1 and utf8bytelength<=256 and
              (startswith("-")|not) and (test("[[:cntrl:]]")|not) and
              (contains("\t")|not) and (startswith(" ")|not) and (endswith(" ")|not) and
              (contains("  ")|not) and (contains("..")|not) and
              (test("[/\\\\;&|<>$`(){}*?!]|\\[|\\]")|not)) and
            (.action | type == "string" and length>=1 and length<=256 and (test("[[:cntrl:]]")|not)) and
            (.confidence | type == "number" and . >= 0 and . <= 1) and
            (.created_at | epoch) and (.last_validated_at | epoch) and (.expires_at | epoch) and
            .last_validated_at>=.created_at and .last_validated_at<=.expires_at and
            .expires_at==(.created_at + 604800) and
            (.proposal_hash | type == "string" and test("^[0-9a-f]{64}$")) and
            (.generation | type == "string" and test("^[0-9a-f]{64}$"))
        )' >/dev/null <<<"$json" || {
        learned_rules_error 'invalid learned rules schema'
        return 2
    }
    jq -c '.' <<<"$json"
}

learned_rules_current_generation_locked() {
    local rules=$1 match=$2 record
    record=$(jq -cS --arg match "$match" '[.patterns[] | select(.match == $match)][0] // null | if . == null then "absent" else del(.generation) end' <<<"$rules") || return 2
    printf '%s' "$record" | learned_rules_sha256
}

learned_rules_trusted_actions() {
    local file json
    for file in "${DR_ORCH_RULES_DEFAULT:-}" "${DR_ORCH_RULES_USER:-}"; do
        [[ -n "$file" && -f "$file" && ! -L "$file" ]] || continue
        json=$(yq -o=json '.' "$file" 2>/dev/null) || return 2
        jq -r '.patterns // [] | .[] | .action | select(type == "string")' <<<"$json"
    done | LC_ALL=C sort -u
}

learned_rules_canonical_action() {
    local requested=$1 candidate trusted
    learned_rules_validate_context "$requested" action || return
    trusted=$(learned_rules_trusted_actions) || {
        learned_rules_error 'trusted action registry is invalid'
        return 2
    }
    candidate=$requested
    if [[ "$requested" != /* && "$requested" == dr-* ]]; then
        candidate="/$requested"
    fi
    if grep -Fqx -- "$candidate" <<<"$trusted"; then
        printf '%s\n' "$candidate"
        return 0
    fi
    learned_rules_error 'action is not in the bundled/user trusted registry'
    return 2
}

learned_rules_audit_has_locked() {
    local event=$1 proposal_hash=$2 file found=0 audit_base content
    while IFS= read -r -d '' file; do
        found=1
        learned_rules_assert_not_symlink "$file" || return
        learned_rules_check_owner_mode "$file" 600 file 644 || return
        content=$(learned_rules_read_secure "$file") || return
        [[ -z "$content" ]] || jq -e '.' <<<"$content" >/dev/null 2>&1 || {
            learned_rules_error 'corrupt audit state'
            return 2
        }
        if [[ -n "$content" ]] && jq -e --arg event "$event" --arg hash "$proposal_hash" \
            'select(.event == $event and .proposal_hash == $hash)' <<<"$content" >/dev/null 2>&1; then
            return 0
        fi
    done < <(find "$(dirname -- "$LEARNED_RULES_AUDIT_FILE")" -maxdepth 1 -type f \
        -name 'audit-*.jsonl' -print0 2>/dev/null)
    audit_base=$(basename -- "$LEARNED_RULES_AUDIT_FILE")
    if [[ -e "$LEARNED_RULES_AUDIT_FILE" \
      && ( $found -eq 0 || "$audit_base" != audit-*.jsonl ) ]]; then
        learned_rules_check_owner_mode "$LEARNED_RULES_AUDIT_FILE" 600 file 644 || return
        content=$(learned_rules_read_secure "$LEARNED_RULES_AUDIT_FILE") || return
        [[ -z "$content" ]] \
          || jq -e '.' <<<"$content" >/dev/null 2>&1 \
          || { learned_rules_error 'corrupt audit state'; return 2; }
        [[ -n "$content" ]] && jq -e --arg event "$event" --arg hash "$proposal_hash" \
          'select(.event == $event and .proposal_hash == $hash)' \
          <<<"$content" >/dev/null 2>&1 && return 0
    fi
    return 1
}

learned_rules_audit_once_locked() {
    local event=$1 proposal_hash=$2 now line audit_rc
    if [[ "${DR_ORCH_TEST_AUDIT_FAIL_EVENT:-}" == "$event" ]]; then
        return 2
    fi
    if learned_rules_audit_has_locked "$event" "$proposal_hash"; then
        return 0
    else
        audit_rc=$?
        (( audit_rc == 1 )) || return "$audit_rc"
    fi
    now=$(learned_rules_now) || return
    line=$(jq -cn --arg event "$event" --arg hash "$proposal_hash" --argjson at "$now" \
        '{schema_version:3,event:$event,proposal_hash:$hash,at:$at}') || return 2
    bash "${DR_ORCH_DIR:?}/scripts/audit_sink.sh" emit "$LEARNED_RULES_AUDIT_FILE" "$line" || return 2
    learned_rules_sync_file "$LEARNED_RULES_AUDIT_FILE"
}

learned_rules_dir_stats() {
    local dir=$1 count=0 bytes=0 file size fd path_identity fd_identity
    while IFS= read -r -d '' file; do
        learned_rules_check_owner_mode "$file" 600 file || return
        exec {fd}<"$file" || return 2
        path_identity=$(portable_identity "$file") || { exec {fd}>&-; return 2; }
        fd_identity=$(portable_identity "/dev/fd/$fd") || { exec {fd}>&-; return 2; }
        [[ ! -L "$file" && "$path_identity" = "$fd_identity" ]] \
          || { exec {fd}>&-; return 2; }
        size=$(portable_size "/dev/fd/$fd") || { exec {fd}>&-; return 2; }
        exec {fd}>&-
        count=$((count + 1))
        bytes=$((bytes + size))
    done < <(find "$dir" -maxdepth 1 -type f -name '*.json' -print0)
    printf '%s %s\n' "$count" "$bytes"
}

learned_rules_write_tombstone_locked() {
    local proposal_hash=$1 reason=$2 now=$3 path record count bytes
    path="$LEARNED_RULES_TOMBSTONES_DIR/$proposal_hash.json"
    [[ ! -e "$path" ]] || return 0
    read -r count bytes < <(learned_rules_dir_stats "$LEARNED_RULES_TOMBSTONES_DIR") || return
    (( count < LEARNED_RULE_TOMBSTONE_CAP )) || {
        learned_rules_error 'tombstone record cap reached'
        return 2
    }
    record=$(jq -cn --arg hash "$proposal_hash" --arg reason "$reason" --argjson consumed "$now" '{proposal_hash:$hash,reason:$reason,consumed_at:$consumed}') || return 2
    (( bytes + ${#record} + 1 <= LEARNED_RULE_TOMBSTONE_BYTES_CAP )) || {
        learned_rules_error 'tombstone byte cap reached'
        return 2
    }
    learned_rules_atomic_write "$path" "$record"
}

learned_rules_remove_proposal_locked() {
    local proposal_hash=$1 reason=$2 now=$3
    learned_rules_write_tombstone_locked "$proposal_hash" "$reason" "$now" || return
    rm -f -- "$LEARNED_RULES_PROPOSALS_DIR/$proposal_hash.json" "$LEARNED_RULES_DELIVERY_DIR/$proposal_hash.json"
}

learned_rules_purge_locked() {
    local now=$1 file expires consumed hash rules active record
    while IFS= read -r -d '' file; do
        record=$(learned_rules_read_secure "$file") || return
        expires=$(jq -er '.expires_at | select(type == "number")' <<<"$record") || return 2
        if (( now >= expires )); then
            hash=$(basename "$file" .json)
            learned_rules_remove_proposal_locked "$hash" expired "$now" || return
        fi
    done < <(find "$LEARNED_RULES_PROPOSALS_DIR" -maxdepth 1 -type f -name '*.json' -print0)
    while IFS= read -r -d '' file; do
        record=$(learned_rules_read_secure "$file") || return
        consumed=$(jq -er '.consumed_at | select(type == "number")' <<<"$record") || return 2
        if (( now >= consumed + LEARNED_RULE_LIFETIME )); then
            rm -f -- "$file"
        fi
    done < <(find "$LEARNED_RULES_TOMBSTONES_DIR" -maxdepth 1 -type f -name '*.json' -print0)
    if [[ -e "$LEARNED_RULES_FILE" ]]; then
        rules=$(learned_rules_load_rules_locked) || return
        active=$(jq -c --argjson now "$now" '.patterns = [.patterns[] | select(.expires_at > $now)]' <<<"$rules") || return 2
        if [[ "$active" != "$rules" ]]; then
            learned_rules_atomic_write "$LEARNED_RULES_FILE" "$active" || return
            learned_rules_sync_file "$LEARNED_RULES_FILE"
        fi
    fi
}

learned_rules_create_proposal() {
    local raw_match=$1 requested_action=$2 confidence=$3 actor=$4 session=$5
    local match action now rules generation nonce proposal_id proposal_hash path record space action_kind
    local file old_hash count
    match=$(learned_rules_normalize_match "$raw_match") || return
    action=$(learned_rules_canonical_action "$requested_action") || return
    learned_rules_validate_confidence "$confidence" || return
    learned_rules_validate_context "$actor" actor || return
    learned_rules_validate_context "$session" session || return
    space="${DR_ORCH_SPACE_CONTEXT:-${DATARIM_ACTIVE_SPACE:-$session}}"
    learned_rules_validate_context "$space" space || return
    action_kind=framework_command
    now=$(learned_rules_now) || return
    learned_rules_lock || return
    learned_rules_purge_locked "$now" || { learned_rules_unlock; return 2; }
    rules=$(learned_rules_load_rules_locked) || { learned_rules_unlock; return 2; }
    generation=$(learned_rules_current_generation_locked "$rules" "$match") || { learned_rules_unlock; return 2; }

    while IFS= read -r -d '' file; do
        record=$(learned_rules_read_secure "$file") || { learned_rules_unlock; return 2; }
        if jq -e --arg actor "$actor" --arg session "$session" --arg match "$match" \
            '.actor == $actor and .session == $session and .match == $match' <<<"$record" >/dev/null; then
            old_hash=$(basename "$file" .json)
            learned_rules_remove_proposal_locked "$old_hash" replaced "$now" || { learned_rules_unlock; return 2; }
        fi
    done < <(find "$LEARNED_RULES_PROPOSALS_DIR" -maxdepth 1 -type f -name '*.json' -print0)
    count=$(find "$LEARNED_RULES_PROPOSALS_DIR" -maxdepth 1 -type f -name '*.json' | wc -l)
    (( count < LEARNED_RULE_PROPOSAL_CAP )) || {
        learned_rules_error 'proposal cap reached'
        learned_rules_unlock
        return 2
    }
    nonce=$(learned_rules_random_id) || { learned_rules_unlock; return 2; }
    while IFS= read -r -d '' file; do
        record=$(learned_rules_read_secure "$file") || { learned_rules_unlock; return 2; }
        if jq -e --arg nonce "$nonce" '.nonce == $nonce' <<<"$record" >/dev/null 2>&1; then
            learned_rules_error 'capability entropy reuse detected'
            learned_rules_unlock
            return 2
        fi
    done < <(find "$LEARNED_RULES_PROPOSALS_DIR" -maxdepth 1 -type f -name '*.json' -print0)
    record=$(jq -cn \
        --arg nonce "$nonce" --arg actor "$actor" --arg session "$session" \
        --arg match "$match" --arg action "$action" --arg confidence "$confidence" \
        --arg space "$space" --arg action_kind "$action_kind" \
        --arg generation "$generation" --argjson created "$now" \
        --argjson expires "$((now + LEARNED_RULE_PROPOSAL_TTL))" \
        '{nonce:$nonce,actor:$actor,session:$session,space:$space,
          match:$match,action:$action,action_kind:$action_kind,confidence:($confidence|tonumber),
          created_at:$created,expires_at:$expires,generation:$generation,status:"pending"}') || {
        learned_rules_unlock
        return 2
    }
    proposal_id=$(learned_rules_capability_for_record_locked "$record") || { learned_rules_unlock; return 2; }
    proposal_hash=$(printf '%s' "$proposal_id" | learned_rules_sha256) || { learned_rules_unlock; return 2; }
    record=$(jq -c --arg hash "$proposal_hash" '.proposal_hash=$hash' <<<"$record") \
      || { learned_rules_unlock; return 2; }
    learned_rules_validate_proposal_record_locked "$record" "$proposal_id" "$proposal_hash" \
      || { learned_rules_unlock; return 2; }
    path="$LEARNED_RULES_PROPOSALS_DIR/$proposal_hash.json"
    [[ ! -e "$path" ]] || { learned_rules_unlock; return 2; }
    learned_rules_atomic_write "$path" "$record" || { learned_rules_unlock; return 2; }
    learned_rules_unlock
    printf '%s\n' "$proposal_id"
    if [[ ${DR_ORCH_TEST_CRASH_POINT:-} = after_proposal_persist ]]; then
        return 75
    fi
}

learned_rules_enqueue_locked() {
    local proposal_id=$1 proposal_hash path record event event_path event_record count bytes
    [[ "$proposal_id" =~ ^[0-9a-f]{64}$ ]] || return 2
    proposal_hash=$(printf '%s' "$proposal_id" | learned_rules_sha256) || return
    path="$LEARNED_RULES_PROPOSALS_DIR/$proposal_hash.json"
    [[ -f "$path" && ! -L "$path" ]] || return 2
    learned_rules_check_owner_mode "$path" 600 file || return
    record=$(learned_rules_read_secure "$path") || return
    learned_rules_validate_proposal_record_locked "$record" "$proposal_id" "$proposal_hash" || return
    event_path="$LEARNED_RULES_DELIVERY_DIR/$proposal_hash.json"
    [[ ! -L "$event_path" ]] || return 2
    if [[ -e "$event_path" ]]; then
        learned_rules_check_owner_mode "$event_path" 600 file || return
        event_record=$(learned_rules_read_secure "$event_path") || return
        jq -e --arg id "$proposal_id" '.proposal_id == $id' <<<"$event_record" >/dev/null || return 2
        return 0
    fi
    read -r count bytes < <(learned_rules_dir_stats "$LEARNED_RULES_DELIVERY_DIR") || return
    (( count < LEARNED_RULE_QUEUE_CAP )) || return 2
    event=$(jq -cn --arg id "$proposal_id" --argjson expires "$(jq -r '.expires_at' <<<"$record")" \
        --arg prompt 'Save as rule? [Y/N]' \
        '{proposal_id:$id,expires_at:$expires,prompt:$prompt}') || return 2
    (( bytes + ${#event} + 1 <= LEARNED_RULE_QUEUE_BYTES_CAP )) || return 2
    learned_rules_atomic_write "$event_path" "$event"
}

learned_rules_enqueue() {
    local proposal_id=$1 rc
    learned_rules_lock || return
    learned_rules_enqueue_locked "$proposal_id"
    rc=$?
    learned_rules_unlock
    return "$rc"
}

learned_rules_mark_delivered() {
    local proposal_id=$1 proposal_hash path record updated rc=0
    [[ "$proposal_id" =~ ^[0-9a-f]{64}$ ]] || return 2
    proposal_hash=$(printf '%s' "$proposal_id" | learned_rules_sha256) || return
    learned_rules_lock || return
    path="$LEARNED_RULES_PROPOSALS_DIR/$proposal_hash.json"
    if [[ ! -f "$path" || -L "$path" || ! -f "$LEARNED_RULES_DELIVERY_DIR/$proposal_hash.json" ]]; then
        rc=2
    else
        record=$(learned_rules_read_secure "$path") || rc=2
        if (( rc == 0 )); then
            learned_rules_validate_proposal_record_locked "$record" "$proposal_id" "$proposal_hash" || rc=2
        fi
        if (( rc == 0 )); then
            updated=$(jq -c '.status = "delivered"' <<<"$record") || rc=2
        fi
        if (( rc == 0 )); then
            learned_rules_atomic_write "$path" "$updated" || rc=2
        fi
    fi
    learned_rules_unlock
    return "$rc"
}

learned_rules_finalize_locked() {
    local proposal_hash=$1 reason=$2 now=$3
    learned_rules_remove_proposal_locked "$proposal_hash" "$reason" "$now"
}

learned_rules_consume() {
    local proposal_id=$1 answer=$2 actor=$3 session=$4
    local proposal_hash path record now expires status match action expected rules actual existing
    local new_rules base generation rc=0 current_space
    [[ "$proposal_id" =~ ^[0-9a-f]{64}$ ]] || return 2
    [[ "$answer" = Y || "$answer" = N ]] || return 2
    learned_rules_validate_context "$actor" actor || return
    learned_rules_validate_context "$session" session || return
    proposal_hash=$(printf '%s' "$proposal_id" | learned_rules_sha256) || return
    now=$(learned_rules_now) || return
    learned_rules_lock || return
    path="$LEARNED_RULES_PROPOSALS_DIR/$proposal_hash.json"
    if [[ ! -f "$path" || -L "$path" ]]; then
        learned_rules_unlock
        return 3
    fi
    learned_rules_check_owner_mode "$path" 600 file || { learned_rules_unlock; return 2; }
    record=$(learned_rules_read_secure "$path") || {
        learned_rules_unlock
        return 2
    }
    learned_rules_validate_proposal_record_locked "$record" "$proposal_id" "$proposal_hash" || {
        learned_rules_unlock
        return 2
    }
    current_space="${DR_ORCH_SPACE_CONTEXT:-${DATARIM_ACTIVE_SPACE:-$session}}"
    [[ $(jq -r '.actor' <<<"$record") = "$actor" && $(jq -r '.session' <<<"$record") = "$session" \
       && $(jq -r '.space' <<<"$record") = "$current_space" ]] || {
        learned_rules_unlock
        return 3
    }
    expires=$(jq -r '.expires_at' <<<"$record")
    (( now < expires )) || { learned_rules_unlock; return 3; }
    status=$(jq -r '.status' <<<"$record")
    [[ "$status" = delivered ]] || { learned_rules_unlock; return 3; }
    if [[ "$answer" = N ]]; then
        learned_rules_finalize_locked "$proposal_hash" declined "$now" || rc=2
        learned_rules_unlock
        return "$rc"
    fi
    match=$(jq -r '.match' <<<"$record")
    action=$(learned_rules_canonical_action "$(jq -r '.action' <<<"$record")") || {
        learned_rules_unlock
        return 2
    }
    [[ "$action" = "$(jq -r '.action' <<<"$record")" ]] || { learned_rules_unlock; return 2; }
    rules=$(learned_rules_load_rules_locked) || { learned_rules_unlock; return 2; }
    if jq -e --arg hash "$proposal_hash" '.patterns[]? | select(.proposal_hash == $hash)' >/dev/null <<<"$rules"; then
        learned_rules_audit_once_locked learned_rule_commit "$proposal_hash" || { learned_rules_unlock; return 2; }
        learned_rules_finalize_locked "$proposal_hash" accepted "$now" || rc=2
        learned_rules_unlock
        return "$rc"
    fi
    expected=$(jq -r '.generation' <<<"$record")
    actual=$(learned_rules_current_generation_locked "$rules" "$match") || { learned_rules_unlock; return 2; }
    [[ "$expected" = "$actual" ]] || { learned_rules_unlock; return 3; }
    existing=$(jq -c --arg match "$match" '[.patterns[] | select(.match == $match)][0] // null' <<<"$rules") || {
        learned_rules_unlock
        return 2
    }
    if [[ "$existing" != null ]] && (( now < $(jq -r '.expires_at' <<<"$existing") )); then
        base=$(jq -c --argjson now "$now" --arg hash "$proposal_hash" \
            '.last_validated_at=$now | .proposal_hash=$hash | del(.generation)' <<<"$existing") || {
            learned_rules_unlock
            return 2
        }
    else
        base=$(jq -cn --arg match "$match" --arg action "$action" \
            --argjson confidence "$(jq -r '.confidence' <<<"$record")" --argjson now "$now" \
            --argjson expiry "$((now + LEARNED_RULE_LIFETIME))" --arg hash "$proposal_hash" \
            '{match:$match,action:$action,confidence:$confidence,created_at:$now,last_validated_at:$now,expires_at:$expiry,proposal_hash:$hash}') || {
            learned_rules_unlock
            return 2
        }
    fi
    generation=$(printf '%s' "$(jq -cS '.' <<<"$base")" | learned_rules_sha256) || { learned_rules_unlock; return 2; }
    base=$(jq -c --arg generation "$generation" '.generation=$generation' <<<"$base") || { learned_rules_unlock; return 2; }
    new_rules=$(jq -c --arg match "$match" --argjson rule "$base" \
        '.patterns = ([.patterns[] | select(.match != $match)] + [$rule])' <<<"$rules") || {
        learned_rules_unlock
        return 2
    }
    jq -e --argjson rule_cap "$LEARNED_RULE_RULE_CAP" '.patterns | length <= $rule_cap' >/dev/null <<<"$new_rules" || { learned_rules_unlock; return 2; }
    learned_rules_audit_once_locked learned_rule_prepare "$proposal_hash" || { learned_rules_unlock; return 2; }
    if [[ ${DR_ORCH_TEST_CRASH_POINT:-} = before_rules_rename ]]; then
        learned_rules_unlock
        return 75
    fi
    learned_rules_atomic_write "$LEARNED_RULES_FILE" "$new_rules" || { learned_rules_unlock; return 2; }
    learned_rules_sync_file "$LEARNED_RULES_FILE"
    if [[ ${DR_ORCH_TEST_CRASH_POINT:-} = after_rules_rename ]]; then
        learned_rules_unlock
        return 75
    fi
    learned_rules_audit_once_locked learned_rule_commit "$proposal_hash" || { learned_rules_unlock; return 2; }
    learned_rules_finalize_locked "$proposal_hash" accepted "$now" || rc=2
    learned_rules_unlock
    return "$rc"
}

learned_rules_store_maintenance() {
    local now file record proposal_id proposal_hash updated rc=0
    now=$(learned_rules_now) || return
    learned_rules_lock || return
    learned_rules_purge_locked "$now" || { learned_rules_unlock; return 2; }
    while IFS= read -r -d '' file; do
        record=$(learned_rules_read_secure "$file") || { rc=2; break; }
        proposal_hash=$(basename -- "$file" .json)
        proposal_id=$(learned_rules_capability_for_record_locked "$record") || { rc=2; break; }
        learned_rules_validate_proposal_record_locked "$record" "$proposal_id" "$proposal_hash" \
          || { rc=2; break; }
        if [[ -e "$LEARNED_RULES_FILE" ]] \
          && jq -e --arg hash "$(jq -r '.proposal_hash' <<<"$record")" \
            '.patterns[]? | select(.proposal_hash==$hash)' \
            <<<"$(learned_rules_load_rules_locked)" >/dev/null 2>&1; then
            learned_rules_audit_once_locked learned_rule_commit "$(jq -r '.proposal_hash' <<<"$record")" || { rc=2; break; }
            learned_rules_finalize_locked "$(jq -r '.proposal_hash' <<<"$record")" accepted "$now" || { rc=2; break; }
            continue
        fi
        if [[ $(jq -r '.status // "invalid"' <<<"$record") = pending ]]; then
            learned_rules_enqueue_locked "$proposal_id" || { rc=2; break; }
            updated=$(jq -c '.status="delivered"' <<<"$record") || { rc=2; break; }
            learned_rules_atomic_write "$file" "$updated" || { rc=2; break; }
        fi
    done < <(find "$LEARNED_RULES_PROPOSALS_DIR" -maxdepth 1 -type f -name '*.json' -print0)
    learned_rules_unlock
    return "$rc"
}
