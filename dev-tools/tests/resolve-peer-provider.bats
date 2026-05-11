#!/usr/bin/env bats
# resolve-peer-provider.bats — TDD coverage for resolve-peer-provider.sh
#
# Coverage (9 chain branches T1-T9 + cost-cap + smoke):
#   T1  CLI flag override wins (--peer-provider deepseek → cli_flag layer)
#   T2  per-project ./datarim/config.yaml wins over ~/.config/datarim/config.yaml
#   T3  per-user ~/.config/datarim/config.yaml wins when per-project absent
#   T4  coworker default (--profile code) when both configs absent → deepseek
#   T5  subagent fallback (cross_claude_family / sonnet) when coworker disabled
#   T6  Codex degraded mode (CODEX_RUNTIME=1 → same_model_isolated + stderr warning)
#   T7  invalid provider value → exit 1
#   T8  cost-cap breach (PEER_REVIEW_COST_THRESHOLD=0.01 --estimate-cost 0.02 → exit 2)
#   T9  peer_review_mode inferred per provider (cross_vendor / cross_claude_family / same_model_isolated)
#
# Output contract: 3 lines on stdout — provider | mode | source_layer.
# Exit codes: 0 success / 1 parse-or-validation error / 2 cost-cap breach.

bats_require_minimum_version 1.5.0

RESOLVE="$BATS_TEST_DIRNAME/../resolve-peer-provider.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    export TMPROOT
    export HOME_OVERRIDE="$TMPROOT/home"
    export PROJECT_DIR="$TMPROOT/proj"
    mkdir -p "$HOME_OVERRIDE/.config/datarim" "$PROJECT_DIR/datarim"
    # Synthetic coworker profiles.yaml — must mimic real layout for D-6 awk recipe.
    mkdir -p "$HOME_OVERRIDE/.config/coworker"
    cat > "$HOME_OVERRIDE/.config/coworker/profiles.yaml" <<'EOF'
code:
  description: Generic code analysis
  recommended_provider: deepseek
datarim:
  description: Datarim artifacts
  recommended_provider: moonshot
EOF
}

teardown() {
    [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

write_per_project() {
    cat > "$PROJECT_DIR/datarim/config.yaml" <<EOF
peer_review:
  provider: $1
  fallback_model: sonnet
EOF
}

write_per_user() {
    cat > "$HOME_OVERRIDE/.config/datarim/config.yaml" <<EOF
peer_review:
  provider: $1
  fallback_model: sonnet
EOF
}

# ---------- T1: CLI flag wins -------------------------------------------------

@test "T1: CLI --peer-provider deepseek → exit 0, cli_flag source" {
    write_per_project moonshot
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --peer-provider deepseek \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "deepseek" ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_vendor" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "cli_flag" ]
}

# ---------- T2: per-project wins over per-user -------------------------------

@test "T2: per-project sonnet over per-user deepseek → sonnet wins" {
    write_per_project sonnet
    write_per_user deepseek
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "sonnet" ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_claude_family" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "per_project_config" ]
}

# ---------- T3: per-user when per-project absent -----------------------------

@test "T3: per-user deepseek when per-project absent" {
    write_per_user deepseek
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "deepseek" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "per_user_config" ]
}

# ---------- T4: coworker default (--profile code) ----------------------------

@test "T4: coworker --profile code default → deepseek (D-6)" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "deepseek" ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_vendor" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "coworker_default" ]
}

# ---------- T5: subagent fallback when coworker disabled ---------------------

@test "T5: subagent fallback when no configs and no coworker profiles" {
    rm "$HOME_OVERRIDE/.config/coworker/profiles.yaml"
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "sonnet" ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_claude_family" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "fallback_subagent" ]
}

# ---------- T6: Codex degraded mode ------------------------------------------

@test "T6: CODEX_RUNTIME=1 + no configs + no coworker → same_model_isolated + stderr warn" {
    rm "$HOME_OVERRIDE/.config/coworker/profiles.yaml"
    run --separate-stderr env HOME="$HOME_OVERRIDE" CODEX_RUNTIME=1 \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '1p')" = "opus" ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "same_model_isolated" ]
    [ "$(printf '%s\n' "$output" | sed -n '3p')" = "fallback_isolated" ]
    echo "$stderr" | grep -q "Codex runtime detected"
}

# ---------- T7: invalid provider value → exit 1 ------------------------------

@test "T7: invalid provider value via CLI → exit 1" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --peer-provider malicious-host \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 1 ]
}

@test "T7b: invalid provider value via per-project config → exit 1" {
    write_per_project typosquat-vendor
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 1 ]
}

# ---------- T8: cost-cap breach → exit 2 -------------------------------------

@test "T8: cost-cap breach (--estimate-cost 0.20 vs threshold 0.10) → exit 2" {
    run env HOME="$HOME_OVERRIDE" PEER_REVIEW_COST_THRESHOLD=0.10 \
        bash "$RESOLVE" \
            --estimate-cost 0.20 \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 2 ]
}

@test "T8b: cost-cap not breached (--estimate-cost 0.05 vs threshold 0.10) → exit 0" {
    run env HOME="$HOME_OVERRIDE" PEER_REVIEW_COST_THRESHOLD=0.10 \
        bash "$RESOLVE" \
            --estimate-cost 0.05 \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
}

# ---------- T9: peer_review_mode inferred per provider ----------------------

@test "T9a: provider=deepseek → mode=cross_vendor" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider deepseek \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_vendor" ]
}

@test "T9b: provider=moonshot → mode=cross_vendor" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider moonshot \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_vendor" ]
}

@test "T9c: provider=openrouter → mode=cross_vendor" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider openrouter \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_vendor" ]
}

@test "T9d: provider=sonnet → mode=cross_claude_family" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider sonnet \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_claude_family" ]
}

@test "T9e: provider=haiku → mode=cross_claude_family" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider haiku \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "cross_claude_family" ]
}

@test "T9f: provider=opus → mode=same_model_isolated" {
    run env HOME="$HOME_OVERRIDE" \
        bash "$RESOLVE" --peer-provider opus \
            --project-config "$PROJECT_DIR/datarim/config.yaml" \
            --user-config "$HOME_OVERRIDE/.config/datarim/config.yaml"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '2p')" = "same_model_isolated" ]
}

# ---------- Smoke: --help works ---------------------------------------------

@test "Smoke: --help exit 0 with usage on stdout" {
    run bash "$RESOLVE" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE "resolve-peer-provider|Resolution chain|Usage"
}
