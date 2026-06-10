#!/usr/bin/env bats
#
# Read-branch token-estimation gate for coworker-hook-guard.
#
# Replaces the legacy `wc -l` line-count gate with an estimated-token gate:
# est_tokens = wc -c / divisor (divisor by extension, conservative-downward).
# Two thresholds — delegation (default 10000 est-tokens, route to coworker ask
# or a Bash-native edit) and a hard ceiling (default 100000 est-tokens, route
# to grep-only / sed / head, never to any LLM). Optional fail-soft tokenizer
# behind COWORKER_GUARD_USE_TOKENIZER=1.
#
# Documentation-only gate: the deny path applies ONLY to .md / .markdown / .txt.
# Code, dense blobs, and extension-less files pass through unconditionally —
# coworker saves tokens on prose + RTK; program code the agent reads natively,
# and `coworker ask` rejects non-doc extensions (exit 6) anyway. Fixtures
# default to a `.md` extension so the threshold/wording/tier cases still
# exercise estimation; passthrough cases pass an explicit code extension.
#
# Synthetic fixtures are generated in-test (no committed large blobs).
#
# Tests run against the canonical Datarim source by default so they exercise
# the freshly-edited script without requiring a relink of ~/.local/bin first.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
}

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

# Invoke the hook with a PreToolUse Read payload carrying $1 as file_path.
run_hook_read() {
    local path="$1"
    local payload
    payload=$(jq -nc --arg p "$path" '{
        hook_event_name: "PreToolUse",
        tool_name: "Read",
        tool_input: { file_path: $p }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# Make a file of exactly $1 bytes of a single repeated char, NO newline
# (so `wc -l` reports 0 lines — the minified/single-line blind spot).
#
# $2 = extension (default `.md`). The read-gate applies ONLY to documentation
# extensions (.md / .markdown / .txt); any other extension passes through
# unconditionally. Threshold / wording / tier tests therefore use a doc
# extension so they still exercise the estimation logic; pass an explicit code
# extension (.py / .ts / …) to assert the passthrough behaviour.
# NB: `${2-.md}` (no colon) defaults ONLY when $2 is *unset* — an explicit
# empty string ("") is honoured as "no extension at all", distinct from the
# default. `${2:-.md}` would wrongly coerce "" back to .md.
make_dense_file() {
    local bytes="$1" ext="${2-.md}"
    local f
    f=$(mktemp -t cw-hook-dense.XXXXXX)
    if [ -n "$ext" ]; then
        mv "$f" "$f$ext"
        f="$f$ext"
    fi
    head -c "$bytes" < /dev/zero | tr '\0' a > "$f"
    printf '%s' "$f"
}

# Many short numeric lines: high line-count, low token density. $2 = extension
# (default `.md`, same rationale as make_dense_file).
make_short_lines() {
    local n="$1" ext="${2-.md}"
    local f
    f=$(mktemp -t cw-hook-short.XXXXXX)
    if [ -n "$ext" ]; then
        mv "$f" "$f$ext"
        f="$f$ext"
    fi
    seq 1 "$n" > "$f"
    printf '%s' "$f"
}

decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision'; }
reason_of()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

# ----------------------------------------------------------------------
# Core token-vs-line cases
# ----------------------------------------------------------------------

@test "delegate-zone single-line dense file (60KB, 0 newlines) → deny" {
    f=$(make_dense_file 60000)            # est = 60000/3 = 20000 > 10000
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
}

@test "delegate deny message routes to coworker ask, NOT to ceiling grep-only" {
    f=$(make_dense_file 60000)
    run run_hook_read "$f"
    rm -f "$f"
    reason=$(reason_of "$output")
    case "$reason" in
        *"coworker ask"*) : ;;
        *) printf 'delegate reason lacked coworker ask: %s\n' "$reason" >&2; return 1 ;;
    esac
}

@test "700-line short file → silent pass (many lines, few tokens)" {
    f=$(make_short_lines 700)             # ~2.7KB → est ~900 < 10000
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ceiling file (360KB) → deny, grep-only wording, NOT coworker ask" {
    f=$(make_dense_file 360000)           # est = 120000 > 100000
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
    reason=$(reason_of "$output")
    # Must steer to byte-window tools …
    case "$reason" in *sed*) : ;; *) printf 'ceiling reason lacked sed: %s\n' "$reason" >&2; return 1 ;; esac
    case "$reason" in *grep*) : ;; *) printf 'ceiling reason lacked grep: %s\n' "$reason" >&2; return 1 ;; esac
    case "$reason" in *head*) : ;; *) printf 'ceiling reason lacked head: %s\n' "$reason" >&2; return 1 ;; esac
    # … and MUST NOT suggest sending the blob to a provider.
    case "$reason" in *"coworker ask"*) printf 'ceiling reason wrongly suggested coworker ask: %s\n' "$reason" >&2; return 1 ;; esac
}

