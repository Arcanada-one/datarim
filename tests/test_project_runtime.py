"""Project isolation, lossless installation and CLI boundary regression tests."""
import importlib.util
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
