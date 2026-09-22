"""Vendor contracts and host/project authority boundaries, without network calls."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
sys.path.insert(0, str(ROOT/'plugins/dr-jev-control/scripts'))
import jev_hook
import jev_host_install
import catalog
import route
from project_state import disabled_reason


class NativeHookTests(unittest.TestCase):
    def test_registration_preserves_mixed_foreign_hooks_and_is_idempotent(self):
        runtime = Path('/host/jev/releases/revision')
        original = {'env': {'KEEP': 'yes'}, 'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [
            {'type': 'command', 'command': 'python3 /legacy/plugins/dr-jev-control/scripts/hook_pre_tool.py'},
            {'type': 'command', 'command': 'foreign-guard'}]}]}}
        once = jev_host_install.merge_hooks(original, 'claude', runtime, [Path('/legacy'), runtime])
        twice = jev_host_install.merge_hooks(once, 'claude', runtime, [Path('/legacy'), runtime])
        self.assertEqual(once, twice)
        self.assertEqual(once['env'], original['env'])
        commands = [h['command'] for e in once['hooks']['PreToolUse'] for h in e['hooks']]
        self.assertIn('foreign-guard', commands)
        self.assertEqual(sum('jev_hook.py' in c for c in commands), 1)
        self.assertFalse(any('/legacy/' in c for c in commands))

    def test_project_hook_retirement_preserves_foreign_entries(self):
        runtime = Path('/project/.datarim-runtime')
        initial = {'version': 1, 'hooks': {'beforeShellExecution': [{'command': 'foreign'}]}}
        with_jev = jev_host_install.merge_hooks(initial, 'cursor', runtime, [runtime])
        without_jev = jev_host_install.merge_hooks(with_jev, 'cursor', runtime, [runtime], register=False)
        self.assertEqual(without_jev['hooks']['beforeShellExecution'], [{'command': 'foreign'}])
        self.assertFalse(any('jev_hook.py' in json.dumps(e) for e in without_jev['hooks'].values()))

    def test_global_catalog_is_empty_without_explicit_provider(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(all(not value for value in catalog.inventory().values()))

    def test_generic_route_has_no_framework_questions_or_hallucinated_component(self):
        received = {}
        def evaluate(state, questions, cfg, **kwargs):
            received.update(questions)
            return {'answers': {'agent_choice': {'choice': 'invented', 'confidence': 1},
                                'model_tier': {'choice': 'invented-model'}}}
        cfg = {'routing': {'enabled': True}, 'telemetry': {'enabled': False}}
        with patch.dict(os.environ, {}, clear=True), patch.object(route, 'evaluate', evaluate):
            result = route.route('Review this program', cfg)
        self.assertEqual(result['model'], 'sonnet')
        self.assertEqual(result['selection']['agents']['choice'], 'none')
        self.assertFalse(any('Datarim' in json.dumps(q) for q in received.values()))
        self.assertEqual(len(received), 6)

    def test_floor_survives_missing_context_for_every_vendor(self):
        for client in ('claude', 'codex', 'cursor'):
            event = 'beforeShellExecution' if client == 'cursor' else 'PreToolUse'
            payload = {'command': 'rm -rf /'} if client == 'cursor' else {
                'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}
            with self.subTest(client=client), patch.object(jev_hook, 'environment', side_effect=AssertionError):
                output = jev_hook.run(client, event, payload)
            self.assertEqual(output['permission'] if client == 'cursor' else
                             output['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_patch_text_is_not_interpreted_as_a_shell_command(self):
        with patch.object(jev_hook, 'environment', side_effect=ValueError('no context')):
            self.assertEqual(jev_hook.run('codex', 'PreToolUse', {
                'tool_name': 'apply_patch', 'tool_input': {'command': 'rm -rf /'}}), {})

    def test_cursor_safe_command_survives_advisory_failure(self):
        with patch.object(jev_hook, 'environment', side_effect=ValueError('no context')):
            self.assertEqual(jev_hook.run('cursor', 'beforeShellExecution',
                             {'command': 'git status'}), {'permission': 'allow'})

    def test_exec_command_cmd_is_guarded_with_broken_scope_import(self):
        with patch.object(jev_hook, 'environment', side_effect=ImportError('broken scope')):
            output = jev_hook.run('codex', 'PreToolUse', {
                'tool_name': 'exec_command', 'tool_input': {'cmd': 'rm -rf /'}})
            self.assertEqual(output['hookSpecificOutput']['permissionDecision'], 'deny')
            self.assertEqual(jev_hook.run('cursor', 'beforeShellExecution',
                             {'command': 'git status'}), {'permission': 'allow'})

    def test_cursor_normalization_retains_native_provenance(self):
        _, value = jev_hook.normalize('cursor', 'postToolUse', {
            'conversation_id': 'session-a', 'generation_id': 'turn-b', 'tool_output': 'result'})
        self.assertEqual(value['session_id'], 'session-a')
        self.assertEqual(value['turn_id'], 'turn-b')
        self.assertEqual(value['jev_native_event'], 'postToolUse')
        self.assertEqual(value['tool_response'], 'result')

    def test_cursor_prompt_does_not_claim_to_inject_advice(self):
        result = {'hookSpecificOutput': {'additionalContext': 'advice'}}
        self.assertEqual(jev_hook.native_output('cursor', 'beforeSubmitPrompt', result), {'continue': True})
        self.assertEqual(jev_hook.native_output('cursor', 'postToolUse', result), {'additional_context': 'advice'})
        self.assertEqual(jev_hook.native_output('cursor', 'afterFileEdit', result), {})

    def test_unsupported_ask_does_not_fail_open_in_codex(self):
        result = {'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                  'permissionDecision': 'ask', 'permissionDecisionReason': 'review'}}
        self.assertEqual(jev_hook.native_output('codex', 'PreToolUse', result)
                         ['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'ask')
        self.assertFalse(jev_hook.native_output('cursor', 'beforeSubmitPrompt',
                         {'decision': 'block', 'reason': 'review'})['continue'])

    def test_cursor_multiple_roots_require_an_explicit_cwd(self):
        with self.assertRaises(ValueError):
            jev_hook.workdir({'workspace_roots': ['/a', '/b']})

    def test_host_key_and_config_cannot_be_replaced_by_project_or_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            runtime = base/'host-runtime'; runtime.mkdir()
            project = base/'project'; project.mkdir()
            provider = project/'.datarim-runtime'; provider.mkdir()
            (provider/'installation.json').write_text(json.dumps({'schema': 1, 'project': str(project)}))
            cfg = base/'host-config.json'
            cfg.write_text(json.dumps({'datarim_projects': [str(project)]})); cfg.chmod(0o600)
            manifest = runtime/'host-installation.json'
            manifest.write_text(json.dumps({'schema': 1, 'runtime': str(runtime), 'config': str(cfg),
                                           'key_file': str(base/'host-key'), 'state_dir': str(base/'state')}))
            manifest.chmod(0o600)
            with patch.dict(os.environ, {'DATARIM_JEV_CONFIG': 'foreign', 'DATARIM_ROOT': 'foreign',
                                         'TYPESAFE_API_KEY': 'synthetic-secret'}, clear=True):
                env, cwd = jev_hook.environment({'cwd': str(project)}, runtime=runtime)
            self.assertEqual(env['DATARIM_JEV_CONFIG'], str(cfg))
            self.assertEqual(env['TYPESAFE_API_KEY_FILE'], str(base/'host-key'))
            self.assertNotIn('TYPESAFE_API_KEY', env)
            self.assertEqual(env['DATARIM_ROOT'], str(provider))
            cfg.write_text(json.dumps({'datarim_projects': []})); cfg.chmod(0o600)
            env, _ = jev_hook.environment({'cwd': str(project)}, runtime=runtime)
            self.assertNotIn('DATARIM_ROOT', env)

    def test_host_disable_applies_to_partitioned_project_state(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base/'DISABLED').touch()
            with patch.dict(os.environ, {'JEV_STATE_DIR': str(base/'projects'/'abc'),
                                        'JEV_HOST_STATE': str(base)}, clear=True):
                self.assertIsNotNone(disabled_reason())


if __name__ == '__main__':
    unittest.main()
