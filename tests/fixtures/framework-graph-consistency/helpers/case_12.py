import pathlib,sys
path=pathlib.Path(sys.argv[1])
text=path.read_text()
assert 'categories: [skills, templates]' in text
path.write_text(text.replace('categories: [skills, templates]', 'categories: [skills, templates, scripts]'))
