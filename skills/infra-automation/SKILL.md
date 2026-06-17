---
name: infra-automation
description: Infrastructure ops — SSH batch execution, health checks, network debugging, pre-migration inventory. Use for Arcana server ops.
model: inherit
current_aal: 1
target_aal: 2
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

> **Bootstrap once** (Datarim § Security Mandate S1, host-key verification):
> add the host key to `~/.ssh/known_hosts` on the operator machine before any
> batch SSH automation. Document the exact bootstrap event in
> `documentation/infrastructure/known-hosts-rotation.md`.
>
> ```bash
> for host in <HOST_LIST>; do
>   ssh-keyscan -H "$host" >> ~/.ssh/known_hosts
> done
> ```

**Mesh-health pre-check.** Before running a fleet sweep or batch command, verify
Tailscale reachability for each node. Unreachable nodes fall back to public IP or
are deferred — never silently skipped without a log entry:

```bash
for host in <MESH_IP_LIST>; do
  if ping -c1 -W2 "$host" >/dev/null 2>&1; then
    echo "mesh-ok: $host"
  else
    echo "mesh-unreachable: $host — falling back to public IP or deferring" >&2
  fi
done
```

Record the reachability result in the sweep log before proceeding.

Run a command on all (or selected) servers (relies on default
`StrictHostKeyChecking=ask` — bootstrap above pre-populates `known_hosts` so the
prompt never fires; an unknown host fails fast in batch mode):

```bash
# nosec-extract
for host in <HOST_LIST>; do
  echo "=== $host ==="
  ssh -o BatchMode=yes -o ConnectTimeout=5 "deploy@$host" "<COMMAND>" 2>&1 | head -20
done
```

**Flags:** `-o BatchMode=yes` disables interactive prompts (fails fast on
unknown host or missing key). `-o ConnectTimeout=5` prevents hanging on
unreachable hosts. Use `deploy@` user with narrow `sudo` rules; reserve `root@`
for one-shot bootstrap with a logged EOL date.

<!-- security:counter-example -->
# UNSAFE — bypasses host-key verification, never use in shipped recipes:
ssh -o StrictHostKeyChecking=no -o BatchMode=yes "$host" "<COMMAND>"
<!-- /security:counter-example -->

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
6. **Live-label probe before authoring runbooks** — any runbook or handoff document that references OS-managed service labels (launchd/systemd) MUST inline labels verified by a live probe at authoring time (`launchctl list | grep -i <service>` / `systemctl list-units | grep <service>`), never placeholders or from-memory labels. A mismatched label turns a one-command cutover into a debugging session.

---

## Network-First Debugging

When a site or endpoint is "not working", investigate in this order BEFORE touching app-layer config:

1. **DNS resolution:** `dig <domain>`, `dig <domain> CNAME`, `dig NS <domain>`
2. **Reachability:** `curl -sI --connect-timeout 10 http://<resolved-ip>/`, `ping -c 3 <ip>`
3. **Origin-side:** `curl -sI -H "Host: <domain>" http://127.0.0.1/`
4. **Only then** investigate app layer (SSL, web server config, file permissions, app logs)

