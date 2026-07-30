#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    chmod 700 "$BATS_TEST_TMPDIR"
    export DR_ORCH_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DR_ORCH_RULES_DEFAULT="$BATS_TEST_TMPDIR/default.yaml"
    export DR_ORCH_RULES_USER="$BATS_TEST_TMPDIR/user.yaml"
    export DR_ORCH_RULES_LEARNED="$DR_ORCH_STATE_DIR/learned-rules.yaml"
    export DR_ORCH_LEARNED_AUDIT="$DR_ORCH_STATE_DIR/learned-rule-audit.jsonl"
    export DR_ORCH_NOW_EPOCH=100
    cat > "$DR_ORCH_RULES_DEFAULT" <<'YAML'
patterns:
  - match: /dr-plan
    action: /dr-plan
    confidence: 0.95
  - match: /dr-qa
    action: /dr-qa
    confidence: 0.95
YAML
    printf 'patterns: []\n' > "$DR_ORCH_RULES_USER"
}

lr() {
    bash "$PLUGIN_ROOT/scripts/learned_rules.sh" "$@"
}

backend() {
    bash "$PLUGIN_ROOT/scripts/proposal_backend.sh" "$@"
}

proposal_count() {
    find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -type f -name '*.json' 2>/dev/null | wc -l
}

queue_count() {
    find "$DR_ORCH_STATE_DIR/learned-rule-delivery" -type f -name '*.json' 2>/dev/null | wc -l
}

rule_value() {
    jq -r ".patterns[0].$1" "$DR_ORCH_RULES_LEARNED"
}

@test "normalization is exact and preserves case and UTF-8" {
    run bash -c 'source "$1/scripts/lib/learned-rules-common.sh"; learned_rules_normalize_match "$2"' _ "$PLUGIN_ROOT" $'  Run\t  Ångström  '
    [ "$status" -eq 0 ]
    [ "$output" = "Run Ångström" ]
}

@test "normalization rejects controls, path syntax, metacharacters, leading options, and overlength" {
    for bad in $'bad\nvalue' '../plan' 'run;plan' '--dr-plan' "$(printf 'x%.0s' {1..257})"; do
        run bash -c 'source "$1/scripts/lib/learned-rules-common.sh"; learned_rules_normalize_match "$2"' _ "$PLUGIN_ROOT" "$bad"
        [ "$status" -ne 0 ]
    done
}

@test "proposal is an opaque capability and delivery leaks only callback fields" {
    run lr propose $'  Run\t plan ' dr-plan 0.91 alice s-1
    [ "$status" -eq 0 ]
    id="$output"
    [[ "$id" =~ ^[0-9a-f]{64}$ ]]
    [ "$(proposal_count)" -eq 1 ]
    [ "$(queue_count)" -eq 1 ]
    proposal="$(find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -name '*.json')"
    event="$(find "$DR_ORCH_STATE_DIR/learned-rule-delivery" -name '*.json')"
    run grep -Fq "$id" "$proposal"
    [ "$status" -ne 0 ]
    jq -e --arg id "$id" '.proposal_id == $id and .expires_at == 1000 and .prompt == "Save as rule? [Y/N]" and (keys | sort == ["expires_at","prompt","proposal_id"])' "$event"
    run grep -Fq 'Run plan' "$event"
    [ "$status" -ne 0 ]
    run grep -Fq '/dr-plan' "$event"
    [ "$status" -ne 0 ]
    [ "$(stat -c %a "$DR_ORCH_STATE_DIR")" = 700 ]
    [ "$(stat -c %a "$proposal")" = 600 ]
    [ "$(stat -c %a "$event")" = 600 ]
}

@test "pending proposal is not consumable and maintenance completes delivery exactly once" {
    export DR_ORCH_TEST_CRASH_POINT=after_proposal_persist
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -eq 75 ]
    id="$(printf '%s\n' "$output" | tail -n1)"
    unset DR_ORCH_TEST_CRASH_POINT
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]
    run lr maintenance
    [ "$status" -eq 0 ]
    run lr maintenance
    [ "$status" -eq 0 ]
    [ "$(queue_count)" -eq 1 ]
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
}

