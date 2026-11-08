import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
g=m.load()
assert any(e['from']=='skill:optional/topic' and e['relation']=='uses_template' and
           e['to']=='template:plugins/optional/templates/demo-template.md' for e in g['edges'])
assert not m.plugin_template_mentions('A demo-template is one type of agreement.',['plugins/optional/templates/demo-template.md'])
assert m.plugin_template_mentions('Use `demo-template` as the required input.',['plugins/optional/templates/demo-template.md'])
assert m.plugin_template_mentions('[protocol](../../templates/demo-template.md)',['plugins/optional/templates/demo-template.md'])

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
