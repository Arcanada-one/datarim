#!/usr/bin/env python3
"""What a launcher hands to the client, and when it asks for no prompts.

Measured on a consumer host: `jevclaude --dangerously-skip-permissions` stopped with
"unrecognized arguments", because client options were accepted only after --.
"""
from __future__ import annotations

import os
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


if __name__ == '__main__':
    unittest.main()
