import importlib.util,pathlib,sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('fg',r/'dev-tools/framework-graph.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base={'inventory':{'plugins':[{'id':'product-discovery','default_enabled':False,'assets':[]}],
                   'commands':['demo'],'agents':[],'skills':[],'fragments':[],'templates':[]}}
for field in ('plugin_enabled','profile_selected'):
    g={**base,'edges':[{'from':'command:demo','relation':'loads','to':'plugin:product-discovery',
                        'condition':{field:'product-discovery'}}]}
    assert 'plugin:product-discovery' not in m.project(g,'off')['nodes'], field
    assert 'plugin:product-discovery' in m.project(g,'on')['nodes'], field
print('plugin_enabled and profile_selected each gate independently')
