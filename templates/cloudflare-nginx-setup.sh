#!/usr/bin/env bash
# Cloudflare-fronted nginx site setup template.
#
# Creates: DNS A/CNAME records (proxied), Origin Certificate (15 years),
# uploads cert to server, creates nginx virtual host, reloads nginx.
#
# Usage:
#   CF_TOKEN=... CF_ZONE=... ./cloudflare-nginx-setup.sh <DOMAIN> [SERVER_IP] [WEBROOT_NAME]
#
# Required env vars:
#   CF_TOKEN  — Cloudflare API token with DNS:Edit + SSL:Edit + Turnstile:Edit
#   CF_ZONE   — Zone ID for the domain
#
# Optional env vars:
#   SSH_KEY   — path to ssh private key (default: $HOME/.ssh/id_ed25519)
#   SERVER    — override SERVER_IP positional, full SSH target (e.g. deploy@host)
#
# Hardening (Datarim § Security Mandate, S1):
#   - All positional args validated with strict regex BEFORE any outbound call.
#   - Python embedded block uses quoted heredoc <<'PY' + os.environ — no shell
#     interpolation into Python source.
#   - SSH host-key verification relies on default StrictHostKeyChecking=ask;
#     bootstrap via `ssh-keyscan -H "$host" >> ~/.ssh/known_hosts`.
#
# Source incident: corporate audit 2026-04-28, Findings 1+2.

set -euo pipefail
IFS=$'\n\t'

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

