# dr-orchestrate-server supervision units

Ship-with templates that replace the foreground `dr_orchestrate_server.sh
start &` invocation documented in `cli/tests/e2e-live-tmux.md` § Smoke
procedure (Phase G) with a supervised, restart-with-backoff service — for
production/long-running use, not for one-off local smoke runs (the runbook's
`&` form remains correct for that).

Neither file is installed or enabled by this change — both are authored
tooling. Installing/enabling a supervision unit on a real host is an
operator action.

## Linux — systemd

```bash
cp dr-orchestrate-server.service /etc/systemd/system/
# edit WorkingDirectory + ExecStart to the actual plugin install path
systemctl daemon-reload && systemctl enable --now dr-orchestrate-server
```

- `Restart=on-failure` + `RestartSec=5`: a crash relaunches after a fixed
  5s delay; a clean `systemctl stop` does NOT relaunch.
- `StartLimitIntervalSec=300` + `StartLimitBurst=5`: caps retries at 5 within
  a rolling 5-minute window — a persistently-crashing process stops
  restart-looping and the unit is marked `failed` (`systemctl reset-failed`
  + `start` to retry manually after investigating).
- systemd ≥ 254 additionally supports true exponential backoff via
  `RestartSteps=` / `RestartMaxDelaySec=` — add both under `[Service]` if the
  target host's systemd is new enough (`systemctl --version`).

Verify: `systemctl status dr-orchestrate-server`; a `kill -TERM` on the main
PID should stop the process cleanly (no relaunch — `systemctl stop` marks the
unit inactive before signalling); a `kill -KILL` crash SHOULD trigger the
RestartSec-delayed relaunch.

## macOS — launchd

```bash
cp com.arcanada.dr-orchestrate-server.plist ~/Library/LaunchAgents/
# edit WorkingDirectory + the two ProgramArguments paths to the actual
# plugin install path
launchctl load -w ~/Library/LaunchAgents/com.arcanada.dr-orchestrate-server.plist
```

- `KeepAlive.SuccessfulExit = false`: only relaunches on a non-zero exit /
  crash — mirrors systemd's `Restart=on-failure`. A clean `launchctl unload`
  or a check/once-mode exit 0 is not relaunched.
- `ThrottleInterval = 5`: launchd's fixed per-attempt restart delay — the
  closest native equivalent to systemd's `RestartSec`. launchd has no
  built-in total-attempt cap (no `StartLimitBurst` equivalent); monitor
  persistent crash-looping via `log show` filtered on the process name.

Verify: `launchctl list | grep dr-orchestrate-server` shows a PID; a clean
`launchctl unload` removes it without relaunch; a `kill -9` on the PID
SHOULD relaunch after `ThrottleInterval` seconds.

## Why this exists

The Phase G runbook's `... start &` invocation is fine for a one-off local
smoke test, but has no crash recovery and dies with the parent shell. For any
long-running deployment the process needs graceful shutdown (`SIGTERM`
handling — both units rely on socat's default signal behaviour since the
launcher script `exec`s directly into socat, leaving no wrapper process to
intercept the signal) and an automatic, rate-limited restart on crash.
