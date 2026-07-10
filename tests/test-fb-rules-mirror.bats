#!/usr/bin/env bats
# test-fb-rules-mirror.bats — TUNE-0187 regression.
# Covers the FB-rules consumer-mirror rollout tracker:
#   - scripts/check-fb-rules-mirror.sh invariants (anchor + rule-id coverage);
#   - the /dr-plugin enable pre-flight gate driven by requires_fb_rules_mirror.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECKER="$REPO_ROOT/scripts/check-fb-rules-mirror.sh"
  PLUGIN_SH="$REPO_ROOT/scripts/dr-plugin.sh"

  TMP="$(mktemp -d)"
  export DR_PLUGIN_WORKSPACE="$TMP"
  export DR_PLUGIN_RUNTIME_ROOT="$TMP/runtime"
  mkdir -p "$TMP/datarim" "$TMP/runtime"

  # A minimal valid-category plugin fixture that opts into the gate.
  PLG="$TMP/fixture-plugin"
  mkdir -p "$PLG/skills/mymod"
  cat > "$PLG/plugin.yaml" <<'Y'
schema_version: 1
id: fixture-autonomy
title: Fixture
version: 0.1.0
author: t
license: MIT
description: test
categories:
  - skills
requires_fb_rules_mirror: true
Y
  printf '# m\n' > "$PLG/skills/mymod/SKILL.md"
}

teardown() {
  rm -rf "$TMP"
}

# ── checker: file/arg errors ────────────────────────────────────────────────

@test "checker exits 2 with no consumer arg" {
  run "$CHECKER"
  [ "$status" -eq 2 ]
}

@test "checker exits 2 when consumer file is missing" {
  run "$CHECKER" /no/such/CLAUDE.md
  [ "$status" -eq 2 ]
}

# ── checker: drift vs in-sync ───────────────────────────────────────────────

@test "checker exits 1 when anchor is absent" {
  printf 'FB-1 FB-2 FB-3 FB-4 FB-5 FB-5a FB-6 FB-7 FB-8\n' > "$TMP/CLAUDE.md"
  run "$CHECKER" --quiet "$TMP/CLAUDE.md"
  [ "$status" -eq 1 ]
}

@test "checker exits 1 when a rule id is not cited" {
  # Anchor present, but FB-6 omitted.
  printf '## Autonomous Agent Operating Rules\nFB-1 FB-2 FB-3 FB-4 FB-5 FB-5a FB-7 FB-8\n' > "$TMP/CLAUDE.md"
  run "$CHECKER" --quiet "$TMP/CLAUDE.md"
  [ "$status" -eq 1 ]
}

@test "checker exits 0 for a full mirror" {
  printf '## Autonomous Agent Operating Rules\nFB-1 FB-2 FB-3 FB-4 FB-5 FB-5a FB-6 FB-7 FB-8\n' > "$TMP/CLAUDE.md"
  run "$CHECKER" --quiet "$TMP/CLAUDE.md"
  [ "$status" -eq 0 ]
}

@test "checker honours FB_RULES_CONSUMER_CLAUDE env fallback" {
  printf '## Autonomous Agent Operating Rules\nFB-1 FB-2 FB-3 FB-4 FB-5 FB-5a FB-6 FB-7 FB-8\n' > "$TMP/CLAUDE.md"
  FB_RULES_CONSUMER_CLAUDE="$TMP/CLAUDE.md" run "$CHECKER" --quiet
  [ "$status" -eq 0 ]
}

# ── enable gate ─────────────────────────────────────────────────────────────

@test "enable refuses when consumer CLAUDE.md is missing" {
  run "$PLUGIN_SH" enable "$PLG"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/datarim/enabled-plugins.md" ] || ! grep -q 'id: fixture-autonomy' "$TMP/datarim/enabled-plugins.md"
}

@test "enable refuses on drift and does not mutate the manifest" {
  printf '# no anchor here\n' > "$TMP/CLAUDE.md"
  run "$PLUGIN_SH" enable "$PLG"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/datarim/enabled-plugins.md" ] || ! grep -q 'id: fixture-autonomy' "$TMP/datarim/enabled-plugins.md"
}

@test "enable succeeds when the consumer mirrors the canonical rules" {
  printf '## Autonomous Agent Operating Rules\nFB-1 FB-2 FB-3 FB-4 FB-5 FB-5a FB-6 FB-7 FB-8\n' > "$TMP/CLAUDE.md"
  run "$PLUGIN_SH" enable "$PLG"
  [ "$status" -eq 0 ]
  grep -q 'id: fixture-autonomy' "$TMP/datarim/enabled-plugins.md"
}

@test "enable is ungated for a plugin without requires_fb_rules_mirror" {
  # Drop the opt-in flag; enable must not consult the consumer CLAUDE.md at all.
  sed '/requires_fb_rules_mirror/d' "$PLG/plugin.yaml" > "$PLG/plugin.yaml.tmp"
  mv "$PLG/plugin.yaml.tmp" "$PLG/plugin.yaml"
  # No CLAUDE.md in the workspace; enable should still succeed.
  run "$PLUGIN_SH" enable "$PLG"
  [ "$status" -eq 0 ]
  grep -q 'id: fixture-autonomy' "$TMP/datarim/enabled-plugins.md"
}