@test "Y callback persists a bounded immutable-expiry learned rule" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
    [ "$(rule_value match)" = 'run plan' ]
    [ "$(rule_value action)" = '/dr-plan' ]
    [ "$(rule_value created_at)" = 100 ]
    [ "$(rule_value last_validated_at)" = 100 ]
    [ "$(rule_value expires_at)" = 604900 ]
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 1 ]
}

@test "wrong actor, wrong session, malformed id, and expiry equality leave rules byte-identical" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    mkdir -p "$DR_ORCH_STATE_DIR"
    chmod 700 "$DR_ORCH_STATE_DIR"
    printf '{"patterns":[]}\n' > "$DR_ORCH_RULES_LEARNED"
    before="$(sha256sum "$DR_ORCH_RULES_LEARNED")"
    run lr consume_callback "$id" Y mallory s-1
    [ "$status" -ne 0 ]
    run lr consume_callback "$id" Y alice wrong
    [ "$status" -ne 0 ]
    run lr consume_callback 'not-a-capability' Y alice s-1
    [ "$status" -ne 0 ]
    export DR_ORCH_NOW_EPOCH=1000
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$DR_ORCH_RULES_LEARNED")" = "$before" ]
}

@test "N tombstones once and never mutates rules" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    run lr consume_callback "$id" N alice s-1
    [ "$status" -eq 0 ]
    [ ! -e "$DR_ORCH_RULES_LEARNED" ]
    [ "$(find "$DR_ORCH_STATE_DIR/learned-rule-tombstones" -name '*.json' | wc -l)" -eq 1 ]
    run lr consume_callback "$id" N alice s-1
    [ "$status" -ne 0 ]
}

@test "learned actions never extend the trusted action registry" {
    mkdir -p "$DR_ORCH_STATE_DIR"
    chmod 700 "$DR_ORCH_STATE_DIR"
    cat > "$DR_ORCH_RULES_LEARNED" <<'JSON'
{"patterns":[{"match":"poison","action":"/dr-evil","confidence":1,"created_at":1,"last_validated_at":1,"expires_at":604801,"proposal_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
JSON
    chmod 600 "$DR_ORCH_RULES_LEARNED"
    run lr propose 'do evil' /dr-evil 0.9 alice s-1
    [ "$status" -ne 0 ]
    run lr propose 'run qa' dr-qa 0.9 alice s-1
    [ "$status" -eq 0 ]
}

@test "same actor session and intent replaces the older outstanding proposal" {
    first="$(lr propose 'run plan' /dr-plan 0.8 alice s-1)"
    second="$(lr propose ' run   plan ' /dr-plan 0.9 alice s-1)"
    [ "$first" != "$second" ]
    [ "$(proposal_count)" -eq 1 ]
    run lr consume_callback "$first" Y alice s-1
    [ "$status" -ne 0 ]
    run lr consume_callback "$second" Y alice s-1
    [ "$status" -eq 0 ]
}

@test "delivery backend enqueue is idempotent by capability hash" {
    export DR_ORCH_TEST_CRASH_POINT=after_proposal_persist
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -eq 75 ]
    id="$(printf '%s\n' "$output" | tail -n1)"
    unset DR_ORCH_TEST_CRASH_POINT
    run backend emit "$id"
    [ "$status" -eq 0 ]
    run backend emit "$id"
    [ "$status" -eq 0 ]
    [ "$(queue_count)" -eq 1 ]
}

@test "prepare is durable before rename and pre-rename crash is retryable" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    export DR_ORCH_TEST_CRASH_POINT=before_rules_rename
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 75 ]
    [ ! -e "$DR_ORCH_RULES_LEARNED" ]
    [ "$(jq -r 'select(.event == "learned_rule_prepare") | .proposal_hash' "$DR_ORCH_LEARNED_AUDIT" | wc -l)" -eq 1 ]
    unset DR_ORCH_TEST_CRASH_POINT
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
    [ "$(jq -r 'select(.event == "learned_rule_commit") | .proposal_hash' "$DR_ORCH_LEARNED_AUDIT" | wc -l)" -eq 1 ]
}

@test "post-rename crash reconciles one commit without duplicate rule" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    export DR_ORCH_TEST_CRASH_POINT=after_rules_rename
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 75 ]
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 1 ]
    unset DR_ORCH_TEST_CRASH_POINT
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 1 ]
    [ "$(jq -r 'select(.event == "learned_rule_commit") | .proposal_hash' "$DR_ORCH_LEARNED_AUDIT" | wc -l)" -eq 1 ]
}

