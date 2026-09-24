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

    # -- a stable hook command ------------------------------------------------
    # Codex stores sha256 over each hook's normalized command as `trusted_hash`
    # and skips any hook whose hash has moved. These pin the property that
    # keeps an operator's trust across upgrades: the registered command string
    # is identical before and after a reinstall at a different revision.

    def _jev_commands(self, rel):
        data = json.loads((self.home/rel).read_text())
        out = []
        def walk(node):
            if isinstance(node, dict):
                if isinstance(node.get('command'), str) and 'jev' in node['command']:
                    out.append(node['command'])
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)
        walk(data.get('hooks', {}))
        return out

    def test_an_upgrade_leaves_every_registered_command_byte_identical(self):
        self.install()
        before = {rel: self._jev_commands(rel) for rel in
                  ('.claude/settings.json', '.codex/hooks.json', '.cursor/hooks.json')}
        self.sha = 'b'*40
        self.install()
        after = {rel: self._jev_commands(rel) for rel in before}
        self.assertEqual(after, before)
        self.assertEqual(len(before['.codex/hooks.json']), 3)
        pointer = json.loads((self.home/'.config/jev/installation.json').read_text())
        self.assertTrue(pointer['runtime'].endswith('b'*40))

    def test_no_registered_command_names_a_release_directory(self):
        """The negative half: a command naming releases/<sha> is the defect."""
        self.install()
        for rel in ('.claude/settings.json', '.codex/hooks.json', '.cursor/hooks.json'):
            for command in self._jev_commands(rel):
                self.assertNotIn('releases/', command)
                self.assertIn('/.local/share/jev/bin/jev-hook', command)

    def test_release_pinned_commands_from_an_older_install_are_replaced(self):
        target = self.home/'.codex/hooks.json'; target.parent.mkdir()
        old = str(self.home/'.local/share/jev/releases'/('c'*40)/'scripts/jev_hook.py')
        target.write_text(json.dumps({'hooks': {'UserPromptSubmit': [
            {'hooks': [{'type': 'command', 'command': '/opt/orca-hook', 'timeout': 10}]},
            {'hooks': [{'type': 'command', 'command': f'{sys.executable} {old} codex UserPromptSubmit',
                        'timeout': 9}]}]}}))
        self.install()
        commands = [h['command'] for g in json.loads(target.read_text())['hooks']['UserPromptSubmit']
                    for h in g['hooks']]
        self.assertIn('/opt/orca-hook', commands)
        self.assertEqual(sum('jev' in c for c in commands), 1)
        self.assertFalse(any('releases/' in c for c in commands))

    def test_the_entry_point_dispatches_to_the_active_release(self):
        self.install()
        entry = self.home/'.local/share/jev/bin/jev-hook'
        env = dict(os.environ, HOME=str(self.home))
        payload = json.dumps({'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                              'tool_input': {'command': 'rm -rf /'}, 'cwd': str(self.project),
                              'session_id': 'entry-probe'})
        result = subprocess.run([sys.executable, str(entry), 'claude', 'PreToolUse'], input=payload,
                                env=env, cwd=self.project, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        # The safety floor answers, which only the release's jev_hook.py can do.
        self.assertIn('"deny"', result.stdout)

    def test_the_entry_point_is_executable_and_runs_directly(self):
        self.install()
        entry = self.home/'.local/share/jev/bin/jev-hook'
        self.assertEqual(entry.stat().st_mode & 0o777, 0o755)
        env = dict(os.environ, HOME=str(self.home))
        payload = json.dumps({'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                              'tool_input': {'command': 'rm -rf /'}, 'cwd': str(self.project)})
        result = subprocess.run([str(entry), 'claude', 'PreToolUse'], input=payload, env=env,
                                cwd=self.project, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"deny"', result.stdout)

    def test_the_entry_point_fails_open_on_a_broken_pointer(self):
        self.install()
        (self.home/'.config/jev/installation.json').write_text('{not json')
        env = dict(os.environ, HOME=str(self.home))
        result = subprocess.run([sys.executable, str(self.home/'.local/share/jev/bin/jev-hook'),
                                 'claude', 'UserPromptSubmit'], input='{}', env=env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('jev-hook:', result.stderr)

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

    def test_update_preserves_omitted_allowlist_and_project_launcher_uses_host(self):
        self.install()
        self.args.datarim_project = None
        self.install()
        cfg = json.loads((self.home/'.config/jev/config.json').read_text())
        self.assertEqual(cfg['datarim_projects'], [str(self.project)])
        runtime = self.project/'.datarim-runtime'; runtime.mkdir()
        (runtime/'installation.json').write_text(json.dumps({'schema': 1,
            'project': str(self.project), 'host_jev': True, 'with_jev': True}))
        result = subprocess.run([sys.executable, str(ROOT/'scripts/jev.py'), '--agent=codex', '--dry-run'],
                                cwd=self.project, env=dict(os.environ, HOME=str(self.home), CODEX_BIN='/usr/bin/true'),
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['scope'], 'host')
        self.assertTrue(report['datarim_enabled'])

    def test_symlinked_registration_is_rejected_before_mutation(self):
        outside = self.home/'outside'; outside.write_text('unchanged')
        folder = self.home/'.codex'; folder.mkdir()
        (folder/'hooks.json').symlink_to(outside)
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(outside.read_text(), 'unchanged')
        self.assertFalse((self.home/'.claude/settings.json').exists())


class StableInterpreter(unittest.TestCase):
    """Hook commands must survive an interpreter upgrade: a versioned path
    (`.../python@3.14/bin/python3.14`) breaks every hook at the next one."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name).resolve()
        self.pinned = base/'opt/python@3.99/bin/python3.99'
        self.pinned.parent.mkdir(parents=True)
        self.pinned.write_text('#!/bin/sh\n')
        self.pinned.chmod(0o755)
        self.bin = base/'bin'
        self.bin.mkdir()

    def test_an_unversioned_name_for_the_same_interpreter_is_preferred(self):
        (self.bin/'python3').symlink_to(self.pinned)
        self.assertEqual(installer.hook_interpreter(str(self.pinned), str(self.bin)), str(self.bin/'python3'))

    def test_a_different_interpreter_on_path_is_not_substituted(self):
        other = self.bin/'python3'
        other.write_text('#!/bin/sh\n')
        other.chmod(0o755)
        self.assertEqual(installer.hook_interpreter(str(self.pinned), str(self.bin)), str(self.pinned))

    def test_an_unversioned_executable_is_kept(self):
        self.assertEqual(installer.hook_interpreter('/usr/bin/python3', str(self.bin)), '/usr/bin/python3')

    def test_registered_commands_use_it(self):
        (self.bin/'python3').symlink_to(self.pinned)
        with patch.object(installer.sys, 'executable', str(self.pinned)), \
                patch.dict(os.environ, {'PATH': str(self.bin)}):
            merged = installer.merge_hooks({}, 'codex', Path('/r'), [Path('/r')])
        commands = [h['command'] for groups in merged['hooks'].values() for g in groups for h in g['hooks']]
        self.assertTrue(commands)
        self.assertTrue(all(c.startswith(str(self.bin/'python3') + ' ') for c in commands), commands)
        self.assertFalse(any('3.99' in c for c in commands))


if __name__ == '__main__':
    unittest.main()
