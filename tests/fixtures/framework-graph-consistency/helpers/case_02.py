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
product_assets={a['component_id'] for a in packages['product-discovery']['assets']}
assert product_assets <= on['nodes'], sorted(product_assets-on['nodes'])
edges={(e['from'],e['relation'],e['to']):e for e in g['edges']}
for package in packages.values():
    for asset in package['assets']:
        assert ('plugin:'+package['id'],'contains',asset['component_id']) in edges, \
            f"missing contains edge for {asset['component_id']}"
assert ('command:dr-prd','loads','skill:product-discovery/product-framing') in edges
assert edges[('command:dr-prd','loads','skill:product-discovery/product-framing')].get('condition') == {
    'plugin_enabled':'product-discovery','profile_selected':'product-discovery'}
assert ('skill:product-discovery/hypothesis-validation','uses_template','template:plugins/product-discovery/templates/experiment-protocol.md') in edges
assert ('skill:product-discovery/hypothesis-validation','uses_template','template:plugins/product-discovery/templates/hypothesis-card.md') in edges
assert ('skill:product-discovery/product-framing','uses_template','template:plugins/product-discovery/templates/opportunity-brief.md') in edges
assert ('skill:product-discovery/decision-record','uses_template','template:plugins/product-discovery/templates/decision-record.md') in edges
assert ('fragment:plugins/product-discovery/skills/decision-record/strategist.product-discovery.md','uses_template','template:plugins/product-discovery/templates/product-brief.md') in edges
assert ('fragment:plugins/product-discovery/skills/product-framing/claim-quality.md','uses_template','template:plugins/product-discovery/templates/source-evidence-ledger.md') in edges
print('plugin isolation and direct reference edges verified')