@test "tiny file → silent pass (below delegate)" {
    f=$(make_dense_file 1200)             # est = 400 < 10000
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ----------------------------------------------------------------------
# Documentation-only gate: code / blobs / extension-less pass through
# regardless of size (operator decision — coworker saves tokens on docs +
# RTK, code the agent reads natively). The deny path is reachable ONLY for
# .md / .markdown / .txt.
# ----------------------------------------------------------------------

@test "code .py far above ceiling → silent pass (agent reads natively)" {
    f=$(make_dense_file 360000 .py)       # 120000 est would ceiling-deny IF gated
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "code .ts in delegate band → silent pass (no coworker-ask dead-end)" {
    f=$(make_dense_file 60000 .ts)        # 20000 est would delegate-deny IF gated
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "code .sh / .json / .go above ceiling → silent pass" {
    for ext in .sh .json .go; do
        f=$(make_dense_file 360000 "$ext")
        run run_hook_read "$f"
        rm -f "$f"
        [ "$status" -eq 0 ]
        [ -z "$output" ] || { printf '%s wrongly gated: %s\n' "$ext" "$output" >&2; return 1; }
    done
}

@test "former dense class .min.js → silent pass (divisor model retired for deny)" {
    f=$(make_dense_file 25000 .min.js)    # once divisor-2 → delegate deny; now passthrough
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "former dense class .b64 above former gate → silent pass" {
    f=$(make_dense_file 10001 .b64)       # once divisor-1 → delegate deny; now passthrough
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "extension-less file far above ceiling → silent pass (Dockerfile/LICENSE class)" {
    f=$(make_dense_file 360000 "")        # no extension at all
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "doc gate still alive: .markdown above ceiling → deny grep-only wording" {
    f=$(make_dense_file 360000 .markdown) # est 120000 > ceiling
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
    reason=$(reason_of "$output")
    case "$reason" in *sed*) : ;; *) printf '.markdown ceiling reason lacked sed: %s\n' "$reason" >&2; return 1 ;; esac
    case "$reason" in *"coworker ask"*) printf '.markdown ceiling wrongly suggested coworker ask: %s\n' "$reason" >&2; return 1 ;; esac
}

@test "doc gate still alive: .txt in delegate band → deny coworker-ask wording" {
    f=$(make_dense_file 60000 .txt)       # est 20000 → delegate band
    run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
    reason=$(reason_of "$output")
    case "$reason" in *"coworker ask"*) : ;; *) printf '.txt delegate reason lacked coworker ask: %s\n' "$reason" >&2; return 1 ;; esac
}

# ----------------------------------------------------------------------
# Env-var migration & legacy footgun
# ----------------------------------------------------------------------

@test "legacy COWORKER_GUARD_READ_THRESHOLD is ignored (no line gating)" {
    # A 700-line file would have tripped the old line gate at 400; under the
    # token model it must pass (legacy line var must not reinterpret as bytes).
    f=$(make_short_lines 700)
    COWORKER_GUARD_READ_THRESHOLD=1 run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "env-tunable delegate threshold lifts the gate" {
    f=$(make_dense_file 60000)            # est 20000 — would deny at default
    COWORKER_GUARD_DELEGATE_TOKENS=999999 COWORKER_GUARD_CEILING_TOKENS=9999999 \
        run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ----------------------------------------------------------------------
# Opt-in tokenizer (fail-soft)
# ----------------------------------------------------------------------

@test "USE_TOKENIZER=1 with absent binary falls back to heuristic (no crash)" {
    f=$(make_short_lines 700)             # heuristic est ~900 → pass
    COWORKER_GUARD_USE_TOKENIZER=1 COWORKER_GUARD_TOKENIZER_BIN=definitely-no-such-binary-xyz \
        run run_hook_read "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "USE_TOKENIZER=1 with a fake tokenizer overrides the heuristic" {
    # Fake tokenizer reports a huge count for a tiny file → ceiling deny.
    bindir=$(mktemp -d -t cw-hook-bin.XXXXXX)
    cat > "$bindir/faketok" <<'EOF'
#!/usr/bin/env bash
echo 200000
EOF
    chmod +x "$bindir/faketok"
    f=$(make_dense_file 1200)             # heuristic est 400 — would pass
    PATH="$bindir:$PATH" COWORKER_GUARD_USE_TOKENIZER=1 COWORKER_GUARD_TOKENIZER_BIN=faketok \
        run run_hook_read "$f"
    rm -f "$f"; rm -rf "$bindir"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
    reason=$(reason_of "$output")
    case "$reason" in *sed*) : ;; *) printf 'tokenizer ceiling reason lacked sed: %s\n' "$reason" >&2; return 1 ;; esac
}

@test "USE_TOKENIZER=1 with non-numeric tokenizer output fails soft to heuristic" {
    bindir=$(mktemp -d -t cw-hook-bin.XXXXXX)
    cat > "$bindir/faketok" <<'EOF'
#!/usr/bin/env bash
echo "error: model not found"
EOF
    chmod +x "$bindir/faketok"
    f=$(make_short_lines 700)             # heuristic est ~900 → pass
    PATH="$bindir:$PATH" COWORKER_GUARD_USE_TOKENIZER=1 COWORKER_GUARD_TOKENIZER_BIN=faketok \
        run run_hook_read "$f"
    rm -f "$f"; rm -rf "$bindir"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ----------------------------------------------------------------------
# Defensive invariant — deny wording bound to the crossed threshold
# ----------------------------------------------------------------------

@test "deny-wording invariant: corrupted tier mapping exits 2" {
    mut="$BATS_TMPDIR/guard-mut-$$.sh"
    cp "$HOOK" "$mut"
    # Corrupt the caller so the delegate band emits the CEILING tier. The
    # ceiling precondition (est must exceed CEILING) then fails for a
    # delegate-band file → exit 2 (invariant fires).
    sed -i.bak 's/emit_read_deny delegate/emit_read_deny ceiling/' "$mut"
    grep -q 'emit_read_deny ceiling "$f" "$est"' "$mut" || skip "mutation point not found (structure changed)"
    chmod +x "$mut"
    f=$(make_dense_file 60000)            # delegate band (est 20000 <= ceiling)
    pf="$BATS_TMPDIR/payload-$$.json"
    jq -nc --arg p "$f" '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:$p}}' > "$pf"
    run bash -c "'$mut' < '$pf'"
    rm -f "$f" "$mut" "$mut.bak" "$pf"
    [ "$status" -eq 2 ]
}
