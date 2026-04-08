---
name: utilities
description: Native shell recipes for common operations (date, UUID, hash, encoding, validation, JSON). Replaces external MCP dependencies. Load when you need utility operations.
---

# Native Shell Utilities

> **Usage rule:** Agent picks the appropriate one-liner from this skill instead of depending on external MCP servers. All recipes use tools available on macOS and Linux by default (bash, python3, openssl, jq).

---

## Date & Time

```bash
# Current date (ISO)
date +%Y-%m-%d

# Current datetime UTC (ISO 8601)
date -u +%Y-%m-%dT%H:%M:%SZ

# Current epoch timestamp
date +%s

# Epoch to human-readable
# macOS:
date -r 1700000000 +%Y-%m-%dT%H:%M:%SZ
# Linux:
date -d @1700000000 +%Y-%m-%dT%H:%M:%SZ

# Timezone conversion
TZ="America/New_York" date +%Y-%m-%dT%H:%M:%S%z
TZ="Europe/London" date +%Y-%m-%dT%H:%M:%S%z
TZ="Asia/Tokyo" date +%Y-%m-%dT%H:%M:%S%z

# Date arithmetic (macOS)
date -v+7d +%Y-%m-%d    # 7 days from now
date -v-1m +%Y-%m-%d    # 1 month ago

# Date arithmetic (Linux)
date -d "+7 days" +%Y-%m-%d
date -d "-1 month" +%Y-%m-%d
```

---

## OS Info

```bash
# Full system info
uname -a

# macOS version
sw_vers

# Linux distribution
lsb_release -a 2>/dev/null || cat /etc/os-release

# Current user
whoami

# Hostname
hostname

# Architecture
uname -m
```

---

## Math

```bash
# Python3 (arbitrary precision, float support)
python3 -c "print(2 ** 256)"
python3 -c "print(round(3.14159 * 100, 2))"
python3 -c "import math; print(math.sqrt(144))"

# bc (pipe expressions)
echo "scale=10; 22/7" | bc -l
echo "2^64" | bc
```

---

## Hashing

```bash
# SHA-256
echo -n "data" | openssl dgst -sha256
openssl dgst -sha256 filename.txt

# SHA-512
echo -n "data" | openssl dgst -sha512

# MD5 (not for security, only checksums)
echo -n "data" | openssl dgst -md5

# File checksum (SHA-256)
# macOS:
shasum -a 256 filename.txt
# Linux:
sha256sum filename.txt
```

---

## Random & UUID

```bash
# UUID v4
uuidgen
# Lowercase UUID (macOS uuidgen outputs uppercase)
uuidgen | tr '[:upper:]' '[:lower:]'

# Random hex string (16 bytes = 32 hex chars)
openssl rand -hex 16

# Random base64 string (32 bytes)
openssl rand -base64 32

# Random integer in range [0, N)
python3 -c "import secrets; print(secrets.randbelow(1000))"
```

---

## Base64

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

---

## Text Case Conversion

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

---

## Validation

```bash
# Validate email
python3 -c "
import re, sys
email = sys.argv[1]
ok = bool(re.match(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$', email))
print('VALID' if ok else 'INVALID')
" "user@example.com"

# Validate URL
python3 -c "
import re, sys
url = sys.argv[1]
ok = bool(re.match(r'^https?://[^\s/$.?#].[^\s]*$', url))
print('VALID' if ok else 'INVALID')
" "https://example.com"

# Validate IPv4
python3 -c "
import re, sys
ip = sys.argv[1]
ok = bool(re.match(r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$', ip))
print('VALID' if ok else 'INVALID')
" "192.168.1.1"

# Validate UUID
python3 -c "
import re, sys
uid = sys.argv[1]
ok = bool(re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', uid, re.I))
print('VALID' if ok else 'INVALID')
" "550e8400-e29b-41d4-a716-446655440000"
```

---

## JSON

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

---

## Password Generation

```bash
# 20-char alphanumeric password
openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | head -c 20

# 32-char with special characters
openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c 32

# Passphrase (4 random words — requires a wordlist or python)
python3 -c "
import secrets
words = ['alpha','bravo','charlie','delta','echo','foxtrot','golf','hotel',
         'india','juliet','kilo','lima','mike','november','oscar','papa',
         'quebec','romeo','sierra','tango','uniform','victor','whiskey','xray']
print('-'.join(secrets.choice(words) for _ in range(4)))
"
```

---

## Byte Humanization

```bash
# Humanize bytes
python3 -c "
def humanize(b):
    for u in ['B','KB','MB','GB','TB','PB']:
        if b < 1024: return f'{b:.1f} {u}'
        b /= 1024
import sys; print(humanize(int(sys.argv[1])))
" 1073741824
# Output: 1.0 GB
```

---

## Number Formatting

```bash
# Thousands separator
python3 -c "print(f'{1234567890:,}')"
# Output: 1,234,567,890

# Currency (USD)
python3 -c "print(f'${1234567.89:,.2f}')"
# Output: $1,234,567.89

# Percentage
python3 -c "print(f'{0.8567:.1%}')"
# Output: 85.7%
```

---

## Color Conversion

```bash
# Hex to RGB
python3 -c "
h = 'FF5733'
print(f'rgb({int(h[0:2],16)}, {int(h[2:4],16)}, {int(h[4:6],16)})')
"

# RGB to Hex
python3 -c "print(f'#{255:02X}{87:02X}{51:02X}')"

# Hex to HSL
python3 -c "
import colorsys
h = 'FF5733'
r,g,b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
hue,l,s = colorsys.rgb_to_hls(r,g,b)
print(f'hsl({hue*360:.0f}, {s*100:.0f}%, {l*100:.0f}%)')
"

# HSL to Hex
python3 -c "
import colorsys
r,g,b = colorsys.hls_to_rgb(11/360, 0.60, 1.0)
print(f'#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}')
"
```

---

## Timezone Conversion

```bash
# Convert between timezones
python3 -c "
from datetime import datetime
from zoneinfo import ZoneInfo
dt = datetime.now(ZoneInfo('America/New_York'))
print('NYC:', dt.strftime('%Y-%m-%d %H:%M:%S %Z'))
print('UTC:', dt.astimezone(ZoneInfo('UTC')).strftime('%Y-%m-%d %H:%M:%S %Z'))
print('Tokyo:', dt.astimezone(ZoneInfo('Asia/Tokyo')).strftime('%Y-%m-%d %H:%M:%S %Z'))
"

# List available timezones
python3 -c "from zoneinfo import available_timezones; print('\n'.join(sorted(available_timezones())))" | head -20
```

**Note:** `zoneinfo` requires Python 3.9+. For older Python, use `pytz`.
