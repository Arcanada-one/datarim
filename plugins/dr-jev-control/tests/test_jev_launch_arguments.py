#!/usr/bin/env python3
"""What a launcher hands to the client, and when it asks for no prompts.

Measured on a consumer host: `jevclaude --dangerously-skip-permissions` stopped with
"unrecognized arguments", because client options were accepted only after --.
"""
from __future__ import annotations

import os
import io
import json
import subprocess
from contextlib import redirect_stdout
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
import jev  # noqa: E402


def parse(launcher, *argv):
    with mock.patch.object(sys, 'argv', [launcher, *argv]):
        return jev.parse(list(argv))


class ClientOptions(unittest.TestCase):
    def test_an_unknown_switch_goes_to_the_client_without_a_separator(self):
        a, extra = parse('jevclaude', '--dangerously-skip-permissions')
        self.assertEqual(extra, ['--dangerously-skip-permissions'])
        self.assertIsNone(a.task)

    def test_a_switch_before_the_task_leaves_the_task_alone(self):
        a, extra = parse('jevclaude', '--dangerously-skip-permissions', 'fix the test')
        self.assertEqual((a.task, extra), ('fix the test', ['--dangerously-skip-permissions']))

    def test_a_client_option_keeps_its_value(self):
        a, extra = parse('jevclaude', '--permission-mode', 'plan', 'fix the test')
        self.assertEqual((a.task, extra), ('fix the test', ['--permission-mode', 'plan']))

    def test_the_same_letter_means_what_that_client_means(self):
        """-c is --continue in Claude and --config KEY=VALUE in Codex."""
        a, extra = parse('jevclaude', '-c')
        self.assertEqual(extra, ['-c'])
        a, extra = parse('jevcodex', '-c', 'model_verbosity=low', 'the task')
        self.assertEqual((a.task, extra), ('the task', ['-c', 'model_verbosity=low']))

    def test_jev_options_are_still_jev_options(self):
        a, extra = parse('jevclaude', '--resume', 'TBT', '--dangerously-skip-permissions')
        self.assertEqual((a.resume, extra), ('TBT', ['--dangerously-skip-permissions']))

    def test_the_separator_still_works(self):
        a, extra = parse('jevclaude', '--resume', 'TBT', '--', '--dangerously-skip-permissions')
        self.assertEqual((a.resume, extra), ('TBT', ['--dangerously-skip-permissions']))

    def test_a_directory_override_is_still_refused_without_a_separator(self):
        with self.assertRaises(SystemExit):
            parse('jevcodex', '--add-dir=/elsewhere')

    def test_permissions_takes_a_setting_and_nothing_else_does(self):
        a, _ = parse('jev', 'permissions', 'full')
        self.assertEqual((a.task, a.setting), ('permissions', 'full'))
        with self.assertRaises(SystemExit):
            parse('jevclaude', 'one task', 'another')


class FullPermissions(unittest.TestCase):
    def setUp(self):
        self.state = Path(tempfile.mkdtemp())
        self.env = mock.patch.dict(os.environ, {}, clear=False)
        self.env.start()
        os.environ.pop('JEV_PERMISSIONS', None)

    def tearDown(self):
        self.env.stop()

    def test_off_unless_chosen(self):
        self.assertFalse(jev.full_permissions(self.state))

    def test_the_stored_choice_turns_it_on(self):
        (self.state/'FULL_PERMISSIONS').touch()
        self.assertTrue(jev.full_permissions(self.state))

    def test_the_environment_overrides_the_stored_choice_both_ways(self):
        (self.state/'FULL_PERMISSIONS').touch()
        os.environ['JEV_PERMISSIONS'] = 'ask'
        self.assertFalse(jev.full_permissions(self.state))
        (self.state/'FULL_PERMISSIONS').unlink()
        os.environ['JEV_PERMISSIONS'] = 'full'
        self.assertTrue(jev.full_permissions(self.state))

    def test_each_client_gets_its_own_flag(self):
        self.assertEqual(jev.permission_flags('claude', []), ['--dangerously-skip-permissions'])
        self.assertEqual(jev.permission_flags('codex', []), ['--dangerously-bypass-approvals-and-sandbox'])
        self.assertEqual(jev.permission_flags('cursor', []), ['--force', '--approve-mcps'])

    def test_an_explicit_policy_from_the_operator_wins(self):
        self.assertEqual(jev.permission_flags('claude', ['--permission-mode', 'plan']), [])
        self.assertEqual(jev.permission_flags('codex', ['-s', 'read-only']), [])
        self.assertEqual(jev.permission_flags('codex', ['--sandbox=read-only']), [])
        self.assertEqual(jev.permission_flags('cursor', ['--yolo']), [])

    def test_a_flag_already_given_is_not_repeated(self):
        self.assertEqual(jev.permission_flags('claude', ['--dangerously-skip-permissions']), [])



