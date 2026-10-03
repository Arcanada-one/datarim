#!/usr/bin/env bats
#
# TUNE-0191 — regression test for the generalised frontmatter-key behaviour-gate
# mirror pattern (source: reflection-TUNE-0184 § P-6).
#
# Covers dev-tools/check-frontmatter-mirror.sh two-pass drift guard:
#   P1 registry-completeness — every live top-level frontmatter key on the
#      instruction surface (commands/skills/agents) is categorised in the
#      registry; no stale `status: live` entry has vanished from the surface.
#   P2 mirror-presence — for every `mirror: required` key, a file carrying the
#      frontmatter key must carry its body marker, and vice-versa (either-side).
#
# The real shipped registry is dev-tools/rules/frontmatter-key-registry.yaml.
# Fixture tests inject a temp registry via --registry to exercise drift paths
# without mutating the real tree.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-frontmatter-mirror.sh"
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/commands" "$TMP/skills/alpha" "$TMP/agents"
}

teardown() {
    rm -rf "$TMP"
}

# Minimal instruction-surface fixture: one command, one skill, one agent, all
# carrying only registered keys.
seed_clean_tree() {
    cat >"$TMP/commands/dr-x.md" <<'EOF'
---
name: dr-x
description: fixture command
---
body
EOF
    cat >"$TMP/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: fixture skill
---
body
EOF
    cat >"$TMP/agents/bot.md" <<'EOF'
---
name: bot
description: fixture agent
---
body
EOF
}

# A registry that categorises exactly name + description as live instruction keys.
seed_registry() {
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
EOF
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "usage error (unknown flag) exits 2" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "usage error (missing registry file) exits 2" {
    seed_clean_tree
    run "$SCRIPT" --root "$TMP" --registry "$TMP/no-such.yaml"
    [ "$status" -eq 2 ]
}

@test "PASS on a clean fixture tree with a matching registry" {
    seed_clean_tree
    seed_registry
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 0 ]
}

@test "P1 FAIL when a live key is not categorised in the registry" {
    seed_clean_tree
    seed_registry
    # Add an uncategorised behaviour-gating key to the command frontmatter.
    cat >"$TMP/commands/dr-x.md" <<'EOF'
---
name: dr-x
description: fixture command
allowed-tools: Read Bash
---
body
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"allowed-tools"* ]]
    [[ "$output" == *"uncategorised"* ]] || [[ "$output" == *"not in registry"* ]]
}

@test "P1 FAIL when a status:live registry entry vanished from the surface" {
    seed_clean_tree
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: ghost-key
    surface: instruction
    category: M
    mirror: none
    status: live
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ghost-key"* ]]
    [[ "$output" == *"stale"* ]] || [[ "$output" == *"vanished"* ]]
}

@test "reserved status entry never triggers the stale-live check" {
    seed_clean_tree
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: disable-model-invocation
    surface: instruction
    category: G
    mirror: required
    status: reserved
    body_marker: model-invocation
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 0 ]
}

@test "P2 FAIL when a mirror:required key is present without its body marker" {
    seed_clean_tree
    # Make allowed-tools a required-mirror key with a body_marker.
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: allowed-tools
    surface: instruction
    category: C
    mirror: required
    status: live
    body_marker: 'Tools:'
EOF
    # Command carries the key but the body lacks the 'Tools:' marker.
    cat >"$TMP/commands/dr-x.md" <<'EOF'
---
name: dr-x
description: fixture command
allowed-tools: Read Bash
---
body without the marker
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"allowed-tools"* ]]
    [[ "$output" == *"marker"* ]]
}

@test "P2 FAIL when a body marker is present without the frontmatter key" {
    seed_clean_tree
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: allowed-tools
    surface: instruction
    category: C
    mirror: required
    status: live
    body_marker: 'Tools:'
EOF
    # Command carries the marker in the body but NOT the frontmatter key.
    cat >"$TMP/commands/dr-x.md" <<'EOF'
---
name: dr-x
description: fixture command
---
**Tools:** Read Bash
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"allowed-tools"* ]]
    [[ "$output" == *"marker"* ]]
}

@test "P2 PASS when key and body marker co-occur" {
    seed_clean_tree
    cat >"$TMP/registry.yaml" <<'EOF'
keys:
  - key: name
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: description
    surface: instruction
    category: M
    mirror: none
    status: live
  - key: allowed-tools
    surface: instruction
    category: C
    mirror: required
    status: live
    body_marker: 'Tools:'
EOF
    cat >"$TMP/commands/dr-x.md" <<'EOF'
---
name: dr-x
description: fixture command
allowed-tools: Read Bash
---
**Tools:** Read Bash
EOF
    run "$SCRIPT" --root "$TMP" --registry "$TMP/registry.yaml"
    [ "$status" -eq 0 ]
}

# ── Real-tree assertion (AC-1 / AC-3): the shipped registry fully covers the
#    live instruction surface and the checker passes against the actual repo. ──
@test "real shipped tree PASSES against the shipped registry" {
    run "$SCRIPT" --root "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "wiring: a CI workflow runs the gate against the shipped tree" {
    # A gate landed without enforcement wiring is documented-but-unwired. Assert a
    # workflow invokes the script itself (not merely its unit tests), so deleting
    # the enforcement job fails this test instead of silently disarming the gate.
    WF="$BATS_TEST_DIRNAME/../.github/workflows/frontmatter-mirror.yml"
    [ -f "$WF" ]
    run grep -c 'check-frontmatter-mirror.sh' "$WF"
    [ "$status" -eq 0 ]
    run grep -c 'bats tests/check-frontmatter-mirror.bats' "$WF"
    [ "$status" -eq 0 ]
}
