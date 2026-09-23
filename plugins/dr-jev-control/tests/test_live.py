#!/usr/bin/env python3
"""Tests for dynamic routing: switch policy, multi-component selection, ledger.

These run entirely offline. The switch policy is the piece that spends real
money (each applied switch re-pays the prompt cache), so it is tested against
its guards rather than against a live session.
"""
import json
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

P = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(P / "scripts"))

import cli_report  # noqa: E402
import components  # noqa: E402
import ledger  # noqa: E402
import live_policy  # noqa: E402
from live_policy import SwitchGate, clamp_to_mode  # noqa: E402


def cfg(**live):
    base = {
        "live": {
            "enabled": True,
            "escalate_threshold": 0.75,
            "deescalate_threshold": 0.85,
            "min_tokens_between_switches": 25000,
            "min_seconds_between_switches": 90,
            "max_switches_per_session": 6,
            "turns_between_reroutes": 2,
            "effort_switching": True,
            "model_ceiling": {"economy": "sonnet", "balanced": "opus", "quality": "opus"},
            "model_floor": {"economy": "haiku", "balanced": "haiku", "quality": "sonnet"},
        },
        "routing": {"component_selection": {
            "multi_select_max": 4, "apply_threshold": 0.70,
            "mention_threshold": 0.45, "candidate_probe_limit": 8}},
        "telemetry": {"enabled": True, "path": "~/.datarim/jev/ledger.jsonl"},
    }
    base["live"].update(live)
    return base


class TestModeEnvelope(unittest.TestCase):
    """A live switch must not reach a tier the mode forbids at startup."""

    def test_economy_ceiling_blocks_opus(self):
        self.assertEqual(clamp_to_mode("opus", "economy", cfg()), "sonnet")

    def test_quality_floor_lifts_haiku(self):
        self.assertEqual(clamp_to_mode("haiku", "quality", cfg()), "sonnet")

    def test_balanced_allows_full_range(self):
        c = cfg()
        self.assertEqual(clamp_to_mode("opus", "balanced", c), "opus")
        self.assertEqual(clamp_to_mode("haiku", "balanced", c), "haiku")

    def test_unknown_tier_falls_back_to_sonnet_rank(self):
        # A garbled tier name must not silently rank as the cheapest option.
        self.assertEqual(live_policy.rank("nonsense"), live_policy.rank("sonnet"))

    def test_clamp_always_returns_a_canonical_tier(self):
        # Regression: a typo in operator-edited JSON ("Haiku") used to be
        # returned verbatim and forwarded to set_model, where Claude Code
        # answers `success` without changing model -- a ledger entry for a
        # switch that never happened.
        typo = cfg()
        typo["live"]["model_floor"] = {"economy": "Haiku"}
        typo["live"]["model_ceiling"] = {"economy": "sonnet"}
        self.assertEqual(clamp_to_mode("haiku", "economy", typo), "haiku")
        for proposed in ("Opus", " SONNET ", "", None, "gpt-6-astra", "opus-9"):
            self.assertIn(clamp_to_mode(proposed, "balanced", cfg()), live_policy.TIERS)

    def test_ceiling_wins_over_a_contradictory_floor(self):
        # A floor above the ceiling must not let economy reach opus just
        # because the floor check runs second. The ceiling is the cost
        # guarantee the README promises.
        c = cfg()
        c["live"]["model_ceiling"] = {"economy": "haiku"}
        c["live"]["model_floor"] = {"economy": "opus"}
        self.assertEqual(clamp_to_mode("sonnet", "economy", c), "haiku")
        self.assertEqual(clamp_to_mode("opus", "economy", c), "haiku")


class TestEscalationAsymmetry(unittest.TestCase):
    """Escalating is cheaper to get wrong than de-escalating, so it needs less confidence."""

    def _gate(self, tier="sonnet", mode="balanced"):
        return SwitchGate(cfg(), mode, tier, now=0.0)

    def test_escalation_passes_at_escalate_threshold(self):
        g = self._gate()
        v = g.evaluate("opus", 0.76, turn=3, now=1000, tokens_seen=60000)
        self.assertTrue(v["switch"], v)

    def test_deescalation_blocked_at_escalate_threshold(self):
        # 0.76 clears the escalate bar but not the stricter de-escalate bar.
        g = self._gate()
        v = g.evaluate("haiku", 0.76, turn=3, now=1000, tokens_seen=60000)
        self.assertFalse(v["switch"])
        self.assertIn("below_threshold", v["blocked_by"])

    def test_deescalation_passes_at_its_own_threshold(self):
        g = self._gate()
        v = g.evaluate("haiku", 0.86, turn=3, now=1000, tokens_seen=60000)
        self.assertTrue(v["switch"], v)


