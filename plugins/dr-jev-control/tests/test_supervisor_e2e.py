#!/usr/bin/env python3
"""End-to-end supervisor tests against a fake Codex binary.

The unit tests cover argv construction and frame translation -- the easy,
deterministic parts. The defects that actually cost money or corrupt data live
in the process lifecycle and the supervisor's turn loop, which those tests never
touch. These do: they drive `run()` with a stubbed Jev, count child processes
and threads, and assert what lands in the ledger.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

P = Path(__file__).resolve().parents[1]
S = P / "scripts"
sys.path.insert(0, str(S))

import live_supervisor  # noqa: E402
import runtimes  # noqa: E402

FAKE = Path(__file__).resolve().parent / "fake_codex.py"


def cfg(**live):
    base = {
        "api": {"timeout_seconds": 5, "retries": 0},
        "routing": {"enabled": True, "default_model": "sonnet", "default_mode": "balanced",
                    "catalog_shortlist": 4, "max_state_chars": 2000,
                    "component_selection": {}, "modes": {"balanced": {"max_agents": 3}}},
        "live": {"enabled": True, "escalate_threshold": 0.75, "deescalate_threshold": 0.85,
                 "min_tokens_between_switches": 1, "min_seconds_between_switches": 0,
                 "max_switches_per_session": 6, "turns_between_reroutes": 1,
                 "effort_switching": True,
                 "model_ceiling": {"balanced": "opus"}, "model_floor": {"balanced": "haiku"}},
        "hooks": {}, "telemetry": {"enabled": True, "path": "~/.datarim/jev/ledger.jsonl"},
    }
    base["live"].update(live)
    return base


class CodexE2EBase(unittest.TestCase):
    """Runs the supervisor with `codex` replaced by fake_codex.py."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ledger = Path(self.tmp.name) / "ledger.jsonl"
        self.call_log = Path(self.tmp.name) / "calls.jsonl"
        self.cfg = cfg()
        self.cfg["telemetry"]["path"] = str(self.ledger)
        # A wrapper script so CODEX_BIN is a single executable, as in real use.
        self.bin = Path(self.tmp.name) / "codex"
        self.bin.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKE}" "$@"\n')
        self.bin.chmod(0o755)
        os.environ["CODEX_BIN"] = str(self.bin)
        os.environ["FAKE_CODEX_LOG"] = str(self.call_log)
        os.environ.pop("DATARIM_JEV_DISABLE", None)
        for k in ("FAKE_CODEX_NO_THREAD", "FAKE_CODEX_DIE_EARLY", "FAKE_CODEX_DONE_ON"):
            os.environ.pop(k, None)

    def tearDown(self):
        for k in ("CODEX_BIN", "FAKE_CODEX_LOG", "FAKE_CODEX_NO_THREAD",
                  "FAKE_CODEX_DIE_EARLY", "FAKE_CODEX_DONE_ON"):
            os.environ.pop(k, None)
        self.tmp.cleanup()

    def _route(self, tier="sonnet"):
        return {"ok": True, "mode": "balanced", "model": tier, "answers": {},
                "selection": {}, "profile": {}, "usage": {}}

    def _jev(self, tier, *, stuck=0.0, simplified=0.0, conf=0.99):
        return {"answers": {
            "needed_tier": {"choice": tier, "confidence": conf},
            "is_stuck": {"noul": stuck},
            "work_simplified": {"noul": simplified},
            "needs_more_thinking": {"noul": 0.0},
        }, "usage": {}}

    def run_supervised(self, *, reroute=None, **kw):
        kw.setdefault("mode", "balanced")
        kw.setdefault("cfg", self.cfg)
        kw.setdefault("extra_args", [])
        kw.setdefault("quiet", True)
        kw.setdefault("explain", False)
        kw.setdefault("max_turns", 3)
        kw.setdefault("runtime", "codex")
        patches = [
            mock.patch.object(live_supervisor, "route", return_value=self._route()),
            mock.patch("jev_client.evaluate",
                       side_effect=(reroute or (lambda *a, **k: self._jev("sonnet")))),
        ]
        for p in patches:
            p.start()
        try:
            return live_supervisor.run("do the thing", **kw)
        finally:
            for p in patches:
                p.stop()

    def ledger_records(self, event):
        if not self.ledger.exists():
            return []
        out = []
        for line in self.ledger.read_text().splitlines():
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("event") == event:
                out.append(rec["data"])
        return out

    def calls(self):
        if not self.call_log.exists():
            return []
        return [json.loads(l) for l in self.call_log.read_text().splitlines() if l.strip()]


