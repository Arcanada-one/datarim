"""Safety-floor denial audit and category drift. Command strings are never executed."""
import ast
import io
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'plugins/dr-jev-control/scripts'))
sys.path.insert(0, str(ROOT / 'scripts'))
import hook_pre_tool as hook
import jev_hook
import ledger
from safety_floor import destructive_reason

DOC = ROOT / 'plugins/dr-jev-control/docs/safety-floor-categories.md'
FLOOR = ROOT / 'plugins/dr-jev-control/scripts/safety_floor.py'

CLAUDE_DENY = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'Jev deterministic safety floor: recursive delete of a protected path',
    }
}
CURSOR_DENY = {
    'permission': 'deny',
    'user_message': 'Jev deterministic safety floor: recursive delete of a protected path',
    'agent_message': 'Jev deterministic safety floor: recursive delete of a protected path',
}
DIRECT_DENY = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': (
            'Jev deterministic safety floor blocked a destructive command '
            '(recursive delete of a protected path).'),
    }
}
SECRET = 'SyntheticEnvSecretValue99'
TOKEN = 'sk-SyntheticTokenValue123456789'
SECRET_COMMAND = f'rm -rf / TOKEN={SECRET} {TOKEN}'


def _documented_reasons(text):
    reasons = []
    in_table = False
    for line in text.splitlines():
        if line.startswith('| Reason |'):
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith('| ---'):
            continue
        if not line.startswith('|'):
            break
        reasons.append(line.split('|')[1].strip())
    return reasons


def _returned_reasons():
    tree = ast.parse(FLOOR.read_text())
    function = next(node for node in tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == 'destructive_reason')
    reasons = set()
    for node in ast.walk(function):
        if not isinstance(node, ast.Return):
            continue
        value = node.value
        if value is None or isinstance(value, ast.Name):
            continue
        if isinstance(value, ast.Constant) and value.value is None:
            continue
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            reasons.add(value.value)
            continue
        raise AssertionError('non-literal reason return: ' + ast.dump(value))
    return reasons


def _nested_shell(levels):
    command = 'true'
    for _ in range(levels):
        command = 'bash -c ' + shlex.quote(command)
    return command


class CategoryDriftTests(unittest.TestCase):
    def test_documented_reasons_match_destructive_reason(self):
        documented = _documented_reasons(DOC.read_text())
        self.assertEqual(len(documented), len(set(documented)))
        self.assertEqual(set(documented), _returned_reasons())
        samples = {
            'recursive delete of a protected path': 'rm -rf /',
            'raw write to a block device': 'dd if=/dev/zero of=/dev/sda',
            'filesystem format of a block device': 'mkfs.ext4 /dev/sda1',
            'SQL DROP DATABASE/SCHEMA': 'DROP DATABASE prod',
            'git force push': 'git push --force',
            'git reset --hard': 'git reset --hard',
            'nested shell exceeds deterministic inspection depth': _nested_shell(5),
        }
        self.assertEqual(set(samples), set(documented))
        for reason, command in samples.items():
            self.assertEqual(destructive_reason(command), reason)
        for command in ('rm -rf ~', 'rm -rf $HOME', 'rm -rf ${HOME}'):
            self.assertEqual(destructive_reason(command), 'recursive delete of a protected path')
        self.assertIsNone(destructive_reason(_nested_shell(4)))