@test "renewal changes validation time but not immutable creation or expiry" {
    first="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    lr consume_callback "$first" Y alice s-1
    export DR_ORCH_NOW_EPOCH=86500
    second="$(lr propose 'run plan' /dr-plan 0.9 alice s-2)"
    lr consume_callback "$second" Y alice s-2
    [ "$(rule_value created_at)" = 100 ]
    [ "$(rule_value last_validated_at)" = 86500 ]
    [ "$(rule_value expires_at)" = 604900 ]
}

@test "expired rule requires a fresh creation window" {
    first="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    lr consume_callback "$first" Y alice s-1
    export DR_ORCH_NOW_EPOCH=604900
    second="$(lr propose 'run plan' /dr-plan 0.9 alice s-2)"
    lr consume_callback "$second" Y alice s-2
    [ "$(rule_value created_at)" = 604900 ]
    [ "$(rule_value expires_at)" = 1209700 ]
}

@test "maintenance preserves due rules and atomically purges expiry equality" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    lr consume_callback "$id" Y alice s-1
    export DR_ORCH_NOW_EPOCH=86500
    lr maintenance
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 1 ]
    export DR_ORCH_NOW_EPOCH=604900
    lr maintenance
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 0 ]
    [ "$(stat -c %a "$DR_ORCH_RULES_LEARNED")" = 600 ]
}

@test "stale same-match proposal loses after another proposal commits" {
    first="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    second="$(lr propose 'run plan' /dr-plan 0.8 bob s-2)"
    lr consume_callback "$first" Y alice s-1
    before="$(sha256sum "$DR_ORCH_RULES_LEARNED")"
    run lr consume_callback "$second" Y bob s-2
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$DR_ORCH_RULES_LEARNED")" = "$before" ]
}

@test "symlinked state targets fail closed" {
    mkdir -p "$BATS_TEST_TMPDIR/real-state"
    ln -s "$BATS_TEST_TMPDIR/real-state" "$DR_ORCH_STATE_DIR"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ -z "$(find "$BATS_TEST_TMPDIR/real-state" -mindepth 1 -print -quit)" ]
}

@test "maintenance purges proposals and tombstones at inclusive boundaries" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    export DR_ORCH_NOW_EPOCH=1000
    lr maintenance
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]

    export DR_ORCH_NOW_EPOCH=1100
    id2="$(lr propose 'run qa' /dr-qa 0.9 alice s-2)"
    lr consume_callback "$id2" N alice s-2
    export DR_ORCH_NOW_EPOCH=605900
    lr maintenance
    [ -z "$(find "$DR_ORCH_STATE_DIR/learned-rule-tombstones" -name '*.json' -print -quit)" ]
}

@test "entropy failure and capability reuse fail closed" {
    export DR_ORCH_TEST_ENTROPY_FAIL=1
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    unset DR_ORCH_TEST_ENTROPY_FAIL
    DR_ORCH_TEST_ENTROPY_HEX="$(printf 'a%.0s' {1..64})"
    export DR_ORCH_TEST_ENTROPY_HEX
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -eq 0 ]
    run lr propose 'run qa' /dr-qa 0.9 bob s-2
    [ "$status" -ne 0 ]
}

@test "callback capability rejects tampered bound proposal fields" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    proposal="$(find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -name '*.json')"
    jq -c '.match="run qa"' "$proposal" >"$proposal.tmp"
    mv "$proposal.tmp" "$proposal"
    chmod 600 "$proposal"
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]
    [ ! -e "$DR_ORCH_RULES_LEARNED" ]
}

@test "corrupted learned YAML fails closed without replacement" {
    mkdir -p "$DR_ORCH_STATE_DIR"
    chmod 700 "$DR_ORCH_STATE_DIR"
    printf 'patterns: [not-valid\n' >"$DR_ORCH_RULES_LEARNED"
    chmod 600 "$DR_ORCH_RULES_LEARNED"
    before="$(sha256sum "$DR_ORCH_RULES_LEARNED")"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$DR_ORCH_RULES_LEARNED")" = "$before" ]
}