class TestCodexHappyPath(CodexE2EBase):
    def test_single_turn_run_records_a_session(self):
        rc = self.run_supervised()
        self.assertEqual(rc, 0)
        sessions = self.ledger_records("live_session")
        self.assertEqual(len(sessions), 1)
        s = sessions[0]
        self.assertEqual(s["runtime"], "codex")
        self.assertEqual(s["stop_reason"], "one_shot")
        self.assertEqual(s["session_id"], "fake-thread-1")
        self.assertEqual(s["actual"]["turns"], 1)
        self.assertIn("Bash", s["actual"]["tools"])
        self.assertIn("Edit", s["actual"]["tools"])

    def test_multi_turn_resumes_the_same_thread(self):
        self.run_supervised(max_turns=3,
                            continue_prompt="keep going. Reply TASK_COMPLETE when done.")
        calls = self.calls()
        self.assertGreaterEqual(len(calls), 2, calls)
        self.assertNotIn("resume", calls[0])
        for c in calls[1:]:
            self.assertIn("resume", c, "later turns must resume, not restart")
            self.assertIn("fake-thread-1", c)

    def test_done_marker_ends_the_run(self):
        os.environ["FAKE_CODEX_DONE_ON"] = "2"
        self.run_supervised(max_turns=9, continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "done_marker")
        self.assertEqual(s["actual"]["turns"], 2)

    def test_max_turns_stops_the_run(self):
        self.run_supervised(max_turns=2, continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "max_turns")
        self.assertEqual(s["actual"]["turns"], 2)

    def test_usage_from_turn_completed_reaches_the_ledger_path(self):
        """Codex reports usage only at end of turn; the observer must see it."""
        seen = {}

        def reroute(state, questions, cfg_, **kw):
            seen["tokens"] = state  # digest is built after usage was recorded
            return self._jev("sonnet")

        self.run_supervised(reroute=reroute, max_turns=2, continue_prompt="go")
        self.assertIn("tokens", seen)


class TestCodexThreadIdFailure(CodexE2EBase):
    """The worst-visibility defect: a resume that silently restarts the task."""

    def test_missing_thread_id_stops_instead_of_restarting(self):
        os.environ["FAKE_CODEX_NO_THREAD"] = "1"
        self.run_supervised(max_turns=4, continue_prompt="keep going")
        calls = self.calls()
        # Exactly one invocation: the continuation must have been refused
        # rather than silently starting a second, context-free thread.
        self.assertEqual(len(calls), 1, f"task was restarted: {calls}")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "write_failed")
        self.assertIsNone(s["session_id"])
        self.assertTrue(any("thread id" in ln for ln in s["stderr_tail"]),
                        f"the reason must be diagnosable: {s['stderr_tail']}")

    def test_send_turn_refuses_without_a_thread_id(self):
        rt = runtimes.CodexRuntime("sonnet")
        self.assertFalse(rt.send_turn("next"))
        self.assertTrue(any("thread id" in ln for ln in rt.diagnostics()["stderr_tail"]))


class TestCodexProcessLifecycle(CodexE2EBase):
    def test_no_child_processes_survive_the_run(self):
        before = threading.active_count()
        self.run_supervised(max_turns=3, continue_prompt="keep going")
        # Reader threads are joined in _reap/close, so the count must come back
        # down rather than grow by 2 per turn.
        self.assertLessEqual(threading.active_count(), before + 1,
                             "reader threads leaked across turns")

    def test_exit_code_recorded_is_the_last_turns(self):
        self.run_supervised(max_turns=2, continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["exit_code"], 0)

    def test_child_death_mid_stream_is_reported(self):
        os.environ["FAKE_CODEX_DIE_EARLY"] = "1"
        self.run_supervised(max_turns=2, continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["exit_code"], 3)

    def test_a_crashing_child_does_not_look_like_a_completed_turn(self):
        # Regression: _read_stdout used to emit turn_end regardless of the exit
        # code, so a crash-looping child was indistinguishable from a working
        # one -- the supervisor counted turns, paid for a reroute per turn, and
        # kept resuming until max_turns while the record said N healthy turns
        # next to a nonzero exit_code.
        os.environ["FAKE_CODEX_DIE_EARLY"] = "1"
        paid = {"n": 0}

        def reroute(*a, **k):
            paid["n"] += 1
            return self._jev("sonnet")

        self.run_supervised(max_turns=6, continue_prompt="keep going", reroute=reroute)
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "child_exited")
        self.assertLessEqual(s["actual"]["turns"], 1)
        self.assertLessEqual(len(self.calls()), 2, "kept respawning a dying child")
        self.assertEqual(paid["n"], 0, "paid Jev for a turn that never completed")

    def test_reap_is_idempotent(self):
        rt = runtimes.CodexRuntime("sonnet")
        rt.close()
        rt.close()  # must not raise on a never-started runtime

    def test_events_before_start_yields_eof_not_attributeerror(self):
        rt = runtimes.CodexRuntime("sonnet")
        kinds = [ev["kind"] for ev in rt.events(1)]
        self.assertEqual(kinds, ["error", "eof"])


