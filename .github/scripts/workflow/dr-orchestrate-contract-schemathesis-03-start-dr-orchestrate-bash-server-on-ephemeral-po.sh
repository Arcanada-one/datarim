#!/usr/bin/env bash
set -euo pipefail
cd plugins/dr-orchestrate
mkdir -p "$DR_ORCH_STATE_DIR"
# TUNE-0295 Phase C dropped the adnanh/webhook reference impl and
# replaced it with the internal bash HTTP server. CI starts the
# bash server on port 8090 so the OpenAPI base-URL contract
# (http://127.0.0.1:8090) stays stable for Schemathesis.
mkdir -p /tmp/dr-orch-ci
nohup bash scripts/dr_orchestrate_server.sh \
  >/tmp/dr-orch-ci/server.out 2>/tmp/dr-orch-ci/server.err &
server_pid=$!
# Wait up to 15s for the listener to come up.
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${DR_ORCH_PORT}" >/dev/null 2>&1; then
    echo "server ready after ${i} probes (curl)"
    break
  fi
  if ss -tlnp 2>/dev/null | grep -q ":${DR_ORCH_PORT}\b"; then
    echo "server ready after ${i} probes (ss)"
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "server PID $server_pid exited before binding the port" >&2
    echo "--- stdout ---" >&2
    cat /tmp/dr-orch-ci/server.out >&2 || true
    echo "--- stderr ---" >&2
    cat /tmp/dr-orch-ci/server.err >&2 || true
    exit 1
  fi
  sleep 0.5
done
echo "WEBHOOK_PID=${server_pid}" >> "$GITHUB_ENV"
