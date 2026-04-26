---
name: infra-automation
description: Infrastructure ops — SSH batch execution, health checks, network debugging, pre-migration inventory. Use for Arcana server ops.
model: sonnet
---

# Infrastructure Automation

Reusable patterns for SSH-based operations across Arcana servers.

## Server Inventory

| Name | Public IP | Tailscale IP | SSH |
|------|-----------|-------------|-----|
| Arcana WWW | 49.13.52.208 | 100.78.174.28 | `ssh root@49.13.52.208` |
| Arcana PROD | 65.108.236.39 | 100.121.155.54 | `ssh root@65.108.236.39` |
| Arcana DB | 135.181.222.38 | 100.70.137.104 | `ssh root@135.181.222.38` |
| Arcana Trading | 37.27.107.227 | 100.90.7.20 | `ssh root@37.27.107.227` |

> Always verify current IPs against `memory/reference_arcana_www_server.md` before use.

## SSH Batch Execute

Run a command on all (or selected) servers:

```bash
for host in 49.13.52.208 65.108.236.39 135.181.222.38 37.27.107.227; do
  echo "=== $host ==="
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 root@$host "<COMMAND>" 2>&1 | head -20
done
```

**Flags:** `-o BatchMode=yes` prevents interactive prompts (fails fast if key not accepted). `-o ConnectTimeout=5` prevents hanging on unreachable hosts.

## Ping Matrix (Tailscale)

Test NxN connectivity across all devices in mesh:

```bash
declare -A TSIP=([www]=100.78.174.28 [prod]=100.121.155.54 [db]=100.70.137.104 [trading]=100.90.7.20)
declare -A PUBIP=([www]=49.13.52.208 [prod]=65.108.236.39 [db]=135.181.222.38 [trading]=37.27.107.227)

for SRC in www prod db trading; do
  printf "%-10s" "$SRC"
  for DST in www prod db trading; do
    [ "$SRC" = "$DST" ] && { printf "%-14s" "—"; continue; }
    LAT=$(ssh -o BatchMode=yes root@${PUBIP[$SRC]} \
      "ping -c 2 -W 3 ${TSIP[$DST]} 2>/dev/null | awk -F'/' '/min\/avg/{print \$5}'" 2>/dev/null)
    [ -n "$LAT" ] && printf "%-14s" "✅ ${LAT}ms" || printf "%-14s" "❌"
  done; echo
done
```

## Health Check (HTTP services)

Check all PROD services:

```bash
for svc in "3400 support" "3500 muneral" "3600 opsbot"; do
  port=$(echo $svc | cut -d' ' -f1)
  name=$(echo $svc | cut -d' ' -f2)
  STATUS=$(ssh root@65.108.236.39 "curl -sf -o /dev/null -w '%{http_code}' http://localhost:$port/health" 2>/dev/null)
  echo "$name (:$port): ${STATUS:-UNREACHABLE}"
done
```

## Common Operations

```bash
# Docker service status on PROD
ssh root@65.108.236.39 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Tailscale status on all servers
for host in 49.13.52.208 65.108.236.39 135.181.222.38 37.27.107.227; do
  echo "=== $host ==="; ssh root@$host "tailscale status" 2>&1 | head -8
done

# Disk usage on all servers
for host in 49.13.52.208 65.108.236.39 135.181.222.38 37.27.107.227; do
  echo "=== $host ==="; ssh root@$host "df -h / | tail -1"
done

# Check nginx configs
ssh root@49.13.52.208 "nginx -t" 2>&1
ssh root@65.108.236.39 "nginx -t" 2>&1
```

## Safety Rules

1. **Never run destructive commands** (rm -rf, DROP DATABASE, etc.) via batch — always one server at a time with explicit confirmation.
2. **Always use `-o BatchMode=yes`** — prevents password prompts from hanging automation.
3. **Verify command on one server first** before running batch across all.
4. **Keep SSH sessions short** — run command and exit, don't keep persistent sessions.
5. **Log operations** — pipe output to file for audit trail when making changes.

---

## Network-First Debugging

When a site or endpoint is "not working", investigate in this order BEFORE touching app-layer config:

1. **DNS resolution:** `dig <domain>`, `dig <domain> CNAME`, `dig NS <domain>`
2. **Reachability:** `curl -sI --connect-timeout 10 http://<resolved-ip>/`, `ping -c 3 <ip>`
3. **Origin-side:** `curl -sI -H "Host: <domain>" http://127.0.0.1/`
4. **Only then** investigate app layer (SSL, web server config, file permissions, app logs)

**Red herrings:** expired SSL cert (irrelevant if DNS points elsewhere), web server config (irrelevant if requests don't reach server), file permissions (check only after confirming requests arrive).

## Pre-Migration Service Inventory

Before migrating a server, enumerate ALL services:
1. Web server configs: `grep -r "server_name" /etc/nginx/`
2. TLS certificates: `sudo certbot certificates`
3. DNS records pointing to server IP
4. Active listeners: `ss -tlnp`
5. Cron jobs: `sudo crontab -l`, `/etc/cron.d/`, `systemctl list-timers`
6. Outgoing connections: webhooks, monitoring, backups

**Migration config edits:** always backup → edit → diff → validate syntax → reload (not restart) → verify with curl.

---

## Remote Measurement

**Core principle:** Upload a script, run it once, stream results back. Never wrap a large per-item loop inside an SSH heredoc — every item pays the SSH parsing tax and failures leak children.

```bash
cat > /tmp/measure.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
while IFS= read -r d; do
  sz=$(du -sb "/var/www/$d" 2>/dev/null | awk '{print $1}')
  [ -n "$sz" ] && printf '%s\t%s\n' "$d" "$sz" >> "$2/bodies.tsv"
done < "$1"
EOS
scp /tmp/measure.sh /tmp/list.txt user@host:/tmp/
ssh user@host "chmod +x /tmp/measure.sh && /tmp/measure.sh /tmp/list.txt /tmp/out"
scp -r user@host:/tmp/out/ /local/reports/
```

**Long-running (>5 min):** use `systemd-run --unit` or `nohup`, never bare `&`.

**Killing leaked processes:** target the process group: `kill -TERM -- -$PGID` (not just PID).

**Anti-patterns:** nested SSH per item, backgrounded SSH loops, `sudo -n` without pre-check.

## Reusable Templates

- `templates/infra-cost-reduction-checklist.md` — pre-execution checklist for any VM/storage right-sizing, server consolidation, or unused-resource cleanup task. Distilled from DEV-1174 (SWC), DEV-1038 (Azure unused disks), DEV-1087 (memory guardrails). Use during `/dr-plan` when the task touches infrastructure costs.
- `templates/infra-artifact-checklist.md` — local-artifact + commit + checkpoint + operator-remote-execution flow for infra deliverables that the operator runs on production. Use when the task ships scripts/configs operators will execute, not code we deploy via CI.
