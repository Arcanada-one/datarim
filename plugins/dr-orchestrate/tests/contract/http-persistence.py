#!/usr/bin/env python3
"""Exercise the single-request router with a persistence-capable HTTP client."""
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import unittest


PLUGIN = Path(__file__).resolve().parents[2]


class RouterResponses(unittest.TestCase):
    def test_utf8_content_length_counts_bytes(self):
        with tempfile.TemporaryDirectory(prefix="http-utf8-") as directory:
            handler = Path(directory) / "handler.sh"
            handler.write_text(
                "#!/usr/bin/env bash\n"
                "printf '202\\r\\nContent-Type: application/json\\r\\n\\r\\n{\"text\":\"café\"}'\n"
            )
            handler.chmod(0o700)
            for locale in ["C", "en_US.UTF-8"]:
                with self.subTest(locale=locale):
                    env = dict(os.environ, LC_ALL=locale,
                               DR_ORCH_TMUX_HANDLER=str(handler),
                               DR_ORCH_CORS_ORIGIN="", DR_ORCH_CORS_ALLOW_WILDCARD="0")
                    result = subprocess.run(
                        ["bash", str(PLUGIN / "scripts/dr_orchestrate_router.sh")],
                        input=b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\n\r\n",
                        env=env, capture_output=True, check=True, timeout=10,
                    )
                    headers, body = result.stdout.split(b"\r\n\r\n", 1)
                    self.assertEqual(body, '{"text":"café"}'.encode())
                    self.assertEqual(len(body), 16)
                    self.assertIn(b"Content-Length: 16", headers.split(b"\r\n"))

    def test_all_final_responses_close_once_and_preserve_payload(self):
        with tempfile.TemporaryDirectory(prefix="http-router-") as directory:
            handler = Path(directory) / "handler.sh"
            handler.write_text(
                "#!/usr/bin/env bash\n"
                "printf '202\\r\\nContent-Type: application/json\\r\\n"
                "Connection: keep-alive\\r\\ncOnNeCtIoN: upgrade\\r\\n"
                "X-Handler: preserved\\r\\n\\r\\n{\"accepted\":true}'\n"
            )
            handler.chmod(0o700)
            env = dict(os.environ, DR_ORCH_TMUX_HANDLER=str(handler),
                       DR_ORCH_ORCH_HANDLER=str(handler), DR_ORCH_BODY_LIMIT="16",
                       DR_ORCH_CORS_ORIGIN="", DR_ORCH_CORS_ALLOW_WILDCARD="0",
                       DR_ORCH_CORS_ALLOW_AUTH="0",
                       DR_ORCH_CORS_ALLOWED_ORIGINS="https://client.example")
            cases = [
                ("default HTTP/1.1", b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\n\r\n", 202),
                ("requested keep-alive", b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n", 202),
                ("requested close", b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n", 202),
                ("HTTP/1.0", b"POST /hooks/tmux HTTP/1.0\r\n\r\n", 202),
                ("preflight HTTP/1.1", b"OPTIONS /hooks/tmux HTTP/1.1\r\nHost: x\r\nOrigin: https://client.example\r\n\r\n", 204),
                ("preflight HTTP/1.0", b"OPTIONS /hooks/tmux HTTP/1.0\r\nOrigin: https://client.example\r\n\r\n", 204),
                ("malformed", b"INVALID\r\n\r\n", 400),
                ("unknown route", b"GET /unknown HTTP/1.1\r\nHost: x\r\n\r\n", 404),
                ("wrong method", b"DELETE /hooks/tmux HTTP/1.1\r\nHost: x\r\n\r\n", 405),
                ("oversized body", b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\nContent-Length: 17\r\n\r\n", 413),
                ("unavailable handler", b"POST /hooks/tmux HTTP/1.1\r\nHost: x\r\n\r\n", 500),
            ]
            for name, request, expected in cases:
                with self.subTest(name=name):
                    case_env = dict(env)
                    if expected == 500:
                        case_env["DR_ORCH_TMUX_HANDLER"] = str(Path(directory) / "absent")
                    result = subprocess.run(
                        ["bash", str(PLUGIN / "scripts/dr_orchestrate_router.sh")],
                        input=request, env=case_env, capture_output=True, timeout=10,
                        check=True,
                    )
                    headers, body = result.stdout.split(b"\r\n\r\n", 1)
                    self.assertNotIn(b"\n", headers.replace(b"\r\n", b""))
                    self.assertNotIn(b"\r", headers.replace(b"\r\n", b""))
                    lines = headers.split(b"\r\n")
                    self.assertEqual(int(lines[0].split()[1]), expected)
                    fields = [line.split(b":", 1) for line in lines[1:]]
                    connections = [value.strip().lower() for key, value in fields
                                   if key.lower() == b"connection"]
                    self.assertEqual(connections, [b"close"])
                    lengths = [value.strip() for key, value in fields
                               if key.lower() == b"content-length"]
                    self.assertEqual(lengths, [str(len(body)).encode()])
                    if expected == 202:
                        self.assertEqual(json.loads(body), {"accepted": True})
                        self.assertIn(b"X-Handler: preserved", lines)
                    elif expected == 204:
                        self.assertEqual(body, b"")
                        self.assertIn(b"Access-Control-Allow-Origin: https://client.example", lines)
                    else:
                        self.assertEqual(json.loads(body)["status"], expected)


class PersistentClient(unittest.TestCase):
    def test_successful_posts_reconnect_without_client_close_override(self):
        class CountingConnection(http.client.HTTPConnection):
            connections = 0

            def connect(self):
                super().connect()
                self.connections += 1

        with tempfile.TemporaryDirectory(prefix="http-persistence-") as directory:
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            env = dict(os.environ, DR_ORCH_DIR=str(PLUGIN),
                       DR_ORCH_BIND="127.0.0.1", DR_ORCH_PORT=str(port),
                       DR_ORCH_STATE_DIR=directory, DR_ORCH_INBOX_DIR=str(Path(directory) / "inbox"),
                       DR_ORCH_TMUX_HANDLER=str(PLUGIN / "scripts/tmux_dispatcher.sh"),
                       DR_ORCH_ORCH_HANDLER=str(PLUGIN / "scripts/orchestrator-input-handler.sh"),
                       DR_ORCH_BODY_LIMIT="65536", DR_ORCH_CORS_ORIGIN="",
                       DR_ORCH_CORS_ALLOWED_ORIGINS="", DR_ORCH_CORS_ALLOW_WILDCARD="0")
            with (Path(directory) / "server.log").open("wb") as log:
                server = subprocess.Popen(
                    ["bash", str(PLUGIN / "scripts/dr_orchestrate_server.sh")],
                    env=env, stdout=log, stderr=log, start_new_session=True,
                )
                try:
                    deadline = time.monotonic() + 5
                    while True:
                        self.assertIsNone(server.poll(), "fixture server exited before readiness")
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                                break
                        except OSError:
                            if time.monotonic() >= deadline:
                                self.fail("fixture server did not become ready")
                            time.sleep(0.02)
                    client = CountingConnection("127.0.0.1", port, timeout=5)
                    try:
                        for index in range(3):
                            payload = {"session_id": "fixture_session", "command": "dr-next", "probe": index}
                            client.request("POST", "/hooks/orchestrator-input", json.dumps(payload),
                                           headers={"Content-Type": "application/json"})
                            response = client.getresponse()
                            body = response.read()
                            self.assertEqual(response.status, 202)
                            self.assertEqual(response.getheaders().count(("Connection", "close")), 1)
                            self.assertTrue(response.will_close)
                            self.assertEqual(json.loads(body)["status"], "queued")
                            self.assertIsNone(client.sock)
                        self.assertEqual(client.connections, 3)
                        queued = [json.loads(path.read_text()) for path in (Path(directory) / "inbox").glob("*.json")]
                        self.assertEqual(sorted(item["probe"] for item in queued), [0, 1, 2])
                    finally:
                        client.close()
                finally:
                    os.killpg(server.pid, signal.SIGTERM)
                    server.wait(timeout=5)
                    with socket.socket() as probe:
                        probe.settimeout(0.2)
                        self.assertNotEqual(probe.connect_ex(("127.0.0.1", port)), 0,
                                            "owned fixture listener remained active")


if __name__ == "__main__":
    unittest.main()