class TestHysteresis(unittest.TestCase):
    """Guards that stop the re-cache cost being paid repeatedly."""

    def test_min_seconds_blocks_rapid_second_switch(self):
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.9, turn=2, now=1000, tokens_seen=60000)
        g.commit(v1, now=1000, tokens_seen=60000)
        v2 = g.evaluate("haiku", 0.99, turn=3, now=1010, tokens_seen=200000)
        self.assertFalse(v2["switch"])
        self.assertEqual(v2["blocked_by"], "min_seconds")

    def test_min_tokens_blocks_switch_before_context_moved(self):
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.9, turn=2, now=1000, tokens_seen=60000)
        g.commit(v1, now=1000, tokens_seen=60000)
        # Plenty of wall-clock elapsed, but the conversation barely grew: the
        # re-cache cost would be paid again for essentially the same context.
        v2 = g.evaluate("haiku", 0.99, turn=9, now=5000, tokens_seen=61000)
        self.assertFalse(v2["switch"])
        self.assertEqual(v2["blocked_by"], "min_tokens")

    def test_max_switches_per_session_is_enforced(self):
        c = cfg(max_switches_per_session=1, min_seconds_between_switches=0,
                min_tokens_between_switches=0)
        g = SwitchGate(c, "balanced", "sonnet", now=0.0)
        v1 = g.evaluate("opus", 0.95, turn=1, now=10, tokens_seen=1000)
        g.commit(v1, now=10, tokens_seen=1000)
        v2 = g.evaluate("haiku", 0.99, turn=2, now=20, tokens_seen=2000)
        self.assertEqual(v2["blocked_by"], "max_switches")

    def test_same_tier_is_a_noop_not_a_switch(self):
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        v = g.evaluate("sonnet", 0.99, turn=3, now=1000, tokens_seen=99999)
        self.assertFalse(v["switch"])
        self.assertEqual(v["blocked_by"], "already_on_tier")

    def test_disabled_live_never_switches(self):
        g = SwitchGate(cfg(enabled=False), "balanced", "sonnet", now=0.0)
        v = g.evaluate("opus", 1.0, turn=5, now=9999, tokens_seen=999999)
        self.assertEqual(v["blocked_by"], "live_disabled")

    def test_commit_only_applies_on_a_real_switch(self):
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        blocked = g.evaluate("sonnet", 0.99, turn=1, now=1000, tokens_seen=60000)
        g.commit(blocked, now=1000, tokens_seen=60000)
        self.assertEqual(g.switches, 0)
        self.assertEqual(g.tier, "sonnet")


class TestReroutePacing(unittest.TestCase):
    def test_phase_change_always_earns_a_reroute(self):
        g = SwitchGate(cfg(turns_between_reroutes=10), "balanced", "sonnet")
        self.assertTrue(g.should_reroute(1, phase_changed=True))

    def test_same_phase_is_paced_by_turn_count(self):
        g = SwitchGate(cfg(turns_between_reroutes=3), "balanced", "sonnet")
        g.note_reroute(1)
        self.assertFalse(g.should_reroute(2, phase_changed=False))
        self.assertTrue(g.should_reroute(4, phase_changed=False))


