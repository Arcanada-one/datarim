setup() { ROOT="${BATS_TEST_DIRNAME}/.."; }

make_fixture() {
  FIXTURE="$BATS_TEST_TMPDIR/graph-fixture"
  mkdir -p "$FIXTURE/dev-tools" "$FIXTURE/commands" "$FIXTURE/agents" \
    "$FIXTURE/skills/base" "$FIXTURE/skills/visual-maps" \
    "$FIXTURE/templates" "$FIXTURE/plugins/optional/skills/topic" \
    "$FIXTURE/plugins/optional/templates"
  cp "$ROOT/dev-tools/framework-graph.py" "$FIXTURE/dev-tools/framework-graph.py"
  cat >"$FIXTURE/AGENTS.md" <<'EOF'
Always load `skills/base/SKILL.md`.
EOF
  cat >"$FIXTURE/dev-tools/command-graph.yaml" <<'EOF'
schema_version: 1
always_load_skills: [base]
commands:
  demo:
    stage: utility
    requires: []
    precedes: []
    optional_at: []
EOF
  cat >"$FIXTURE/skills/base/SKILL.md" <<'EOF'
---
name: base
description: A fixture skill used to verify core graph inventory behavior.
---
# Base
EOF
  cat >"$FIXTURE/plugins/optional/plugin.yaml" <<'EOF'
schema_version: 1
id: optional
title: Optional
author: Fixture
version: 1.0.0
license: MIT
description: Optional fixture package for graph tests.
categories: [skills, templates]
EOF
  cat >"$FIXTURE/plugins/optional/skills/topic/SKILL.md" <<'EOF'
---
name: topic
description: A plugin skill fixture with a declared package template dependency.
---
Use the `demo-template` template.
EOF
  cat >"$FIXTURE/plugins/optional/templates/demo-template.md" <<'EOF'
# Fixture template
EOF
  cat >"$FIXTURE/commands/demo.md" <<'EOF'
Only for the optional profile, read `plugins/optional/skills/topic/SKILL.md`.
EOF
}

@test "canonical framework graph is current" {
  run python3 "$ROOT/dev-tools/framework-graph.py" --check
  [ "$status" -eq 0 ]
}

@test "command graph exactly matches command files" {
  run python3 - "$ROOT" <<'PY'
import pathlib,sys,yaml
r=pathlib.Path(sys.argv[1])
files={p.stem for p in (r/'commands').glob('*.md')}
declared=set(yaml.safe_load((r/'dev-tools/command-graph.yaml').read_text())['commands'])
assert files==declared, f'files-only={sorted(files-declared)} graph-only={sorted(declared-files)}'
print(len(files))
PY
  [ "$status" -eq 0 ]
}

@test "plugin assets are discovered with unique ownership and conditional reachability" {
  run python3 - "$ROOT" <<'PY'
import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); g=m.load()
owners={}; packages={p['id']:p for p in g['inventory']['plugins']}
for p in packages.values():
    for asset in p['assets']:
        key=asset['component_id']; assert key not in owners, f'duplicate owner for {key}'
        owners[key]=p['id']
assert {'product-discovery','controller-continuation','dr-jev-control','dr-orchestrate','tdd-enforcement'} <= packages.keys()
assert packages['product-discovery']['default_state']=='disabled'
assert packages['tdd-enforcement']['default_state']=='active'
expected={'decision-record.md','experiment-protocol.md','hypothesis-card.md','opportunity-brief.md','product-brief.md','source-evidence-ledger.md'}
plugin_templates={pathlib.Path(a['path']).name for a in packages['product-discovery']['assets'] if a['category']=='templates'}
assert expected <= plugin_templates
for name in expected:
    assert 'template:plugins/product-discovery/templates/'+name in {a['component_id'] for a in packages['product-discovery']['assets']}
off=m.project(g,'off'); on=m.project(g,'on')
assert 'plugin:product-discovery' not in off['nodes']
assert 'plugin:product-discovery' in on['nodes']
for start in ('command:dr-prd','command:dr-plan','agent:researcher','agent:strategist'):
    adjacency={}
    for edge in on['edges']: adjacency.setdefault(edge['from'],set()).add(edge['to'])
    seen={start}; pending=[start]
    while pending:
        for target in adjacency.get(pending.pop(),()):
            if target not in seen: seen.add(target); pending.append(target)
    assert { 'template:plugins/product-discovery/templates/'+name for name in expected } <= seen, start
