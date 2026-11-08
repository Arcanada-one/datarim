import pathlib,sys,yaml
p=pathlib.Path(sys.argv[1]); g=yaml.safe_load(p.read_text())
g['inventory']['plugins'].append({'id':'hand-copied','assets':[]})
p.write_text(yaml.safe_dump(g,sort_keys=False,width=120))
