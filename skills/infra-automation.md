---
name: infra-automation
description: SSH batch execution, ping matrices, health checks for Arcana servers. Use when performing infrastructure operations across multiple servers.
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