@test "manual extended TTL and fractional lifecycle state is rejected" {
    mkdir -p "$DR_ORCH_STATE_DIR"
    chmod 700 "$DR_ORCH_STATE_DIR"
    cat >"$DR_ORCH_RULES_LEARNED" <<'JSON'
{"patterns":[{"match":"run plan","action":"/dr-plan","confidence":0.9,"created_at":1.5,"last_validated_at":2,"expires_at":9999999999,"proposal_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
JSON
    chmod 600 "$DR_ORCH_RULES_LEARNED"
    before="$(sha256sum "$DR_ORCH_RULES_LEARNED")"
    run lr maintenance
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$DR_ORCH_RULES_LEARNED")" = "$before" ]
}

@test "distinct callbacks commit concurrently without lost updates" {
    first="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    second="$(lr propose 'run qa' /dr-qa 0.9 bob s-2)"
    lr consume_callback "$first" Y alice s-1 >"$BATS_TEST_TMPDIR/first.out" 2>&1 & p1=$!
    lr consume_callback "$second" Y bob s-2 >"$BATS_TEST_TMPDIR/second.out" 2>&1 & p2=$!
    wait "$p1"; r1=$?; wait "$p2"; r2=$?
    [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]
    [ "$(jq -r '[.patterns[].match] | sort | join(",")' "$DR_ORCH_RULES_LEARNED")" = 'run plan,run qa' ]
}

@test "same callback has exactly one concurrent consumer" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    set +e
    lr consume_callback "$id" Y alice s-1 >/dev/null 2>&1 & p1=$!
    lr consume_callback "$id" Y alice s-1 >/dev/null 2>&1 & p2=$!
    wait "$p1"; r1=$?; wait "$p2"; r2=$?
    set -e
    [ $(( (r1 == 0) + (r2 == 0) )) -eq 1 ]
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 1 ]
}

@test "lifecycle constants ignore environment overrides" {
    export LEARNED_RULE_PROPOSAL_TTL=9999 LEARNED_RULE_LIFETIME=9999
    export LEARNED_RULE_REVALIDATE_AFTER=9999 LEARNED_RULE_PROPOSAL_CAP=1
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    proposal="$(find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -name '*.json')"
    [ "$(jq -r '.expires_at' "$proposal")" -eq 1000 ]
    lr consume_callback "$id" Y alice s-1
    [ "$(jq -r '.patterns[0].expires_at' "$DR_ORCH_RULES_LEARNED")" -eq 604900 ]
}

@test "proposal and rule caps fail closed at immutable boundaries" {
    mkdir -p "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    chmod 700 "$DR_ORCH_STATE_DIR" "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    for n in $(seq 1 128); do
        printf '{"expires_at":1000}\n' >"$DR_ORCH_STATE_DIR/learned-rule-proposals/$n.json"
        chmod 600 "$DR_ORCH_STATE_DIR/learned-rule-proposals/$n.json"
    done
    run lr propose 'run plan three' /dr-plan 0.9 carol s-3
    [ "$status" -ne 0 ]

    rm -rf "$DR_ORCH_STATE_DIR"
    second="$(lr propose 'run qa' /dr-qa 0.9 bob s-2)"
    mkdir -p "$DR_ORCH_STATE_DIR"
    jq -cn '[range(0;256) | {match:("seed " + tostring),action:"/dr-plan",confidence:0.9,
      created_at:100,last_validated_at:100,expires_at:604900,
      proposal_hash:("a"*64),generation:("b"*64)}] | {patterns:.}' \
      >"$DR_ORCH_RULES_LEARNED"
    chmod 600 "$DR_ORCH_RULES_LEARNED"
    run lr consume_callback "$second" Y bob s-2
    [ "$status" -ne 0 ]
    [ "$(jq '.patterns | length' "$DR_ORCH_RULES_LEARNED")" -eq 256 ]
}

