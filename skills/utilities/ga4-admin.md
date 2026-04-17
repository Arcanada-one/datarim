# Google Analytics 4 Admin API

**Important:** gcloud default client blocks analytics scopes. Always use Arcanada CLI OAuth client (`Areas/Credentials/client_secret_336808097146-*.json`).

```bash
# Setup (one-time, in venv)
python3 -m venv /tmp/ga4-tools
/tmp/ga4-tools/bin/pip install google-auth google-auth-oauthlib requests

# Get OAuth token (opens browser)
/tmp/ga4-tools/bin/python3 -c "
from google_auth_oauthlib.flow import InstalledAppFlow
import json, os
flow = InstalledAppFlow.from_client_secrets_file(
    os.path.expanduser('~/arcanada/Areas/Credentials/client_secret_336808097146-1c9d7ebmb5pi690ahh2oikgmcbmmk5s2.apps.googleusercontent.com.json'),
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
r = requests.get('https://analyticsadmin.googleapis.com/v1beta/properties/532478786/dataStreams',
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
r = requests.post('https://analyticsadmin.googleapis.com/v1beta/properties/532478786/dataStreams',
    headers={'Authorization': f'Bearer {creds.token}','Content-Type':'application/json'},
    json={'type':'WEB_DATA_STREAM','webStreamData':{'defaultUri':'https://DOMAIN'},'displayName':'DOMAIN'})
print(json.dumps(r.json(), indent=2))
"
```

**GA4 Property:** 532478786 (Arcanada Ecosystem), Account: 390926962
