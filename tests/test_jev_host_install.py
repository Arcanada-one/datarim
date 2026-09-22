"""Host installer lifecycle in a disposable home, never the operator's home."""
from argparse import Namespace
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import jev_host_install as installer


class HostInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.project = self.home/'project'; self.project.mkdir()
        self.args = Namespace(home=str(self.home), client=['claude', 'codex', 'cursor'],
                              datarim_project=[str(self.project)], replace_legacy_root=[], dry_run=False)
        self.sha = 'a'*40

    def install(self):
        def git(argv, **kwargs):
            return self.sha+'\n' if 'rev-parse' in argv else ''
        with patch.object(installer.subprocess, 'check_output', git), contextlib.redirect_stdout(io.StringIO()):
            installer.install(self.args)

    def test_private_key_idempotent_registration_and_standalone_dispatch(self):
        self.install()
        cfg = self.home/'.claude/settings.json'
        original = json.loads(cfg.read_text())
        self.install()
        self.assertEqual(json.loads(cfg.read_text()), original)
        key = self.home/'.config/jev/credentials/api-key'
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(key.read_bytes(), b'')
        runtime = self.home/'.local/share/jev/releases'/self.sha
        self.assertFalse((runtime/'skills').exists())
        self.assertFalse((runtime/'AGENTS.md').exists())
        env = dict(os.environ, CODEX_BIN='/usr/bin/true')
        result = subprocess.run([sys.executable, str(runtime/'scripts/jev.py'), '--agent=codex', '--dry-run'],
                                cwd=self.project, env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['network_calls'], 0)
        self.assertFalse((self.project/'.datarim-runtime').exists())
        self.assertFalse((self.project/'datarim').exists())

    def test_partial_registration_failure_restores_foreign_config(self):
        target = self.home/'.claude/settings.json'; target.parent.mkdir()
        before = b'{"env":{"FOREIGN":"preserve"}}\n'; target.write_bytes(before)
        write = installer.atomic_write
        def fail_codex(path, data):
            if path == self.home/'.codex/hooks.json':
                raise OSError('synthetic write failure')
            return write(path, data)
        with patch.object(installer, 'atomic_write', fail_codex):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual(target.read_bytes(), before)
        self.assertFalse((self.home/'.config/jev/config.json').exists())

    def test_symlinked_registration_is_rejected_before_mutation(self):
        outside = self.home/'outside'; outside.write_text('unchanged')
        folder = self.home/'.codex'; folder.mkdir()
        (folder/'hooks.json').symlink_to(outside)
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(outside.read_text(), 'unchanged')
        self.assertFalse((self.home/'.claude/settings.json').exists())


if __name__ == '__main__':
    unittest.main()
