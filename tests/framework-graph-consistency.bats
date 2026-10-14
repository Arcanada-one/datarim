#!/usr/bin/env bats
setup() { ROOT="${BATS_TEST_DIRNAME}/.."; }

@test "canonical framework graph is current" {
  run python3 "$ROOT/dev-tools/framework-graph.py" --check
  [ "$status" -eq 0 ]
}

@test "framework map renders fragment targets without truncating their kind prefix" {
  run python3 - "$ROOT" <<'PY'
import importlib.util, pathlib, sys
root=pathlib.Path(sys.argv[1])
spec=importlib.util.spec_from_file_location('framework_graph', root/'dev-tools/framework-graph.py')
graph=importlib.util.module_from_spec(spec); spec.loader.exec_module(graph)
rendered=graph.render(graph.load())
for label in (
    'plugins/product-discovery/skills/hypothesis-validation/researcher.product-discovery.md',
    'plugins/product-discovery/skills/decision-record/strategist.product-discovery.md',
):
    assert f'["{label}"]' in rendered, f'missing full fragment label: {label}'
assert 'nt:plugins/' not in rendered
print('fragment labels retain their complete paths')
PY
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

@test "every skill frontmatter block is strict YAML" {
  run python3 - "$ROOT" <<'PY'
import pathlib,sys,yaml
r=pathlib.Path(sys.argv[1]); bad=[]
for p in (r/'skills').glob('**/SKILL.md'):
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
