#!/usr/bin/env python3
"""Codex runs a hook only after the operator trusts it, not when it is written.

These cover the gap that hid a whole class of hook events for 45 minutes: the
hooks were installed and the client reported them Active, while the ledger held
zero UserPromptSubmit events because the entries were still awaiting review.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from jev import codex_hook_trust  # noqa: E402

SHA = 'b13540486fc0ee34f7726dabcf9e1ba1a6ca35fc'
OTHER = '57d591d04d0d47e5798db3c970992df1b238004f'


def _hook(sha):
    return {'type': 'command', 'timeout': 9,
            'command': f'/usr/bin/python3 /home/a/.local/share/jev/releases/{sha}/scripts/jev_hook.py codex X'}


def _home(tmp, hooks, state):
    home = Path(tmp)
    (home/'.codex').mkdir(parents=True, exist_ok=True)
    (home/'.codex/hooks.json').write_text(json.dumps({'hooks': hooks}))
    (home/'.codex/config.toml').write_text(state)
    return home


def _block(event_key, index, enabled):
    body = 'trusted_hash = "sha256:deadbeef"\n'
    if enabled:
        body += 'enabled = true\n'
    return f'[hooks.state."/home/a/.codex/hooks.json:{event_key}:{index}:0"]\n{body}\n'


class CodexHookTrust(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()

    def test_a_written_hook_without_the_enabled_flag_reads_as_untrusted(self):
        """The measured failure: installed, counted Active, never executed."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=False))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['pending'], ['UserPromptSubmit'])

    def test_an_enabled_hook_reads_as_trusted(self):
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'trusted')
        self.assertEqual(result['pending'], [])

    def test_one_untrusted_hook_among_trusted_ones_is_still_reported(self):
        """The real host state: PreToolUse ran while UserPromptSubmit did not."""
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}],
                      'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True) +
                     _block('user_prompt_submit', 0, enabled=False))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['pending'], ['UserPromptSubmit'])
        self.assertIn('PreToolUse', result['installed'])

    def test_trust_for_a_different_release_does_not_count_for_this_one(self):
        """Trust is keyed to the command string, which carries releases/<sha>."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(OTHER)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'not_measured')

    def test_a_foreign_hook_is_never_claimed_as_ours(self):
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [{'type': 'command',
                                                 'command': '/home/a/.local/bin/coworker-hook-guard'}]}]},
                     '')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'not_measured')

    def test_absent_configuration_is_not_measured_rather_than_trusted(self):
        """A missing file must not read as a pass: it answers nothing."""
        result = codex_hook_trust(SHA, Path(self.tmp)/'nowhere')
        self.assertEqual(result['state'], 'not_measured')

    def test_the_index_must_match_not_merely_the_event(self):
        """Two hooks on one event: trusting the foreign one is not trusting ours."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [{'type': 'command', 'command': '/bin/true'}]},
                                           {'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')


if __name__ == '__main__':
    unittest.main()
