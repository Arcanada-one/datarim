#!/usr/bin/env python3
"""Fixture-based tests for Cursor Auto-only guard and stream-json observation."""
from __future__ import annotations

import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

S = Path(__file__).resolve().parents[1] / "scripts"
FIX = Path(__file__).resolve().parent / "fixtures" / "cursor-stream"
sys.path.insert(0, str(S))

import cursor_model_policy as policy  # noqa: E402
import runtimes  # noqa: E402


def _fixture(name: str) -> list[str]:
    return (FIX / name).read_text(encoding="utf-8").splitlines()


class TestResolveLaunchModel(unittest.TestCase):
    def tearDown(self):
        os.environ.pop(policy.ALLOW_NON_AUTO_ENV, None)

    def test_missing_model_defaults_to_auto(self):
        self.assertEqual(policy.resolve_launch_model(None), "auto")
        self.assertEqual(policy.resolve_launch_model(""), "auto")
        self.assertEqual(policy.resolve_launch_model("   "), "auto")

    def test_auto_accepted_case_insensitive(self):
        self.assertEqual(policy.resolve_launch_model("auto"), "auto")
        self.assertEqual(policy.resolve_launch_model("Auto"), "auto")
        self.assertEqual(policy.resolve_launch_model("AUTO"), "auto")

    def test_named_model_refused(self):
        with self.assertRaises(policy.CursorModelRefused) as ctx:
            policy.resolve_launch_model("grok-4.7-high-fast")
        self.assertIn("only Auto is allowed", str(ctx.exception))
        self.assertIn(policy.ALLOW_NON_AUTO_ENV, str(ctx.exception))

    def test_escape_hatch_allows_named_model(self):
        os.environ[policy.ALLOW_NON_AUTO_ENV] = "1"
        self.assertEqual(
            policy.resolve_launch_model("grok-4.7-high-fast"),
            "grok-4.7-high-fast",
        )

    def test_model_argv_always_includes_flag(self):
        self.assertEqual(policy.model_argv(None), ["--model", "auto"])
        self.assertEqual(policy.model_argv("auto"), ["--model", "auto"])


class TestObserveStreamJson(unittest.TestCase):
    def test_auto_happy_path_logs_requested_and_actual(self):
        record = policy.observe_stream_json(
            _fixture("auto-happy.jsonl"), requested_model="auto"
        )
        self.assertTrue(record["init_seen"])
        self.assertEqual(record["requested_model"], "auto")
        self.assertEqual(record["actual_model"], "Auto")
        self.assertEqual(record["session_id"], "sess-auto-001")
        self.assertEqual(record["usage"]["input_tokens"], 12)
        self.assertEqual(record["usage"]["output_tokens"], 3)
        self.assertEqual(record["alerts"], [])
        self.assertIn("requested_service_tier", record)
        self.assertIn("actual_service_tier", record)
        self.assertIsNone(record["requested_service_tier"])
        self.assertIsNone(record["actual_service_tier"])

    def test_missing_init_warns(self):
        record = policy.observe_stream_json(
            _fixture("missing-init.jsonl"), requested_model="auto"
        )
        self.assertFalse(record["init_seen"])
        self.assertIsNone(record["actual_model"])
        self.assertEqual(record["session_id"], "sess-missing-001")
        self.assertEqual(len(record["alerts"]), 1)
        self.assertIn("missing stream-json system/init", record["alerts"][0])

    def test_named_cli_actual_under_auto_warns(self):
        record = policy.observe_stream_json(
            _fixture("named-mismatch.jsonl"), requested_model="auto"
        )
        self.assertEqual(record["actual_model"], "grok-4.7-high-fast")
        self.assertEqual(len(record["alerts"]), 1)
        self.assertIn("named CLI model", record["alerts"][0])

    def test_resolved_display_name_under_auto_is_not_a_violation(self):
        record = policy.observe_stream_json(
            _fixture("resolved-display-ok.jsonl"), requested_model="auto"
        )
        self.assertEqual(record["actual_model"], "Claude 4 Sonnet")
        self.assertEqual(record["alerts"], [])

    def test_emit_writes_log_and_alert_prefixes(self):
        buf = io.StringIO()
        record = policy.observe_and_emit(
            _fixture("missing-init.jsonl"),
            requested_model="auto",
            stream=buf,
        )
        text = buf.getvalue()
        self.assertIn(policy.LOG_PREFIX, text)
        self.assertIn(policy.ALERT_PREFIX, text)
        log_line = [ln for ln in text.splitlines() if ln.startswith(policy.LOG_PREFIX)][0]
        payload = json.loads(log_line[len(policy.LOG_PREFIX) + 1 :])
        self.assertEqual(payload["event"], "cursor_model_run")
        self.assertEqual(payload["session_id"], record["session_id"])
        self.assertNotIn("say hi", text)  # no prompt text


