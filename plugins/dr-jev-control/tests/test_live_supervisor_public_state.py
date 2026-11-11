#!/usr/bin/env python3
"""Frozen public-state cohort for live supervisor (G-SUPERVISOR-COVERAGE).

Separate from the e2e base (`test_supervisor_e2e.py`) and from the primary
routing/pretool cohorts. Cases are table-driven from a secret-free JSON fixture
so integration denominators stay explicit. Shadow-only: offline execution is not
a live runtime switch PASS.
"""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

P = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(P / "scripts"))

import live_supervisor  # noqa: E402
import runtimes  # noqa: E402
from live_policy import SwitchGate  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "live_supervisor_public_state_v1.json"


def _deep_merge(base, overlay):
    out = copy.deepcopy(base)
    for key, value in (overlay or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def _load_fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def _observer(spec):
    obs = live_supervisor.TurnObserver()
    if not spec:
        return obs
    obs.tools = list(spec.get("tools") or [])
    if "tokens" in spec:
        obs.context_tokens = int(spec["tokens"])
    return obs


class TestLiveSupervisorPublicStateCohort(unittest.TestCase):
    """One integration case per fixture row; accuracy/live switch stay separate."""

    @classmethod
    def setUpClass(cls):
        cls.doc = _load_fixture()
        if cls.doc.get("schema") != "jev.live_supervisor.public_state.v1":
            raise AssertionError(f"unexpected schema: {cls.doc.get('schema')}")
        cls.cases = cls.doc["cases"]
        cls.default_cfg = cls.doc["default_cfg"]

    def test_fixture_is_non_empty_and_id_unique(self):
        self.assertGreaterEqual(len(self.cases), 20)
        ids = [c["id"] for c in self.cases]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(self.doc.get("shadow_only") is True)

    def test_cohort_cases(self):
        failures = []
        for case in self.cases:
            try:
                self._run_case(case)
            except Exception as exc:  # noqa: BLE001 — collect full denominator
                failures.append(f"{case['id']}: {exc}")
        self.assertEqual(failures, [], "\n".join(failures))

    def _cfg(self, case):
        return _deep_merge(self.default_cfg, case.get("cfg_overlay") or {})

    def _run_case(self, case):
        family = case["family"]
        if family == "reroute_questions":
            self._run_reroute_questions(case)
        elif family == "decide":
            self._run_decide(case)
        elif family == "hysteresis":
            self._run_hysteresis(case)
        elif family == "runtimes":
            self._run_runtimes(case)
        else:
            raise AssertionError(f"unknown family {family}")

    def _run_reroute_questions(self, case):
        q = live_supervisor.reroute_questions(self._cfg(case))
        expect = case["expect"]
        self.assertEqual(sorted(q.keys()), sorted(expect["keys"]))
        for key, typ in expect["types"].items():
            self.assertEqual(q[key]["type"], typ, key)
        joined = " ".join(q.keys()).lower()
        for bad in expect.get("forbidden_substrings_in_keys") or []:
            self.assertNotIn(bad, joined)

    def _run_decide(self, case):
        cfg = self._cfg(case)
        gspec = case["gate"]
        gate = SwitchGate(cfg, gspec["mode"], gspec["tier"], now=float(gspec.get("now", 0.0)))
        obs = _observer(case.get("observer"))
        kwargs = dict(case.get("decide_kwargs") or {})
        verdict, effort = live_supervisor.decide(
            case.get("answers") or {},
            gate,
            obs,
            cfg=cfg,
            **kwargs,
        )
        self._assert_expect(case["expect"], verdict, effort)

    def _run_hysteresis(self, case):
        cfg = self._cfg(case)
        gspec = case["gate"]
        gate = SwitchGate(cfg, gspec["mode"], gspec["tier"], now=float(gspec.get("now", 0.0)))
        pre = case.get("precommit")
        if pre:
            v1 = gate.evaluate(
                pre["proposed"],
                pre["confidence"],
                turn=pre["turn"],
                now=pre["now"],
                tokens_seen=pre["tokens_seen"],
                token_hysteresis=pre.get("token_hysteresis", True),
            )
            self.assertTrue(v1["switch"], f"{case['id']} precommit failed: {v1}")
            gate.commit(v1, now=pre["now"], tokens_seen=pre["tokens_seen"])
        ev = case["evaluate"]
        verdict = gate.evaluate(
            ev["proposed"],
            ev["confidence"],
            turn=ev["turn"],
            now=ev["now"],
            tokens_seen=ev["tokens_seen"],
            token_hysteresis=ev.get("token_hysteresis", True),
        )
        self._assert_expect(case["expect"], verdict, None)

    def _run_runtimes(self, case):
        expect = case["expect"]["reports_usage"]
        mapping = {
            "BaseRuntime": runtimes.BaseRuntime,
            "ClaudeRuntime": runtimes.ClaudeRuntime,
            "CodexRuntime": runtimes.CodexRuntime,
            "CursorRuntime": runtimes.CursorRuntime,
            "AntigravityRuntime": runtimes.AntigravityRuntime,
        }
        for name, flag in expect.items():
            self.assertEqual(bool(mapping[name].reports_usage), bool(flag), name)

    def _assert_expect(self, expect, verdict, effort):
        if "switch" in expect:
            self.assertEqual(bool(verdict.get("switch")), bool(expect["switch"]), verdict)
        if "to" in expect:
            self.assertEqual(verdict.get("to"), expect["to"], verdict)
        if "blocked_by" in expect:
            self.assertEqual(verdict.get("blocked_by"), expect["blocked_by"], verdict)
        if "blocked_by_contains" in expect:
            blocked = verdict.get("blocked_by") or ""
            self.assertIn(expect["blocked_by_contains"], blocked, verdict)
        if "reason_contains" in expect:
            reason = verdict.get("reason") or ""
            for needle in expect["reason_contains"]:
                self.assertIn(needle, reason, verdict)
        if "token_hysteresis" in expect:
            self.assertEqual(verdict.get("token_hysteresis"), expect["token_hysteresis"], verdict)
        if "effort" in expect:
            self.assertEqual(effort, expect["effort"], f"effort={effort} verdict={verdict}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
