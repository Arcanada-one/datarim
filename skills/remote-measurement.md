---
name: remote-measurement
description: Efficient remote host iteration — upload script, run once, stream results. Avoids SSH-heredoc loops that leak orphan processes on ≥50-item lists.
model: haiku
---

# Skill: Remote Measurement

**Purpose:** Measure state on remote hosts efficiently and without leaking
orphan processes. Applies whenever you need to iterate a list (domains, files,
DBs) against a remote server.

**Triggers:** Any task that would otherwise run a `for` / `while` loop inside
a single `ssh host "..."` invocation with ≥ 50 iterations.

---

## Core Principle

**Upload a script, run it once, stream results back.** Never wrap a large
per-item loop inside a bash heredoc over SSH — every item pays the SSH
parsing tax and failures leak children.

---

## Pattern (recommended)

```bash
# 1. Write the script locally (or use an existing one in documentation/).
cat > /tmp/measure.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
KEEP="${1:?keep-list required}"
OUT="${2:?output dir required}"
mkdir -p "$OUT"
while IFS= read -r d; do
  sz=$(du -sb "/var/www/$d" 2>/dev/null | awk '{print $1}')
  [ -n "$sz" ] && printf '%s\t%s\n' "$d" "$sz" >> "$OUT/bodies.tsv"
done < "$KEEP"
EOS

# 2. Ship it + inputs.
scp /tmp/measure.sh /tmp/keep-list.txt user@host:/tmp/
ssh user@host "chmod +x /tmp/measure.sh && /tmp/measure.sh /tmp/keep-list.txt /tmp/out"

# 3. Retrieve results.
scp -r user@host:/tmp/out/ /local/reports/
```

## Long-running work (>5 min)

Use `systemd-run --unit` or `nohup` with PID capture — **never a bare
background `&`** on a heredoc.

```bash
ssh host 'systemd-run --user --unit=dev1174-measure --working-directory=/tmp \
  /tmp/measure.sh /tmp/keep.txt /tmp/out'
# Poll later:
ssh host 'systemctl --user status dev1174-measure'
# Cleanup:
ssh host 'systemctl --user stop dev1174-measure || true'
```

## Killing leaked processes

If a loop got orphaned (SSH channel closed, parent shell killed but children
survived):

```bash
# Find the PID
ssh host "ps -eo pid,ppid,pgid,cmd | grep -E 'du |rsync|find' | grep -v grep"

# Kill the ENTIRE process group, not just the PID.
# The leading '-' before the PGID is critical.
ssh host "kill -TERM -- -$PGID"

# Verify it's gone (allow 2 s for TERM, then SIGKILL if needed).
sleep 2
ssh host "ps -p $PID || echo ok"
```

**Why `kill -- -$PGID` and not `kill $PID`:** killing a wrapper bash leaves its
`du`/`rsync`/`find` children running as orphans owned by init, invisible from
the caller. They may saturate IO for hours. Always target the process group.

## Anti-patterns

- ❌ `ssh host "for d in \$(cat list); do ssh deeper \"$d\"; done"` — nested
  SSH per item, 1 min handshake × N items.
- ❌ `ssh host "while read d; do curl ...; done < list" &` — backgrounded SSH
  where the local shell thinks work is done but the remote keeps running.
- ❌ `sudo -n` inside the loop without verifying sudo worked at the start —
  silent `2>/dev/null` swallows "a password is required" and returns empty.
- ❌ Measuring the entire tree and one-by-one in the same invocation (`du -sh
  /var/www/` AND `du -sb /var/www/$d` per item) — the full-tree scan reads
  the same inodes and dominates runtime.

## Recipe: live-traffic diff

```bash
# On remote:
find /var/log/nginx/ -name '*.access.log' -mtime -7 -printf '%f\n' \
  | sed 's/\.access\.log$//' | sort -u > /tmp/live.txt
comm -23 /tmp/live.txt /tmp/keep-sorted.txt > /tmp/surprise.txt
```

Log mtime is free — no grep through multi-GB logs needed.

## Recipe: DB size per item

```bash
mysql --defaults-file=/root/.my.cnf -NB -e "
  SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,1)
  FROM information_schema.tables
  WHERE table_schema LIKE 'prefix_%'
  GROUP BY table_schema" > /tmp/db-sizes.tsv
```

One query returns all DB sizes. Never loop `SELECT ... WHERE schema=$d` N times.

## Recipe: process-group cleanup on exit

```bash
# At the top of a remote script that spawns children:
trap 'kill -TERM 0' EXIT INT TERM
```

`kill 0` sends TERM to every process in the current process group, so children
die with the script.