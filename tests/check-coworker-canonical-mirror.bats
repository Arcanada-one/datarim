#!/usr/bin/env bats
# check-coworker-canonical-mirror.bats — unit matrix for the coworker
# Type-Signature Mirror Guard linter (scripts/check-coworker-canonical-mirror.sh).
#
# Contract under test (see skills/coworker-context/SKILL.md
# § Type-Signature Mirror Guard):
#   Given a coworker draft / spec that quotes named types, signatures, or
#   variants, assert three conditions on a single file —
#     (a) a non-empty <!-- canonical --> … <!-- /canonical --> block,
#     (b) a mirror instruction ("mirror … exactly" + "do not invent/rename"),
#     (c) every CamelCase identifier in the canonical block appears verbatim in
#         the body outside that block (plus any --identifier the caller adds).
#   Any breach → exit 1. Missing file / bad usage → exit 2. All conditions
#   met → exit 0.
#
# The DoD case is T2: a synthetic spec that quotes types but ships NO verbatim
# canonical block MUST be caught (guard unmet, exit 1).

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-coworker-canonical-mirror.sh"

setup() {
    D="$(mktemp -d)"
}

teardown() { rm -rf "$D"; }

# A fully-compliant type-quoting draft.
write_good() {
    cat > "$D/draft.md" <<'EOF'
# Overview
<!-- canonical -->
fn on_post_hook(ctx: &PostHookContext) -> Result<Vec<Event>, HookError>
enum Payload { Text(String), Binary(Bytes) }
<!-- /canonical -->
Mirror the named types from the canonical block exactly. Do not invent
generics, do not rename fields.
The hook receives a PostHookContext and returns a Result wrapping a Vec of
Event values; on failure it yields HookError. The Payload enum carries a
Text of String or Binary of Bytes.
EOF
}

# T1: fully-compliant draft → exit 0.
@test "T1 compliant draft (block + instruction + coverage) → exit 0" {
    write_good
    run bash "$SCRIPT" --quiet "$D/draft.md"
    [ "$status" -eq 0 ]
}

# T2 (DoD): synthetic spec quoting types but WITHOUT a verbatim canonical
# block → guard unmet, exit 1.
@test "T2 spec quotes types but has no canonical block → exit 1" {
    cat > "$D/spec.md" <<'EOF'
# Overview
The hook takes a PostHookContext and returns Result<Vec<Event>, HookError>.
Mirror the named types exactly. Do not invent generics.
EOF
    run bash "$SCRIPT" --quiet "$D/spec.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"canonical"* ]]
}

# T3: block present but no mirror instruction → exit 1.
@test "T3 canonical block but missing mirror instruction → exit 1" {
    cat > "$D/spec.md" <<'EOF'
<!-- canonical -->
enum Payload { Text(String) }
<!-- /canonical -->
The Payload enum has a Text of String.
EOF
    # non-quiet so the per-condition [MISSING] diagnostic line is emitted.
    run bash "$SCRIPT" "$D/spec.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mirror instruction"* ]]
}

# T4: block + instruction but a canonical identifier is NOT mirrored in the
# body (drift) → exit 1, drift name reported.
@test "T4 canonical identifier absent from body → exit 1 with drift name" {
    cat > "$D/spec.md" <<'EOF'
<!-- canonical -->
struct PostHookContext
<!-- /canonical -->
Mirror the types exactly. Do not invent generics.
The overview describes a context struct passed to the hook.
EOF
    run bash "$SCRIPT" --quiet "$D/spec.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PostHookContext"* ]]
}

# T5: an identifier inside the block does not self-satisfy coverage — the same
# name absent from the body outside the block still drifts.
@test "T5 identifier only inside block, absent from body → exit 1" {
    cat > "$D/spec.md" <<'EOF'
<!-- canonical -->
enum Payload { Text(String) }
<!-- /canonical -->
Mirror the types exactly. Do not rename fields.
This overview mentions String but never the enum name.
EOF
    run bash "$SCRIPT" --quiet "$D/spec.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Payload"* ]]
}

# T6: --identifier extends coverage to a lowercase / exotic name the auto
# CamelCase derivation intentionally skips.
@test "T6 --identifier flags a lowercase name absent from body → exit 1" {
    write_good
    # on_post_hook is a snake_case fn name (auto-derivation skips it); force it.
    # The good draft body never repeats the literal "on_post_hook" token.
    run bash "$SCRIPT" --quiet --identifier on_post_hook "$D/draft.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"on_post_hook"* ]]
}

# T7: missing file → usage error exit 2.
@test "T7 missing file under test → exit 2" {
    run bash "$SCRIPT" --quiet "$D/nope.md"
    [ "$status" -eq 2 ]
}

# T8: no file argument and no env → usage error exit 2.
@test "T8 no file argument → exit 2" {
    run bash "$SCRIPT" --quiet
    [ "$status" -eq 2 ]
}

# T9: COWORKER_MIRROR_FILE env supplies the target when no positional arg.
@test "T9 COWORKER_MIRROR_FILE env resolves the target → exit 0" {
    write_good
    COWORKER_MIRROR_FILE="$D/draft.md" run bash "$SCRIPT" --quiet
    [ "$status" -eq 0 ]
}
