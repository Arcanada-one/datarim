#!/bin/bash
# Cloudflare + nginx setup for new domain on Arcana WWW server (49.13.52.208)
#
# Creates: DNS A/CNAME records (proxied), Origin Certificate (15 years),
# uploads cert to server, creates nginx virtual host, reloads nginx.
#
# Requires env vars:
#   CF_TOKEN  — Cloudflare API token with DNS:Edit + SSL:Edit
#   CF_ZONE   — Zone ID for the domain
#
# Usage:
#   CF_TOKEN=... CF_ZONE=... ./cloudflare-nginx-setup.sh <domain> [server_ip] [webroot_name]
#
# Examples:
#   CF_TOKEN=... CF_ZONE=... ./cloudflare-nginx-setup.sh datarim.club
#   CF_TOKEN=... CF_ZONE=... ./cloudflare-nginx-setup.sh example.com 49.13.52.208 example

set -euo pipefail

DOMAIN="${1:?Usage: $0 <domain> [server_ip] [webroot_name]}"
SERVER_IP="${2:-49.13.52.208}"
WEBROOT="${3:-$DOMAIN}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SERVER="root@${SERVER_IP}"

if [[ -z "${CF_TOKEN:-}" || -z "${CF_ZONE:-}" ]]; then
    echo "ERROR: CF_TOKEN and CF_ZONE env vars required" >&2
    exit 1
fi

CF_API="https://api.cloudflare.com/client/v4"
CF_AUTH="Authorization: Bearer ${CF_TOKEN}"
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT

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
CSR=$(cat "${TMP}/csr.pem")
python3 - "${TMP}" <<PY
import json, sys, os, urllib.request
tmp = sys.argv[1]
body = json.dumps({
    "hostnames": ["${DOMAIN}", "*.${DOMAIN}"],
    "requested_validity": 5475,
    "request_type": "origin-rsa",
    "csr": open(tmp + "/csr.pem").read()
}).encode()
req = urllib.request.Request("${CF_API}/certificates", data=body,
    headers={"Authorization": "Bearer ${CF_TOKEN}", "Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req).read())
if resp["success"]:
    open(tmp + "/cert.pem", "w").write(resp["result"]["certificate"])
    print("CERT_OK")
else:
    print("CERT_FAIL:", resp["errors"], file=sys.stderr)
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
ssh -i "${SSH_KEY}" "${SERVER}" "mkdir -p /var/www/${WEBROOT} && cat > /etc/nginx/sites-enabled/${DOMAIN}" <<NGINX
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/ssl/cloudflare/${DOMAIN}.pem;
    ssl_certificate_key /etc/ssl/cloudflare/${DOMAIN}-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/${WEBROOT};
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

ssh -i "${SSH_KEY}" "${SERVER}" "nginx -t && systemctl reload nginx"

echo ""
echo "================================================================="
echo "✓ ${DOMAIN} is live at https://${DOMAIN}/"
echo "  Webroot: /var/www/${WEBROOT}/"
echo "  Next: deploy site files via rsync, then set up GA4 + Search Console"
echo "================================================================="
