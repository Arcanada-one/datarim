"""`jev doctor` in a project install: registrations, Codex trust, liveness.

Each test installs this repository into a disposable project under a
disposable home, and runs the installed `jev.py` there, as an operator would.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import jev
import jev_host_install


class RegisteredEvents(unittest.TestCase):
    def test_doctor_expects_exactly_what_the_installer_registers(self):
        self.assertEqual({c: tuple(e for e, _ in events) for c, events in jev_host_install.EVENTS.items()},
                         jev.REGISTERED_EVENTS)


class ProjectDoctor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name).resolve()
        self.home = base/'home'
        self.home.mkdir()
        self.project = base/'project'
        self.project.mkdir()
        (self.project/'AGENTS.md').write_text('# Rules\n')
        self.env = dict(os.environ, HOME=str(self.home), CLAUDE_BIN='/usr/bin/true',
                        CODEX_BIN='/usr/bin/true', CURSOR_BIN='/usr/bin/true')
        self.env.pop('JEV_PERMISSIONS', None)

    def install(self, *extra):
        run = subprocess.run([sys.executable, str(ROOT/'scripts/project_install.py'), '--project',
                              str(self.project), '--with-jev',
                              *(extra if '--client' in extra else ('--client', 'all', *extra))],
                             env=self.env, capture_output=True, text=True, timeout=120)
        self.assertEqual(run.returncode, 0, run.stderr)

    def jev(self, *argv):
        return subprocess.run([sys.executable, str(self.project/'.datarim-runtime/scripts/jev.py'), *argv],
                              cwd=self.project, env=self.env, capture_output=True, text=True, timeout=60)

    def doctor(self, agent):
        run = self.jev('doctor', '--agent=' + agent)
        return run.returncode, json.loads(run.stdout)

    # -- defect: a hand-deleted registration read as healthy ------------------

    def test_a_deleted_hook_file_is_a_finding(self):
        self.install()
        code, report = self.doctor('cursor')
        self.assertEqual((code, report['findings']), (0, []))
        (self.project/'.cursor/hooks.json').unlink()
        code, report = self.doctor('cursor')
        self.assertEqual(code, 1)
        self.assertEqual(len(report['findings']), 1)
        self.assertIn('cursor: Jev hook file missing', report['findings'][0])

    def test_a_removed_entry_is_a_finding_naming_the_event(self):
        self.install()
        path = self.project/'.claude/settings.local.json'
        data = json.loads(path.read_text())
        del data['hooks']['PreToolUse']
        path.write_text(json.dumps(data))
        code, report = self.doctor('claude')
        self.assertEqual(code, 1)
        self.assertTrue(any('claude: Jev hook not registered for PreToolUse' in f for f in report['findings']),
                        report['findings'])

    def test_a_client_not_selected_is_not_expected_to_have_hooks(self):
        self.install('--client', 'codex')
        code, report = self.doctor('cursor')
        self.assertEqual(report['findings'], [])
        self.assertEqual(report['hook_clients'], ['codex'])
        self.assertEqual(report['native_agents_live']['cursor']['state'], 'not_measured')

    def test_a_missing_managed_command_is_a_finding(self):
        self.install('--client', 'claude')
        (self.project/'.claude/commands/dr-do.md').unlink()
        code, report = self.doctor('claude')
        self.assertTrue(any('managed file(s) missing' in f for f in report['findings']), report['findings'])

    def test_doctor_names_the_live_settings_file_not_the_template(self):
        self.install('--client', 'cursor')
        report = self.doctor('cursor')[1]
        self.assertEqual(report['config_path'], str(self.project/'.datarim-runtime/jev-config.json'))
        live = json.loads(Path(report['config_path']).read_text())
        self.assertNotIn('_comment', live)
        template = json.loads((ROOT/'plugins/dr-jev-control/config/jev-control.json').read_text())
        self.assertIn('Template', template['_comment'])

    # -- defect: Codex trust was never measured for a project install ---------

    def test_codex_trust_is_read_from_the_project_hooks_file(self):
        self.install('--client', 'codex')
        (self.home/'.codex').mkdir()
        (self.home/'.codex/config.toml').write_text('model = "x"\n')
        code, report = self.doctor('codex')
        trust = report['codex_hook_trust']
        self.assertEqual(trust['state'], 'untrusted', trust)
        self.assertEqual(trust['untrusted'], ['PostToolUse', 'PreToolUse', 'UserPromptSubmit'])
        self.assertTrue(any('jev trust' in f for f in report['findings']))
        run = self.jev('trust')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('re-granted to 3', run.stdout)
        code, report = self.doctor('codex')
        self.assertEqual(report['codex_hook_trust']['state'], 'trusted')
        self.assertEqual((code, report['findings']), (0, []))
        # The grants are keyed by the project's own hooks file.
        self.assertIn(f'[hooks.state."{self.project}/.codex/hooks.json:pre_tool_use:0:0"]',
                      (self.home/'.codex/config.toml').read_text())

    def test_trust_without_a_codex_config_says_codex_has_not_reviewed_the_hooks(self):
        """`jev trust` said "Codex already trusts every Jev hook (or has none
        installed)" while doctor said not_measured."""
        self.install('--client', 'codex')
        run = self.jev('trust')
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn('Codex has not reviewed these project hooks yet', run.stdout)
        self.assertIn("open codex in the project and choose 'Trust all and continue'", run.stdout)
        self.assertNotIn('already trusts', run.stdout)

    def test_trust_in_a_project_without_codex_hooks_has_nothing_to_do(self):
        self.install('--client', 'claude')
        run = self.jev('trust')
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertIn('nothing to trust', run.stdout)

    def test_no_codex_config_is_not_measured_with_its_own_reason(self):
        self.install('--client', 'codex')
        trust = self.doctor('codex')[1]['codex_hook_trust']
        self.assertEqual(trust['state'], 'not_measured')
        self.assertNotEqual(trust['reason'], 'no Codex hook configuration')

    def test_a_project_without_codex_hooks_says_so(self):
        self.install('--client', 'claude')
        trust = self.doctor('codex')[1]['codex_hook_trust']
        self.assertEqual(trust['state'], 'not_measured')
        self.assertIn('no Jev hooks installed for Codex', trust['reason'])

    # -- defect: liveness was always not_measured ----------------------------

    def test_a_real_hook_delivery_makes_the_client_live(self):
        self.install('--client', 'cursor')
        self.assertEqual(self.doctor('cursor')[1]['native_agents_live']['cursor']['state'], 'not_measured')
        payload = json.dumps({'cwd': str(self.project), 'command': 'ls', 'conversation_id': 'probe'})
        command = json.loads((self.project/'.cursor/hooks.json').read_text())['hooks']['beforeShellExecution'][0]
        import shlex
        run = subprocess.run(shlex.split(command['command']), input=payload, cwd=self.project, env=self.env,
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        live = self.doctor('cursor')[1]['native_agents_live']['cursor']
        self.assertEqual(live['state'], 'live', live)
        self.assertEqual(live['deliveries'], 1)
        self.assertEqual(live['events'], ['beforeShellExecution'])

    # -- defect: a versioned interpreter path in every hook -------------------

    def test_registered_commands_use_the_stable_interpreter(self):
        self.install('--client', 'codex')
        commands = [h['command'] for groups in json.loads((self.project/'.codex/hooks.json').read_text())
                    ['hooks'].values() for g in groups for h in g['hooks']]
        expected = jev_host_install.hook_interpreter()
        self.assertEqual(len(commands), 3)
        self.assertTrue(all(c.split()[0] == expected for c in commands), commands)


class Liveness(unittest.TestCase):
    def test_deliveries_are_counted_per_client_and_other_events_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory)/'ledger.jsonl'
            now = time.time()
            ledger.write_text('\n'.join([
                json.dumps({'event': 'hook_delivery', 'ts': now, 'data': {'client': 'codex',
                                                                         'native_event': 'PreToolUse'}}),
                json.dumps({'event': 'hook_delivery', 'ts': now - 5, 'data': {},
                            'hook_context': {'client': 'codex', 'native_event': 'UserPromptSubmit'}}),
                json.dumps({'event': 'route', 'ts': now, 'data': {'client': 'claude'}}),
                'not json',
            ]) + '\n')
            out = jev.hook_liveness([ledger], ['claude', 'codex'], ['claude', 'codex'])
        self.assertEqual(out['codex']['state'], 'live')
        self.assertEqual(out['codex']['deliveries'], 2)
        self.assertEqual(out['codex']['events'], ['PreToolUse', 'UserPromptSubmit'])
        self.assertEqual(out['claude']['state'], 'not_measured')

    def test_a_symlinked_ledger_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            real = Path(directory)/'real.jsonl'
            real.write_text(json.dumps({'event': 'hook_delivery', 'ts': 1, 'data': {'client': 'claude'}}) + '\n')
            link = Path(directory)/'ledger.jsonl'
            link.symlink_to(real)
            self.assertEqual(jev.hook_liveness([link], ['claude'], ['claude'])['claude']['state'], 'not_measured')

    def test_disabled_telemetry_is_named_as_the_reason(self):
        out = jev.hook_liveness([], ['claude'], ['claude'], telemetry_enabled=False)
        self.assertIn('telemetry disabled', out['claude']['reason'])


class Registration(unittest.TestCase):
    def test_a_command_that_only_mentions_the_script_does_not_count(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'hooks.json'
            entry = '/p/.datarim-runtime/scripts/jev_hook.py'
            hooks = {event: [{'command': f'echo {entry} cursor {event}'}]
                     for event in jev.REGISTERED_EVENTS['cursor']}
            path.write_text(json.dumps({'version': 1, 'hooks': hooks}))
            findings = jev.registration_findings(['cursor'], {'cursor': path}, (entry,))
            self.assertEqual(len(findings), 1)
            hooks = {event: [{'command': f'/usr/bin/python3 {entry} cursor {event}'}]
                     for event in jev.REGISTERED_EVENTS['cursor']}
            path.write_text(json.dumps({'version': 1, 'hooks': hooks}))
            self.assertEqual(jev.registration_findings(['cursor'], {'cursor': path}, (entry,)), [])


if __name__ == '__main__':
    unittest.main()
