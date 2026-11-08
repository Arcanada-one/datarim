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
