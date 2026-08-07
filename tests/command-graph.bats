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

# The Mermaid file is a DERIVED artefact; the YAML is the source of truth.
# Without this test the pair drifts silently: dr-continue, dr-save and
# dr-wizard were declared in the YAML with real edges and appeared nowhere in
# the diagram, while the suite stayed green because the only diagram assertion
# was a single hardcoded edge.
@test "every command in command-graph.yaml appears in command-dependencies.md" {
    run python3 -c "
import re, yaml
with open('$GRAPH') as f:
    cmds = set(yaml.safe_load(f)['commands'])
text = open('$MERMAID').read()
# Not every command is dr-prefixed: the standalone content utilities
# (factcheck, humanize) carry no prefix, so match each declared name.
missing = sorted(c for c in cmds if not re.search(r'\b' + re.escape(c) + r'\b', text))
assert not missing, 'declared in command-graph.yaml but absent from the diagram: ' + ', '.join(missing)
print(f'ok: all {len(cmds)} graph commands present in the derived diagram')
"
    [ "$status" -eq 0 ]
}
