# Text Case Conversion

```bash
# camelCase
python3 -c "s='hello world example'; parts=s.split(); print(parts[0].lower()+''.join(w.capitalize() for w in parts[1:]))"

# PascalCase
python3 -c "s='hello world example'; print(''.join(w.capitalize() for w in s.split()))"

# snake_case
python3 -c "s='Hello World Example'; print('_'.join(w.lower() for w in s.split()))"

# kebab-case
python3 -c "s='Hello World Example'; print('-'.join(w.lower() for w in s.split()))"

# CONSTANT_CASE
python3 -c "s='Hello World Example'; print('_'.join(w.upper() for w in s.split()))"

# CamelCase to snake_case (from existing identifier)
python3 -c "import re; print(re.sub(r'(?<!^)(?=[A-Z])', '_', 'myVariableName').lower())"
```

---

## Slug Generation

```bash
# URL-safe slug from text
echo "Hello, World! This is a Test 123" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//'

# Python version (handles unicode)
python3 -c "
import re, unicodedata
s = 'Hello, World! This is a Test'
s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()
print(re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-'))
"
```
