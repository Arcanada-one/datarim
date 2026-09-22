#!/usr/bin/env python3
"""Tests for the runtime adapters and for graceful degradation without Jev.

Two concerns, both offline:

1. **Runtime parity** -- the supervisor must not care whether it is driving
   Claude Code (in-process `set_model`) or Codex (resume-chaining with a new
   effort/model). Both must expose the same `apply_tier` / `send_turn` /
   normalised-event surface.
2. **Datarim without the integration** -- every degraded control-plane state
   (no API key, corrupt config, missing config, kill switch) must leave the host
   CLI usable, and must NOT weaken the deterministic safety floor.
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

P = Path(__file__).resolve().parents[1]
S = P / "scripts"
sys.path.insert(0, str(S))

import route as route_mod  # noqa: E402
import runtimes  # noqa: E402


class TestRegistry(unittest.TestCase):
    def test_both_runtimes_registered(self):
        self.assertEqual(sorted(runtimes.REGISTRY), ["claude", "codex"])

    def test_unknown_runtime_is_rejected(self):
        with self.assertRaises(runtimes.RuntimeError_):
            runtimes.build("emacs", "sonnet")

    def test_adapters_share_the_supervisor_surface(self):
        """Parity check: a missing method would only surface mid-run otherwise."""
        for name in runtimes.REGISTRY:
            rt = runtimes.build(name, "sonnet")
            for attr in ("start", "send_turn", "apply_tier", "apply_effort",
                         "events", "close", "diagnostics"):
                self.assertTrue(callable(getattr(rt, attr, None)), f"{name}.{attr}")
            for attr in ("tiers", "in_process_switch", "reports_usage", "name"):
                self.assertTrue(hasattr(rt, attr), f"{name}.{attr}")
            self.assertEqual(rt.tiers, ("haiku", "sonnet", "opus"),
                             f"{name} must speak the same tier vocabulary as the router")

    def test_switch_semantics_differ_as_documented(self):
        # Claude reconfigures the live session; Codex applies the change on the
        # next resumed turn. Both report usage, so both get token hysteresis.
        self.assertTrue(runtimes.build("claude", "sonnet").in_process_switch)
        self.assertFalse(runtimes.build("codex", "sonnet").in_process_switch)
        self.assertTrue(runtimes.build("claude", "sonnet").reports_usage)
        self.assertTrue(runtimes.build("codex", "sonnet").reports_usage)


class TestCodexArgv(unittest.TestCase):
    """Codex's tier change is an argv change on the next turn."""

    def setUp(self):
        self._saved = dict(runtimes.CODEX_TIER_MAP)
        for k in list(os.environ):
            if k.startswith("DATARIM_CODEX_MODEL_"):
                del os.environ[k]

    def tearDown(self):
        runtimes.CODEX_TIER_MAP.clear()
        runtimes.CODEX_TIER_MAP.update(self._saved)
        for k in list(os.environ):
            if k.startswith("DATARIM_CODEX_MODEL_"):
                del os.environ[k]

    def test_first_turn_starts_a_thread(self):
        rt = runtimes.CodexRuntime("sonnet")
        argv = rt._argv("TASK", resume=False)
        self.assertNotIn("resume", argv)
        self.assertIn("--json", argv)
        self.assertEqual(argv[-1], "TASK")

    def test_later_turns_resume_the_same_thread(self):
        rt = runtimes.CodexRuntime("sonnet")
        rt.thread_id = "T-1"
        argv = rt._argv("NEXT", resume=True)
        self.assertEqual(argv[1:4], ["exec", "resume", "T-1"])

    def test_resume_without_a_thread_id_starts_fresh(self):
        # Defensive: a first turn that never emitted thread.started must not
        # produce `codex exec resume None`.
        rt = runtimes.CodexRuntime("sonnet")
        self.assertNotIn("resume", rt._argv("NEXT", resume=True))

    def test_tier_maps_to_reasoning_effort(self):
        rt = runtimes.CodexRuntime("sonnet")
        for tier, effort in (("haiku", "low"), ("sonnet", "medium"), ("opus", "high")):
            ok, _ = rt.apply_tier(tier)
            self.assertTrue(ok)
            self.assertIn(f"model_reasoning_effort={effort}", " ".join(rt._argv("x", resume=False)))

    def test_no_model_flag_by_default(self):
        """Model availability is account-dependent, so the default sends no -m."""
        rt = runtimes.CodexRuntime("opus")
        self.assertNotIn("-m", rt._argv("x", resume=False))

    def test_env_override_supplies_a_model(self):
        os.environ["DATARIM_CODEX_MODEL_OPUS"] = "some-big-model"
        rt = runtimes.CodexRuntime("opus")
        argv = rt._argv("x", resume=False)
        self.assertIn("-m", argv)
        self.assertIn("some-big-model", argv)

    def test_git_repo_check_flag_tracks_the_cwd(self):
        """Codex refuses to run outside a repo without the flag; inside one the
        flag is omitted so Codex keeps its own default behaviour."""
        rt = runtimes.CodexRuntime("sonnet")
        with mock.patch.object(rt, "_outside_git", return_value=True):
            self.assertIn("--skip-git-repo-check", rt._argv("x", resume=False))
        with mock.patch.object(rt, "_outside_git", return_value=False):
            self.assertNotIn("--skip-git-repo-check", rt._argv("x", resume=False))

    def test_git_probe_failure_assumes_the_flag_is_needed(self):
        rt = runtimes.CodexRuntime("sonnet")
        with mock.patch.object(runtimes.subprocess, "run", side_effect=OSError("no git")):
            self.assertTrue(rt._outside_git())

    def test_unknown_tier_is_refused(self):
        rt = runtimes.CodexRuntime("sonnet")
        ok, detail = rt.apply_tier("gpt-nonsense")
        self.assertFalse(ok)
        self.assertEqual(detail["reason"], "unknown_tier")
        self.assertEqual(rt.tier, "sonnet")

    def test_bad_effort_is_refused(self):
        rt = runtimes.CodexRuntime("sonnet")
        ok, detail = rt.apply_effort("turbo")
        self.assertFalse(ok)
        self.assertEqual(detail["reason"], "unsupported_effort")