@test "delivery and tombstone byte caps fail closed" {
    mkdir -p "$DR_ORCH_STATE_DIR/learned-rule-delivery"
    chmod 700 "$DR_ORCH_STATE_DIR" "$DR_ORCH_STATE_DIR/learned-rule-delivery"
    printf '%65536s' x >"$DR_ORCH_STATE_DIR/learned-rule-delivery/full.json"
    chmod 600 "$DR_ORCH_STATE_DIR/learned-rule-delivery/full.json"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ "$(proposal_count)" -eq 1 ]

    rm -rf "$DR_ORCH_STATE_DIR"
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    mkdir -p "$DR_ORCH_STATE_DIR/learned-rule-tombstones"
    printf '{"consumed_at":100,"padding":"' \
      >"$DR_ORCH_STATE_DIR/learned-rule-tombstones/full.json"
    head -c 1048576 /dev/zero | tr '\0' x \
      >>"$DR_ORCH_STATE_DIR/learned-rule-tombstones/full.json"
    printf '"}\n' >>"$DR_ORCH_STATE_DIR/learned-rule-tombstones/full.json"
    chmod 600 "$DR_ORCH_STATE_DIR/learned-rule-tombstones/full.json"
    run lr consume_callback "$id" N alice s-1
    [ "$status" -ne 0 ]
    [ "$(proposal_count)" -eq 1 ]
}

@test "proposal directory and learned target symlinks are rejected" {
    mkdir -p "$DR_ORCH_STATE_DIR" "$BATS_TEST_TMPDIR/elsewhere"
    chmod 700 "$DR_ORCH_STATE_DIR" "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    rm "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    printf 'victim\n' >"$BATS_TEST_TMPDIR/victim"
    ln -s "$BATS_TEST_TMPDIR/victim" "$DR_ORCH_RULES_LEARNED"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/victim")" = victim ]
}

@test "proposal-file and intermediate symlinks plus unsafe modes fail closed" {
    mkdir -p "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    chmod 700 "$DR_ORCH_STATE_DIR" "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    printf 'victim\n' >"$BATS_TEST_TMPDIR/proposal-victim"
    ln -s "$BATS_TEST_TMPDIR/proposal-victim" \
      "$DR_ORCH_STATE_DIR/learned-rule-proposals/unsafe.json"
    run lr maintenance
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/proposal-victim")" = victim ]

    rm -rf "$DR_ORCH_STATE_DIR"
    mkdir -p "$DR_ORCH_STATE_DIR" "$BATS_TEST_TMPDIR/elsewhere"
    chmod 700 "$DR_ORCH_STATE_DIR" "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$DR_ORCH_STATE_DIR/intermediate"
    export DR_ORCH_PROPOSALS_DIR="$DR_ORCH_STATE_DIR/intermediate/proposals"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]

    unset DR_ORCH_PROPOSALS_DIR
    rm -rf "$DR_ORCH_STATE_DIR"
    mkdir -p "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    chmod 700 "$DR_ORCH_STATE_DIR" "$DR_ORCH_STATE_DIR/learned-rule-proposals"
    printf '{}\n' >"$DR_ORCH_STATE_DIR/learned-rule-proposals/unsafe.json"
    chmod 644 "$DR_ORCH_STATE_DIR/learned-rule-proposals/unsafe.json"
    run lr maintenance
    [ "$status" -ne 0 ]
}

@test "configured state path escape is rejected" {
    export DR_ORCH_PROPOSALS_DIR="$BATS_TEST_TMPDIR/outside"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/outside" ]
}

@test "configured state ancestor symlink is rejected" {
    mkdir -p "$BATS_TEST_TMPDIR/real"
    ln -s "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/link"
    export DR_ORCH_STATE_DIR="$BATS_TEST_TMPDIR/link/state"
    unset DR_ORCH_RULES_LEARNED DR_ORCH_PROPOSALS_DIR DR_ORCH_TOMBSTONES_DIR DR_ORCH_DELIVERY_DIR
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/real/state" ]
}