class TestMultiComponentSelection(unittest.TestCase):
    CANDS = [{"name": f"skill-{i}", "description": f"does thing {i}"} for i in range(6)]

    def _answers(self, scores):
        return {components.probe_key("skills", n): {"noul": s} for n, s in scores.items()}

    def test_several_components_can_apply_at_once(self):
        a = self._answers({"skill-0": 0.95, "skill-1": 0.81, "skill-2": 0.72, "skill-3": 0.10})
        r = components.resolve("skills", self.CANDS, a, cfg())
        self.assertEqual([x["name"] for x in r["apply"]], ["skill-0", "skill-1", "skill-2"])
        self.assertEqual(r["applied_by"], "threshold")

    def test_cap_limits_how_many_apply(self):
        c = cfg()
        c["routing"]["component_selection"]["multi_select_max"] = 2
        a = self._answers({"skill-0": 0.95, "skill-1": 0.9, "skill-2": 0.85})
        r = components.resolve("skills", self.CANDS, a, c)
        self.assertEqual(len(r["apply"]), 2)

    def test_candidates_lost_to_the_cap_stay_in_the_record(self):
        # They used to fall out of `apply` and `mention` both and vanish from
        # the prediction entirely, which biases the divergence metric: the same
        # session is flagged "work broader than prediction" at one cap and not
        # at another.
        c = cfg()
        c["routing"]["component_selection"]["multi_select_max"] = 2
        a = self._answers({"skill-0": 0.95, "skill-1": 0.9, "skill-2": 0.85, "skill-3": 0.8})
        r = components.resolve("skills", self.CANDS, a, c)
        self.assertEqual([x["name"] for x in r["mention"]], ["skill-2", "skill-3"])
        self.assertEqual(r["capped_out"], ["skill-2", "skill-3"])
        self.assertEqual(r["applied_by"], "cap", "the cap decided, not the threshold")

    def test_rounding_cannot_lift_a_score_over_the_gate(self):
        a = self._answers({"skill-0": 0.6996})
        r = components.resolve("skills", self.CANDS, a, cfg())
        self.assertEqual(r["apply"], [], "0.6996 is below a 0.70 gate")
        self.assertEqual(r["ranked"][0]["score"], 0.7, "still reported rounded")
        self.assertFalse(components.single_choice(
            {"choice": "x", "confidence": 0.6996}, cfg())["applied"])

    def test_out_of_range_probability_is_rejected(self):
        a = self._answers({"skill-0": 42.0, "skill-1": -1.0})
        self.assertEqual(components.resolve("skills", self.CANDS, a, cfg())["ranked"], [])

    def test_internal_raw_score_is_not_recorded(self):
        a = self._answers({"skill-0": 0.9, "skill-1": 0.5})
        r = components.resolve("skills", self.CANDS, a, cfg())
        for bucket in ("apply", "mention", "ranked"):
            for x in r[bucket]:
                self.assertNotIn("_raw", x)

    def test_weak_field_applies_nothing(self):
        # The historical failure mode: a 0.55 best-of-a-bad-field pick presented
        # as a decision. Now it lands in `mention` and applies nothing.
        a = self._answers({"skill-0": 0.55, "skill-1": 0.5, "skill-2": 0.12})
        r = components.resolve("skills", self.CANDS, a, cfg())
        self.assertEqual(r["apply"], [])
        self.assertEqual(r["applied_by"], "none")
        self.assertEqual([x["name"] for x in r["mention"]], ["skill-0", "skill-1"])

    def test_missing_and_malformed_answers_are_skipped(self):
        a = self._answers({"skill-0": 0.9})
        a[components.probe_key("skills", "skill-1")] = {"noul": "not-a-number"}
        a[components.probe_key("skills", "skill-2")] = "garbage"
        r = components.resolve("skills", self.CANDS, a, cfg())
        self.assertEqual([x["name"] for x in r["apply"]], ["skill-0"])

    def test_probe_limit_bounds_question_count(self):
        c = cfg()
        c["routing"]["component_selection"]["candidate_probe_limit"] = 3
        q = components.build_probes("skills", self.CANDS, c)
        self.assertEqual(len(q), 3)
        for v in q.values():
            self.assertEqual(v["type"], "noul")

    def test_single_choice_gates_on_confidence(self):
        applied = components.single_choice(
            {"choice": "tester", "confidence": 0.93, "probabilities": {"tester": 0.93}}, cfg())
        self.assertTrue(applied["applied"])
        weak = components.single_choice(
            {"choice": "tester", "confidence": 0.55, "probabilities": {"tester": 0.55}}, cfg())
        self.assertFalse(weak["applied"])
        self.assertEqual(weak["choice"], "tester")  # still reported, just not applied

    def test_single_choice_none_never_applies(self):
        r = components.single_choice({"choice": "none", "confidence": 0.99}, cfg())
        self.assertFalse(r["applied"])

    def test_single_choice_tolerates_garbage(self):
        r = components.single_choice(None, cfg())
        self.assertEqual(r["choice"], "none")
        self.assertFalse(r["applied"])


