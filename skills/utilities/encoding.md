# Base64

```bash
# Encode
echo -n "hello world" | base64

# Decode
# macOS:
echo "aGVsbG8gd29ybGQ=" | base64 -D
# Linux:
echo "aGVsbG8gd29ybGQ=" | base64 --decode

# Encode file
base64 < input.bin > output.b64

# Decode file
# macOS:
base64 -D < input.b64 > output.bin
# Linux:
base64 --decode < input.b64 > output.bin
```

**Cross-platform note:** macOS uses `-D` for decode, Linux uses `-d` or `--decode`.

---

## URL Encoding

```bash
# Encode
python3 -c "from urllib.parse import quote; print(quote('hello world & foo=bar'))"

# Encode (full, including slashes)
python3 -c "from urllib.parse import quote; print(quote('https://example.com/path?q=a b', safe=''))"

# Decode
python3 -c "from urllib.parse import unquote; print(unquote('hello%20world%20%26%20foo%3Dbar'))"
```
