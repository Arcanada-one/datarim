import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])
for flag,expected in [('--profile-off','product-discovery profile-off: disabled or unselected'),('--profile-on','product-discovery profile-on: enabled and selected')]:
    result=subprocess.run(['python3',str(root/'dev-tools/framework-graph.py'),'--check',flag],capture_output=True,text=True)
    assert result.returncode==0, result.stderr
    assert expected in result.stdout, result.stdout
print('both profile projections checked')
