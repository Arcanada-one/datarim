# YAML Utilities

Recipes for reading YAML — including YAML frontmatter embedded in markdown.

## Extract YAML frontmatter from a markdown file

A markdown file's body breaks a whole-file YAML parse: the first `:` inside prose
(e.g. "a complex task with several subtasks:") makes `yq <file>` / `yaml.safe_load`
fail with "mapping values are not allowed in this context". Parse ONLY the
frontmatter block, between the first two `---` delimiters:

```bash
# Print frontmatter block (between the first two --- markers), then parse it.
awk '/^---$/{c++; next} c==1' file.md | yq -r '.metadata.some_key'

# Python equivalent (frontmatter-only):
python3 - file.md <<'PY'
import sys, yaml
lines, seen, body = [], 0, []
for ln in open(sys.argv[1], encoding="utf-8"):
    if ln.rstrip("\n") == "---":
        seen += 1
        continue
    if seen == 1:
        body.append(ln)
    elif seen >= 2:
        break
fm = yaml.safe_load("".join(body)) or {}
print(fm.get("metadata", {}).get("some_key"))
PY
```

**Anti-pattern:** `yq '.foo' file.md` directly on a markdown file. Works only when
the body happens not to contain a `:`-bearing line before the parser gives up —
silently returns empty or errors on the next file. Always extract the frontmatter
block first.

## Validate a standalone YAML file

```bash
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('valid')" file.yaml
```

Use `yaml.safe_load`, never `yaml.load` (the latter can execute arbitrary tags).
