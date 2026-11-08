import pathlib,sys,yaml
plugins=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())['inventory']['plugins']
assets={asset['path'] for package in plugins for asset in package['assets']}
assert 'plugins/optional/scripts/entry.py' in assets
assert not any('__pycache__' in path or path.endswith(('.pyc','.pyo')) for path in assets)
print('plugin runtime caches excluded from generated assets')
