---
name: utilities
description: Native shell recipes for common operations (date, UUID, hash, encoding, validation, JSON). Replaces external MCP dependencies. Load when you need utility operations.
model: haiku
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

---

## Datarim Sync

Synchronize framework files between `$HOME/.claude/` (active) and the Datarim repo.

```bash
# Set repo path (adjust per project)
DR_REPO="Projects/Datarim/code/datarim"

# Sync TO repo (after editing framework files locally)
for d in agents skills commands templates; do
  diff -rq "$HOME/.claude/$d/" "$DR_REPO/$d/" 2>/dev/null | grep "differ\|Only"
done
# Then copy changed files:
# cp $HOME/.claude/agents/tester.md $DR_REPO/agents/

# Sync FROM repo (after pulling repo updates)
for d in agents skills commands templates; do
  diff -rq "$DR_REPO/$d/" "$HOME/.claude/$d/" 2>/dev/null | grep "differ\|Only"
done
# Then copy changed files:
# cp $DR_REPO/skills/datarim-system.md $HOME/.claude/skills/

# Full sync TO repo (overwrite all)
for d in agents skills commands templates; do
  cp "$HOME/.claude/$d/"*.md "$DR_REPO/$d/"
done

# Full sync FROM repo (overwrite all)
for d in agents skills commands templates; do
  cp "$DR_REPO/$d/"*.md "$HOME/.claude/$d/"
done

# Verify sync (should produce no output if identical)
for d in agents skills commands templates; do
  diff -rq "$HOME/.claude/$d/" "$DR_REPO/$d/" 2>/dev/null
done
```

---

## Google Analytics 4 Admin API

**Important:** gcloud default client blocks analytics scopes. Always use Arcanada CLI OAuth client (`Areas/Credentials/client_secret_REDACTED-OAUTH-*.json`).

```bash
# Setup (one-time, in venv)
python3 -m venv /tmp/ga4-tools
/tmp/ga4-tools/bin/pip install google-auth google-auth-oauthlib requests

# Get OAuth token (opens browser)
/tmp/ga4-tools/bin/python3 -c "
from google_auth_oauthlib.flow import InstalledAppFlow
import json, os
flow = InstalledAppFlow.from_client_secrets_file(
    os.path.expanduser('~/arcanada/Areas/Credentials/client_secret_REDACTED-OAUTH-CLIENT.json'),
    ['https://www.googleapis.com/auth/analytics.edit','https://www.googleapis.com/auth/analytics.readonly'])
creds = flow.run_local_server(port=0)
with open('/tmp/ga4-token.json','w') as f: f.write(creds.to_json())
print('Token saved')
"

# List data streams
/tmp/ga4-tools/bin/python3 -c "
import json, requests
from google.oauth2.credentials import Credentials
creds = Credentials.from_authorized_user_file('/tmp/ga4-token.json')
r = requests.get('https://analyticsadmin.googleapis.com/v1beta/properties/REDACTED-GA4-PROPERTY/dataStreams',
    headers={'Authorization': f'Bearer {creds.token}'})
for s in r.json().get('dataStreams',[]):
    wd = s.get('webStreamData',{})
    print(f\"{wd.get('measurementId','N/A'):20s} {wd.get('defaultUri','')}\")
"

# Create data stream
/tmp/ga4-tools/bin/python3 -c "
import json, requests
from google.oauth2.credentials import Credentials
creds = Credentials.from_authorized_user_file('/tmp/ga4-token.json')
r = requests.post('https://analyticsadmin.googleapis.com/v1beta/properties/REDACTED-GA4-PROPERTY/dataStreams',
    headers={'Authorization': f'Bearer {creds.token}','Content-Type':'application/json'},
    json={'type':'WEB_DATA_STREAM','webStreamData':{'defaultUri':'https://DOMAIN'},'displayName':'DOMAIN'})
print(json.dumps(r.json(), indent=2))
"
```

