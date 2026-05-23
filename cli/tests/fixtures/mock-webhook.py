#!/usr/bin/env python3
"""Minimal /dr-orchestrate mock webhook for bats.

Modes (via env vars):
  MOCK_MODE=sync_ok       — POST /hooks/orchestrator-input → 200 {status:"ok"}
  MOCK_MODE=async_ok      — POST → 202 {job_id:"job-1"}; GET /hooks/orchestrator-job/job-1 → 200 {result:"ok"}
  MOCK_MODE=server_5xx    — POST → 500 {error:"boom"}
  MOCK_MODE=server_4xx    — POST → 400 {error:"bad"}
  MOCK_MODE=count_calls   — sync_ok + maintain counter (?count → returns N)
"""
import os, sys, json, threading, time, signal
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("MOCK_PORT", "18090"))
MODE = os.environ.get("MOCK_MODE", "sync_ok")
COUNT = {"posts": 0}


class H(BaseHTTPRequestHandler):
    def log_message(self, *args, **kwargs):
        pass

    def _send(self, status, body_obj):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        body = json.dumps(body_obj).encode("utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        COUNT["posts"] += 1
        n = int(self.headers.get("Content-Length", 0))
        _ = self.rfile.read(n) if n else b""
        if MODE in ("sync_ok", "count_calls"):
            self._send(200, {"status": "ok", "posts": COUNT["posts"]})
        elif MODE == "async_ok":
            self._send(202, {"job_id": "job-1"})
        elif MODE == "server_5xx":
            self._send(500, {"error": "boom"})
        elif MODE == "server_4xx":
            self._send(400, {"error": "bad"})
        else:
            self._send(500, {"error": "unknown mode"})

    def do_GET(self):
        if self.path.startswith("/hooks/orchestrator-job/"):
            self._send(200, {"result": "ok"})
        else:
            self._send(404, {"error": "not found"})


def main():
    srv = HTTPServer(("127.0.0.1", PORT), H)
    print(f"mock-webhook PORT={PORT} MODE={MODE}", file=sys.stderr)
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
