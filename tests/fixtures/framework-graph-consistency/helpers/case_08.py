import pathlib,sys,yaml
g=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())
assert 'plugins/optional/templates/added.md' in g['inventory']['templates']
assert any(a['path']=='plugins/optional/templates/added.md' for a in g['inventory']['plugins'][0]['assets'])
print('manifest category discovery confirmed')
