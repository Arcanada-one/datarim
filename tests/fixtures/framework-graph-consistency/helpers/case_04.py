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