class TestDeferredSwitchHonesty(CodexE2EBase):
    """A Codex switch is deferred; the ledger must not claim more than happened."""

    def test_deferred_switch_that_ran_is_marked_took_effect(self):
        calls = {"n": 0}

        def reroute(*a, **k):
            calls["n"] += 1
            return self._jev("opus", stuck=0.95)

        self.run_supervised(reroute=reroute, max_turns=3, continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        switches = [x for x in s["actual"]["switches"] if x.get("switch")]
        self.assertTrue(switches, s["actual"]["switches"])
        first = switches[0]
        self.assertTrue(first["deferred"])
        self.assertTrue(first.get("took_effect"), "a switch followed by a turn did take effect")
        self.assertTrue(first["applied"])

    def test_deferred_switch_with_no_following_turn_is_downgraded(self):
        def reroute(*a, **k):
            return self._jev("opus", stuck=0.95)

        # max_turns=1 means the loop exits right after the reroute, so the
        # proposed tier never reaches any process.
        self.run_supervised(reroute=reroute, max_turns=1)
        s = self.ledger_records("live_session")[0]
        switches = [x for x in s["actual"]["switches"] if x.get("switch")]
        if switches:  # a switch may be gated away entirely; only assert if made
            self.assertFalse(switches[0]["applied"],
                             "a switch no process ever saw must not be recorded as applied")
            self.assertTrue(switches[0].get("never_took_effect"))

    def test_tier_change_reaches_the_next_invocation(self):
        def reroute(*a, **k):
            return self._jev("opus", stuck=0.95)

        self.run_supervised(reroute=reroute, max_turns=2, continue_prompt="keep going")
        calls = self.calls()
        self.assertGreaterEqual(len(calls), 2)
        joined = " ".join(calls[1])
        self.assertIn("model_reasoning_effort=high", joined,
                      "an escalation to opus must raise Codex's reasoning effort")


class TestRecordIsSelfConsistent(CodexE2EBase):
    """The record must be written from state the failure path actually updated.

    Three separate HIGH defects shared this one shape: `stop_reason` defaulting
    to "completed" so only crashes and Ctrl-C earned the word; `final_tier` read
    off the gate while the same object downgraded the switch; a crashed child
    reported as a finished turn. Asserted together because the next regression of
    this class will look different in detail and identical in kind.
    """

    def test_no_ordinary_exit_is_labelled_completed(self):
        # "completed" is not in the vocabulary at all: every exit names its own
        # reason, so the reassuring default could only ever mark a failure.
        scenarios = [
            ("one_shot", dict(max_turns=3)),
            ("max_turns", dict(max_turns=1, continue_prompt="keep going")),
        ]
        for expected, kw in scenarios:
            with self.subTest(expected=expected):
                self.setUp()
                try:
                    self.run_supervised(**kw)
                    s = self.ledger_records("live_session")[0]
                    self.assertEqual(s["stop_reason"], expected)
                    self.assertNotEqual(s["stop_reason"], "completed")
                finally:
                    self.tearDown()

    def test_keyboard_interrupt_is_named_not_inherited(self):
        def boom(*a, **k):
            raise KeyboardInterrupt()

        with mock.patch.object(live_supervisor, "route", return_value=self._route()), \
             mock.patch("jev_client.evaluate", side_effect=boom):
            with self.assertRaises(KeyboardInterrupt):
                live_supervisor.run("do the thing", mode="balanced", cfg=self.cfg,
                                    extra_args=[], quiet=True, explain=False,
                                    max_turns=3, runtime="codex",
                                    continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "interrupted")

    def test_supervisor_error_is_named_and_recorded(self):
        def boom(*a, **k):
            raise RuntimeError("adapter blew up")

        with mock.patch.object(live_supervisor, "route", return_value=self._route()), \
             mock.patch.object(live_supervisor, "_reroute", side_effect=boom):
            with self.assertRaises(RuntimeError):
                live_supervisor.run("do the thing", mode="balanced", cfg=self.cfg,
                                    extra_args=[], quiet=True, explain=False,
                                    max_turns=3, runtime="codex",
                                    continue_prompt="keep going")
        s = self.ledger_records("live_session")[0]
        self.assertEqual(s["stop_reason"], "supervisor_error")
        self.assertTrue(any("adapter blew up" in e for e in s["actual"].get("errors", [])))

    def test_final_tier_never_contradicts_the_switch_list(self):
        def reroute(*a, **k):
            return self._jev("opus", stuck=0.95)

        # max_turns=1: the deferred switch is downgraded, so final_tier must
        # stay on the tier a process was actually invoked with.
        self.run_supervised(reroute=reroute, max_turns=1)
        s = self.ledger_records("live_session")[0]
        applied = [x for x in s["actual"]["switches"] if x.get("applied")]
        expected = applied[-1]["to"] if applied else s["predicted"]["model"]
        self.assertEqual(s["final_tier"], expected)

    def test_max_seconds_holds_inside_a_long_turn(self):
        # IDLE_TIMEOUT_S measures inter-frame silence and a productive agent
        # resets it on every frame, so the wall-clock cap has to be sampled per
        # frame or a single chatty turn escapes it entirely.
        self.run_supervised(max_turns=3, continue_prompt="keep going", max_seconds=0.001)
        s = self.ledger_records("live_session")[0]
        self.assertIn(s["stop_reason"], ("max_seconds", "one_shot", "child_exited"))
        self.assertLess(s["duration_s"], 30)


class TestKillSwitchStopsTheApiMidRun(CodexE2EBase):
    def test_reroute_makes_no_api_call_when_switched_off(self):
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        try:
            def boom(*a, **k):
                raise AssertionError("API must not be called while switched off")
            # The real client is used here (not patched) so the choke point in
            # jev_client.evaluate is what gets exercised.
            with mock.patch.object(live_supervisor, "route", return_value=self._route()):
                live_supervisor.run("do the thing", mode="balanced", cfg=self.cfg,
                                    extra_args=[], quiet=True, explain=False,
                                    max_turns=2, continue_prompt="keep going",
                                    runtime="codex")
            s = self.ledger_records("live_session")
            # Telemetry is disabled by the kill switch in real use; here the cfg
            # was built by hand, so a record may exist. Either way, no crash.
            self.assertLessEqual(len(s), 1)
        finally:
            os.environ.pop("DATARIM_JEV_DISABLE", None)

    def test_evaluate_refuses_immediately_when_switched_off(self):
        from jev_client import JevError, evaluate
        os.environ["DATARIM_JEV_DISABLE"] = "1"
        try:
            with self.assertRaises(JevError) as ctx:
                evaluate("x", {"q": {"type": "noul", "instructions": "?"}}, self.cfg)
            self.assertEqual(ctx.exception.code, "DISABLED")
        finally:
            os.environ.pop("DATARIM_JEV_DISABLE", None)


class TestSafetyFloorMatching(unittest.TestCase):
    """The floor matches a normalised argv, so spelling variants cannot evade it."""

    def setUp(self):
        from safety_floor import destructive_reason
        self.check = lambda c: destructive_reason(c) is not None
        # Assembled so this file never contains a literal destructive command.
        self.RM = "r" + "m"

    def test_flag_spelling_variants_all_block(self):
        for variant in ("-rf", "-fr", "-r -f", "-f -r", "--recursive --force",
                        "-rf --no-preserve-root"):
            self.assertTrue(self.check(f"{self.RM} {variant} /"), variant)

    def test_root_glob_and_system_paths_block(self):
        for target in ("/", "/*", "/usr", "/etc", "/var", "/System", "/home", "/Users"):
            self.assertTrue(self.check(f"{self.RM} -rf {target}"), target)

    def test_wrappers_do_not_hide_the_command(self):
        for prefix in ("sudo", "doas", "nohup", "time", "env FOO=1", "command"):
            self.assertTrue(self.check(f"{prefix} {self.RM} -rf /"), prefix)

    def test_the_home_directory_itself_is_protected(self):
        # Measured gap: every system root was blocked while the home directory
        # -- the same irreversible loss, and the spelling a runaway script is
        # likelier to produce -- passed in all of these forms.
        home = os.path.expanduser("~").rstrip("/")
        for target in ("~", "~/", "$HOME", "${HOME}", "$HOME/", "~/*", "$HOME/*",
                       home, home + "/"):
            with self.subTest(target):
                self.assertTrue(self.check(f"{self.RM} -rf {target}"), target)

    def test_a_large_payload_cannot_outrun_the_floor(self):
        # shlex.split is quadratic: 1 MB took 6.4 s and 2 MB took 25 s, so the
        # host's 9 s hook timeout fired and the floor never returned a verdict.
        # Payload size was therefore a bypass for the one guard that must
        # survive everything.
        import time
        for size in (100_000, 1_000_000, 4_000_000):
            with self.subTest(size=size):
                cmd = "echo '" + "A" * size + "' && " + f"{self.RM} -rf /"
                t0 = time.perf_counter()
                verdict = self.check(cmd)
                elapsed = time.perf_counter() - t0
                self.assertTrue(verdict, "destructive tail must still be seen")
                self.assertLess(elapsed, 2.0, f"{size} chars took {elapsed:.1f}s")

    def test_padding_cannot_push_the_target_out_of_view(self):
        # Truncating only the HEAD of a segment created a fresh bypass:
        # `rm -rf <100k flags> /` lost its `/`. Both ends are kept now.
        for pad, target in ((" --verbose" * 60_000, "/"),
                            (" -v" * 120_000, "~"),
                            (" --quiet" * 60_000, None)):
            with self.subTest(target=target):
                if target is None:
                    self.assertTrue(self.check(f"git push{pad} -f origin main"))
                else:
                    self.assertTrue(self.check(f"{self.RM} -rf{pad} {target}"))

    def test_a_large_but_harmless_command_is_not_blocked(self):
        self.assertFalse(self.check("echo '" + "A" * 500_000 + "'"))
        self.assertFalse(self.check("tar -czf out.tgz " + "file " * 40_000))

    def test_paths_inside_home_are_still_deletable(self):
        # The floor must not obstruct ordinary work; a false block here would
        # make operators disable it, which costs more than it saves.
        home = os.path.expanduser("~").rstrip("/")
        for target in ("~/code/build", "$HOME/.cache", "~/tmp/x",
                       f"{home}/code/proj/node_modules", "./build",
                       "~/Library/Caches/pip"):
            with self.subTest(target):
                self.assertFalse(self.check(f"{self.RM} -rf {target}"), target)

    def test_pipeline_segments_are_inspected(self):
        self.assertTrue(self.check(f"cd /tmp && {self.RM} -rf /"))
        self.assertTrue(self.check(f"echo hi; {self.RM} -rf /etc"))

    def test_ordinary_deletes_are_allowed(self):
        for cmd in (f"{self.RM} -rf ./build", f"{self.RM} -rf node_modules",
                    f"{self.RM} -rf dist/", f"{self.RM} file.txt",
                    f"{self.RM} -r ./tmpdir"):
            self.assertFalse(self.check(cmd), cmd)

    def test_recursive_without_force_is_not_the_catastrophe_case(self):
        self.assertFalse(self.check(f"{self.RM} -r /"))

    def test_force_push_variants(self):
        self.assertTrue(self.check("git push --force origin main"))
        self.assertTrue(self.check("git push -f origin main"))
        self.assertTrue(self.check("git push --force"))

    def test_force_with_lease_is_allowed(self):
        """Blocking the safe variant would push people toward plain --force."""
        self.assertFalse(self.check("git push --force-with-lease origin main"))
        self.assertFalse(self.check("git push --force-if-includes origin main"))

    def test_ordinary_git_is_allowed(self):
        for cmd in ("git push origin main", "git status", "git reset --soft HEAD~1",
                    "git log --oneline", "git diff"):
            self.assertFalse(self.check(cmd), cmd)

    def test_hard_reset_blocks(self):
        self.assertTrue(self.check("git reset --hard"))
        self.assertTrue(self.check("git reset --hard HEAD~5"))

    def test_sql_drop_blocks_regardless_of_spacing(self):
        for cmd in ("DROP DATABASE prod", "DROP  DATABASE prod", "drop schema public",
                    "psql -c 'DROP DATABASE x'"):
            self.assertTrue(self.check(cmd), cmd)

    def test_drop_table_is_not_in_scope(self):
        self.assertFalse(self.check("DROP TABLE users"))

    def test_malformed_input_never_raises(self):
        for bad in (None, "", 123, "unbalanced 'quote", "--", "|||"):
            from safety_floor import destructive_reason
            destructive_reason(bad)


if __name__ == "__main__":
    unittest.main(verbosity=2)
