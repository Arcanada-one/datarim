"""Exercise the real hook with synthetic advice; command strings never execute."""
import io
import hashlib
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
    def test_installed_questions_are_preserved_on_frozen_review_corpus(self):
        # Private operational inputs are not shipped in the public repository.
        # Delivery must run with this hash-bound corpus and REQUIRED=1; a public
        # CI run without it cannot establish operational baseline coverage.
        path = os.environ.get('JEV_GUARD_REPLAY_CORPUS')
        if not path:
            if os.environ.get('JEV_GUARD_REPLAY_REQUIRED') == '1':
                self.fail('Required frozen operational corpus is unavailable')
            self.skipTest('Private frozen operational corpus not supplied')
        raw = Path(path).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         '58d78297fc2f3292ae30ea846faefe29b8cbe08030b3a6d53baa2964c65c0f20')
        rows = json.loads(raw)
        self.assertEqual(len(rows), 783)
        self.assertEqual(sum(row['old'] for row in rows), 114)
        self.assertEqual(sum(row['new'] for row in rows), 372)
        for index, row in enumerate(rows):
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(case=index, tool=tool):
                    evaluate, output = self.invoke(tool, {field: row['cmd']})
                    covered = bool(evaluate.call_count) or output.get(
                        'hookSpecificOutput', {}).get('permissionDecision') == 'deny'
                    self.assertTrue(not row['old'] or covered,
                                    'Installed question lost (private command omitted)')

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
        for command in ['echo <placeholder>',
                        "printf '%s' '<placeholder>'", 'echo "<placeholder>"',
                        "echo 'a > b'", 'echo "a > b"', r'echo \> tail',
                        'printf ok 2>&1', 'cat <input.txt', 'git status']:
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_review_shell_normalization_and_wrappers(self):
        commands = ['sys"t"emctl daemon-reload', 'u""seradd service',
                    r"$'\x73ystemctl' daemon-reload", '"$CMD" daemon-reload',
                    'cp config /etc ', 'cd /etc; tee hosts', 'git -C /etc commit -am x',
                    'timeout 60 bash scripts/ops.sh', 'npx tsx scripts/ops.ts',
                    'nice -n 5 env -i timeout 60 ./worker.sh',
                    'sort <data> out', 'cp config /e\"\"tc',
                    r"$'\u0073ystemctl' daemon-reload",
                    'echo \"$(git branch -D review-branch)\"',
                    'echo \"$(git diff --output=review-output)\"',
                    '$(pwd)/ops-runner', 'echo \"$(sudo pwd)\"',
                    'echo \"$(grep pattern file | tee result)\"',
                    'echo \"$(grep pattern file; sudo reboot)\"',
                    'echo \"$($CMD argument)\"', 'X=1 $(pwd)/ops-runner',
                    'stdbuf --output L node scripts/ops.js', 'cat <q> out', 'bash ops-runner',
                    'setsid bash scripts/ops.sh', 'pnpm exec tsx scripts/ops.ts',
                    'uv run python scripts/ops.py',
                    'stdbuf -o L node scripts/ops.js',
                    "npx -c 'node scripts/ops.js'",
                    'npm exec -- node scripts/ops.js',
                    'echo \"$(date -s2026-01-01)\"', r"echo $'\x'"]
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

    def test_review_privilege_wrappers_and_shell_grammar_reach_question(self):
        commands = [
            'sudo reboot', 'sudo kill 1234', 'sudo mount /dev/example /mnt/example',
            'sudo apt-get install example', 'sudo talomnia-deploy purge-edge prod',
            'env -i sudo reboot', 'nice -n 5 sudo reboot',
            'timeout 30 sudo reboot', 'doas reboot',
            "env --split-string='sudo reboot'",
            '/usr/bin/time -o timings sudo reboot',
            "eval 'if true; then sudo reboot; fi'",
            'su'+chr(92)+'\n'+'do reboot',
            '( git push origin main )', '(git push origin main)',
            'if true; then git push origin main; fi',
            'if git push origin main; then echo done; fi',
            'for host in example.invalid; do ssh "$host" uptime; done',
            'while true; do curl -X POST https://example.invalid/event; done',
            '{ git push origin main; }',
            'worker() { ssh example.invalid uptime; }',
        ]
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

    def test_reviewer_privilege_grammar_and_remaining_wrappers(self):
        commands = [
            'sudo reboot', 'sudo shutdown -h now', 'sudo kill -9 1234',
            'sudo mount /dev/sdb1 /mnt', 'sudo apt-get update',
            'sudo apt-get install -y bats', 'sudo npm i -g x',
            'sudo tee /opt/app/config.yml', 'sudo talomnia-deploy purge-edge prod',
            '( git push origin main )', '{ git push origin main; }',
            '! git push origin main',
            'if git push --quiet origin HEAD:main 2>/dev/null; then echo ok; fi',
            'if true; then git push origin main; fi',
            'for h in a b; do ssh $h reboot; done',
            'while true; do curl -X POST http://x; done',
            'talomnia-deploy deploy',
            'su -c reboot', 'pkexec reboot',
            'flock lock bash scripts/ops.sh',
            'flock -w 5 lock bash scripts/ops.sh',
            'xargs -I{} bash scripts/ops.sh', 'busybox sh scripts/ops.sh',
            'pnpm tsx scripts/ops.ts', 'cat scripts/ops.sh | bash',
            'cargo install tool --locked', 'pnpm install --frozen-lockfile',
            'npm ci', 'npm i', 'pnpm i', 'yarn', 'yarn --immutable',
            'cat scripts/ops.sh | bash -s',
            'cat scripts/ops.py | python3 -', 'cat scripts/ops.js | node -',
            'cat scripts/ops.sh | bash --noprofile -s',
            'cat scripts/ops.sh | bash -eu', 'cat scripts/ops.sh | bash -h',
            'cat scripts/ops.py | python3 -u',
            'cat scripts/ops.js | node --input-type=module',
            'pnpm exec playwright install chromium',
            'GIT_SSH_COMMAND="ssh -i key" git clone example.invalid/repo',
        ]
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

    def test_review_shell_grammar_does_not_turn_argument_words_into_commands(self):
        commands = ['echo "( git status )"',
                    'printf "%s" "if true; then printf ok; fi"',
                    'if test -f file; then echo yes; else echo no; fi',
                    'for item in a b; do echo "$item"; done',
                    '( git status )', '{ git status; }']
        for command in commands:
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_legacy_question_signals_are_additive(self):
        for command in ['echo "sudo reboot"', 'echo "( git push origin main )"',
                        'printf "%s" "if true; then ssh host; fi"',
                        'echo "before -> after"',
                        'if command -v sha256sum >/dev/null 2>&1; then',
                        "' <<<\"$checks\" >/dev/null"]:
            with self.subTest(command=command):
                self.assert_question('Bash', {'command': command})

    def test_review_cost_is_based_on_executed_argv(self):
        commands = ['echo systemctl daemon-reload',
                    'python3 --version', 'bash --help', 'node --version',
                    'printf "%s" install', 'git log --grep=deploy',
                    'python3 -m pytest tests/test_worker.py',
                    'python3 -m unittest tests/test_worker.py',
                    "python3 -c \"print('worker.py')\"",
                    'echo "$(git rev-parse HEAD)"',
                    'echo "$(date -u)"', "echo '<data> out'"]
        for command in commands:
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_readonly_substitution_pipelines_stay_cheap(self):
        for command in ['VERSION=$(grep version Cargo.toml | cut -d = -f 2)',
                        'SIZE=$(stat -f %z "$file")',
                        "PIN=$(tr -d '\\r\\n' < deploy/knowledge-pin)"]:
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})
        for command in ['echo "$(grep pattern file >result)"',
                        'echo "$(grep pattern file | tee result)"',
                        'echo "$(stat -f %z ${file@P})"',
                        'echo "$(./grep pattern file)"',
                        'echo "$($TOOL/grep pattern file)"',
                        'echo "$(time -o timings grep pattern file)"',
                        'echo "$(date $FLAGS)"',
                        'echo "$(grep pattern < $FILE)"',
                        'echo "$(grep pattern < /dev/tcp/example.invalid/80)"',
                        'echo "$(grep pattern < /dev/t\"\"cp/example.invalid/80)"',
                        'echo "$(grep pattern < /dev/t\\cp/example.invalid/80)"']:
            with self.subTest(command=command):
                self.assert_question('Bash', {'command': command})

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
                             ('Bash', {'command': 'python3 -m unittest discover'}),
                             ('Write', {'file_path': 'src/app.py', 'content': 'test'}),
                             ('apply_patch', {'patch': '*** Update File: src/app.py\n+test'})]:
            with self.subTest(tool=tool, inputs=inputs):
                evaluate, output = self.invoke(tool, inputs)
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_python_test_runner_modules_with_file_arguments_stay_cheap(self):
        # Measured on real agent commands: test files passed to `python -m
        # pytest|unittest` were read as repository scripts and asked for review.
        for command in ("python3 -m unittest discover -s tests -p 'test_jev_*.py'",
                        'python3 -m pytest -q tests/test_retrieval_shadow.py',
                        'python3.12 -m unittest tests/test_x.py'):
            with self.subTest(command=command):
                evaluate, output = self.invoke('Bash', {'command': command})
                evaluate.assert_not_called()
                self.assertEqual(output, {})

    def test_other_python_modules_and_direct_scripts_still_reach_question(self):
        for command in ('python3 -m deploy_tool scripts/push.py', 'python3 scripts/bootstrap.py',
                        'python3 -m pytest -q tests/test_x.py && bash scripts/sync.sh'):
            with self.subTest(command=command):
                self.assert_question('Bash', {'command': command})

    def test_census_f1_source_wrappers_reach_question(self):
        commands = [
            'bash deploy/broker/bootstrap-host.sh ./reviewed-checkout',
            'node dist/../scripts/support-sync.js',
            'bash deploy/monitoring/talomnia-monitor.sh',
            # Unknown repository scripts can hide production DB/API writes.
            './worker.sh', 'bash tests/check.sh', 'python3 scripts/worker.py',
            'env NODE_ENV=production node scripts/worker.js',
            'cd checkout && node scripts/worker.js',
            'arcana login', 'arcana run task',
        ]
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

    def test_census_f1_privilege_and_production_reach_question(self):
        commands = [
            'install -m 0440 f /etc/sudoers.d/x', 'systemctl daemon-reload',
            'bash -c "useradd x"', './deploy.sh prod', 'make deploy', 'pnpm deploy',
            'make release', 'pnpm run sync', 'npm run migrate',
            'useradd service', 'visudo -c', 'crontab jobs', 'iptables -A INPUT -j DROP',
            'cp config /etc/service.conf', 'touch /usr/local/sbin/service',
            'tee /var/lib/service/ledger.json',
            # Direct DB/POST already matched the old list; retain that protection.
            'psql "$DATABASE_URL" -c "UPDATE records SET active=false"',
            'node -e "connect(process.env.DATABASE_URL)"',
            'curl -X POST https://example.invalid/events -d @event.json',
        ]
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

    def test_census_f2_literals_comparisons_and_null_redirects_stay_cheap(self):
        commands = ['arcana kb-read "<q>"', 'git log --format="<%an>"',
                    'python3 -c "print(1 >= 0)"', 'echo ">="',
                    'ls 2>/dev/null', 'ls 2>>/dev/null', 'ls 2>"/dev/null"',
                    "ls 2>'/dev/null'", 'ls >/dev/null 2>&1', 'ls &>/dev/null',
                    'cat scripts/worker.js', 'node --version']
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    evaluate, output = self.invoke(tool, {field: command})
                    evaluate.assert_not_called()
                    self.assertEqual(output, {})

    def test_census_f2_exclusions_cannot_mask_real_risks(self):
        commands = ['ls 2>/dev/null >result', 'ls 2>/dev/null; tee /etc/sudoers.d/x',
                    'node scripts/worker.js 2>/dev/null',
                    'node scripts/worker.js>/dev/null', 'bash scripts/worker.sh>/dev/null',
                    'node scripts/worker.js>>"/dev/null"',
                    'curl -X POST https://example.invalid/events 2>/dev/null',
                    'echo "<q>" >/dev/null; ./deploy.sh prod',
                    'ls 2>/dev/null.backup', 'ls 2>"/dev/null".backup',
                    'ls >&output', 'echo >=output', 'printf ok >']
        for command in commands:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    self.assert_question(tool, {field: command})

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
        cases = [('sudo reboot', 'ask'),
                 ('( git push origin main )', 'ask'),
                 ('if true; then git push origin main; fi', 'ask'),
                 ('while true; do curl -X POST https://example.invalid/event; done', 'ask'),
                 ('bash '+('-- -'*2000)+"-c 'true'", 'ask'),
                 ('bash deploy/broker/bootstrap-host.sh', 'ask'),
                 ('tee /etc/sudoers.d/service', 'ask'),
                 ('touch /etc/systemd/system/service.service', 'ask'),
                 ('node dist/../scripts/support-sync.js', 'ask'),
                 ('node scripts/worker.js>/dev/null', 'ask'),
                 ('ls 2>/dev/null', None), ('arcana kb-read "<q>"', None),
                 ('python3 -c "print(1 >= 0)"', None),
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

    def test_long_descriptor_preserves_json_and_privileged_evidence(self):
        command = 'printf '+('x'*12500)+'; tee /etc/sudoers.d/service'
        descriptor = self.assert_question('Bash', {'command': command})
        self.assertTrue(descriptor['descriptor_truncated'])
        self.assertEqual(descriptor['command'], '[oversized command omitted]')
        self.assertIn('/etc/sudoers.d', descriptor['path'])
        self.assertIn('privileged_path_or_workdir', descriptor['risk_signals'])
        self.assertLessEqual(len(json.dumps(descriptor)), 12000)

    def test_oversized_unknown_command_is_evaluated_without_argv_parse(self):
        with patch.object(hook, '_split', side_effect=AssertionError('unbounded argv parse')):
            descriptor = self.assert_question('Bash', {'command': 'echo '+('x'*20000)})
        self.assertTrue(descriptor['descriptor_truncated'])
        self.assertIn('repository_script_or_opaque_execution', descriptor['risk_signals'])

    def test_inline_file_bodies_do_not_enter_model_descriptor(self):
        for command in ["eval 'printf PRIVATE_BODY > /etc/sudoers.d/service'",
                        "env -S 'printf PRIVATE_BODY > /etc/sudoers.d/service'",
                        r"env -Sprintf\ PRIVATE_BODY\ /etc/sudoers.d/service",
                        "python3 -\"\"c \"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "python3 -c \"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "python3 -c\"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "python3 '-c' \"open('/etc/sudoers.d/service','w').write('PRIVATE_BODY')\"",
                        "ruby -e\"File.write('/etc/sudoers.d/service', 'PRIVATE_BODY')\"",
                        "python3 -c \"open('/etc/sudoers.d/service','w').write('/etc/PRIVATE_BODY')\"",
                        "bash -c \"printf PRIVATE_BODY > /etc/sudoers.d/service\"",
                        "cat <<'EOF' > /etc/sudoers.d/service\nPRIVATE_BODY\nEOF"]:
            with self.subTest(command=command):
                descriptor = self.assert_question('Bash', {'command': command})
                self.assertNotIn('PRIVATE_BODY', json.dumps(descriptor))
                self.assertIn('/etc/sudoers.d', descriptor['path'])
                self.assertIn('inline_code_omitted', descriptor['risk_signals'])

    def test_repository_cli_credentials_are_omitted(self):
        for command in ['node scripts/worker.js --api-key SYNTHETIC_PRIVATE_VALUE',
                        'node scripts/worker.js --pass\"\"word SYNTHETIC_PRIVATE_VALUE',
                        'node scripts/worker.js --token=SYNTHETIC_PRIVATE_VALUE',
                        'node scripts/worker.js --password "head/etc/SYNTHETIC_PRIVATE_VALUE"',
                        "node scripts/worker.js '--password' 'SYNTHETIC_PRIVATE_VALUE'"]:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(command=command, tool=tool):
                    descriptor = self.assert_question(tool, {field: command})
                    self.assertNotIn('SYNTHETIC_PRIVATE_VALUE', json.dumps(descriptor))
                    self.assertIn('credential_argument_omitted', descriptor['risk_signals'])


    def test_stdin_pipeline_bodies_do_not_enter_model_descriptor(self):
        for command in ["printf 'PRIVATE_BODY' | bash -s",
                        "printf 'PRIVATE_BODY' | /bin/bash -s",
                        "printf 'PRIVATE_BODY' | busybox sh",
                        "printf 'PRIVATE_BODY' | python3 -"]:
            for tool, field in [('Bash', 'command'), ('exec_command', 'cmd')]:
                with self.subTest(tool=tool, command=command):
                    descriptor = self.assert_question(tool, {field: command})
                    self.assertNotIn('PRIVATE_BODY', json.dumps(descriptor))
                    self.assertIn('inline_code_omitted', descriptor['risk_signals'])


if __name__ == '__main__':
    unittest.main()
