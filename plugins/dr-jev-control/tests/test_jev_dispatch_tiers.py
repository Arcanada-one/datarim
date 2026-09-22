#!/usr/bin/env python3
"""How `jev` turns a routing tier into client arguments.

Covers the dispatcher itself rather than the supervisor runtimes: the two
express a tier differently, and only this path runs for an ordinary
`jevclaude` / `jevcodex` invocation.
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
JEV = ROOT/'scripts/jev.py'
SCRIPTS = ROOT/'plugins/dr-jev-control/scripts'
sys.path.insert(0, str(SCRIPTS))
from runtimes import (  # noqa: E402
    CODEX_EFFORT_ORDER, CODEX_TIER_PREFERENCES, codex_tier_settings)


class CodexTierUsesTheAccountsOwnCatalogue(unittest.TestCase):
    """A tier resolves against ~/.codex/models_cache.json, not a hardcoded list."""

    CACHE = {'models': [
        {'slug': 'gpt-6-astra', 'visibility': 'list', 'default_reasoning_level': 'medium',
         'supported_reasoning_levels': [{'effort': e} for e in
                                        ('low', 'medium', 'high', 'xhigh', 'max', 'ultra')]},
        {'slug': 'gpt-5.6-terra', 'visibility': 'list', 'default_reasoning_level': 'medium',
         'supported_reasoning_levels': [{'effort': e} for e in
                                        ('low', 'medium', 'high', 'xhigh', 'max', 'ultra')]},
        {'slug': 'gpt-5.6-luna', 'visibility': 'list', 'default_reasoning_level': 'medium',
         'supported_reasoning_levels': [{'effort': e} for e in
                                        ('low', 'medium', 'high', 'xhigh', 'max')]},
    ]}

    def _home(self, cache):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = pathlib.Path(tmp.name)
        (home/'.codex').mkdir()
        if cache is not None:
            (home/'.codex/models_cache.json').write_text(json.dumps(cache))
        return home

    def test_each_tier_picks_a_distinct_model_from_the_cache(self):
        home = self._home(self.CACHE)
        got = {t: codex_tier_settings(t, home) for t in ('haiku', 'sonnet', 'opus')}
        self.assertEqual(got['haiku'], ('gpt-5.6-luna', 'low'))
        self.assertEqual(got['sonnet'], ('gpt-5.6-terra', 'medium'))
        self.assertEqual(got['opus'], ('gpt-6-astra', 'high'))
        models = [m for m, _ in got.values()]
        self.assertEqual(len(set(models)), 3,
                         'tiers that collapse to one model cannot steer Codex by model at all')

    def test_a_model_absent_from_this_account_is_skipped_not_attempted(self):
        """An unavailable id is only rejected server-side, mid-run, as HTTP 400."""
        thin = {'models': [m for m in self.CACHE['models'] if m['slug'] == 'gpt-5.6-luna']}
        model, effort = codex_tier_settings('opus', self._home(thin))
        self.assertIsNone(model, 'preferred opus models are absent here; none may be invented')
        self.assertEqual(effort, 'high', 'effort still steers when no model is available')

    def test_effort_is_clamped_to_what_the_chosen_model_supports(self):
        """gpt-5.5 stops at xhigh; the CLI would not complain, the server would."""
        cache = {'models': [{'slug': 'gpt-5.6-luna', 'visibility': 'list',
                             'default_reasoning_level': 'medium',
                             'supported_reasoning_levels': [{'effort': 'low'}]}]}
        model, effort = codex_tier_settings('sonnet', self._home(cache))
        self.assertEqual(model, 'gpt-5.6-luna')
        self.assertEqual(effort, 'low',
                         'medium is unsupported by this model, so the tier must step down')

    def test_a_missing_cache_falls_back_to_effort_only(self):
        model, effort = codex_tier_settings('opus', self._home(None))
        self.assertIsNone(model)
        self.assertEqual(effort, 'high')

    def test_documented_but_rejected_effort_is_not_offered(self):
        """`minimal` is in OpenAI's config reference and the API refuses it."""
        self.assertNotIn('minimal', CODEX_EFFORT_ORDER)
        for _, effort in CODEX_TIER_PREFERENCES.values():
            with self.subTest(effort=effort):
                self.assertIn(effort, CODEX_EFFORT_ORDER)


class ResumeStillRoutes(unittest.TestCase):
    """Resuming is the normal way long work continues, so it must route too.

    MEASURED 2026-09-22 on dev-ai: a session resumed with `jevcodex -- resume <id>`
    produced 111 hook_delivery events and ZERO route events, because routing is
    gated on a positional task that a resume does not supply. The session kept
    whatever tier it was last started with.
    """

    def setUp(self):
        """A real project installation: jev refuses to run outside one."""
        self._tmp = tempfile.TemporaryDirectory()
        self.project = pathlib.Path(self._tmp.name).resolve()
        manifest = self.project/'.datarim-runtime'
        manifest.mkdir()
        (manifest/'installation.json').write_text(json.dumps({
            'schema': 1, 'project': str(self.project),
            'with_jev': True, 'host_jev': False, 'contexts': [], 'files': {},
        }))
        self.addCleanup(self._tmp.cleanup)

    def _argv(self, *args):
        """Ask jev what it would exec, without executing it."""
        return subprocess.run(
            [sys.executable, str(JEV), '--dry-run', *args],
            capture_output=True, text=True, timeout=60,
            cwd=str(self.project))

    def test_dry_run_returns_before_any_routing_happens(self):
        """`--dry-run` cannot show a tier, and must not be read as if it could.

        MEASURED: jev.py returns on its `--dry-run` branch (~line 174) before the
        routing gate (~line 196), so its JSON carries no model or effort for any
        input. Recorded as a test because the output *looks* like a full plan —
        it names the agent, binary, project and scope — and reading it as "no
        tier was chosen" is a false negative. Two probes in this project's own
        bring-up were wasted on exactly that.
        """
        trivial = self._argv('--agent=codex', 'fix a typo')
        complex_ = self._argv('--agent=codex',
                              'design a byzantine-fault-tolerant consensus protocol')
        for proc in (trivial, complex_):
            with self.subTest(stdout=proc.stdout[:60]):
                self.assertNotIn('Jev recommends', proc.stderr)
                self.assertNotIn('model', proc.stdout)
                self.assertNotIn('effort', proc.stdout)
        self.assertEqual(trivial.stdout, complex_.stdout,
                         'if dry-run ever starts differing by task, it has begun routing '
                         'and this test should be replaced by one that checks the tier')
