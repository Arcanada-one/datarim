#!/usr/bin/env bats
# command-graph.bats — contract tests for dev-tools/command-graph.yaml.

setup() {
    GRAPH="${BATS_TEST_DIRNAME}/../dev-tools/command-graph.yaml"
    MERMAID="${BATS_TEST_DIRNAME}/../skills/visual-maps/command-dependencies.md"
}

@test "command-graph.yaml is valid YAML" {
    run python3 -c "
import yaml, sys
with open('$GRAPH') as f:
    data = yaml.safe_load(f)
assert 'commands' in data, 'missing commands key'
assert 'schema_version' in data, 'missing schema_version'
print('ok: valid YAML with commands and schema_version')
"
    [ "$status" -eq 0 ]
}

@test "command-graph.yaml has at least 24 commands" {
    run python3 -c "
import yaml, sys
with open('$GRAPH') as f:
    data = yaml.safe_load(f)
n = len(data['commands'])
print(f'commands: {n}')
assert n >= 24, f'expected >= 24 commands, got {n}'
"
    [ "$status" -eq 0 ]
}

@test "command-graph.yaml includes all core pipeline commands" {
    run python3 -c "
import yaml
with open('$GRAPH') as f:
    data = yaml.safe_load(f)
cmds = set(data['commands'].keys())
required = {'dr-init','dr-prd','dr-plan','dr-design','dr-do','dr-qa','dr-compliance','dr-archive'}
missing = required - cmds
assert not missing, f'missing core commands: {missing}'
print('ok: all core pipeline commands present')
"
    [ "$status" -eq 0 ]
}

@test "command-dependencies.md contains pipeline graph reference" {
    run grep -c 'dr-do --> dr-qa' "$MERMAID"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