class TestConfidenceAccounting(unittest.TestCase):
    """A confident refusal is not a weak recommendation.

    Regression from the real ledger: 32 of 33 template picks were a confident
    `none`, and folding them into the same denominator reported
    "templates conf 0.80 -> applied 0% (n=33)" when the truth was a single
    0.33 pick. It also under-reported agents/commands by 11-12 points. This is
    the exact quantity the measurement campaign exists to read, so the
    distinction is load-bearing, not cosmetic.
    """

    def _stats_over(self, selections, *, render=False):
        """Aggregate a synthetic ledger in a temp dir.

        `render_stats` takes the *config* and re-reads the ledger itself, so the
        temp path has to stay in scope for the render too -- passing it a stats
        dict silently makes it read the operator's real ledger instead.
        """
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            for sel in selections:
                ledger.log_event(c, "route", "task", {"model": "sonnet", "selection": sel})
            return cli_report.render_stats(c) if render else ledger.stats(c)

    def test_confident_none_is_counted_as_a_refusal_not_a_miss(self):
        refusal = {"templates": {"choice": "none", "confidence": 0.82, "applied": False}}
        pick = {"templates": {"choice": "docs-stub", "confidence": 0.33, "applied": False}}
        s = self._stats_over([refusal] * 4 + [pick])
        slot = s["confidence"]["templates"]
        self.assertEqual(slot["n"], 1, "refusals must stay out of the denominator")
        self.assertEqual(slot["refused"], 4)
        self.assertAlmostEqual(slot["mean_confidence"], 0.33, places=2)

    def test_applied_rate_reflects_only_named_components(self):
        sels = [
            {"agents": {"choice": "none", "confidence": 0.9, "applied": False}},
            {"agents": {"choice": "tester", "confidence": 0.95, "applied": True}},
            {"agents": {"choice": "reviewer", "confidence": 0.40, "applied": False}},
        ]
        slot = self._stats_over(sels)["confidence"]["agents"]
        self.assertEqual((slot["n"], slot["refused"]), (2, 1))
        self.assertAlmostEqual(slot["applied_rate"], 0.5, places=3)

    def test_axis_with_no_probe_answers_is_not_scored_as_zero(self):
        # An empty `ranked` means no probe answered: absence of data, not a
        # score of 0.0, which would drag the mean toward a stated confidence
        # that Jev never gave.
        slot = self._stats_over([{"skills": {"ranked": [], "apply": []}}] * 3)["confidence"]["skills"]
        self.assertEqual((slot["n"], slot["refused"]), (0, 3))
        self.assertEqual(slot["mean_confidence"], 0.0)

    def test_renderer_flags_an_axis_that_never_named_anything(self):
        out = self._stats_over([{"skills": {"ranked": [], "apply": []}}], render=True)
        self.assertIn("no component ever named", out)
        self.assertIn("refused 1", out)


