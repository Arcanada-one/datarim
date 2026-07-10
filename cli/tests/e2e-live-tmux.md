# `datarim tmux` end-to-end live smoke (TUNE-0295 V-AC-7)

This runbook validates the `datarim tmux ls` CLI command against the
real bash HTTP server `dr_orchestrate_server.sh` (no `mock-webhook.py`)
on a Linux runner with live `tmux` sessions.

Operator's macOS does NOT have `socat` / `tmux` / `redis-cli` installed
— Phase A–F was developed and tested with PATH-override stubs and
fixture-bound assertions. Phase G covers the gap that cannot be
self-verified locally.

## Prereqs (one-time, Linux runner)

```bash
# Ubuntu / Debian
sudo apt-get install -y socat tmux redis-server jq bats

# Verify:
socat -V | head -1
tmux -V
redis-cli --version
jq --version
bats --version
```

## Smoke procedure

```bash
# noshellcheck-extract
# 1. Start a Redis server in foreground (or as a service):
redis-server --daemonize yes
redis-cli ping     # expect PONG

# 2. Start two tmux sessions with known panes:
tmux new -d -s smoketest
tmux split-window -t smoketest

# 3. Start the dr-orchestrate server (foreground; logs to stderr):
cd ~/path/to/code/datarim
bash plugins/dr-orchestrate/scripts/dr_orchestrate_server.sh --check
bash plugins/dr-orchestrate/scripts/dr_orchestrate_server.sh start &
SERVER_PID=$!
sleep 1

# 4. Direct curl smoke — POST /hooks/tmux op=list:
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"op":"list","params":{},"session_id":"smoke001","ts":"2026-05-24T00:00:00Z","meta":{}}' \
  http://127.0.0.1:31415/hooks/tmux | jq .
# Expected: {"data":{"panes":[...],"count":N}} where N is the live pane count.

# 5. CLI end-to-end (V-AC-7 closure):
DATARIM_CLI_WEBHOOK_URL=http://127.0.0.1:31415 \
  ./cli/datarim tmux ls --json | jq .

# Cross-verify against direct tmux:
tmux list-panes -a -F '#{pane_id}|#{session_name}|#{pane_current_command}'

# Expected: pane_id list from CLI matches direct tmux output by count
# and content.

# 6. Async smoke — op=new returns 202+job_id; poll until complete:
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"op":"new","params":{"task_id":"smoketest-2","cmd":"claude -p"},"session_id":"smoke002","ts":"2026-05-24T00:00:00Z","meta":{}}' \
  http://127.0.0.1:31415/hooks/tmux | jq .
# Expected: {"job_id":"<uuid-v4>"}; capture <uuid>.

JOB=<paste-uuid-here>
curl -sS http://127.0.0.1:31415/hooks/tmux/job/$JOB | jq .
# Expected: {"status":"complete","data":{...}} within ~5s

# 7. Security smoke — whitelist + pane regex (both rejected 422 BEFORE tmux):
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"op":"new","params":{"task_id":"x","cmd":"rm -rf /"},"session_id":"s","ts":"t","meta":{}}' \
  http://127.0.0.1:31415/hooks/tmux
# Expected: {"error":"whitelist_reject","reason":"cmd 'rm -rf /' does not match whitelist"}

curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"op":"kill","params":{"pane":"%abc","force":false},"session_id":"s","ts":"t","meta":{}}' \
  http://127.0.0.1:31415/hooks/tmux
# Expected: {"error":"pane_regex_reject","reason":"pane '%abc' does not match ^%[0-9]+$"}

# 8. CLI bats real-mode (12 fixture-bound skip in mock-only; the rest
#    14 should pass against the real dispatcher):
DATARIM_CLI_USE_REAL_DISPATCHER=1 \
DATARIM_CLI_WEBHOOK_URL=http://127.0.0.1:31415 \
  bats cli/tests/tmux-*.bats

# 9. Cleanup:
kill $SERVER_PID
tmux kill-session -t smoketest
tmux kill-session -t smoketest-2 2>/dev/null || true
redis-cli shutdown
```

## Production supervision (beyond one-off smoke)

Step 3 above (`... start &`) is correct for this one-off smoke session — the
server dies with the shell and there is no crash recovery, which is fine for
a bounded manual verification run. For any long-running deployment, use the
supervised units in `plugins/dr-orchestrate/deploy/` instead:
`dr-orchestrate-server.service` (systemd, Linux) and
`com.arcanada.dr-orchestrate-server.plist` (launchd, macOS) — both add
graceful shutdown and an automatic restart-with-backoff on crash. See that
directory's `README.md` for install steps and the backoff policy. Neither
unit is installed or enabled by shipping these templates; installing one on
a real host is a separate operator action.

## V-AC-7 acceptance

The smoke is acceptable when:

1. Step 4 returns HTTP 200 with `data.panes` count matching step 2.
2. Step 5 (CLI `tmux ls`) returns the same pane set as direct `tmux list-panes`.
3. Step 6 async cycle returns `status:complete` within 30 seconds.
4. Step 7 returns `422` on both whitelist + pane-regex rejection; the
   server access log MUST NOT contain a `tmux new-session` / `tmux kill-pane`
   call for the rejected payloads (audit-sentinel).
5. Step 8 bats run reports `26/26 ok` (mix of real-pass + Phase-G-only-skip).

Record the result + Linux runner kernel/distro/socat/tmux versions in
the `documentation/archive/framework/archive-TUNE-0295.md` § E2E
smoke section at `/dr-archive` time.

## Known limitations

- macOS dev loop CANNOT execute this runbook (no socat / tmux / redis-cli).
  Stubs cover unit + contract; live behaviour deferred to Linux.
- Step 7 audit-sentinel: production observability hooks not yet wired —
  manual inspection of stderr until SEC-NNNN ships a structured access log.
- bearerAuth on `/hooks/tmux*` deferred to SEC-NNNN (creative debate
  decision — current security model relies on whitelist + pane regex +
  loopback bind).