**Red herrings:** expired SSL cert (irrelevant if DNS points elsewhere), web server config (irrelevant if requests don't reach server), file permissions (check only after confirming requests arrive).

## CDN-Proxied Origin Discrimination

Before removing a suspected-stale copy of a web origin that sits behind a CDN proxy (Cloudflare-style "orange cloud"), a naive DNS pre-check is invalid: `dig A <domain>` returns the CDN's anycast IPs, never the origin, so it cannot prove which server actually serves traffic.

Prove the live origin by querying each candidate server directly with the production Host header and comparing response bodies:

```bash
for ip in <candidate-ip-1> <candidate-ip-2>; do
  echo "== $ip"
  curl -s --resolve <domain>:443:$ip https://<domain>/ -o /tmp/body-$ip --write-out '%{http_code} %{size_download}\n'
done
# Compare /tmp/body-* against the public CDN response (curl -s https://<domain>/ | wc -c)
```

The candidate whose body matches the public CDN response byte-for-byte (or by size) is the real origin; a candidate returning a default web-server placeholder page is a dead copy and safe to remove. Body size is a reliable first discriminator (e.g. real site 40 KB vs default page 600 B); confirm with content diff when sizes are close. After removal, re-check the public domain end-to-end.

## Backup-Tool Secret Handling

Never pass a backup-repository password as an inline environment assignment on the command line — `SOMETOOL_PASSWORD=value sometool ...` lands verbatim in shell history and journald the moment the unit/exec is logged. Use a password file instead:

```bash
# Correct: secret never transits the command line
export RESTIC_PASSWORD_FILE=/root/.restic-env   # file mode 0600 root:root
restic -r <repo> snapshots

# Incorrect: secret recoverable from journald/history
RESTIC_PASSWORD="secretvalue" restic -r <repo> snapshots
```

If a secret did transit a logged command line, treat it as exposed: record the incident and schedule rotation (`restic key passwd`, or the tool's equivalent).

## Decommission Data-Inventory Rule

When a host is being decommissioned, every non-empty dataset on it (databases, file stores, dashboards, configs) is a migration candidate **by default**. Excluding anything requires an explicit operator decision with a recorded reason (empty schema, intentional size-based skip). Enumerate from the engines themselves (`listDatabases`, `\l`, du over data dirs) — never from the consumer configs you already know about: known consumers see only part of the data, and after teardown there is no way back.

## IP-Scanning Script Test Matrix

Any script that greps config surfaces for an IP address MUST cover, in its
test suite, every common form the address takes — missing one creates a
silent false-negative path. At minimum: (1) key-value `ip: <IP>` /
`address: <IP>`, (2) bare YAML list item `  - <IP>` (common in
`cluster_hosts:`, `allowed_ips:` inventories), (3) connection string
`host=<IP>` / DSN, (4) URI scheme `scheme://<IP>`, and (5) `<IP>:<port>`.
The bare-list form (2) is the one most often forgotten because it carries no
key to anchor the pattern on.

## Acceptance-Criterion Authoring (infra)

When a success criterion is verified by a shell command, record TWO fields, not one: the state-of-system intent ("no active connection strings reference host X") and the verification command (`grep -rE 'X' <files>` + expected exit code). A literal command alone is brittle — commented-out lines, renamed files, or unrelated matches flip its exit code while the intent stays satisfied. The intent field is what QA judges; the command is one way to check it.

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

---

## Tracked Deploy Artefact Rule

Any script, config, systemd unit, or shell wrapper installed under a production path (e.g. `/usr/local/bin/`, `/etc/systemd/system/`, container image layer) AND referenced downstream as a verification surface — a task's acceptance criterion runs it, a verdict gate executes it, a smoke test invokes it — MUST be tracked in the framework or project repository before the referencing acceptance criterion ships.

**Rationale.** An untracked operator-authored artefact has no diff history, no review trail, and no code-review gate. Drift propagates invisibly: a verdict gate written against the artefact's expected behaviour can pass at design time and silently mismeasure later because the on-server artefact diverged from the operator's mental model. Tracking the artefact in a repository provides four anchors:

1. **Source-of-truth diff** — version-control history shows every change to the artefact since deploy time.
2. **Review gate** — the canonical surface goes through whatever quality gates the repo enforces (lint, tests, stack-agnostic checks).
3. **Re-deploy reproducibility** — disaster recovery installs the tracked source via the project's standard deploy channel (`scp` / install script / CI deploy), not by reconstructing intent from server state.
4. **Acceptance criterion grounding** — the AC text can cite the tracked path (e.g. `dev-tools/<artefact>`) and any reader can resolve what the AC means by reading the canonical source.

**Rule.** Before any acceptance criterion ships that references an on-server operator-authored artefact, add the canonical version of the artefact to the repository, mark the deploy path in a deploy comment or install script, and cite the tracked path (not the on-server path) in the AC text.

**When to apply.** L2+ tasks where the deliverable includes both new on-server tooling AND a verdict gate / acceptance criterion that consumes that tooling. Skip for one-shot artefacts with no downstream verification consumer.

## Compose Deploy Race Pattern

When a CI deploy job uses `docker compose up -d --build` against services declaring `restart: unless-stopped`, prepend an explicit teardown:

<!-- gate:example-only -->
```bash
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.codex.yml"
$COMPOSE down --remove-orphans || true
$COMPOSE up -d --build
```
<!-- /gate:example-only -->

**Why.** `up -d --build` allocates a container name before the previous instance fully transitions to a clean stopped state. After a healthcheck or `start_period` tightening, the previous container may still hold the name when the new one tries to claim it — the deploy job fails with «Container `<project>-<service>-1` already in use». The cleanup is idempotent on cold-start (`|| true` handles the empty-state case) and named volumes survive (`down` without `-v` does not touch them). The orphan removal is defensive against future drift where a service is removed from the compose file.

**Blast radius.** `--remove-orphans` only touches containers owned by the current compose project; foreign containers from other compose projects are untouched, even when they share networks.

**Smoke gate.** After applying, the deploy job must verify named-volume preservation (`docker volume ls | grep -E '<known-volume-names>' | wc -l` matches the expected count) before declaring the deploy clean.

**Anti-pattern.** Targeted `docker rm -f <container-name>` per service — duplicated work for multi-service compose projects and brittle against future service additions.

## Reusable Templates

- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-cost-reduction-checklist.md` — pre-execution checklist for any VM/storage right-sizing, server consolidation, or unused-resource cleanup task. Distilled from prior infra cost-reduction tasks (SWC, Azure unused disks, memory guardrails). Use during `/dr-plan` when the task touches infrastructure costs.
- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-artifact-checklist.md` — local-artifact + commit + checkpoint + operator-remote-execution flow for infra deliverables that the operator runs on production. Use when the task ships scripts/configs operators will execute, not code we deploy via CI.