class LiveWallClockCaps(unittest.TestCase):
    def launches(self):
        return [('jev', ['--agent=codex']), ('jevclaude', []),
                ('jevcodex', []), ('jevcursor', [])]

    def test_all_entrypoints_refuse_nonfinite_explicit_caps(self):
        import contextlib
        import io
        for launcher, prefix in self.launches():
            for value in ('nan', 'inf', '-inf'):
                with self.subTest(launcher=launcher, value=value):
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stop:
                        parse(launcher, *prefix, '--live', '--max-seconds='+value, 'do the thing')
                    self.assertEqual(stop.exception.code, 2)

    def test_all_entrypoints_accept_positive_finite_caps(self):
        for launcher, prefix in self.launches():
            for value in ('0.25', '1', '150', '1e3'):
                with self.subTest(launcher=launcher, value=value):
                    args, extra = parse(launcher, *prefix, '--live', '--max-seconds='+value, 'do the thing')
                    self.assertEqual(args.max_seconds, float(value))
                    self.assertEqual(extra, [])

    def test_all_entrypoints_keep_nonpositive_cap_refusal(self):
        import contextlib
        import io
        for launcher, prefix in self.launches():
            for value in ('0', '-1', '-0.25'):
                with self.subTest(launcher=launcher, value=value):
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stop:
                        parse(launcher, *prefix, '--live', '--max-seconds='+value, 'do the thing')
                    self.assertEqual(stop.exception.code, 2)


class BareWordTasks(unittest.TestCase):
    """`jev status --agent=claude` started a nested client session with the
    prompt "status": a mistyped subcommand became a task."""

    def refused(self, launcher, *argv):
        import contextlib
        import io
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as stop:
            parse(launcher, *argv)
        self.assertEqual(stop.exception.code, 2)
        return err.getvalue()

    def test_an_unknown_single_word_is_refused_with_the_subcommands(self):
        for launcher, argv in (('jev', ('status', '--agent=claude')), ('jevclaude', ('status',)),
                               ('jevcodex', ('doctr',))):
            with self.subTest(argv=argv):
                message = self.refused(launcher, *argv)
                self.assertIn(f"unknown subcommand '{argv[0]}'", message)
                self.assertIn('subcommands: doctor, stats, on, off, permissions, trust', message)
                self.assertIn('quote a sentence or use --', message)

    def test_sentences_subcommands_files_and_client_arguments_still_work(self):
        self.assertEqual(parse('jevclaude', 'fix the failing test')[0].task, 'fix the failing test')
        self.assertEqual(parse('jev', 'doctor', '--agent=claude')[0].task, 'doctor')
        self.assertEqual(parse('jev', 'permissions', 'full')[0].setting, 'full')
        a, extra = parse('jevclaude', '--', 'status')
        self.assertEqual((a.task, extra), (None, ['status']))
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory)/'task.md'
            task.write_text('Do the thing.\n')
            self.assertEqual(parse('jevclaude', str(task))[0].task, str(task))

    def test_no_task_at_all_is_not_refused(self):
        self.assertIsNone(parse('jevclaude')[0].task)




class DoctorVersionProbeFailures(unittest.TestCase):
    def doctor(self, failure):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / '.datarim-runtime'
            runtime.mkdir()
            (runtime / 'installation.json').write_text(json.dumps({
                'source_sha': 'fake-source-only', 'files': {}}))
            scope = {'files': {'codex': root / 'hooks.json'},
                     'entries': ['synthetic-no-execution-hook'],
                     'selected': ['claude', 'codex', 'cursor'],
                     'ledgers': {}, 'telemetry_enabled': False, 'config': None}
            calls = []
            def version(argv, **kwargs):
                calls.append((argv, kwargs))
                if argv[0] == '/fake/claude':
                    raise failure
                return subprocess.CompletedProcess(argv, 0, argv[0] + ' 1.0', '')
            output = io.StringIO()
            with mock.patch.object(sys, 'argv', ['jev', 'doctor']), \
                 mock.patch.object(jev, 'project_root', return_value=root), \
                 mock.patch.object(jev, 'activate', return_value=runtime), \
                 mock.patch.object(jev, 'scope_hooks', return_value=scope), \
                 mock.patch.object(jev, 'binary', side_effect=lambda a: '/fake/' + a), \
                 mock.patch.object(jev, 'hook_liveness', return_value={}), \
                 mock.patch.object(jev, 'registration_findings', return_value=[]), \
                 mock.patch.object(jev, 'codex_hook_trust', return_value={'state': 'trusted'}), \
                 mock.patch.object(jev, 'datarim_enabled', return_value=False), \
                 mock.patch.dict(os.environ, {'TYPESAFE_API_KEY_FILE': str(root / 'absent-key')}), \
                 mock.patch('subprocess.run', side_effect=version), \
                 redirect_stdout(output):
                code = jev.main()
            return code, json.loads(output.getvalue()), calls

    def test_timeout_reports_failed_probe_and_checks_remaining_clients(self):
        code, report, calls = self.doctor(subprocess.TimeoutExpired(
            ['/fake/claude', '--version'], 15, output='SYNTHETIC_SECRET'))
        self.assertEqual(code, 1)
        self.assertIn('claude: version probe timed out', report['findings'])
        self.assertEqual(set(report['versions']), {'codex', 'cursor'})
        self.assertNotIn('SYNTHETIC_SECRET', json.dumps(report))
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(args[1] == '--version' and opts['timeout'] == 15
                            for args, opts in calls))
        self.assertEqual(report['api'], 'not_measured')

    def test_spawn_error_reports_failed_probe_and_checks_remaining_clients(self):
        code, report, calls = self.doctor(PermissionError('SYNTHETIC_SECRET'))
        self.assertEqual(code, 1)
        self.assertIn('claude: version probe could not execute', report['findings'])
        self.assertEqual(set(report['versions']), {'codex', 'cursor'})
        self.assertNotIn('SYNTHETIC_SECRET', json.dumps(report))
        self.assertEqual(len(calls), 3)
        self.assertEqual(report['api'], 'not_measured')

if __name__ == '__main__':
    unittest.main()
