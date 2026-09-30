"""Exercise the real hook with synthetic advice; command strings never execute."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import hook_pre_tool as hook


class PretoolRiskSignals(unittest.TestCase):
    def invoke(self, tool, inputs, *, enabled=True, enforce=True, error=False):
        cfg = {'hooks': {'pretool_risk': enabled, 'enforce_jev_denials': enforce}}
        answer = {'answers': {'risky': {'noul': .99}}, 'usage': {}}
        output = io.StringIO()
        with patch.object(hook, 'load_cfg', return_value=cfg), \
             patch.object(hook, 'evaluate', return_value=answer,
                          side_effect=RuntimeError('synthetic outage') if error else None) as evaluate, \
             patch.object(hook, 'log'), \
             patch('sys.stdin', io.StringIO(json.dumps({'tool_name': tool, 'tool_input': inputs}))), \
             patch('sys.stdout', output):
            self.assertEqual(hook.main(), 0)
        return evaluate, json.loads(output.getvalue()) if output.getvalue() else {}

    def assert_question(self, tool, inputs):
        evaluate, output = self.invoke(tool, inputs)
        evaluate.assert_called_once()
        state, questions, _ = evaluate.call_args.args
        self.assertEqual(questions['risky']['type'], 'noul')
        self.assertEqual(evaluate.call_args.kwargs['budget'], {'timeout_seconds': 4, 'retries': 0})
        self.assertEqual(output['hookSpecificOutput']['permissionDecision'], 'ask')
        return json.loads(state)

    def test_root_install_scripts_reach_question_without_sudo(self):
        for command in ['bash deploy/broker/bootstrap-host.sh',
                        '/bin/bash -eu deploy/broker/bootstrap-host.sh',
                        'env -i bash deploy/broker/bootstrap-host.sh',
                        './deploy/broker/bootstrap-host.sh',
                        'sh scripts/install-root.sh', '. scripts/setup-host.sh',
                        'bash scripts/provision.sh', 'bash deploy/system.sh']:
            for tool, field in [('Bash', 'command'), ('shell', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    descriptor = self.assert_question(tool, {field: command})
                    self.assertEqual(descriptor['command'], command)

    def test_privileged_shell_targets_reach_question(self):
        for command in ['tee /etc/sudoers.d/service',
                        'cp local.rules /etc/sudoers',
                        'install unit /etc/systemd/system/service.service',
                        "python3 -c \"open('/usr/lib/systemd/system/service.service','w')\"",
                        'touch /lib/systemd/system/service.service',
                        'systemctl enable service',
                        'tee /etc/../etc/sudoers.d/service']:
            with self.subTest(command=command):
                self.assert_question('Bash', {'command': command})

    def test_privileged_file_edits_reach_question_without_contents(self):
        for target in ['/etc/sudoers', '/etc/sudoers.d/service',
                       '/etc/systemd/system/service.service',
                       '/usr/lib/systemd/system/service.service',
                       '/lib/systemd/system/service.service',
                       '/run/systemd/system/service.service']:
            for tool in ['Write', 'Edit', 'MultiEdit']:
                with self.subTest(target=target, tool=tool):
                    descriptor = self.assert_question(tool, {'file_path': target, 'content': 'PRIVATE_CONTENT'})
                    self.assertNotIn('PRIVATE_CONTENT', json.dumps(descriptor))
            for header in ['Add File', 'Update File', 'Delete File', 'Move to']:
                with self.subTest(target=target, header=header):
                    descriptor = self.assert_question('apply_patch', {'patch':
                        '*** Begin Patch\n*** Update File: ordinary.txt\n*** '+header+': '+target+
                        '\n+PRIVATE_CONTENT\n*** End Patch'})
                    self.assertIn(target, descriptor['path'])
                    self.assertNotIn('PRIVATE_CONTENT', json.dumps(descriptor))

    def test_placeholder_and_quoted_greater_than_are_not_output_redirections(self):
        for command in ['echo <placeholder>', 'echo <placeholder> tail',
                        "printf '%s' '<placeholder>'", 'echo "<placeholder>"',
                        "echo 'a > b'", 'echo "a > b"', r'echo \> tail',
                        'printf ok 2>&1', 'cat <input.txt', 'git status']:
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_real_output_redirections_still_reach_question(self):
        for command in ['printf ok > result', 'printf ok >>result',
                        'printf ok 2>errors', 'printf ok &>result',
                        'printf ok >|result', "echo '<placeholder>' > result",
                        'echo <placeholder> > result', 'cat <input >result',
                        'echo <placeholder>result',
                        'bash -c "printf ok > result"',
                        'echo "$(printf ok > result)"']:
            with self.subTest(command=command):
                self.assert_question('Bash', {'command': command})

    def test_ordinary_reads_tests_and_edits_stay_cheap(self):
        for tool, inputs in [('Read', {'file_path': '/etc/sudoers'}),
                             ('Bash', {'command': 'bash tests/check.sh'}),
                             ('Bash', {'command': 'python3 -m unittest discover'}),
                             ('Write', {'file_path': 'src/app.py', 'content': 'test'}),
                             ('apply_patch', {'patch': '*** Update File: src/app.py\n+test'})]:
            with self.subTest(tool=tool, inputs=inputs):
                evaluate, output = self.invoke(tool, inputs)
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_advisory_disabled_and_outage_contracts_preserved(self):
        inputs = {'command': 'bash deploy/broker/bootstrap-host.sh'}
        evaluate, output = self.invoke('Bash', inputs, enforce=False)
        evaluate.assert_called_once()
        self.assertIn('additionalContext', output['hookSpecificOutput'])
        self.assertNotIn('permissionDecision', output['hookSpecificOutput'])
        evaluate, output = self.invoke('Bash', inputs, enabled=False)
        evaluate.assert_not_called()
        self.assertEqual(output, {})
        evaluate, output = self.invoke('Bash', inputs, error=True)
        evaluate.assert_called_once()
        self.assertEqual(output, {})

    def test_placeholder_never_disables_floor(self):
        evaluate, output = self.invoke('Bash', {'command': 'echo <placeholder>; rm -rf /'}, enabled=False)
        evaluate.assert_not_called()
        self.assertEqual(output['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_late_privileged_patch_header_is_inspected_and_described(self):
        ordinary = ''.join('*** Update File: file%d.py\n' % i for i in range(110))
        descriptor = self.assert_question('apply_patch', {'command':
            ordinary+'*** Move to: /etc/sudoers.d/service\n+PRIVATE_CONTENT'})
        self.assertIn('/etc/sudoers.d/service', descriptor['path'])
        self.assertLessEqual(len(descriptor['path'].splitlines()), 100)
        self.assertNotIn('PRIVATE_CONTENT', json.dumps(descriptor))

    def test_hook_entrypoint_process_canary(self):
        # Real hook __main__, floor and scrubber; only configuration/provider
        # and persistence are fixtures. No installed hooks, API or shell calls.
        fixture = '''
import json, runpy, sys, types
def evaluate(state, questions, cfg, **kwargs):
    assert questions['risky']['type'] == 'noul'
    print('EVALUATED', file=sys.stderr)
    return {'answers': {'risky': {'noul': .99}}, 'usage': {}}
sys.modules['jev_client'] = types.SimpleNamespace(evaluate=evaluate, provenance=lambda r: {})
sys.modules['route'] = types.SimpleNamespace(
    load_cfg=lambda: {'hooks': {'pretool_risk': True, 'enforce_jev_denials': True}},
    log=lambda *a, **k: None)
runpy.run_path(sys.argv[1], run_name='__main__')
'''
        cases = [('bash deploy/broker/bootstrap-host.sh', 'ask'),
                 ('tee /etc/sudoers.d/service', 'ask'),
                 ('touch /etc/systemd/system/service.service', 'ask'),
                 ("echo '<placeholder>'", None), ('echo <placeholder>', None),
                 ("echo '<placeholder>' > result", 'ask'), ('rm -rf /', 'deny')]
        for command, decision in cases:
            with self.subTest(command=command):
                process = subprocess.run(
                    [sys.executable, '-I', '-c', fixture, str(Path(hook.__file__).resolve())],
                    input=json.dumps({'tool_name': 'Bash', 'tool_input': {'command': command}}),
                    text=True, capture_output=True, timeout=10,
                    env={key: value for key, value in os.environ.items() if key in ('PATH', 'TMPDIR')})
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertEqual(process.stderr, 'EVALUATED\n' if decision == 'ask' else '')
                output = json.loads(process.stdout) if process.stdout else {}
                self.assertEqual(output.get('hookSpecificOutput', {}).get('permissionDecision'), decision)

    def test_relative_privileged_workdir_is_evaluated(self):
        for field in ['workdir', 'cwd']:
            descriptor = self.assert_question('exec_command', {
                'cmd': 'cp /tmp/unit example.service', field: '/etc/systemd/system'})
            self.assertEqual(descriptor['workdir'], '/etc/systemd/system')
        self.assert_question('Write', {'file_path': 'service', 'workdir': '/etc/sudoers.d'})

    def test_long_descriptor_preserves_json_risk_signals_and_command_tail(self):
        command = 'printf '+('x'*12500)+'; tee /etc/sudoers.d/service'
        descriptor = self.assert_question('Bash', {'command': command})
        self.assertTrue(descriptor['descriptor_truncated'])
        self.assertIn('/etc/sudoers.d/service', descriptor['command'])
        self.assertIn('privileged_path_or_workdir', descriptor['risk_signals'])
        self.assertLessEqual(len(json.dumps(descriptor)), 12000)

    def test_inline_file_bodies_do_not_enter_model_descriptor(self):
        for command in ["python3 -c \"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "python3 -c\"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "python3 '-c' \"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "ruby -e\"File.write('/etc/sudoers.d/service', 'PRIVATE_BODY')\"",
                        "bash -c \"printf PRIVATE_BODY > /etc/sudoers.d/service\"",
                        "cat <<'EOF' > /etc/sudoers.d/service\nPRIVATE_BODY\nEOF"]:
            with self.subTest(command=command):
                descriptor = self.assert_question('Bash', {'command': command})
                self.assertNotIn('PRIVATE_BODY', json.dumps(descriptor))
                self.assertIn('/etc/sudoers.d/service', descriptor['path'])
                self.assertIn('inline_code_omitted', descriptor['risk_signals'])


if __name__ == '__main__':
    unittest.main()