class TestLedgerRedaction(unittest.TestCase):
    """The ledger outlives the session, so secrets must never land in it."""

    def test_known_secret_shapes_are_redacted(self):
        for secret in ("sk-abcdefghij1234567890abcd",
                       "ghp_abcdefghij1234567890abcdefghij12",
                       "AKIAIOSFODNN7EXAMPLE",
                       "Bearer abcdefghijklmnopqrstuvwxyz123456"):
            self.assertIn("<redacted>", ledger.redact(f"token is {secret} ok"), secret)

    def test_ordinary_text_survives(self):
        s = "fix add() in calc.py, it subtracts"
        self.assertEqual(ledger.redact(s), s)

    def test_credential_shapes_that_previously_leaked(self):
        # Measured regressions: each of these passed an earlier version of the
        # pattern because of a character-class error in an alternative that was
        # *meant* to cover the vendor.
        leaks = {
            "github_pat": "github_pat_11ABCDEFG0abcdefghijkl_MnOpQrStUvWxYz0123456789AbCdEfGh",
            "stripe_live": "STRIPE=sk_live_" + "a" * 32,
            "stripe_restricted": "rk_live_" + "a" * 32,
            "slack_webhook": "https://hooks.slack.com/services/" + "/".join(["T" + "0" * 8, "B" + "0" * 8, "X" * 24]),
            "azure_accountkey": "AccountKey=" + "Ab0+/" * 12,
            "pypi": "pypi-" + "a" * 64,
            "short_url_password": "postgres://appuser:abc12@db.internal:5432/prod",
            "aws_secret_bare": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        }
        for label, raw in leaks.items():
            with self.subTest(label):
                self.assertIn("<redacted>", ledger.redact(raw))

    def test_private_key_body_is_redacted_not_just_its_header(self):
        # The worst shape of all: matching only the "-----BEGIN-----" delimiter
        # redacted the label and wrote the key material out verbatim.
        pem = ("-----BEGIN " + "RSA PRIVATE KEY-----\n"
               "MIIEpAIBAAKCAQEA5Ln8s0mVerySecretKeyMaterialHere\n"
               "-----END RSA PRIVATE KEY-----")
        out = ledger.redact(pem)
        self.assertNotIn("MIIEpAIBAAKCAQEA", out)
        self.assertNotIn("SecretKeyMaterial", out)

    def test_jwt_signature_is_redacted_too(self):
        import base64
        parts = [json.dumps({"alg": "HS256"}), json.dumps({"sub": "synthetic-test"}), "synthetic-signature"]
        jwt = ".".join(base64.urlsafe_b64encode(part.encode()).decode().rstrip("=") for part in parts)
        self.assertEqual(ledger.redact(jwt), "<redacted>")

    def test_git_sha_and_hashes_are_not_false_positives(self):
        # The AWS-key shape rule matches 40 chars of base64; a 40-char hex SHA-1
        # must not be caught, because commit ids are useful telemetry.
        for keep in ("commit 1a2b3c4d5e6f7890abcdef1234567890abcdef12 touched three files",
                     "sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                     "run pytest tests/test_live.py -k switch"):
            with self.subTest(keep[:24]):
                self.assertEqual(ledger.redact(keep), keep)

    def test_secret_in_a_dict_key_is_scrubbed(self):
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            ledger.log_event(c, "route", "t", {
                "env": {"ANTHROPIC_API_KEY=sk-ant-api03-REALSECRET012345678901234567890AA": "present"}})
            self.assertNotIn("REALSECRET", (Path(d) / "ledger.jsonl").read_text())

    def test_unserialisable_value_does_not_discard_the_record(self):
        # A dropped live_session silently removes a whole predicted-vs-actual
        # sample while stats() reports a smaller, biased count. A visible
        # placeholder is analysable; a hole is not.
        class Opaque:
            pass

        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            ledger.log_event(c, "live_session", "t", {"obj": Opaque(), "model": "sonnet"})
            recs = ledger.read_events(c)
            self.assertEqual([r["event"] for r in recs], ["live_session"])
            # _scrub reduces the opaque value to its repr, so the rest of the
            # record -- the part the campaign reads -- survives intact rather
            # than the whole line being discarded.
            self.assertEqual(recs[0]["data"]["model"], "sonnet")
            self.assertIn("Opaque", recs[0]["data"]["obj"])

    def test_a_serialisation_failure_degrades_to_a_marker_not_a_hole(self):
        # Backstop for anything _scrub cannot reduce: the line must still be
        # written, because a missing live_session is an invisible gap in the
        # dataset while a marker is analysable.
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            with mock.patch.object(ledger, "_scrub", side_effect=lambda o, *a, **k: o):
                ledger.log_event(c, "live_session", "t", {"obj": object()})
            recs = ledger.read_events(c)
            self.assertEqual([r["event"] for r in recs], ["live_session"])
            self.assertTrue(recs[0]["data"].get("unserialisable"))

    def test_deep_nesting_does_not_discard_the_record(self):
        deep = cur = {}
        for _ in range(2000):
            cur["n"] = {}
            cur = cur["n"]
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            ledger.log_event(c, "route", "t", deep)
            self.assertEqual(len(ledger.read_events(c)), 1)

    def test_nan_does_not_produce_invalid_jsonl(self):
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            ledger.log_event(c, "route", "t", {"x": float("nan")})
            body = (Path(d) / "ledger.jsonl").read_text()
            self.assertNotIn("NaN", body)

    def test_ledger_is_created_private(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "fresh.jsonl"
            c = cfg()
            c["telemetry"]["path"] = str(p)
            ledger.log_event(c, "route", "t", {"ok": True})
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_reading_rejects_a_non_config(self):
        # Silently defaulting to the real ledger turned a caller mistake into a
        # plausible-looking report of production data.
        with self.assertRaises(TypeError):
            ledger.read_events({"routes": 5, "confidence": {}})

    def test_nested_structures_are_scrubbed(self):
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "ledger.jsonl")
            ledger.log_event(c, "t", "prompt", {"a": ["sk-abcdefghij1234567890abcd"],
                                                "b": {"c": "ghp_abcdefghij1234567890abcdefghij12"}})
            body = (Path(d) / "ledger.jsonl").read_text()
            self.assertNotIn("sk-abcdefghij", body)
            self.assertNotIn("ghp_abcdefghij", body)
            self.assertIn("<redacted>", body)

    def test_prompt_text_is_hashed_not_stored_by_default(self):
        with tempfile.TemporaryDirectory() as d:
            c = cfg()
            c["telemetry"]["path"] = str(Path(d) / "l.jsonl")
            ledger.log_event(c, "route", "a very secret task description", {"ok": True})
            rec = json.loads((Path(d) / "l.jsonl").read_text().strip())
            self.assertNotIn("text", rec)
            self.assertEqual(len(rec["sha256"]), 64)

    def test_telemetry_failure_never_raises(self):
        c = cfg()
        c["telemetry"]["path"] = "/nonexistent-root-dir-xyz/nope/l.jsonl"
        ledger.log_event(c, "route", "task", {"ok": True})  # must not raise


class TestObserverPhase(unittest.TestCase):
    def test_tool_mix_maps_to_phase(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        o.tools = ["Read", "Grep", "Read"]
        self.assertEqual(o.phase(), "investigate")
        o.tools = ["Edit", "Write"]
        self.assertEqual(o.phase(), "implement")
        o.tools = ["Bash"]
        self.assertEqual(o.phase(), "verify")
        o.tools = []
        self.assertEqual(o.phase(), "reason")

    def test_unknown_tools_do_not_crash_phase(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        o.tools = ["SomeFutureTool"]
        self.assertIn(o.phase(), ("reason", "verify"))

    def test_done_marker_detection(self):
        from live_supervisor import _looks_done
        self.assertTrue(_looks_done("work finished TASK_COMPLETE", "TASK_COMPLETE"))
        self.assertFalse(_looks_done("still going", "TASK_COMPLETE"))
        self.assertFalse(_looks_done("TASK_COMPLETE", ""))  # no marker configured


class TestContextTokenMonotonicity(unittest.TestCase):
    """The gate's re-cache hysteresis is only sound if its token counter is monotone.

    Regression for the defect where `tokens` was a per-turn max reset every turn:
    a high-cache turn followed by a low-cache turn made the gate's delta negative,
    so `min_tokens` blocked every switch for the rest of the session while the
    telemetry looked like the policy working correctly.
    """

    def _turn(self, obs, *, inp=0, create=0, read=0):
        obs.note({"type": "assistant", "message": {
            "model": "claude-sonnet-5",
            "usage": {"input_tokens": inp, "cache_creation_input_tokens": create,
                      "cache_read_input_tokens": read},
            "content": []}})

    def test_counter_never_decreases_across_turns(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        self._turn(o, inp=2, read=30000, create=5000)   # cache-heavy turn
        high = o.tokens
        o.reset()
        self._turn(o, inp=10, read=0, create=1000)      # post-switch, cache cold
        self.assertGreaterEqual(o.tokens, high)

    def test_reset_preserves_context_counter(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        self._turn(o, inp=5, read=20000)
        before = o.tokens
        o.reset()
        self.assertEqual(o.tokens, before)
        self.assertEqual(o.tools, [])  # per-turn state IS cleared

    def test_malformed_usage_does_not_crash_or_reset(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        self._turn(o, inp=1, read=10000)
        before = o.tokens
        o.note({"type": "assistant", "message": {"usage": {"input_tokens": None,
                                                           "cache_read_input_tokens": "x"},
                                                 "content": []}})
        self.assertEqual(o.tokens, before)

    def test_gate_still_switches_after_a_cache_heavy_switch(self):
        """End-to-end of the regression: two switches must remain possible."""
        from live_supervisor import TurnObserver
        o = TurnObserver()
        c = cfg(min_seconds_between_switches=0)
        g = SwitchGate(c, "balanced", "sonnet", now=0.0)
        self._turn(o, inp=2, read=30000, create=5000)
        v1 = g.evaluate("opus", 0.95, turn=2, now=100, tokens_seen=o.tokens)
        self.assertTrue(v1["switch"])
        g.commit(v1, now=100, tokens_seen=o.tokens)
        o.reset()
        self._turn(o, inp=10, create=60000)  # context grew past the threshold
        v2 = g.evaluate("haiku", 0.95, turn=6, now=900, tokens_seen=o.tokens)
        self.assertTrue(v2["switch"], f"second switch wrongly blocked: {v2}")


class TestDirectionalSignals(unittest.TestCase):
    """`stuck` may only reinforce escalation; `simplified` only de-escalation."""

    def _answers(self, tier, conf, *, stuck=0.0, simplified=0.0, thinking=0.0):
        return {
            "needed_tier": {"choice": tier, "confidence": conf},
            "is_stuck": {"noul": stuck},
            "work_simplified": {"noul": simplified},
            "needs_more_thinking": {"noul": thinking},
        }

    def _obs(self):
        from live_supervisor import TurnObserver
        o = TurnObserver()
        o.tools = ["Edit"]
        o.context_tokens = 80000
        return o

    def test_simplified_cannot_push_an_escalation_through(self):
        from live_supervisor import decide
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        a = self._answers("opus", 0.10, simplified=0.95)
        v, _ = decide(a, g, self._obs(), turn=4, now=1000, cfg=cfg())
        self.assertFalse(v["switch"], "de-escalation evidence escalated the tier")

    def test_stuck_cannot_push_a_deescalation_through(self):
        from live_supervisor import decide
        g = SwitchGate(cfg(), "balanced", "opus", now=0.0)
        a = self._answers("haiku", 0.10, stuck=0.95)
        v, _ = decide(a, g, self._obs(), turn=4, now=1000, cfg=cfg())
        self.assertFalse(v["switch"], "escalation evidence de-escalated the tier")

    def test_stuck_does_reinforce_escalation(self):
        from live_supervisor import decide
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        a = self._answers("opus", 0.30, stuck=0.90)
        v, _ = decide(a, g, self._obs(), turn=4, now=1000, cfg=cfg())
        self.assertTrue(v["switch"], v)
        self.assertIn("stuck", v["reason"])

    def test_simplified_does_reinforce_deescalation(self):
        from live_supervisor import decide
        g = SwitchGate(cfg(), "balanced", "opus", now=0.0)
        a = self._answers("haiku", 0.30, simplified=0.95)
        v, _ = decide(a, g, self._obs(), turn=4, now=1000, cfg=cfg())
        self.assertTrue(v["switch"], v)
        self.assertIn("simplified", v["reason"])

    def test_malformed_answers_fail_open_to_no_switch(self):
        from live_supervisor import decide
        g = SwitchGate(cfg(), "balanced", "sonnet", now=0.0)
        for bad in ({}, {"needed_tier": None}, {"needed_tier": {"choice": None, "confidence": "x"}},
                    {"needed_tier": {"choice": "opus"}, "is_stuck": "garbage"}):
            v, eff = decide(bad, g, self._obs(), turn=2, now=500, cfg=cfg())
            self.assertFalse(v["switch"], bad)


class FakeProc:
    """Stand-in for the Claude child process: canned stdout, recorded stdin."""

    def __init__(self, frames, *, respond=True, delay=0.0):
        import io
        self._frames = frames
        self.respond = respond
        self.delay = delay
        self.written = []
        self.returncode = None
        self.stdout = io.StringIO("".join(json.dumps(f) + "\n" for f in frames))
        self.stderr = io.StringIO("some stderr line\n")
        outer = self

        class _Stdin:
            closed = False

            def write(self, s):
                outer.written.append(s)

            def flush(self):
                pass

            def close(self):
                self.closed = True

        self.stdin = _Stdin()

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self.returncode = 0
        return 0

    def terminate(self):
        self.returncode = -15

    def kill(self):
        self.returncode = -9


class TestClaudeSessionControl(unittest.TestCase):
    """control_request/response handshake, without launching Claude."""

    def _session(self, frames):
        import live_supervisor
        from unittest import mock
        proc = FakeProc(frames)
        with mock.patch.object(live_supervisor.subprocess, "Popen", return_value=proc):
            s = live_supervisor.ClaudeSession("sonnet")
        return s, proc

    def test_control_response_is_matched_by_request_id(self):
        s, proc = self._session([
            {"type": "control_response", "response": {"subtype": "success", "request_id": "drjev-1"}},
        ])
        ok, resp = s.control("set_model", timeout=5, model="opus")
        self.assertTrue(ok)
        self.assertEqual(resp["request_id"], "drjev-1")
        sent = json.loads(proc.written[0])
        self.assertEqual(sent["request"], {"subtype": "set_model", "model": "opus"})

    def test_refusal_is_reported_not_raised(self):
        s, _ = self._session([
            {"type": "control_response", "response": {"subtype": "error", "request_id": "drjev-1",
                                                      "error": "model_not_available_for_org"}},
        ])
        ok, resp = s.control("set_model", timeout=5, model="opus")
        self.assertFalse(ok)
        self.assertEqual(resp["subtype"], "error")

    def test_timeout_does_not_leak_a_pending_slot(self):
        s, _ = self._session([])  # no response ever arrives
        ok, resp = s.control("set_model", timeout=0.2, model="opus")
        self.assertFalse(ok)
        self.assertEqual(resp["subtype"], "timeout")
        self.assertEqual(s._ctrl, {}, "timed-out request left an entry behind")

    def test_unmatched_response_buffer_is_bounded(self):
        """A stream of responses nobody waits for must not grow without limit."""
        s, _ = self._session([])
        for i in range(200):
            with s._ctrl_lock:
                s._ctrl_early[f"drjev-{i}"] = {"subtype": "success"}
                while len(s._ctrl_early) > 32:
                    s._ctrl_early.pop(next(iter(s._ctrl_early)))
        self.assertLessEqual(len(s._ctrl_early), 32)

    def test_response_arriving_before_the_waiter_is_still_matched(self):
        """The child may answer faster than the main thread reaches the wait."""
        s, _ = self._session([
            {"type": "control_response", "response": {"subtype": "success", "request_id": "drjev-1"}},
        ])
        import time as _t
        _t.sleep(0.2)  # let the reader park the response first
        ok, resp = s.control("set_model", timeout=5, model="opus")
        self.assertTrue(ok, f"early response was lost: {resp}")

    def test_non_control_frames_reach_the_event_queue(self):
        s, _ = self._session([
            {"type": "assistant", "session_id": "abc", "message": {"model": "m", "content": []}},
            {"type": "result", "total_cost_usd": 0.01},
        ])
        seen = []
        for _ in range(3):
            ev = s.events.get(timeout=5)
            seen.append(ev.get("type"))
            if ev.get("type") == "__eof__":
                break
        self.assertEqual(seen, ["assistant", "result", "__eof__"])

    def test_ask_returns_false_on_dead_child_instead_of_raising(self):
        s, proc = self._session([])
        proc.returncode = 1
        self.assertFalse(s.ask("hello"))

    def test_control_on_dead_child_returns_error(self):
        s, proc = self._session([])
        proc.returncode = 1
        ok, resp = s.control("set_model", timeout=1, model="opus")
        self.assertFalse(ok)
        self.assertEqual(resp["subtype"], "error")
        self.assertEqual(s._ctrl, {})

    def test_stderr_tail_is_retained_for_diagnosis(self):
        s, _ = self._session([])
        import time as _t
        for _ in range(20):
            if s.stderr_tail():
                break
            _t.sleep(0.05)
        self.assertTrue(any("stderr" in ln for ln in s.stderr_tail()))


class TestRenderSummaryRobustness(unittest.TestCase):
    """The summary is cosmetic and must never abort a run."""

    def test_malformed_selection_still_renders(self):
        from live_supervisor import render_summary
        for bad in (
            {},
            {"selection": {"skills": {"apply": [{"name": "x"}]}}},          # missing score
            {"selection": {"agents": {"choice": "dev", "confidence": None}}},
            {"selection": {"skills": {"apply": ["not-a-dict"]}}},
            {"selection": {"skills": {"mention": [{"score": 0.5}]}}},       # missing name
            {"answers": {"complexity": None}},
            {"answers": {"needs_system2": {"noul": "x"}}},
        ):
            out = render_summary(bad)
            self.assertIn("Datarim", out, f"renderer produced nothing for {bad}")

    def test_runtime_is_shown_when_given(self):
        from live_supervisor import render_summary
        out = render_summary({"mode": "balanced", "model": "sonnet"}, runtime="codex")
        self.assertIn("codex", out)

    def test_well_formed_decision_renders(self):
        from live_supervisor import render_summary
        out = render_summary({
            "mode": "balanced", "model": "sonnet",
            "answers": {"complexity": {"score": 2.4}, "needs_system2": {"noul": 0.9}},
            "selection": {"skills": {"apply": [{"name": "testing", "score": 0.84}], "mention": []},
                          "agents": {"choice": "tester", "confidence": 0.93, "applied": True}},
            "usage": {"input_tokens": 10, "output_tokens": 2},
        })
        self.assertIn("testing 0.84", out)
        self.assertIn("Sonnet".lower(), out.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