class TestClaudeFrameTolerance(unittest.TestCase):
    """Malformed assistant frames must not kill the generator.

    An AttributeError raised out of ClaudeRuntime.events() escapes the
    supervisor's only handler: the run dies on a parse error while the `finally`
    block still writes an apparently healthy session record. stream-json
    legitimately emits `"content": "plain string"` for simple messages, so this
    is a real frame shape, not a hypothetical one.
    """

    def _drain(self, frames):
        rt = runtimes.ClaudeRuntime("sonnet")
        rt.session = mock.Mock()
        q = queue.Queue()
        for f in frames:
            q.put(f)
        q.put({"type": "result", "total_cost_usd": 0.0})
        rt.session.events = q
        return [ev["kind"] for ev in rt.events(1)]

    def test_string_content_is_read_as_text(self):
        kinds = self._drain([{"type": "assistant", "message": {"content": "plain string"}}])
        self.assertEqual(kinds, ["text", "turn_end"])

    def test_non_dict_shapes_do_not_raise(self):
        for frame in (
            {"type": "assistant", "message": "a bare string"},
            {"type": "assistant", "message": {"content": [None, 42]}},
            {"type": "assistant", "message": {"content": ["text block"]}},
            {"type": "assistant", "message": {"usage": "not-a-dict", "content": []}},
            {"type": "assistant", "message": {"content": None}},
        ):
            with self.subTest(repr(frame)[:48]):
                self.assertIn("turn_end", self._drain([frame]))


