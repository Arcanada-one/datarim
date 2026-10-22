"""Client binary discovery without relying on interactive shell PATH."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'plugins/dr-jev-control/scripts'))

import jev  # noqa: E402
import runtimes  # noqa: E402


class BinaryDiscovery(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        for key in ('CLAUDE_BIN', 'CODEX_BIN', 'CURSOR_BIN'):
            os.environ.pop(key, None)

    def _plant(self, relative, name='codex'):
        directory = self.home / relative
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        path.write_text('#!/bin/sh\n')
        path.chmod(0o755)
        return path

    def test_finds_codex_under_npm_global_when_path_lacks_it(self):
        planted = self._plant('.npm-global/bin', 'codex')
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/no-such-bin-dir'}):
                found = jev.binary('codex')
        self.assertEqual(found, str(planted))

    def test_finds_codex_under_local_bin(self):
        planted = self._plant('.local/bin', 'codex')
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/no-such-bin-dir'}):
                found = jev.binary('codex')
        self.assertEqual(found, str(planted))

    def test_override_env_wins_over_well_known_dirs(self):
        self._plant('.npm-global/bin', 'codex')
        override = self._plant('.override', 'my-codex')
        os.environ['CODEX_BIN'] = str(override)
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/no-such-bin-dir', 'CODEX_BIN': str(override)}):
                found = jev.binary('codex')
        self.assertEqual(found, str(override))

    def test_cursor_falls_back_to_agent_in_well_known_dir(self):
        planted = self._plant('.local/bin', 'agent')
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/no-such-bin-dir'}):
                found = jev.binary('cursor')
        self.assertEqual(found, str(planted))

    def test_prepend_puts_well_known_dirs_ahead_of_path(self):
        (self.home / '.npm-global' / 'bin').mkdir(parents=True)
        (self.home / '.local' / 'bin').mkdir(parents=True)
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/usr/bin'}, clear=False):
                # Drop orca dir presence so only home dirs matter.
                with mock.patch.object(jev, 'agent_search_dirs',
                                       return_value=[self.home / '.local' / 'bin',
                                                     self.home / '.npm-global' / 'bin']):
                    jev.prepend_agent_search_dirs_to_path()
                    parts = os.environ['PATH'].split(os.pathsep)
        self.assertEqual(parts[0], str(self.home / '.local' / 'bin'))
        self.assertEqual(parts[1], str(self.home / '.npm-global' / 'bin'))
        self.assertIn('/usr/bin', parts)

    def test_runtimes_available_sees_npm_global_codex(self):
        planted = self._plant('.npm-global/bin', 'codex')
        with mock.patch.object(Path, 'home', return_value=self.home):
            with mock.patch.dict(os.environ, {'PATH': '/no-such-bin-dir'}):
                self.assertTrue(runtimes.available('codex'))
                self.assertEqual(runtimes.resolve_client_binary('codex'), str(planted))


if __name__ == '__main__':
    unittest.main()
