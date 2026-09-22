"""Project isolation, lossless installation and CLI boundary regression tests."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from project_scope import ScopeError, project_root
import project_install


class ProjectScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()/'project'
        self.root.mkdir()

    def mark(self):
        runtime = self.root/'.datarim-runtime'
        runtime.mkdir()
        (runtime/'installation.json').write_text(json.dumps({'schema': 1, 'project': str(self.root)}))

    def test_no_home_or_neighbor_fallback(self):
        self.mark()
        sibling = self.root.parent/'project-elsewhere'
        sibling.mkdir()
        with self.assertRaises(ScopeError):
            project_root(sibling)

    def test_nested_repository_requires_explicit_context(self):
        self.mark()
        nested = self.root/'child'
        nested.mkdir()
        (nested/'.git').mkdir()
        with self.assertRaises(ScopeError):
            project_root(nested)
        manifest = self.root/'.datarim-runtime/installation.json'
        data = json.loads(manifest.read_text())
        data['contexts'] = ['child']
        manifest.write_text(json.dumps(data))
        self.assertEqual(project_root(nested), self.root)

    def test_scope_rejects_copied_installation(self):
        self.mark()
        moved = self.root.with_name('moved')
        self.root.rename(moved)
        with self.assertRaises(ScopeError):
            project_root(moved)

    def test_symlink_escape_cannot_write_credentials(self):
        outside = self.root.parent/'outside'
        outside.mkdir()
        (self.root/'config').symlink_to(outside)
        with self.assertRaises(ValueError):
            project_install.safe_path(self.root, 'config/credentials/jev/api-key')

    def test_rule_merge_preserves_foreign_instructions(self):
        original = '# Client rules\nKeep every production boundary.\n'
        once = project_install.replace_block(original, project_install.BEGIN+'\nnew\n'+project_install.END)
        twice = project_install.replace_block(once, project_install.BEGIN+'\nupdated\n'+project_install.END)
        self.assertIn('Keep every production boundary.', twice)
        self.assertEqual(twice.count(project_install.BEGIN), 1)
        self.assertNotIn('\nnew\n', twice)

    def test_no_task_state_in_product(self):
        self.assertFalse((ROOT/'datarim').exists())
        self.assertTrue((ROOT/'AGENTS.md').is_file())
        self.assertFalse((ROOT/'AGENTS.md').is_symlink())
        self.assertFalse((ROOT/'CLAUDE.md').exists())

    def test_installer_rejects_global_flags(self):
        run = subprocess.run([str(ROOT/'install.sh'), '--with-claude'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn('--project', run.stderr)


class InstallationLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name).resolve()
        self.source, self.project = base/'source', base/'project'
        self.source.mkdir()
        self.project.mkdir()
        for name in ('agents', 'skills', 'commands'):
            (self.source/name).mkdir()
        (self.source/'skills/testing').mkdir()
        (self.source/'skills/testing/SKILL.md').write_text('---\nname: testing\n---\nTest behavior.\n')
        (self.source/'commands/dr-do.md').write_text('Run the task.\n')
        (self.source/'AGENTS.md').write_text('# Framework\n')
        (self.source/'VERSION').write_text('test\n')
        (self.project/'AGENTS.md').write_text('# Original project rules\n')
        (self.project/'.gitignore').write_text('/build/\n')
        self.args = Namespace(project=str(self.project), with_jev=False,
                              context=[], dry_run=False, init=True)
        self.source_patch = patch.object(project_install, 'SOURCE', self.source)
        self.source_patch.start()
        self.addCleanup(self.source_patch.stop)

    def test_install_update_uninstall_preserves_originals_and_private_ignores(self):
        project_install.install(self.args)
        for vendor in ('.agents', '.claude', '.cursor'):
            skill = self.project/vendor/'skills/testing/SKILL.md'
            self.assertIn('name: testing', skill.read_text())
        manifest = self.project/'.datarim-runtime/installation.json'
        before = manifest.stat().st_mtime_ns
        project_install.install(self.args)
        self.assertEqual(manifest.stat().st_mtime_ns, before)
        (self.source/'VERSION').write_text('new version\n')
        project_install.install(self.args)
        project_install.uninstall(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')
        self.assertFalse((self.project/'.agents/skills/testing/SKILL.md').exists())
        self.assertTrue((self.project/'datarim/tasks.md').is_file())
        self.assertIn('/build/', (self.project/'.gitignore').read_text())
        for rule in project_install.PRIVATE_IGNORES:
            self.assertIn(rule, (self.project/'.gitignore').read_text())
        self.assertEqual((self.project/'.datarim-uninstalled').stat().st_mode & 0o077, 0)

    def test_foreign_skill_conflict_has_no_partial_install(self):
        foreign = self.project/'.cursor/skills/testing/SKILL.md'
        foreign.parent.mkdir(parents=True)
        foreign.write_text('Foreign instructions')
        with self.assertRaisesRegex(ValueError, 'Unmanaged'):
            project_install.install(self.args)
        self.assertEqual(foreign.read_text(), 'Foreign instructions')
        self.assertFalse((self.project/'.datarim-runtime').exists())
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')

    def test_nested_context_cannot_escape(self):
        self.args.context = ['../outside']
        with self.assertRaisesRegex(ValueError, 'relative subdirectories'):
            project_install.install(self.args)
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_update_rejects_state_symlink_without_replacing_runtime(self):
        project_install.install(self.args)
        state = self.project/'.datarim-runtime/state'
        state.mkdir()
        (state/'escape').symlink_to(self.source)
        (self.source/'VERSION').write_text('new version\n')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'test\n')

    def test_repeated_updates_retire_owned_discovery_and_preserve_backups(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('second\n')
        project_install.install(self.args)
        (self.source/'commands/dr-do.md').unlink()
        (self.source/'VERSION').write_text('third\n')
        project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'third\n')
        self.assertEqual((self.project/'.datarim-runtime-previous/VERSION').read_text(), 'second\n')
        self.assertEqual(len(list((self.project/'.datarim-runtime-backups').iterdir())), 1)
        self.assertFalse((self.project/'.agents/skills/dr-do/SKILL.md').exists())
        self.assertFalse((self.project/'.claude/commands/dr-do.md').exists())

    def test_failed_preparation_does_not_restore_an_older_backup_over_current(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('second\n')
        project_install.install(self.args)
        state = self.project/'.datarim-runtime/state'; state.mkdir()
        (state/'bad').symlink_to(self.source)
        (self.source/'VERSION').write_text('third\n')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'second\n')
        self.assertEqual((self.project/'.datarim-runtime-previous/VERSION').read_text(), 'test\n')

    def test_concurrent_installation_is_refused(self):
        with project_install.project_lock(self.project):
            with self.assertRaisesRegex(ValueError, 'Another installation'):
                project_install.install(self.args)
        self.assertFalse((self.project/'.datarim-runtime').exists())


class JevTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(ROOT/'plugins/dr-jev-control/scripts'))

    def test_curl_keeps_key_out_of_argv(self):
        import jev_client
        response = subprocess.CompletedProcess([], 0, b'{"answers":{}}\n__DRJEV_HTTP__:200\n', b'')
        key = 'synthetic-credential-for-test'
        with patch.object(jev_client.subprocess, 'run', return_value=response) as run:
            jev_client._curl('https://example.invalid/api', key, b'{"state":"test"}', 1, 1)
        args = run.call_args
        self.assertNotIn(key, ' '.join(args.args[0]))
        self.assertIn(key.encode(), args.kwargs['input'])

    def test_cursor_refuses_missing_session_continuation(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        self.assertFalse(runtime.send_turn('continue'))

    def test_cursor_session_change_is_an_error(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        runtime._translate({'type': 'system', 'session_id': 'original'})
        events = runtime._translate({'type': 'system', 'session_id': 'different'})
        self.assertEqual(events[0]['kind'], 'error')
        self.assertEqual(runtime.thread_id, 'original')

    def test_cursor_does_not_claim_unmapped_tier_applied(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        with patch.dict(os.environ, {}, clear=True):
            ok, reason = runtime.apply_tier('opus')
        self.assertFalse(ok)
        self.assertEqual(reason['reason'], 'cursor_model_mapping_missing')


if __name__ == '__main__':
    unittest.main()
