# Google Analytics 4 Admin API

**Important:** gcloud default client blocks analytics scopes. Always use a dedicated OAuth Desktop client with `analytics.edit + analytics.readonly` scopes. Reference the secret file generically; never name the client in shipped recipes.

```bash
# Prerequisites
# 1. Create an OAuth 2.0 Client (Desktop type) in Google Cloud Console.
# 2. Save the JSON to ${PROJECT_CREDS_DIR:-$HOME/.config/datarim}/client_secret_<id>.json (mode 0600).
# 3. Export the property ID for your GA4 account:
#    export GA4_PROPERTY_ID=<your-ga4-property-id>

# Setup (one-time, in venv off /tmp)
GA4_VENV="${GA4_VENV:-$HOME/.cache/ga4-tools}"
python3 -m venv "$GA4_VENV"
"$GA4_VENV/bin/pip" install google-auth google-auth-oauthlib requests

# Get OAuth token (opens browser); writes refresh token atomically to XDG_STATE_HOME with mode 0600.
"$GA4_VENV/bin/python3" - <<'PY'
import os, glob
from google_auth_oauthlib.flow import InstalledAppFlow

creds_dir = os.environ.get('PROJECT_CREDS_DIR', os.path.expanduser('~/.config/datarim'))
matches = glob.glob(os.path.join(creds_dir, 'client_secret_*.json'))
if not matches:
    raise SystemExit(f'no client_secret_*.json found in {creds_dir}')
client_file = matches[0]

flow = InstalledAppFlow.from_client_secrets_file(
    client_file,
    ['https://www.googleapis.com/auth/analytics.edit',
     'https://www.googleapis.com/auth/analytics.readonly'])
creds = flow.run_local_server(port=0)

state_dir = os.path.expanduser('~/.local/state/datarim')
os.makedirs(state_dir, mode=0o700, exist_ok=True)
token_path = os.path.join(state_dir, 'ga4-token.json')
# Atomic write with mode 0600, no symlink follow (Security Mandate S2 rule 2).
try:
    os.unlink(token_path)
except FileNotFoundError:
    pass
fd = os.open(token_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write(creds.to_json())
print(f'Token saved to {token_path}')
PY

# List data streams
GA4_PROPERTY_ID="${GA4_PROPERTY_ID:?set GA4_PROPERTY_ID first}" \
"$GA4_VENV/bin/python3" - <<'PY'
import os, requests
from google.oauth2.credentials import Credentials
token_path = os.path.expanduser('~/.local/state/datarim/ga4-token.json')
creds = Credentials.from_authorized_user_file(token_path)
prop = os.environ['GA4_PROPERTY_ID']
r = requests.get(f'https://analyticsadmin.googleapis.com/v1beta/properties/{prop}/dataStreams',
    headers={'Authorization': f'Bearer {creds.token}'})
for s in r.json().get('dataStreams', []):
    wd = s.get('webStreamData', {})
    print(f"{wd.get('measurementId','N/A'):20s} {wd.get('defaultUri','')}")
PY

# Create data stream
GA4_PROPERTY_ID="${GA4_PROPERTY_ID:?set GA4_PROPERTY_ID first}" \
DOMAIN="${DOMAIN:?set DOMAIN first}" \
"$GA4_VENV/bin/python3" - <<'PY'
import os, json, requests
from google.oauth2.credentials import Credentials
token_path = os.path.expanduser('~/.local/state/datarim/ga4-token.json')
creds = Credentials.from_authorized_user_file(token_path)
prop = os.environ['GA4_PROPERTY_ID']
domain = os.environ['DOMAIN']
r = requests.post(f'https://analyticsadmin.googleapis.com/v1beta/properties/{prop}/dataStreams',
    headers={'Authorization': f'Bearer {creds.token}', 'Content-Type': 'application/json'},
    json={'type': 'WEB_DATA_STREAM',
          'webStreamData': {'defaultUri': f'https://{domain}'},
          'displayName': domain})
print(json.dumps(r.json(), indent=2))
PY
```

**Security notes:**
- Refresh token lives at `~/.local/state/datarim/ga4-token.json` (XDG_STATE_HOME), mode 0600, written via `O_EXCL` (Security Mandate S2 rule 2).
- Heredocs are quoted (`<<'PY'`); dynamic values pass via env vars (Security Mandate S1 rule 4-5).
- `client_secret_*.json` glob — never name the OAuth Client ID in recipes (Security Mandate S3 rule 1-2).
- Property ID, domain, and credentials directory are env-driven; no tenant identifiers in shipped artifact.