class FloorDenialAuditTests(unittest.TestCase):
    def _env(self, directory, *, enabled=True):
        base = Path(directory)
        config = base / 'jev-config.json'
        config.write_text(json.dumps({'telemetry': {'enabled': enabled}}))
        state = base / 'state'
        return {
            'DATARIM_JEV_CONFIG': str(config),
            'JEV_STATE_DIR': str(state),
            'JEV_EVENT_CONTEXT': json.dumps({'client': 'claude', 'native_event': 'PreToolUse'}),
        }, state / 'ledger.jsonl'

    def _run(self, directory, payload, client, event, *, enabled=True, environment_error=None):
        env, ledger_path = self._env(directory, enabled=enabled)
        side = environment_error if environment_error is not None else None
        with patch.dict(os.environ, {'JEV_EVENT_CONTEXT': ''}, clear=False), \
             patch.object(jev_hook, 'environment',
                          side_effect=side,
                          return_value=None if side else (env, Path(directory))):
            os.environ.pop('JEV_EVENT_CONTEXT', None)
            output = jev_hook.run(client, event, payload)
        return output, ledger_path

    def test_floor_deny_writes_one_scrubbed_record_and_keeps_the_decision(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}
        with tempfile.TemporaryDirectory() as directory:
            denied, _ = self._run(directory, payload, 'claude', 'PreToolUse',
                                  environment_error=RuntimeError('ledger unavailable'))
            self.assertEqual(denied, CLAUDE_DENY)
            output, ledger_path = self._run(directory, payload, 'claude', 'PreToolUse')
            self.assertEqual(output, denied)
            rows = [json.loads(line) for line in ledger_path.read_text().splitlines() if line.strip()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['event'], ledger.FLOOR_DENIAL_EVENT)
        self.assertEqual(rows[0]['data']['command'], 'rm -rf /')
        self.assertEqual(rows[0]['data']['reason'], 'recursive delete of a protected path')
        self.assertTrue(rows[0]['data']['blocked'])
        self.assertEqual(rows[0]['data']['client'], 'claude')
        self.assertNotIn('text', rows[0])

    def test_cursor_and_exec_command_deny_payloads_stay_put(self):
        cases = (
            ('cursor', 'beforeShellExecution', {'command': 'rm -rf /'}, CURSOR_DENY),
            ('codex', 'PreToolUse',
             {'tool_name': 'exec_command', 'tool_input': {'cmd': 'rm -rf /'}}, CLAUDE_DENY),
        )
        for client, event, payload, expected in cases:
            with self.subTest(client=client):
                with tempfile.TemporaryDirectory() as directory:
                    output, ledger_path = self._run(directory, payload, client, event)
                    rows = [json.loads(line) for line in ledger_path.read_text().splitlines()]
                self.assertEqual(output, expected)
                self.assertEqual([row['event'] for row in rows], [ledger.FLOOR_DENIAL_EVENT])

    def test_secret_assignment_and_token_are_scrubbed(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': SECRET_COMMAND}}
        with tempfile.TemporaryDirectory() as directory:
            output, ledger_path = self._run(directory, payload, 'claude', 'PreToolUse')
            raw = ledger_path.read_text()
        self.assertEqual(output, CLAUDE_DENY)
        rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['data']['reason'], 'recursive delete of a protected path')
        self.assertNotIn(SECRET, raw)
        self.assertNotIn(TOKEN, raw)
        self.assertIn('<redacted>', rows[0]['data']['command'])
        self.assertIn('rm -rf /', rows[0]['data']['command'])

    def test_ledger_failure_leaves_the_deny_in_place(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}
        with tempfile.TemporaryDirectory() as directory:
            env, ledger_path = self._env(directory)
            with patch.object(jev_hook, 'environment', return_value=(env, Path(directory))), \
                 patch.object(ledger, 'log_event', side_effect=RuntimeError('disk full')):
                failed = jev_hook.run('claude', 'PreToolUse', payload)
            with patch.object(jev_hook, 'record_floor_denial', side_effect=RuntimeError('audit bug')):
                raised = jev_hook.run('claude', 'PreToolUse', payload)
            self.assertFalse(ledger_path.exists())
        self.assertEqual(failed, CLAUDE_DENY)
        self.assertEqual(raised, CLAUDE_DENY)
        with patch.object(jev_hook, 'environment', side_effect=AssertionError('no context')):
            self.assertEqual(jev_hook.run('claude', 'PreToolUse', payload), CLAUDE_DENY)

    def test_disabled_telemetry_records_nothing_and_still_denies(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}
        with tempfile.TemporaryDirectory() as directory:
            output, ledger_path = self._run(directory, payload, 'claude', 'PreToolUse', enabled=False)
            self.assertFalse(ledger_path.exists())
        self.assertEqual(output, CLAUDE_DENY)

    def test_main_stays_exit_zero_without_a_workspace(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}
        output = io.StringIO()
        with patch('sys.argv', ['jev_hook.py', 'claude', 'PreToolUse']), \
             patch('sys.stdin', io.StringIO(json.dumps(payload))), \
             patch('sys.stdout', output):
            code = jev_hook.main()
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue()), CLAUDE_DENY)

    def test_allowed_command_does_not_emit_a_floor_event(self):
        with patch.object(jev_hook, 'record_floor_denial') as recorded:
            output = jev_hook.run('cursor', 'beforeShellExecution', {'command': 'git status'})
        self.assertEqual(output, {'permission': 'allow'})
        recorded.assert_not_called()


class DirectPreToolAuditTests(unittest.TestCase):
    def _invoke(self, command, env):
        output = io.StringIO()
        with patch.dict(os.environ, env, clear=False), \
             patch('sys.stdin', io.StringIO(json.dumps({
                 'tool_name': 'Bash', 'tool_input': {'command': command}}))), \
             patch('sys.stdout', output):
            code = hook.main()
        parsed = json.loads(output.getvalue()) if output.getvalue() else {}
        return code, parsed

    def test_direct_deny_writes_one_scrubbed_record(self):
        with tempfile.TemporaryDirectory() as directory:
            code, output = self._invoke(SECRET_COMMAND, {'JEV_STATE_DIR': directory})
            ledger_path = Path(directory) / 'ledger.jsonl'
            raw = ledger_path.read_text()
        self.assertEqual(code, 0)
        self.assertEqual(output, DIRECT_DENY)
        self.assertNotIn(SECRET, output['hookSpecificOutput']['permissionDecisionReason'])
        rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['event'], ledger.FLOOR_DENIAL_EVENT)
        self.assertEqual(rows[0]['data']['reason'], 'recursive delete of a protected path')
        self.assertNotIn(SECRET, raw)
        self.assertNotIn(TOKEN, raw)
        self.assertIn('<redacted>', rows[0]['data']['command'])

    def test_direct_deny_without_a_ledger_location_is_unchanged(self):
        code, output = self._invoke('rm -rf /', {})
        self.assertEqual(code, 0)
        self.assertEqual(output, DIRECT_DENY)

    def test_advice_disable_still_records_and_denies(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'jev-config.json'
            config.write_text(json.dumps({'telemetry': {'enabled': True}}))
            code, output = self._invoke('rm -rf /', {
                'DATARIM_JEV_DISABLE': '1',
                'DATARIM_JEV_CONFIG': str(config),
                'JEV_STATE_DIR': directory,
            })
            rows = [json.loads(line) for line in (Path(directory) / 'ledger.jsonl').read_text().splitlines()]
        self.assertEqual(code, 0)
        self.assertEqual(output, DIRECT_DENY)
        self.assertEqual([row['event'] for row in rows], [ledger.FLOOR_DENIAL_EVENT])

    def test_disabled_telemetry_records_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'jev-config.json'
            config.write_text(json.dumps({'telemetry': {'enabled': False}}))
            code, output = self._invoke('rm -rf /', {
                'DATARIM_JEV_CONFIG': str(config),
                'JEV_STATE_DIR': directory,
            })
        self.assertEqual(code, 0)
        self.assertEqual(output, DIRECT_DENY)
        self.assertFalse((Path(directory) / 'ledger.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
