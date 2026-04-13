# Infra Cost-Reduction Checklist

Use this checklist before executing any VM/storage right-sizing or server
consolidation task. Adapted from lessons in DEV-1174 (SWC), DEV-1038 (Azure
unused disks), DEV-1087 (ae-lovable-sites memory guardrails).

---

## 1. Baseline Discovery (read-only)

- [ ] VM SKU confirmed via cloud API (`az vm list --show-details` / AWS
      `describe-instances`). **Beware constrained-core SKUs** (e.g. Azure
      `E16-8s_v3` reports 8 vCPU via `nproc` but is billed as 16).
- [ ] All attached disks mapped: `lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT`.
      Confirm which are ephemeral vs persistent (on Azure: **`/mnt` is wiped
      on deallocate/resize**).
- [ ] `free -h`, `swapon -s`, `uptime` captured. Note if swap is 0.
- [ ] Service inventory: `systemctl list-units --state=running` — identify
      long-running processes (mysqld uptime, nginx version, PHP-FPM pool).
- [ ] Config-management footprint: `grep -l "Ansible managed\|Puppet\|Chef"
      /etc/nginx/sites-*/`. **If present, find the repo BEFORE any edit —
      direct changes are silently overwritten on next run.**
- [ ] Cost-driver sizing: `du -sh` on data volumes, `SHOW DATABASES` + size
      query, count of `sites-enabled/` configs. Record in report.

## 2. Live-Traffic Diff (critical for pruning)

- [ ] Before removing ANY site/config/DB, generate a N-day live-traffic list
      (access-log mtime, CDN analytics, or traffic metrics).
- [ ] `comm -23 live.txt keep.txt` → "surprise-live" set. **Zero surprises
      expected; any non-zero result is a user-decision gate.**
- [ ] For each surprise-live entry, classify:
   - Own TLS cert (Let's Encrypt / purchased) → direct-origin traffic, cannot
     be silently dropped.
   - CDN-fronted (Cloudflare `real_ip` allow-list present) → origin HTTP,
     safer to disable.
   - Static vs dynamic (has WP/DB vs plain files).
- [ ] Produce a signed-off keep-list that covers ALL traffic-bearing domains,
      not just the original task's whitelist.

## 3. Resource Right-Sizing

- [ ] MySQL/Postgres `buffer_pool_size` vs actual RAM — an undertuned DB on a
      big VM often means the VM can shrink without tuning changes.
- [ ] Peak connection / query rate from `SHOW STATUS` / `pg_stat_activity` vs
      configured max.
- [ ] IO baseline: `iostat -x 1 30` during a representative hour. Target
      post-resize `%util < 70 %`.
- [ ] Page-cache working set: `free -h` after 24 h uptime; compare to
      proposed new RAM size (must fit hot data + 20 % headroom).

## 4. Pre-Cutover Safety

- [ ] Cloud snapshot of each persistent disk (e.g. `az snapshot create`).
      Retention: minimum 14 days post-cutover.
- [ ] Cloud backup state verified (Recovery Services Vault / AWS Backup) —
      if enabled, confirm last successful backup < 24 h old.
- [ ] Source data kept read-only-mounted for 14 days after cutover; deletion
      handled in a separate follow-up task.
- [ ] Rollback command for SKU change pre-staged with the PRIOR SKU string
      hardcoded (not looked up at rollback time).

## 5. Execution Hygiene

- [ ] Any long-running remote command (`du`, `rsync`, `mysqldump`) runs via
      `nohup` or `systemd-run --unit=...` with PID captured — **never as a
      bare SSH-background loop.** Orphan children on remote hosts waste real
      CPU for hours before being noticed.
- [ ] Kill remote processes by process group: `kill -- -$PGID`, not `kill
      $PID` of the wrapper shell.
- [ ] Every destructive step produces a log entry in `datarim/reports/` with
      timestamp + full command + exit code.
- [ ] Maintenance window announced (Cloudflare status page / internal chat)
      before any stop-service step.

## 6. Post-Cutover Validation

- [ ] Smoke-test a representative sample (≥ 20 sites) via curl, not just
      spot-checks.
- [ ] DB checksum comparison on largest N tables pre/post.
- [ ] 24-h monitoring window: RAM headroom ≥ 20 %, IO `%util < 70 %`,
      zero 5xx spike.
- [ ] Handoff of decommissioned resources to unused-resource cleanup task
      (e.g. DEV-1038) with resource IDs.

## 7. Scope Boundaries

- [ ] EOL OS / runtime upgrades explicitly OUT of scope unless added.
- [ ] DNS / CDN config changes OUT of scope unless enumerated.
- [ ] Credential rotation OUT of scope unless enumerated (but flag stale
      plaintext creds for follow-up).

---

## Red-flag patterns (auto-STOP)

Abort and ask user if you find:

- A keep-list that covers < 50 % of traffic-bearing domains.
- A data disk that is actually the Azure ephemeral `/mnt`.
- An "unused" process that is in fact the only active replica of a service.
- A resource with no owner / unclear purpose (`sdd` unmounted, orphan NIC).
- Direct-origin TLS (Let's Encrypt) on hosts you planned to set to HTTP-only.