class TestCursorRuntimeGuard(unittest.TestCase):
    def tearDown(self):
        for key in list(os.environ):
            if key.startswith("DATARIM_CURSOR_MODEL") or key == policy.ALLOW_NON_AUTO_ENV:
                del os.environ[key]

    def test_argv_defaults_to_auto_when_unconfigured(self):
        rt = runtimes.CursorRuntime("sonnet")
        argv = rt._argv("TASK", resume=False)
        self.assertIn("--model", argv)
        self.assertEqual(argv[argv.index("--model") + 1], "auto")
        self.assertIn("stream-json", argv)

    def test_argv_refuses_named_env_mapping(self):
        os.environ["DATARIM_CURSOR_MODEL_SONNET"] = "grok-4.7-high-fast"
        rt = runtimes.CursorRuntime("sonnet")
        with self.assertRaises(runtimes.RuntimeError_) as ctx:
            rt._argv("TASK", resume=False)
        self.assertIn("only Auto is allowed", str(ctx.exception))

    def test_argv_escape_hatch_permits_named_model(self):
        os.environ[policy.ALLOW_NON_AUTO_ENV] = "1"
        os.environ["DATARIM_CURSOR_MODEL_SONNET"] = "grok-4.7-high-fast"
        rt = runtimes.CursorRuntime("sonnet")
        argv = rt._argv("TASK", resume=False)
        self.assertEqual(argv[argv.index("--model") + 1], "grok-4.7-high-fast")

    def test_apply_tier_succeeds_with_auto_default(self):
        rt = runtimes.CursorRuntime("sonnet")
        ok, detail = rt.apply_tier("opus")
        self.assertTrue(ok)
        self.assertEqual(detail["model"], "auto")

    def test_apply_tier_refuses_named_mapping(self):
        os.environ["DATARIM_CURSOR_MODEL_OPUS"] = "grok-4.7-high-fast"
        rt = runtimes.CursorRuntime("sonnet")
        ok, detail = rt.apply_tier("opus")
        self.assertFalse(ok)
        self.assertEqual(detail["reason"], "cursor_model_refused")

    def test_read_stdout_emits_observation_from_fixture(self):
        rt = runtimes.CursorRuntime("sonnet")
        rt._requested_model = "auto"
        rt._stream_lines = []
        q = __import__("queue").Queue()
        lines = _fixture("auto-happy.jsonl")

        class FakeProc:
            returncode = 0
            stdout = lines

            def wait(self):
                return 0

        err = io.StringIO()
        with mock.patch("sys.stderr", err):
            rt._read_stdout(FakeProc(), q, gen=1)

        text = err.getvalue()
        self.assertIn(policy.LOG_PREFIX, text)
        self.assertIn('"requested_model":"auto"', text.replace(" ", ""))
        self.assertIn("sess-auto-001", text)
        kinds = []
        while not q.empty():
            kinds.append(q.get()["kind"])
        self.assertIn("turn_end", kinds)
        self.assertIn("usage", kinds)


class TestCli(unittest.TestCase):
    def tearDown(self):
        os.environ.pop(policy.ALLOW_NON_AUTO_ENV, None)

    def test_cli_resolve_refuses_named(self):
        self.assertEqual(policy._cli(["resolve", "grok-4.7-high-fast"]), 2)

    def test_cli_resolve_defaults(self):
        buf = io.StringIO()
        with mock.patch("sys.stdout", buf):
            rc = policy._cli(["resolve"])
        self.assertEqual(rc, 0)
        self.assertEqual(buf.getvalue().strip(), "auto")

    def test_cli_observe_missing_init_nonzero(self):
        stdin = io.StringIO("\n".join(_fixture("missing-init.jsonl")) + "\n")
        err = io.StringIO()
        with mock.patch("sys.stdin", stdin), mock.patch("sys.stderr", err):
            rc = policy._cli(["observe", "--requested", "auto"])
        self.assertEqual(rc, 1)
        self.assertIn(policy.ALERT_PREFIX, err.getvalue())


if __name__ == "__main__":
    unittest.main()
