#!/usr/bin/env python3
"""The operator's --mode must reach the session's prompt hook, and --live must not route twice.

Measured on a live host (2026-09-27) before this fix: 272 prompts launched with
`jevclaude --live --mode quality` were routed once by the supervisor in quality
and again by the prompt hook in balanced. The hook never saw the mode: nothing
exported it, and the hook's environment scrub drops every DATARIM_* variable.
On the same input the advised tier differed on 233 of 272 (always higher under
quality), so the advice an agent saw was not the advice the operator asked for.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
S = ROOT / 'plugins/dr-jev-control/scripts'
sys.path.insert(0, str(ROOT / 'scripts')); sys.path.insert(0, str(S))
import jev
import jev_hook
import live_supervisor
import prompt_cache


class HookEnvironmentKeepsOnlyAValidMode(unittest.TestCase):
    def _env(self, extra):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d).resolve(); runtime = base / 'rt'; runtime.mkdir(); project = base / 'p'; project.mkdir()
            cfg = base / 'cfg.json'; cfg.write_text('{}'); cfg.chmod(0o600)
            m = runtime / 'host-installation.json'
            m.write_text(json.dumps({'schema': 1, 'runtime': str(runtime), 'config': str(cfg),
                                     'key_file': str(base / 'k'), 'state_dir': str(base / 'state')})); m.chmod(0o600)
            with mock.patch.dict(os.environ, extra, clear=True):
                env, _ = jev_hook.environment({'cwd': str(project)}, runtime=runtime)
        return env

    def test_known_modes_survive_the_scrub(self):
        for mode in ('economy', 'balanced', 'quality'):
            self.assertEqual(self._env({'DATARIM_JEV_MODE': mode}).get('DATARIM_JEV_MODE'), mode)

    def test_anything_else_is_dropped_and_other_datarim_vars_still_are(self):
        env = self._env({'DATARIM_JEV_MODE': '../quality', 'DATARIM_ROOT': 'foreign'})
        self.assertNotIn('DATARIM_JEV_MODE', env)
        self.assertNotIn('DATARIM_ROOT', env)
        self.assertNotIn('DATARIM_JEV_MODE', self._env({}))


class ParseKnowsWhetherTheModeWasChosen(unittest.TestCase):
    def test_explicit_and_default(self):
        a, _ = jev.parse(['--agent', 'codex', '--mode', 'quality', 'do it'])
        self.assertEqual((a.mode, a.mode_explicit), ('quality', True))
        a, _ = jev.parse(['--agent', 'codex', 'do it'])
        self.assertEqual((a.mode, a.mode_explicit), ('balanced', False))


class ClientProcessReceivesTheMode(unittest.TestCase):
    """Drives the real jev.py exec chain into a fake client that reports its environment."""

    def _launch(self, *mode):
        with tempfile.TemporaryDirectory() as d:
            project = (Path(d) / 'project').resolve(); project.mkdir()
            runtime = project / '.datarim-runtime'; runtime.mkdir()
            (runtime / 'plugins').symlink_to(ROOT / 'plugins')
            (runtime / 'installation.json').write_text(json.dumps({'schema': 1, 'project': str(project),
                                                                    'with_jev': False}))
            out = Path(d) / 'seen'
            fake = Path(d) / 'codex'
            fake.write_text(f'#!/bin/sh\necho "${{DATARIM_JEV_MODE-unset}}" > "{out}"\n'); fake.chmod(0o755)
            env = {k: v for k, v in os.environ.items() if not k.startswith(('DATARIM_', 'JEV_'))}
            env['CODEX_BIN'] = str(fake)
            r = subprocess.run([sys.executable, str(ROOT / 'scripts/jev.py'), '--agent', 'codex', *mode,
                                'do the thing', '--'], cwd=project, env=env, capture_output=True, text=True,
                               timeout=30)
            self.assertTrue(out.exists(), r.stderr)
            return out.read_text().strip()

    def test_explicit_mode_is_exported(self):
        self.assertEqual(self._launch('--mode', 'quality'), 'quality')

    def test_no_mode_leaves_the_configured_default_in_charge(self):
        self.assertEqual(self._launch(), 'unset')


class LiveHandsItsDecisionToTheHook(unittest.TestCase):
    def test_first_prompt_is_served_from_the_cache(self):
        decision = {'ok': True, 'model': 'opus', 'mode': 'quality', 'answers': {}, 'selection': {}}

        class Stop(Exception):
            pass

        def build(*a, **k):
            raise Stop

        with tempfile.TemporaryDirectory() as d, \
             mock.patch.dict(os.environ, {'JEV_STATE_DIR': d}, clear=False), \
             mock.patch.object(live_supervisor, 'route', lambda *a, **k: dict(decision)), \
             mock.patch.object(live_supervisor.runtimes, 'build', build):
            os.environ.pop('JEV_PROMPT_CACHE', None); os.environ.pop('JEV_HOST_STATE', None)
            with self.assertRaises(Stop):
                live_supervisor.run('the task', mode='quality', cfg={'routing': {}}, extra_args=[], quiet=True,
                                    explain=False, max_turns=1)
            self.assertIn('JEV_PROMPT_CACHE', os.environ)
            self.assertEqual(prompt_cache.consume('the task')['model'], 'opus')
            os.environ.pop('JEV_PROMPT_CACHE', None)

    def test_failed_route_leaves_no_cache(self):
        with mock.patch.object(live_supervisor, 'route', mock.Mock(side_effect=RuntimeError('down'))), \
             mock.patch.object(live_supervisor.runtimes, 'build', mock.Mock(side_effect=KeyError('stop'))):
            os.environ.pop('JEV_PROMPT_CACHE', None)
            with self.assertRaises(KeyError):
                live_supervisor.run('t', mode='quality', cfg={'routing': {}}, extra_args=[], quiet=True,
                                    explain=False, max_turns=1)
            self.assertNotIn('JEV_PROMPT_CACHE', os.environ)


if __name__ == '__main__':
    unittest.main()
