#!/usr/bin/env bats
# Synthetic controls for enabled-and-selected product-discovery agent fragments.

@test "enabled and selected profile reads both installed fragments with receipts" {
    python3 "$BATS_TEST_DIRNAME/helpers/product_discovery_agent_fragments.py" enabled-selected
}

@test "selected profile with disabled plugin does not read a fragment" {
    python3 "$BATS_TEST_DIRNAME/helpers/product_discovery_agent_fragments.py" selected-disabled
}

@test "enabled plugin with profile off does not read a fragment" {
    python3 "$BATS_TEST_DIRNAME/helpers/product_discovery_agent_fragments.py" enabled-profile-off
}

@test "active profile with a missing installed fragment fails loudly" {
    python3 "$BATS_TEST_DIRNAME/helpers/product_discovery_agent_fragments.py" missing-fragment
}

@test "agent fragments stay gated and render complete graph labels" {
    python3 "$BATS_TEST_DIRNAME/helpers/product_discovery_agent_fragments.py" prompt-gates
}
