# JSON

```bash
# Pretty-print
echo '{"a":1,"b":[2,3]}' | jq '.'

# Minify
echo '{ "a": 1, "b": [2, 3] }' | jq -c '.'

# Validate (returns 0 on valid, non-zero on invalid)
echo '{"a":1}' | python3 -m json.tool > /dev/null 2>&1 && echo "VALID" || echo "INVALID"

# Extract field
echo '{"name":"foo","version":"1.0"}' | jq -r '.name'

# Validate file
python3 -m json.tool < data.json > /dev/null
```
