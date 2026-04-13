---
name: incident-investigation
description: Production incident triage and root-cause investigation. Use when a server is under abnormal load, a service is degraded, or you need to diagnose "why is the server on fire." Enforces CPU-first triage order and standard diagnostic bundle.
model: opus
---

# Incident Investigation

Production incident investigation is a discipline, not improvisation. Follow the triage order below. Attack hypotheses come last, not first — most load is operational, not adversarial.

## Triage Order (do not skip steps)

1. **Snapshot the machine first.** Capture `uptime`, `free -h`, `df -h`, `top -bn1 | head -30`, `ps aux --sort=-%cpu | head -20` in one SSH call. Never make decisions from `top` alone — the 1/5/15-minute load averages tell you whether load is rising, peaking, or recovering.

2. **What's consuming CPU right NOW?** Identify the top 3-5 processes by `%CPU`. Group by name — is it many small workers (php-fpm, nginx) or one fat process (a collector, a daemon)?

3. **`strace` one hot process to verify legitimacy.** For worker-pool processes (php-fpm, python, node), `sudo strace -p <pid> -e trace=read,write -s 200 -t 2>&1 | head -50` shows what file/URL/query it's processing in <5 seconds. Faster than reading source code, faster than grep-ing for patterns.

4. **Check observability agents.** Grafana Alloy, Datadog, Telegraf, Prometheus node-exporter, etc. These are silent CPU thieves — they run as root, nobody watches them, and config drift can pin them at 100%+ CPU for weeks. If load is mysterious, suspect the collector.

5. **Correlate with cron.** Run `sudo crontab -l`, `sudo crontab -u www-data -l`, `sudo crontab -u root -l`. Compare schedule against the time the load started. Daily load at 03:00? It's a cron job, not an attack.

6. **Only THEN consider attack hypotheses.** Scan nginx/apache logs for request patterns (`awk '{print $1}' | sort | uniq -c | sort -rn | head -20` on access.log for top IPs; same with `$7` for top URLs). Separate reconnaissance (scanning for `/wp-admin`, random `.php`) from actual exploitation (200 responses to suspicious URLs).

## Standard Diagnostic Bundle

Consolidate into 2-3 SSH calls. Each SSH round-trip costs ~500ms; 15 calls = 7.5s wasted.

### Initial snapshot (one SSH call)

```bash
ssh user@host "uptime && echo '---MEM---' && free -h && \
  echo '---DISK---' && df -h / && \
  echo '---TOP---' && top -bn1 | head -30 && \
  echo '---PS---' && ps aux --sort=-%cpu | head -20 && \
  echo '---CONNECTIONS---' && sudo ss -tnp | grep ':80\|:443' | wc -l"
```

### Log analysis (one SSH call)

```bash
ssh user@host "sudo ls -lhS /var/log/nginx/*.access.log | head -10 && \
  echo '---TOP IPs TODAY---' && \
  sudo tail -2000 /var/log/nginx/access.log | grep \"$(date -u +%d/%b/%Y)\" | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20 && \
  echo '---TOP URLS TODAY---' && \
  sudo tail -2000 /var/log/nginx/access.log | grep \"$(date -u +%d/%b/%Y)\" | awk '{print \$7}' | sort | uniq -c | sort -rn | head -20 && \
  echo '---RECENT ERRORS---' && sudo tail -30 /var/log/nginx/error.log"
```

### Cron + config (one SSH call)

```bash
ssh user@host "sudo crontab -l 2>/dev/null; \
  sudo crontab -u www-data -l 2>/dev/null; \
  sudo crontab -u root -l 2>/dev/null; \
  echo '---PHP-FPM---' && sudo cat /etc/php/*/fpm/pool.d/www.conf 2>/dev/null | grep -E 'pm\s*=|max_children|max_requests|request_terminate_timeout'"
```

## Heuristics

- **Load > CPU count** = CPU-bound contention. Reduce worker count or offload.
- **Load rising but `%wa` > 20%** = I/O-bound. Check disk (`iotop`, `iostat`), NFS, or database.
- **Many workers stuck on the same endpoint** = that endpoint is the bottleneck. `strace` confirms.
- **`pm.max_children` >> `N × cores`** = over-provisioned pool amplifies load under contention. Target `3-4 × cores` for CPU-bound PHP workloads.
- **0 swap + high memory** = one OOM away from cascade failure. Swap is a safety net, not a performance feature.
- **Monitoring that scales with resource count** (sites, containers, DBs) = self-DDoS at scale. A health check that does a SQL query × 10,000 sites = dedicated attack on yourself.

## What NOT to Do

- **Never run destructive commands** (`kill -9`, `systemctl restart`, `iptables -F`) without explicit user approval, even when load is critical. A misfire makes incidents worse.
- **Never assume compromise from a 200 response alone.** See `security.md` § Reconnaissance vs Compromise.
- **Never rely on a single metric.** Load average without CPU% and I/O% is ambiguous. CPU% without process attribution is useless.

## Output Format

Incident investigations produce two artifacts:

1. **Raw notes** in `datarim/tasks/INCIDENT-<subject>-<date>.md` — for the forensic trail.
2. **Formal report** in `datarim/reports/incident-<subject>-<date>.md` — use the `incident-report-template.md` if available.

Both should be produced — they serve different audiences (engineers vs stakeholders).