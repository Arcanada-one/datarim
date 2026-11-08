import pathlib,sys,yaml
r=pathlib.Path(sys.argv[1])
files={p.stem for p in (r/'commands').glob('*.md')}
declared=set(yaml.safe_load((r/'dev-tools/command-graph.yaml').read_text())['commands'])
assert files==declared, f'files-only={sorted(files-declared)} graph-only={sorted(declared-files)}'
print(len(files))