# ---- input validation ----
[[ $# -ge 1 && $# -le 3 ]] || die "Usage: $0 <DOMAIN> [SERVER_IP] [WEBROOT_NAME]"

DOMAIN="$1"
SERVER_IP="${2:-}"
WEBROOT_NAME="${3:-$DOMAIN}"

DOMAIN_RE='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
IP_RE='^[0-9]+(\.[0-9]+){3}$'
NAME_RE='^[a-zA-Z0-9_.-]+$'

[[ "$DOMAIN"       =~ $DOMAIN_RE ]] || die "invalid domain: $DOMAIN"
[[ "$WEBROOT_NAME" =~ $NAME_RE   ]] || die "invalid webroot name: $WEBROOT_NAME"
case "$WEBROOT_NAME" in
  .|..|*..*) die "webroot name must not be '.' / '..' or contain '..': $WEBROOT_NAME" ;;
esac

if [[ -n "$SERVER_IP" ]]; then
  [[ "$SERVER_IP" =~ $IP_RE ]] || die "invalid server IP: $SERVER_IP"
fi

: "${CF_TOKEN:?CF_TOKEN env var required}"
: "${CF_ZONE:?CF_ZONE env var required}"

# Default SERVER_IP only after validation gate; allow override via SERVER env.
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SERVER_IP="${SERVER_IP:-$ARCANA_WWW_SERVER_IP}"
SERVER="${SERVER:-deploy@${SERVER_IP}}"

CF_API="https://api.cloudflare.com/client/v4"
CF_AUTH="Authorization: Bearer ${CF_TOKEN}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[1/7] Creating DNS A record: ${DOMAIN} → ${SERVER_IP}"
curl -sf -X POST "${CF_API}/zones/${CF_ZONE}/dns_records" \
    -H "${CF_AUTH}" -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${SERVER_IP}\",\"ttl\":1,\"proxied\":true}" \
    > /dev/null

echo "[2/7] Creating CNAME: www.${DOMAIN} → ${DOMAIN}"
curl -sf -X POST "${CF_API}/zones/${CF_ZONE}/dns_records" \
    -H "${CF_AUTH}" -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"www\",\"content\":\"${DOMAIN}\",\"ttl\":1,\"proxied\":true}" \
    > /dev/null

echo "[3/7] Generating CSR"
openssl req -new -newkey rsa:2048 -nodes \
    -keyout "${TMP}/key.pem" -out "${TMP}/csr.pem" \
    -subj "/CN=${DOMAIN}" 2>/dev/null

echo "[4/7] Requesting Origin Certificate (15 years)"
# Quoted heredoc terminator — no shell interpolation into Python source. Values
# pass via os.environ. (Finding 2 fix.)
DOMAIN="$DOMAIN" CF_TOKEN="$CF_TOKEN" CF_API="$CF_API" TMP="$TMP" python3 - <<'PY'
import json, os, sys, urllib.request

domain = os.environ['DOMAIN']
token  = os.environ['CF_TOKEN']
cf_api = os.environ['CF_API']
tmp    = os.environ['TMP']

with open(f'{tmp}/csr.pem') as f:
    csr = f.read()

body = json.dumps({
    'hostnames': [domain, f'*.{domain}'],
    'requested_validity': 5475,
    'request_type': 'origin-rsa',
    'csr': csr,
}).encode()
req = urllib.request.Request(
    f'{cf_api}/certificates',
    data=body,
    headers={
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json',
    },
)
resp = json.loads(urllib.request.urlopen(req).read())
if resp.get('success'):
    with open(f'{tmp}/cert.pem', 'w') as f:
        f.write(resp['result']['certificate'])
    print('CERT_OK')
else:
    print('CERT_FAIL:', resp.get('errors'), file=sys.stderr)
    sys.exit(1)
PY

echo "[5/7] Setting SSL mode to Full (Strict)"
curl -sf -X PATCH "${CF_API}/zones/${CF_ZONE}/settings/ssl" \
    -H "${CF_AUTH}" -H "Content-Type: application/json" \
    --data '{"value":"strict"}' > /dev/null

echo "[6/7] Uploading certificate to ${SERVER}"
scp -i "${SSH_KEY}" "${TMP}/cert.pem" "${SERVER}:/etc/ssl/cloudflare/${DOMAIN}.pem"
scp -i "${SSH_KEY}" "${TMP}/key.pem"  "${SERVER}:/etc/ssl/cloudflare/${DOMAIN}-key.pem"

echo "[7/7] Creating nginx vhost and reloading"
# DOMAIN and WEBROOT_NAME are passed via env to the remote shell, then re-validated
# against the same regex on the receiving end. No interpolation into the
# command string itself. (Finding 1 fix.)
ssh -i "${SSH_KEY}" \
    -o BatchMode=yes -o ConnectTimeout=5 \
    "${SERVER}" \
    DOMAIN="${DOMAIN}" WEBROOT_NAME="${WEBROOT_NAME}" \
    'bash -s' <<'REMOTE'
set -euo pipefail
DOMAIN_RE='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
NAME_RE='^[a-zA-Z0-9_.-]+$'
[[ "$DOMAIN"       =~ $DOMAIN_RE ]] || { echo "remote: bad DOMAIN" >&2; exit 2; }
[[ "$WEBROOT_NAME" =~ $NAME_RE   ]] || { echo "remote: bad WEBROOT_NAME" >&2; exit 2; }
case "$WEBROOT_NAME" in .|..|*..*) echo "remote: bad WEBROOT_NAME" >&2; exit 2 ;; esac

sudo mkdir -p "/var/www/${WEBROOT_NAME}"
sudo tee "/etc/nginx/sites-enabled/${DOMAIN}" >/dev/null <<NGINX
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/ssl/cloudflare/${DOMAIN}.pem;
    ssl_certificate_key /etc/ssl/cloudflare/${DOMAIN}-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/${WEBROOT_NAME};
    index index.php index.html;

    if (\$host = www.${DOMAIN}) { return 301 https://${DOMAIN}\$request_uri; }

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    gzip on; gzip_vary on; gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
    }

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. { deny all; }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}
NGINX

sudo nginx -t
sudo systemctl reload nginx
REMOTE

echo ""
echo "================================================================="
echo "✓ ${DOMAIN} is live at https://${DOMAIN}/"
echo "  Webroot: /var/www/${WEBROOT_NAME}/"
echo "  Next: deploy site files via rsync, then set up GA4 + Search Console"
echo "================================================================="
