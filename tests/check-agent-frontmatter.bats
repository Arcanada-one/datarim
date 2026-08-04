#!/usr/bin/env bats
# check-agent-frontmatter.bats — regression suite for the agent-frontmatter
# runtime-agnosticism gate (dev-tools/check-agent-frontmatter.sh).
#
# Contract pinned here:
#   - PASS on the real shipped tree (all agents 'model: inherit' + valid tier).
#   - FAIL on a hardcoded model-generation name (e.g. a vendor alias).
#   - FAIL on missing model, missing metadata.model_tier, invalid tier.
#   - FAIL (fail-closed) when the canonical tier registry is missing.
#   - Allowed tier set is parsed from config/model-tiers.yaml, not hardcoded.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/dev-tools/check-agent-frontmatter.sh"
  FIX="$(mktemp -d)"
  mkdir -p "$FIX/agents" "$FIX/config"
  cp "$REPO_ROOT/config/model-tiers.yaml" "$FIX/config/model-tiers.yaml"
}

teardown() {
  rm -rf "$FIX"
}

write_agent() {
  # write_agent <basename> <model-line-or-empty> <tier-line-or-empty>
  local base="$1" model_line="$2" tier_line="$3"
  {
    echo '---'
    echo "name: ${base%.md}"
    echo 'description: fixture agent for the frontmatter gate suite.'
    [ -n "$model_line" ] && echo "$model_line"
    if [ -n "$tier_line" ]; then
      echo 'metadata:'
      echo "  $tier_line"
    fi
    echo '---'
    echo
    echo 'Body.'
  } > "$FIX/agents/$base"
}

@test "real shipped tree passes" {
  run bash "$SCRIPT" --root "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "compliant fixture agent passes" {
  write_agent good.md 'model: inherit' 'model_tier: balanced'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 0 ]
}

@test "hardcoded model alias fails" {
  write_agent bad-model.md 'model: sonnet' 'model_tier: balanced'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hardcoded model 'sonnet'"* ]]
}

@test "full hardcoded model ID fails" {
  write_agent bad-full-id.md 'model: some-vendor/some-model-4' 'model_tier: fast'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hardcoded model"* ]]
}

@test "missing model line fails" {
  write_agent no-model.md '' 'model_tier: balanced'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISS model"* ]]
}

@test "missing metadata.model_tier fails" {
  write_agent no-tier.md 'model: inherit' ''
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISS metadata.model_tier"* ]]
}

@test "invalid tier name fails" {
  write_agent bad-tier.md 'model: inherit' 'model_tier: turbo'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid metadata.model_tier 'turbo'"* ]]
}

@test "one bad agent among good ones still fails the run" {
  write_agent good.md 'model: inherit' 'model_tier: reasoning'
  write_agent bad.md 'model: opus' 'model_tier: reasoning'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.md"* ]]
  [[ "$output" != *"FAIL (good.md)"* ]]
}

@test "missing tier registry fails closed" {
  write_agent good.md 'model: inherit' 'model_tier: balanced'
  rm "$FIX/config/model-tiers.yaml"
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"canonical tier registry missing"* ]]
}

@test "tier set is parsed from the registry, not hardcoded" {
  # Add a custom tier to the fixture registry; an agent using it must pass.
  awk '1; /^tiers:/ { print "  experimental_fixture_tier:"; print "    selection: vendor-default" }' \
    "$FIX/config/model-tiers.yaml" > "$FIX/config/model-tiers.yaml.new"
  mv "$FIX/config/model-tiers.yaml.new" "$FIX/config/model-tiers.yaml"
  write_agent custom.md 'model: inherit' 'model_tier: experimental_fixture_tier'
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 0 ]
}

@test "empty agents dir fails" {
  run bash "$SCRIPT" --root "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agents/*.md found"* ]]
}
