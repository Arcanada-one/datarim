---
name: infrastructure-debugging
description: Network-first debugging for unreachable services and pre-migration service inventory. Use when a site/endpoint is down, or before any server migration.
---

# Infrastructure Debugging

## Network-First Debugging for Unreachable Services

When a site or endpoint is reported "not working", investigate in this order
BEFORE touching application-layer configuration (SSL certs, web server,
file permissions, application code). Most "broken app" reports are actually
network/DNS issues.

### Step 1 — DNS resolution
```bash
dig <domain>            # Does it resolve? To what IP?
dig <domain> CNAME      # Is it aliased? Where does the chain end?
dig NS <domain>         # Who owns the DNS zone? (Cloudflare, GoDaddy, Route53, Azure DNS)
```

Check:
- Does the domain resolve at all?
- Is the target IP the server you expect?
- If CNAME, follow the chain to the final A record.
- Identify the DNS provider — you need access credentials to change records.

### Step 2 — Reachability of resolved IP
```bash
curl -sI --connect-timeout 10 http://<resolved-ip>/
curl -sI --connect-timeout 10 https://<resolved-ip>/
ping -c 3 <resolved-ip>
```

If HTTP 000 / timeout: the target IP is dead, firewalled, or wrong.
Stop debugging the application — the problem is upstream.

### Step 3 — Origin-side sanity check
On the actual server, test from localhost with explicit Host header:
```bash
curl -sI -H "Host: <domain>" http://127.0.0.1/
curl -sk --resolve "<domain>:443:127.0.0.1" https://<domain>/
```

If origin returns HTTP 200 but external fails: confirmed network/DNS
problem, not application.

### Step 4 — Only now investigate app layer
- SSL cert validity and SAN coverage
- Web server config (virtual host, routing, try_files)
- File permissions and ownership
- Application logs and error messages

### Common Red Herrings

- **Expired SSL cert** — noisy in logs but irrelevant if DNS points elsewhere.
- **Web server config mismatch** — matters only if the origin is actually receiving requests.
- **File permissions** — check only after confirming requests reach the server.

---

## Pre-Migration Service Inventory

Before migrating a server, enumerate ALL services it hosts — not just the
primary workload. Undiscovered services cause outages during cutover.

### Inventory Sources

1. **Web server configs**
   - List all server blocks: `ls /etc/nginx/sites-enabled/`
   - Extract every `server_name`: `grep -r "server_name" /etc/nginx/`
   - Note per-site `root`, `ssl_certificate`, special locations (`/app/`, `/api/`)

2. **TLS certificates**
   - `sudo certbot certificates` or `ls /etc/letsencrypt/live/`
   - Each cert = a publicly-reachable endpoint = a migration concern

3. **DNS records pointing to the server IP**
   - Ask DNS provider for all A/CNAME records targeting the server IP
   - For multi-provider DNS: check each provider separately

4. **Active listeners**
   - `ss -tlnp` — all open TCP ports and owning processes
   - `systemctl list-units --type=service --state=running` — managed services

5. **Cron jobs and background workers**
   - `sudo crontab -l` (per user), `/etc/cron.d/`, `/etc/cron.*`
   - systemd timers: `systemctl list-timers`

6. **Outgoing scheduled connections**
   - Webhooks, monitoring endpoints, cert renewal cron
   - Backup jobs writing to external targets

### Inventory Output

For each discovered service, document:
- Domain(s) served
- Document root / working directory
- Certificate source (LE, Cloudflare Origin, self-signed)
- Dependencies (database, external API, shared storage)
- Ownership — who uses this service, who should be notified

Missing any one of these during planning is a likely cause of migration-day
surprises.

---

## Migration Config Edits — Always Backup and Diff

Before editing any web-server or service config during migration:

1. Copy to timestamped backup: `cp config.conf config.conf.backup.$(date +%Y%m%d_%H%M%S)`
2. Edit the live file
3. `diff config.conf.backup.* config.conf` — sanity check the change
4. Validate syntax: `nginx -t`, `apachectl configtest`, etc.
5. Reload, not restart, if the service supports it
6. Verify with curl before closing the session

Never edit a live config without a backup. Rollback requires it.