print('conditional plugin graph and six template paths verified')
PY
  [ "$status" -eq 0 ]
}

@test "profile off and on checks report their reachable graph states" {
  run python3 - "$ROOT" <<'PY'
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])
for flag,expected in [('--profile-off','product-discovery profile-off: disabled or unselected'),('--profile-on','product-discovery profile-on: enabled and selected')]:
    result=subprocess.run(['python3',str(root/'dev-tools/framework-graph.py'),'--check',flag],capture_output=True,text=True)
    assert result.returncode==0, result.stderr
    assert expected in result.stdout, result.stdout
print('both profile projections checked')
PY
  [ "$status" -eq 0 ]
}

@test "profile-off preserves all legacy-to-legacy graph edges" {
  run python3 - "$ROOT" <<'PY'
import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); g=m.load(); inv=g['inventory']
plugin_nodes={'plugin:'+p['id'] for p in inv['plugins']}
plugin_nodes|={a['component_id'] for p in inv['plugins'] for a in p['assets']}
nodes={kind+':'+name for kind,items in [('command',inv['commands']),('agent',inv['agents']),('skill',inv['skills']),('fragment',inv['fragments']),('template',inv['templates'])] for name in items}
legacy=nodes-plugin_nodes
all_edges={(e['from'],e['relation'],e['to'],e['source']) for e in g['edges'] if e['from'] in legacy and e['to'] in legacy}
off=m.project(g,'off'); off_edges={(e['from'],e['relation'],e['to'],e['source']) for e in off['edges'] if e['from'] in legacy and e['to'] in legacy}
assert all_edges==off_edges
print(f'{len(all_edges)} legacy edges unchanged')
PY
  [ "$status" -eq 0 ]
}

@test "missing referenced plugin skill fails check" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ] || return 1
  sed -i 's#skills/topic/SKILL.md#skills/missing/SKILL.md#' "$FIXTURE/commands/demo.md"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ] && [[ "$output" == *"broken reference"* ]]
}

@test "hand-copied plugin inventory fails check" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ] || return 1
  run python3 - "$FIXTURE/dev-tools/framework-graph.yaml" <<'PY'
import pathlib,sys,yaml
p=pathlib.Path(sys.argv[1]); g=yaml.safe_load(p.read_text())
g['inventory']['plugins'].append({'id':'hand-copied','assets':[]})
p.write_text(yaml.safe_dump(g,sort_keys=False,width=120))
PY
  [ "$status" -eq 0 ] || return 1
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ] && [[ "$output" == *"dev-tools/framework-graph.yaml is missing or stale"* ]]
}

@test "new plugin files enter the graph from the manifest category" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ] || return 1
  printf '# Added after graph generation\n' >"$FIXTURE/plugins/optional/templates/added.md"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ] || return 1
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ] || return 1
  run python3 - "$FIXTURE/dev-tools/framework-graph.yaml" <<'PY'
import pathlib,sys,yaml
g=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())
assert 'plugins/optional/templates/added.md' in g['inventory']['templates']
assert any(a['path']=='plugins/optional/templates/added.md' for a in g['inventory']['plugins'][0]['assets'])
print('manifest category discovery confirmed')
PY
  [ "$status" -eq 0 ]
}

@test "independent write runs produce identical graph and map bytes" {
  run python3 "$ROOT/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ] || return 1
  first="$(sha256sum "$ROOT/dev-tools/framework-graph.yaml" "$ROOT/skills/visual-maps/framework-architecture.md" "$ROOT/skills/visual-maps/command-dependencies.md")"
  run python3 "$ROOT/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  second="$(sha256sum "$ROOT/dev-tools/framework-graph.yaml" "$ROOT/skills/visual-maps/framework-architecture.md" "$ROOT/skills/visual-maps/command-dependencies.md")"
  [ "$first" = "$second" ]
}

@test "every skill frontmatter block is strict YAML" {
  run python3 - "$ROOT" <<'PY'
import pathlib,sys,yaml
r=pathlib.Path(sys.argv[1]); bad=[]
for base in (r/'skills', *(r/'plugins').glob('*/skills')):
    for p in base.glob('**/SKILL.md'):
        try:
            parts=p.read_text().split('---',2)
            assert len(parts)==3
            d=yaml.safe_load(parts[1]); assert isinstance(d,dict) and d.get('name')
        except Exception as e: bad.append(f'{p.relative_to(r)}: {e}')
assert not bad, '\n'.join(bad)
print('ok')
PY
  [ "$status" -eq 0 ]
}
