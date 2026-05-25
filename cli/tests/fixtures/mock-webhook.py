#!/usr/bin/env python3
"""Minimal /dr-orchestrate mock webhook for bats.

Modes (via env vars):
  MOCK_MODE=sync_ok       — POST /hooks/orchestrator-input → 200 {status:"ok"}
  MOCK_MODE=async_ok      — POST → 202 {job_id:"job-1"}; GET /hooks/orchestrator-job/job-1 → 200 {result:"ok"}
  MOCK_MODE=server_5xx    — POST → 500 {error:"boom"}
  MOCK_MODE=server_4xx    — POST → 400 {error:"bad"}
  MOCK_MODE=count_calls   — sync_ok + maintain counter (?count → returns N)

Phase 4 tmux modes (POST /hooks/tmux + GET /hooks/tmux/job/<job_id>):
  MOCK_MODE=tmux_list_3pane   — list op → 200 {data:{panes:[<3 fixtures>], count:3}}
  MOCK_MODE=tmux_list_empty   — list op → 200 {data:{panes:[], count:0}}
  MOCK_MODE=tmux_new_202      — new op → 202 {job_id:"tmux-job-1"};
                                GET /hooks/tmux/job/tmux-job-1 → 200 {data:{pane:"%1",session:"datarim",cmd:"claude -p"}}
  MOCK_MODE=tmux_new_async_never — new op → 202; job never completes (polling will time out via DATARIM_CLI_ASYNC_TIMEOUT override)
  MOCK_MODE=tmux_kill_200     — kill op → 200 {data:{pane:"%0",killed:true}}
  MOCK_MODE=tmux_read_50lines — read op → 200 {data:{pane:"%0",lines:["L"+i for i in 0..49],truncated:false}}
  MOCK_MODE=tmux_attach_200   — attach op → 200 {data:{pane:"%0",session:"datarim",tmux_cmd:"tmux attach-session -t datarim ; select-pane -t %0"}}
  MOCK_MODE=tmux_pane_not_found_404 — any op → 404 {error:"pane not found"}
"""
import os, sys, json
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("MOCK_PORT", "18090"))
MODE = os.environ.get("MOCK_MODE", "sync_ok")
COUNT = {"posts": 0}


THREE_PANE_FIXTURE = [
    {"id": "%0", "session": "datarim", "cmd": "claude -p", "pid": 1001},
    {"id": "%1", "session": "datarim", "cmd": "python3",   "pid": 1002},
    {"id": "%2", "session": "datarim", "cmd": "bash",      "pid": 1003},
]


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

    def _read_post_body(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return {}

    def do_POST(self):
        COUNT["posts"] += 1
        path = self.path.split("?")[0]
        body = self._read_post_body()
        # Phase 4 — /hooks/tmux dispatch.
        if path == "/hooks/tmux":
            self._handle_tmux_post(body)
            return
        # Phase 3 — /hooks/orchestrator-input behaviour preserved.
        if MODE in ("sync_ok", "count_calls"):
            self._send(200, {"status": "ok", "posts": COUNT["posts"]})
        elif MODE == "async_ok":
            self._send(202, {"job_id": "job-1"})
        elif MODE == "server_5xx":
            self._send(500, {"error": "boom"})
        elif MODE == "server_4xx":
            self._send(400, {"error": "bad"})
        else:
            self._send(500, {"error": "unknown mode " + MODE})

    def _handle_tmux_post(self, body):
        op = (body or {}).get("op", "")
        if MODE == "tmux_pane_not_found_404":
            self._send(404, {"error": "pane not found"})
            return
        if MODE == "tmux_list_3pane" and op == "list":
            self._send(200, {"data": {"panes": THREE_PANE_FIXTURE, "count": 3}})
            return
        if MODE == "tmux_list_empty" and op == "list":
            self._send(200, {"data": {"panes": [], "count": 0}})
            return
        if MODE in ("tmux_new_202", "tmux_new_async_never") and op == "new":
            self._send(202, {"job_id": "tmux-job-1"})
            return
        if MODE == "tmux_kill_200" and op == "kill":
            params = (body or {}).get("params", {})
            self._send(200, {"data": {"pane": params.get("pane", "?"), "killed": True}})
            return
        if MODE == "tmux_read_50lines" and op == "read":
            params = (body or {}).get("params", {})
            n = int(params.get("lines", 50))
            self._send(200, {"data": {
                "pane": params.get("pane", "?"),
                "lines": ["L" + str(i) for i in range(min(n, 50))],
                "truncated": False,
            }})
            return
        if MODE == "tmux_attach_200" and op == "attach":
            params = (body or {}).get("params", {})
            pane = params.get("pane", "?")
            self._send(200, {"data": {
                "pane": pane, "session": "datarim",
                "tmux_cmd": "tmux attach-session -t datarim \\; select-pane -t " + pane,
            }})
            return
        # Default: unknown mode/op pairing.
        self._send(500, {"error": "no handler for MODE=" + MODE + " op=" + op})

    def do_GET(self):
        # Phase 3 — async completion poll.
        if self.path.startswith("/hooks/orchestrator-job/"):
            self._send(200, {"result": "ok"})
            return
        # Phase 4 — /hooks/tmux job completion poll.
        if self.path.startswith("/hooks/tmux/job/"):
            if MODE == "tmux_new_202":
                self._send(200, {"data": {"pane": "%1", "session": "datarim", "cmd": "claude -p"}})
                return
            if MODE == "tmux_new_async_never":
                self._send(202, {"status": "pending"})
                return
            self._send(404, {"error": "no handler"})
            return
        self._send(404, {"error": "not found"})


def main():
    srv = HTTPServer(("127.0.0.1", PORT), H)
    print("mock-webhook PORT=" + str(PORT) + " MODE=" + MODE, file=sys.stderr)
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
