#!/usr/bin/env bats
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
import json
edge_keys=[json.dumps(edge,sort_keys=True) for edge in g['edges']]
assert len(edge_keys)==len(set(edge_keys)), 'canonical graph contains exact duplicate edges'
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
assets={a['component_id'] for p in packages.values() for a in p['assets']}
assert not assets.intersection(off['nodes']), sorted(assets.intersection(off['nodes']))
assert assets <= on['nodes'], sorted(assets-on['nodes'])
edges={(e['from'],e['relation'],e['to']):e for e in g['edges']}
assert ('command:dr-prd','loads','skill:product-discovery/product-framing') in edges
assert edges[('command:dr-prd','loads','skill:product-discovery/product-framing')].get('condition') == {
    'plugin_enabled':'product-discovery','profile_selected':'product-discovery'}
assert ('skill:product-discovery/hypothesis-validation','uses_template','template:plugins/product-discovery/templates/experiment-protocol.md') in edges
assert ('skill:product-discovery/hypothesis-validation','uses_template','template:plugins/product-discovery/templates/hypothesis-card.md') in edges
assert ('skill:product-discovery/product-framing','uses_template','template:plugins/product-discovery/templates/opportunity-brief.md') in edges
print('plugin isolation and direct reference edges verified')
PY
  [ "$status" -eq 0 ]
}

@test "plugin condition fields independently gate profile reachability" {
  run python3 - "$ROOT" <<'PY'
import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base={'inventory':{'plugins':[{'id':'product-discovery','default_enabled':False,'assets':[]}],
                   'commands':['demo'],'agents':[],'skills':[],'fragments':[],'templates':[]}}
for field in ('plugin_enabled','profile_selected'):
    g={**base,'edges':[{'from':'command:demo','relation':'loads','to':'plugin:product-discovery',
                        'condition':{field:'product-discovery'}}]}
    assert 'plugin:product-discovery' not in m.project(g,'off')['nodes'], field
    assert 'plugin:product-discovery' in m.project(g,'on')['nodes'], field
print('plugin_enabled and profile_selected each gate independently')
PY
  [ "$status" -eq 0 ]
}

@test "profile CLI refuses a projection that violates its requested state" {
  run python3 - "$ROOT" <<'PY'
import contextlib,importlib.util,io,pathlib,sys,tempfile,yaml
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); g=m.load()
with tempfile.TemporaryDirectory() as d:
    d=pathlib.Path(d); m.OUT=d/'graph.yaml'; m.MAP=d/'map.md'; m.CMDMAP=d/'cmd.md'
    m.OUT.write_text(yaml.safe_dump(g,sort_keys=False,width=120)); m.MAP.write_text(m.render(g)); m.CMDMAP.write_text(m.render_cmd(g))
    m.validate=lambda _:[]
    m.load=lambda:g
    m.project=lambda graph,state:{'nodes':set(),'edges':[]}
    sys.argv=['framework-graph.py','--check','--profile-on']
    stderr=io.StringIO()
    with contextlib.redirect_stderr(stderr): rc=m.main()
    assert rc==1 and 'reachability is inconsistent' in stderr.getvalue(), stderr.getvalue()
print('profile-specific CLI guard rejects an inconsistent projection')
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
  [ "$status" -ne 0 ] && [[ "$output" == *"plugin inventory is stale or hand-maintained"* ]]
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

@test "plugin reference extraction and manifest guards reject invalid inputs" {
  make_fixture
  run python3 - "$FIXTURE" <<'PY'
import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
g=m.load()
assert any(e['from']=='skill:optional/topic' and e['relation']=='uses_template' and
           e['to']=='template:plugins/optional/templates/demo-template.md' for e in g['edges'])
assert not m.plugin_template_mentions('A demo-template is one type of agreement.',['plugins/optional/templates/demo-template.md'])
assert m.plugin_template_mentions('Use `demo-template` as the required input.',['plugins/optional/templates/demo-template.md'])

original=m.plugin_component_id
m.plugin_component_id=lambda *args:'duplicate-component'
try:
    try: m.plugin_packages()
    except ValueError as e: assert 'duplicate plugin component id' in str(e)
    else: raise AssertionError('duplicate component guard did not fire')
finally: m.plugin_component_id=original

manifest=r/'plugins/optional/plugin.yaml'; original_text=manifest.read_text()
manifest.write_text(original_text.replace('id: optional','id: another'))
try:
    try: m.plugin_packages()
    except ValueError as e: assert 'does not match directory' in str(e)
    else: raise AssertionError('id/dir guard did not fire')
finally: manifest.write_text(original_text)

asset=r/'plugins/optional/templates/linked.md'; asset.symlink_to(r/'plugins/optional/templates/demo-template.md')
try:
    try: m.plugin_packages()
    except ValueError as e: assert 'plugin asset is a symlink' in str(e)
    else: raise AssertionError('symlink guard did not fire')
finally: asset.unlink()

bad=m.load(); bad['inventory']['plugins'][0]['assets'].append({'path':'forged','category':'templates','component_id':'template:forged'})
assert any('plugin inventory is stale' in e for e in m.validate(bad))
bad=m.load(); bad['edges'][0]['condition']={'plugin_enabled':'unknown-plugin'}
assert any('unknown plugin' in e for e in m.validate(bad))
print('direct reference and all reachable manifest guards verified')
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
