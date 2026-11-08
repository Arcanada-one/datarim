#!/usr/bin/env bash
set -euo pipefail
kill "$WEBHOOK_PID" 2>/dev/null || pkill -f "webhook.*8090" 2>/dev/null || true
