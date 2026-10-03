# Drift-sweep scheduler templates

Ship-with templates for scheduling `dev-tools/check-site-drift-sweep.sh`
(level-3 ecosystem site-drift sweep). The sweep's canonical host is the **Mac
primary** — it reads local git working trees under `Projects/*/code/`, which
the servers do not carry (ADR-0001). These units exist for a future server
move; on the Mac, install the documented crontab line below.

## Mac primary — crontab (operator-installed; a system crontab edit is a
## hard-gated mutation, so this is never auto-applied)

```cron
# Daily at 09:15 local — Datarim ecosystem site-drift sweep.
# The script stamp-guards a 24h cadence, so re-runs within the window no-op.
15 9 * * * /Users/<you>/.claude/dev-tools/check-site-drift-sweep.sh >> "$HOME/.local/state/datarim/drift-sweep.log" 2>&1
```

Export `OPSBOT_KEY` (or set it in the cron environment) for Ops Bot heartbeats.
Missing key → the sweep fail-soft-warns and still generates backlog tasks.

## Future server move — systemd

```bash
cp drift-sweep.service drift-sweep.timer /etc/systemd/system/
# edit WorkingDirectory (KB root) + EnvironmentFile (OPSBOT_KEY) in the .service
systemctl daemon-reload && systemctl enable --now drift-sweep.timer
```

Neither unit declares `Requires=`: an idempotent periodic sweep must not be
coupled to another unit's restart cycle.