**GA4 Property:** REDACTED-GA4-PROPERTY (Arcanada Ecosystem), Account: 390926962

---

## SSH-Deploy Scripts via Base64

**Problem:** SSH heredoc (`ssh host bash <<EOF ... EOF`) corrupts scripts that contain `jq`, `$(...)`, backticks, or escaped quotes — bash performs local expansion before transmission. Result: scripts fail on the remote host with cryptic syntax errors or act on local variables.

**Solution:** base64-encode the script locally, decode-execute remotely:

```bash
# Encode local script
CMD=$(base64 < my-script.sh | tr -d '\n')

# Execute on remote (no expansion, no escaping, handles special chars)
ssh user@host "echo '$CMD' | base64 -d | bash"

# With sudo:
ssh user@host "echo '$CMD' | base64 -d | sudo bash"

# With stdout capture:
ssh user@host "echo '$CMD' | base64 -d | bash" > local-output.log
```

**One-liner for ad-hoc commands:**
```bash
# Run a one-off command with complex quoting
CMD=$(echo 'jq -r ".[].name" data.json | sort -u' | base64)
ssh host "echo $CMD | base64 -d | bash"
```

**When to use:**
- Scripts with `jq`, `awk`, or bash special characters
- Multi-line scripts with embedded variable expansion
- Server-side automation (INFRA tasks, CI deploys, agent rollouts)

Source: INFRA-0008 reflection — heredoc approach broke on restic+B2 deploy scripts across arcana-www/prod/db. Base64 pattern resolved it universally.

---

## Recovering Runtime Files from Compacted Session Context

**When to use:** A runtime file in `$HOME/.claude/` (skill, agent, command, template) has been overwritten or deleted in the current session, and:
- No git history exists for the runtime tree (typical case).
- External backups (Time Machine, APFS snapshots, cloud sync) are unavailable or not configured.
- The lost file was previously **invoked via the Skill tool** or **read via the Read tool** earlier in the same session.

**Why this works:** when the harness loads a skill via the Skill tool, the full skill body is injected into the conversation as a `<system-reminder>` block. When the session is compacted with `/compact`, those blocks survive in the compacted summary as verbatim text. The pre-incident file content is therefore recoverable from the session's system-reminder history even after the filesystem copy is destroyed.

**Recipe:**

1. Search the current conversation's system-reminder blocks for either:
   - `### Skill: <lost-name>` followed by the full body (when skill was invoked), or
   - `Called the Read tool with the following input: {"file_path":"<path-to-lost-file>"}` followed by its Result block (when file was read).
2. Extract the body text verbatim. Strip the surrounding `<system-reminder>...</system-reminder>` wrapping; keep the inner markdown.
3. Validate the extracted content: check frontmatter opens with `---` / closes with `---`, sections are intact, no truncation markers (`... (truncated`).
4. Write back with the Write tool to `$HOME/.claude/{agents,skills,commands,templates}/<name>.md`.
5. Curate runtime → repo via selective `cp`, then `scripts/check-drift.sh` to verify in-sync state.

**Limits:**

- Only recovers files that were loaded **earlier in the same session before the incident**. Files never invoked in the session are not in the context.
- If compaction was itself more aggressive than default, some skill bodies may be summarized rather than verbatim. Check for ellipses or `[summary]` markers before trusting.
- Not a substitute for real backups — this is an emergent, opportunistic recovery path. Set up proper backup for the runtime tree (e.g. APFS snapshots or a git-tracked `~/.claude/`) for durability.

**Source:** TUNE-0011 — `install.sh --force` during TUNE-0003 /dr-archive overwrote 4 runtime files. 2 of them (`commands/dr-do.md`, `commands/dr-qa.md`) were recovered verbatim from system-reminder blocks preserved through /compact. Channel 2 of the Disaster Recovery checklist in `skills/evolution.md`.