class TestCodexEventTranslation(unittest.TestCase):
    """Codex JSONL -> the normalised vocabulary the supervisor consumes."""

    def setUp(self):
        self.rt = runtimes.CodexRuntime("sonnet")

    def t(self, frame):
        return self.rt._translate(frame)

    def test_thread_started_yields_session_and_records_id(self):
        out = self.t({"type": "thread.started", "thread_id": "T-9"})
        self.assertEqual(out, [{"kind": "session", "id": "T-9"}])
        self.assertEqual(self.rt.thread_id, "T-9")

    def test_agent_message_becomes_text(self):
        out = self.t({"type": "item.completed", "item": {"type": "agent_message", "text": "hi"}})
        self.assertEqual(out, [{"kind": "text", "text": "hi"}])

    def test_command_execution_becomes_a_bash_tool(self):
        out = self.t({"type": "item.completed", "item": {"type": "command_execution", "command": "ls"}})
        self.assertEqual(out, [{"kind": "tool", "name": "Bash"}])

    def test_file_change_yields_one_edit_per_path(self):
        out = self.t({"type": "item.completed", "item": {
            "type": "file_change", "changes": [{"path": "a"}, {"path": "b"}]}})
        self.assertEqual(out, [{"kind": "tool", "name": "Edit"}] * 2)

    def test_file_change_without_changes_still_counts_once(self):
        out = self.t({"type": "item.completed", "item": {"type": "file_change"}})
        self.assertEqual(out, [{"kind": "tool", "name": "Edit"}])

    def test_errors_are_surfaced_not_swallowed(self):
        for frame in ({"type": "error", "message": "boom"},
                      {"type": "turn.failed", "error": {"message": "nope"}}):
            out = self.t(frame)
            self.assertEqual(out[0]["kind"], "error")

    def test_unknown_frames_are_ignored(self):
        self.assertEqual(self.t({"type": "item.started"}), [])
        self.assertEqual(self.t({"type": "some.future.event"}), [])

    def test_turn_completed_usage_becomes_a_usage_event(self):
        """Codex reports usage once per turn, so the token guard works here too."""
        out = self.t({"type": "turn.completed", "usage": {
            "input_tokens": 70953, "cached_input_tokens": 58880,
            "cache_write_input_tokens": 0, "output_tokens": 202}})
        self.assertEqual(out, [{"kind": "usage", "tokens": 70953 + 58880}])

    def test_turn_completed_without_usage_yields_nothing(self):
        self.assertEqual(self.t({"type": "turn.completed"}), [])

    def test_malformed_usage_values_are_skipped(self):
        out = self.t({"type": "turn.completed", "usage": {
            "input_tokens": "x", "cached_input_tokens": None, "cache_write_input_tokens": 5}})
        self.assertEqual(out, [{"kind": "usage", "tokens": 5}])

    def test_translated_events_drive_the_phase_heuristic(self):
        """The whole point of normalising: phase inference works on Codex too."""
        from live_supervisor import TurnObserver
        obs = TurnObserver()
        frames = [
            {"type": "item.completed", "item": {"type": "command_execution", "command": "cat x"}},
            {"type": "item.completed", "item": {"type": "file_change", "changes": [{"path": "a"}]}},
            {"type": "item.completed", "item": {"type": "file_change", "changes": [{"path": "b"}]}},
        ]
        for f in frames:
            for ev in self.rt._translate(f):
                if ev["kind"] == "tool":
                    obs.add_tool(ev["name"])
        self.assertEqual(obs.phase(), "implement")