@test "secure state read rejects replacement between validation and use" {
    target="$BATS_TEST_TMPDIR/replace.json"
    printf 'trusted\n' >"$target"
    chmod 600 "$target"
    run bash -c '
      source "$1/scripts/lib/learned-rules-common.sh"
      portable_identity() {
        if [[ "$1" != /dev/fd/* ]]; then
          mv "$1" "$1.original"
          printf "replaced\\n" >"$1"
          chmod 600 "$1"
        fi
        stat -Lc "%d:%i" -- "$1"
      }
      learned_rules_read_secure "$2"
    ' _ "$PLUGIN_ROOT" "$target"
    [ "$status" -ne 0 ]
    [[ "$output" != *replaced* ]]
}

@test "shared lock symlink is rejected without victim mutation" {
    mkdir -p "$DR_ORCH_STATE_DIR"
    chmod 700 "$DR_ORCH_STATE_DIR"
    printf 'LOCK-VICTIM' >"$BATS_TEST_TMPDIR/lock-victim"
    ln -s "$BATS_TEST_TMPDIR/lock-victim" "$DR_ORCH_STATE_DIR/.learned-rules.lock"
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/lock-victim")" = LOCK-VICTIM ]
}

@test "shared lock contention is bounded" {
    lr maintenance
    flock -x "$DR_ORCH_STATE_DIR/.learned-rules.lock" -c 'sleep 2' & holder=$!
    sleep 0.1
    export DR_ORCH_LOCK_TIMEOUT_S=1
    run lr propose 'run plan' /dr-plan 0.9 alice s-1
    [ "$status" -ne 0 ]
    wait "$holder"
}

@test "prepare audit failure prevents mutation and commit failure reconciles once" {
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    export DR_ORCH_TEST_AUDIT_FAIL_EVENT=learned_rule_prepare
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ] && [ ! -e "$DR_ORCH_RULES_LEARNED" ]
    unset DR_ORCH_TEST_AUDIT_FAIL_EVENT

    export DR_ORCH_TEST_AUDIT_FAIL_EVENT=learned_rule_commit
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ] && [ -s "$DR_ORCH_RULES_LEARNED" ]
    unset DR_ORCH_TEST_AUDIT_FAIL_EVENT
    run lr maintenance
    [ "$status" -eq 0 ]
    [ "$(jq -r 'select(.event=="learned_rule_commit") | .proposal_hash' "$DR_ORCH_LEARNED_AUDIT" | wc -l)" -eq 1 ]
    ! grep -Fq "$id" "$DR_ORCH_LEARNED_AUDIT"
}

@test "day-rotated maintenance does not duplicate a prior commit" {
    mkdir -p "$BATS_TEST_TMPDIR/audit"
    chmod 700 "$BATS_TEST_TMPDIR/audit"
    export DR_ORCH_LEARNED_AUDIT="$BATS_TEST_TMPDIR/audit/audit-2026-07-17.jsonl"
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    proposal_hash="$(basename "$(find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -name '*.json')" .json)"
    export DR_ORCH_TEST_ATOMIC_FAIL_BASENAME="$proposal_hash.json"
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]
    [ "$(jq -s '[.[]|select(.event=="learned_rule_commit")]|length' "$DR_ORCH_LEARNED_AUDIT")" -eq 1 ]
    unset DR_ORCH_TEST_ATOMIC_FAIL_BASENAME
    export DR_ORCH_LEARNED_AUDIT="$BATS_TEST_TMPDIR/audit/audit-2026-07-18.jsonl"
    run lr maintenance
    [ "$status" -eq 0 ]
    [ "$(jq -s '[.[]|select(.event=="learned_rule_commit")]|length' \
      "$BATS_TEST_TMPDIR"/audit/audit-*.jsonl)" -eq 1 ]
}

@test "standalone callback writes the canonical daily audit ledger" {
    unset DR_ORCH_LEARNED_AUDIT DR_ORCH_AUDIT_FILE
    export AUDIT_DIR="$BATS_TEST_TMPDIR/canonical-audit"
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    run "$PLUGIN_ROOT/scripts/plugin.sh" dispatch on_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
    audit="$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"
    [ -s "$audit" ]
    jq -s -e 'any(.[]; .event=="learned_rule_prepare") and
      any(.[]; .event=="learned_rule_commit")' "$audit"
    [ ! -e "$DR_ORCH_STATE_DIR/learned-rule-audit.jsonl" ]
}

@test "callback binds space and persists non-overridable framework action kind" {
    export DATARIM_ACTIVE_SPACE=space-a
    id="$(lr propose 'run plan' /dr-plan 0.9 alice s-1)"
    proposal="$(find "$DR_ORCH_STATE_DIR/learned-rule-proposals" -name '*.json')"
    jq -e '.space=="space-a" and .action_kind=="framework_command"' "$proposal"
    export DATARIM_ACTIVE_SPACE=space-b
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -ne 0 ]
    export DATARIM_ACTIVE_SPACE=space-a
    run lr consume_callback "$id" Y alice s-1
    [ "$status" -eq 0 ]
}
