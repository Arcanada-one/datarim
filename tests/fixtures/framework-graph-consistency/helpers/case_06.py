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