class TestTokenHysteresisOptOut(unittest.TestCase):
    """A runtime with no usage reporting must skip, not fake, the token guard."""

    def _cfg(self):
        return {
            "live": {"enabled": True, "escalate_threshold": 0.75, "deescalate_threshold": 0.85,
                     "min_tokens_between_switches": 25000, "min_seconds_between_switches": 0,
                     "max_switches_per_session": 6, "turns_between_reroutes": 2,
                     "effort_switching": True,
                     "model_ceiling": {"balanced": "opus"}, "model_floor": {"balanced": "haiku"}},
            "routing": {}, "telemetry": {"enabled": False},
        }

    def test_zero_tokens_blocks_when_hysteresis_is_on(self):
        from live_policy import SwitchGate
        g = SwitchGate(self._cfg(), "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.95, turn=2, now=100, tokens_seen=60000)
        g.commit(v1, now=100, tokens_seen=60000)
        v2 = g.evaluate("haiku", 0.95, turn=6, now=900, tokens_seen=0)
        self.assertEqual(v2["blocked_by"], "min_tokens")

    def test_zero_tokens_does_not_block_when_hysteresis_is_off(self):
        from live_policy import SwitchGate
        g = SwitchGate(self._cfg(), "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.95, turn=2, now=100, tokens_seen=0, token_hysteresis=False)
        g.commit(v1, now=100, tokens_seen=0)
        v2 = g.evaluate("haiku", 0.95, turn=6, now=900, tokens_seen=0, token_hysteresis=False)
        self.assertTrue(v2["switch"], v2)
        self.assertEqual(v2.get("token_hysteresis"), "unavailable",
                         "an unavailable guard must be recorded, not implied to have passed")

    def test_other_guards_still_apply_without_token_hysteresis(self):
        from live_policy import SwitchGate
        cfg = self._cfg()
        cfg["live"]["max_switches_per_session"] = 1
        g = SwitchGate(cfg, "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.95, turn=1, now=10, tokens_seen=0, token_hysteresis=False)
        g.commit(v1, now=10, tokens_seen=0)
        v2 = g.evaluate("haiku", 0.99, turn=2, now=20, tokens_seen=0, token_hysteresis=False)
        self.assertEqual(v2["blocked_by"], "max_switches")


class TestKillSwitch(unittest.TestCase):
    """Turning the integration off must be trivial and total."""

    def setUp(self):
        os.environ.pop("DATARIM_JEV_DISABLE", None)

    tearDown = setUp

    def test_env_values_that_disable(self):
        for v in ("1", "true", "yes", "on"):
            os.environ["DATARIM_JEV_DISABLE"] = v
            self.assertIsNotNone(route_mod.kill_switch_reason(), v)

    def test_env_values_that_do_not_disable(self):
        for v in ("", "0", "false", "no"):
            os.environ["DATARIM_JEV_DISABLE"] = v
            self.assertIsNone(route_mod.kill_switch_reason(), v)

    def test_disabled_config_turns_every_consumer_off(self):
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        cfg = route_mod.load_cfg()
        self.assertFalse(cfg["routing"]["enabled"])
        self.assertFalse(cfg["hooks"]["prompt_router"])
        self.assertFalse(cfg["hooks"]["pretool_risk"])
        self.assertFalse(cfg["live"]["enabled"])
        self.assertFalse(cfg["telemetry"]["enabled"])
        self.assertIn("DATARIM_JEV_DISABLE", cfg["disabled_reason"])

    def test_kill_switch_wins_over_a_valid_config(self):
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        cfg = route_mod.load_cfg()
        self.assertFalse(cfg["hooks"]["prompt_router"])


class TestRoutingEnabledIsLoadBearing(unittest.TestCase):
    """`routing.enabled` must gate the API call, not merely be documented.

    The kill switch and the fallback config both express "advise nothing" by
    clearing this flag, so a caller that builds its own cfg must not be able to
    reach the network past it.
    """

    def setUp(self):
        os.environ.pop("DATARIM_JEV_DISABLE", None)

    tearDown = setUp

    def test_route_refuses_when_disabled(self):
        cfg = route_mod.load_cfg(strict=True)
        cfg["routing"]["enabled"] = False
        with mock.patch.object(route_mod, "evaluate",
                               side_effect=AssertionError("API must not be called")):
            with self.assertRaises(route_mod.RoutingDisabled):
                route_mod.route("task", cfg)

    def test_kill_switch_makes_route_refuse(self):
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        with mock.patch.object(route_mod, "evaluate",
                               side_effect=AssertionError("API must not be called")):
            with self.assertRaises(route_mod.RoutingDisabled):
                route_mod.route("task")

    def test_reroute_does_not_call_the_api_when_disabled(self):
        import live_supervisor
        from live_policy import SwitchGate
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        cfg = route_mod.load_cfg()
        obs = live_supervisor.TurnObserver()
        obs.add_tool("Edit")
        gate = SwitchGate(cfg, "balanced", "sonnet", now=0.0)
        with mock.patch("jev_client.evaluate", side_effect=AssertionError("API must not be called")):
            self.assertIsNone(live_supervisor._reroute(object(), gate, obs, cfg, 3, True))


class TestConfigDegradation(unittest.TestCase):
    """A broken config must not break the host CLI (hooks) but must be reported (CLI)."""

    def test_missing_config_yields_a_disabled_default(self):
        with mock.patch.dict(os.environ, {"DATARIM_JEV_CONFIG": "/nonexistent/x.json"}, clear=False):
            cfg = route_mod.load_cfg()
        self.assertFalse(cfg["routing"]["enabled"])
        self.assertEqual(cfg["routing"]["default_model"], "sonnet")

    def test_corrupt_config_yields_a_disabled_default(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write("{not json")
            path = f.name
        try:
            with mock.patch.dict(os.environ, {"DATARIM_JEV_CONFIG": path}, clear=False):
                cfg = route_mod.load_cfg()
            self.assertFalse(cfg["routing"]["enabled"])
        finally:
            os.unlink(path)

    def test_non_object_config_is_rejected(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write("[1,2,3]")
            path = f.name
        try:
            with mock.patch.dict(os.environ, {"DATARIM_JEV_CONFIG": path}, clear=False):
                self.assertFalse(route_mod.load_cfg()["routing"]["enabled"])
        finally:
            os.unlink(path)

    def test_strict_mode_raises_for_the_cli(self):
        with mock.patch.dict(os.environ, {"DATARIM_JEV_CONFIG": "/nonexistent/x.json"}, clear=False):
            with self.assertRaises(Exception):
                route_mod.load_cfg(strict=True)

    def test_fallback_is_a_fresh_copy_per_caller(self):
        """A caller mutating its config must not poison the next one."""
        with mock.patch.dict(os.environ, {"DATARIM_JEV_CONFIG": "/nonexistent/x.json"}, clear=False):
            a = route_mod.load_cfg()
            a["routing"]["default_model"] = "mutated"
            b = route_mod.load_cfg()
        self.assertEqual(b["routing"]["default_model"], "sonnet")


class TestHooksFailOpen(unittest.TestCase):
    """The host CLI keeps working with no Jev at all -- as a subprocess, as Claude runs it."""

    HOOKS = ("hook_user_prompt.py", "hook_pre_tool.py", "hook_post_tool.py", "hook_stop.py")

    PAYLOAD = {
        "hook_user_prompt.py": {"prompt": "implement a feature"},
        "hook_pre_tool.py": {"tool_name": "Bash", "tool_input": {"command": "ls -la"}},
        "hook_post_tool.py": {"tool_name": "Edit", "tool_input": {"file_path": "x.py"}},
        "hook_stop.py": {"stop_hook_active": False},
    }

    def _run(self, hook, extra_env):
        env = dict(os.environ)
        env.update(extra_env)
        return subprocess.run([sys.executable, str(S / hook)],
                              input=json.dumps(self.PAYLOAD[hook]),
                              capture_output=True, text=True, env=env, timeout=30)

    def test_every_hook_exits_zero_when_disabled(self):
        for hook in self.HOOKS:
            p = self._run(hook, {"DATARIM_JEV_DISABLE": "1"})
            self.assertEqual(p.returncode, 0, f"{hook}: {p.stderr[:200]}")
            self.assertNotIn("Traceback", p.stderr, hook)

    def test_every_hook_exits_zero_with_a_corrupt_config(self):
        for hook in self.HOOKS:
            p = self._run(hook, {"DATARIM_JEV_CONFIG": "/dev/null"})
            self.assertEqual(p.returncode, 0, f"{hook}: {p.stderr[:200]}")
            self.assertNotIn("Traceback", p.stderr, hook)

    def test_every_hook_exits_zero_without_an_api_key(self):
        for hook in self.HOOKS:
            p = self._run(hook, {"TYPESAFE_API_KEY": ""})
            self.assertEqual(p.returncode, 0, f"{hook}: {p.stderr[:200]}")
            self.assertNotIn("Traceback", p.stderr, hook)

    def test_disabled_router_adds_no_context(self):
        p = self._run("hook_user_prompt.py", {"DATARIM_JEV_DISABLE": "1"})
        self.assertEqual(p.stdout.strip(), "")

    def test_malformed_stdin_never_crashes_a_hook(self):
        # Two distinct failure modes: input that fails to PARSE (caught by the
        # try/except), and input that parses into a non-object, which then
        # breaks at .get(). Only the first was covered, and the second crashed
        # three of the four hooks with a traceback and rc=1.
        for payload in ("not json at all", "", "null", "[1,2,3]", '"s"', "123",
                        "true", "[]", "{}"):
            for hook in self.HOOKS:
                with self.subTest(hook=hook, payload=payload[:12]):
                    p = subprocess.run([sys.executable, str(S / hook)], input=payload,
                                       capture_output=True, text=True,
                                       env=dict(os.environ), timeout=30)
                    self.assertEqual(p.returncode, 0, f"{hook}: {p.stderr[:200]}")
                    if p.stdout.strip():
                        json.loads(p.stdout)  # must still emit valid JSON


class TestSafetyFloorIndependence(unittest.TestCase):
    """The deterministic floor must not depend on the control plane's state.

    Regression: the config check used to run BEFORE the floor, so
    DATARIM_JEV_DISABLE=1 (or a corrupt config) silently removed the guard
    against destructive commands.
    """

    DESTRUCTIVE = ("rm -" + "rf /", "git push --force origin main",
                   "git reset --hard HEAD~3", "DROP DATABASE prod")
    BENIGN = ("ls -la", "git status", "pytest -q")
    MODES = ({"DATARIM_JEV_DISABLE": "1"},
             {"DATARIM_JEV_CONFIG": "/dev/null"},
             {"DATARIM_JEV_CONFIG": "/nonexistent/x.json"},
             {"TYPESAFE_API_KEY": ""})

    def _decide(self, cmd, extra_env):
        env = dict(os.environ)
        env.update(extra_env)
        p = subprocess.run([sys.executable, str(S / "hook_pre_tool.py")],
                           input=json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}),
                           capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(p.returncode, 0, p.stderr[:200])
        return '"permissionDecision": "deny"' in p.stdout

    def test_floor_blocks_destructive_commands_in_every_degraded_mode(self):
        for env in self.MODES:
            for cmd in self.DESTRUCTIVE:
                self.assertTrue(self._decide(cmd, env),
                                f"floor did not hold for {cmd!r} under {env}")

    def test_floor_does_not_block_benign_commands(self):
        for env in self.MODES:
            for cmd in self.BENIGN:
                self.assertFalse(self._decide(cmd, env), f"{cmd!r} wrongly denied under {env}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
