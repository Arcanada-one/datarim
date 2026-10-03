"""Installer boundary, interoperability and reversible-update regression tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('installer', ROOT / 'scripts/human_reporting_install.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'; self.home.mkdir()
        self.source = self.root / installer.NAME; self.source.mkdir()
        (self.source / 'SKILL.md').write_text('---\nname: human-outcome-reporting\n---\nPolicy\n')
        (self.source / 'references').mkdir()
        (self.source / 'references/profile.md').write_text('Profile\n')

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, action='install', *extra, expected=0):
        out = subprocess.run([sys.executable, str(ROOT / 'scripts/human_reporting_install.py'), action, '--home', str(self.home), '--source', str(self.source), *extra], text=True, capture_output=True)
        self.assertEqual(out.returncode, expected, out.stderr + out.stdout)
        return json.loads(out.stdout or out.stderr)

    def write(self, rel, text):
        path = self.home / rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text); return path

    def test_install_native_scopes_and_idempotence(self):
        self.run_cli()
        for agent in ('claude', 'codex', 'cursor'):
            self.assertEqual((self.home / ('.agents' if agent=='codex' else '.'+agent) / 'skills' / installer.NAME / 'SKILL.md').read_bytes(), (self.source/'SKILL.md').read_bytes())
        self.assertFalse((self.home/'.claude/CLAUDE.md').exists())
        self.assertFalse((self.home/'.claude/commands').exists())
        self.assertIn('keep-coding-instructions: true', (self.home/'.claude/output-styles/human-outcome-reporting.md').read_text())
        self.assertEqual(self.run_cli()['operations'], [])
        self.assertEqual(self.run_cli('check')['verdict'], 'verified')

    def test_dry_run_changes_nothing(self):
        self.run_cli('install', '--dry-run')
        self.assertEqual(list(self.home.iterdir()), [])

    def test_preserves_settings_hooks_and_exact_originals(self):
        settings = self.write('.claude/settings.json', '{"outputStyle":"Concise","permissions":{"deny":["secret"]}}\n')
        agents = self.write('.codex/AGENTS.md', 'Existing instructions\n')
        hooks = self.write('.cursor/hooks.json', '{"version":1,"hooks":{"sessionStart":[{"command":"foreign"}],"stop":[{"command":"safety"}]}}\n')
        before = [p.read_bytes() for p in (settings, agents, hooks)]
        self.run_cli()
        self.assertEqual(json.loads(settings.read_text())['permissions']['deny'], ['secret'])
        self.assertEqual(json.loads(hooks.read_text())['hooks']['sessionStart'][0]['command'], 'foreign')
        self.run_cli('uninstall')
        self.assertEqual([p.read_bytes() for p in (settings, agents, hooks)], before)

    def test_uninstall_keeps_later_foreign_changes(self):
        self.run_cli()
        agents = self.home/'.codex/AGENTS.md'
        agents.write_text(agents.read_text()+'Later foreign instructions\n')
        settings = self.home/'.claude/settings.json'; cfg=json.loads(settings.read_text());cfg['language']='English';settings.write_text(json.dumps(cfg))
        hooks=self.home/'.cursor/hooks.json';cfg=json.loads(hooks.read_text());cfg['hooks']['stop']=[{'command':'new-owner'}];hooks.write_text(json.dumps(cfg))
        self.run_cli('uninstall')
        self.assertIn('Later foreign instructions', agents.read_text())
        self.assertNotIn(installer.BEGIN, agents.read_text())
        self.assertEqual(json.loads(settings.read_text()), {'language':'English'})
        self.assertEqual(json.loads(hooks.read_text())['hooks']['stop'], [{'command':'new-owner'}])

    def test_nonempty_codex_override_is_selected(self):
        path=self.write('.codex/AGENTS.override.md', 'Override rules\n')
        self.run_cli()
        self.assertIn(installer.BEGIN, path.read_text())
        self.assertFalse((self.home/'.codex/AGENTS.md').exists())

    def test_symlink_destination_cannot_escape_home(self):
        outside=self.root/'outside';outside.mkdir();(self.home/'.claude').symlink_to(outside)
        self.run_cli(expected=2)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((self.home/'.codex').exists())

    def test_malformed_shared_config_is_preflight_refusal(self):
        self.write('.cursor/hooks.json', '{broken')
        self.run_cli(expected=2)
        self.assertFalse((self.home/'.claude').exists())

    def test_modified_owned_file_blocks_whole_update(self):
        self.run_cli()
        file=self.home/'.cursor/skills/human-outcome-reporting/SKILL.md';file.write_text('Foreign edits')
        (self.source/'SKILL.md').write_text('Updated')
        self.run_cli(expected=2)
        self.assertNotEqual((self.home/'.claude/skills/human-outcome-reporting/SKILL.md').read_text(), 'Updated')
        self.assertEqual(file.read_text(), 'Foreign edits')
        self.run_cli('uninstall', expected=2)

    def test_upgrade_removes_stale_owned_reference(self):
        self.run_cli();(self.source/'references/profile.md').unlink()
        self.run_cli()
        self.assertFalse((self.home/'.cursor/skills/human-outcome-reporting/references/profile.md').exists())

    def test_changed_user_output_style_is_not_overwritten(self):
        self.run_cli();path=self.home/'.claude/settings.json';cfg=json.loads(path.read_text());cfg['outputStyle']='Explanatory';path.write_text(json.dumps(cfg))
        self.run_cli(expected=2)
        self.assertEqual(json.loads(path.read_text())['outputStyle'], 'Explanatory')

    def test_cursor_hook_emits_context_without_data_access(self):
        self.run_cli();script=self.home/'.cursor/hooks/human-outcome-reporting.py'
        out=subprocess.run([sys.executable,str(script)],input='secret input',text=True,capture_output=True,check=True)
        context=json.loads(out.stdout)['additional_context']
        self.assertIn('Human Outcome Reporting',context)
        self.assertNotIn('secret input',context)
        self.assertIn(str(self.home/'.cursor/skills/human-outcome-reporting/SKILL.md'),context)

    def test_corrupted_state_traversal_is_refused(self):
        self.run_cli()
        state=self.home/'.local/state/datarim-human-reporting/installation.json'
        cfg=json.loads(state.read_text());cfg['files']['../outside.txt']=next(iter(cfg['files'].values()));state.write_text(json.dumps(cfg))
        outside=self.root/'outside.txt';outside.write_text('Protected')
        self.run_cli('uninstall',expected=2)
        self.assertEqual(outside.read_text(),'Protected')

    def test_cursor_later_version_survives_uninstall(self):
        self.write('.cursor/hooks.json','{}')
        self.run_cli()
        path=self.home/'.cursor/hooks.json';cfg=json.loads(path.read_text());cfg['version']=2;path.write_text(json.dumps(cfg))
        self.run_cli('uninstall')
        self.assertEqual(json.loads(path.read_text())['version'],2)

    def test_concurrent_installs_keep_foreign_settings_and_state(self):
        self.write('.claude/settings.json','{"permissions":{"deny":["Protected"]}}')
        argv=[sys.executable,str(ROOT/'scripts/human_reporting_install.py'),'install','--home',str(self.home),'--source',str(self.source)]
        processes=[subprocess.Popen(argv,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for _ in range(4)]
        for process in processes:
            stdout,stderr=process.communicate(timeout=15)
            self.assertEqual(process.returncode,0,stderr)
        self.assertEqual(json.loads((self.home/'.claude/settings.json').read_text())['permissions']['deny'],['Protected'])
        self.run_cli('check')
        self.run_cli('uninstall')
        self.assertEqual(json.loads((self.home/'.claude/settings.json').read_text()),{'permissions':{'deny':['Protected']}})

    def test_upgrade_stale_file_restores_previous_foreign_content(self):
        path=self.write('.cursor/skills/human-outcome-reporting/references/profile.md','Previous profile')
        self.run_cli();(self.source/'references/profile.md').unlink();self.run_cli()
        self.assertEqual(path.read_text(),'Previous profile')
        self.run_cli('uninstall')
        self.assertEqual(path.read_text(),'Previous profile')

    def test_failed_write_rolls_back_transaction(self):
        state_path=self.home/'.local/state/datarim-human-reporting/installation.json'
        real=installer.atomic_write;count=0
        def fail_once(*args,**kwargs):
            nonlocal count
            count+=1
            if count==3: raise OSError('simulated disk write failure')
            return real(*args,**kwargs)
        with patch.object(installer,'atomic_write',side_effect=fail_once):
            with self.assertRaises(OSError):
                installer.install(self.home,self.source,['claude','codex','cursor'],state_path,{},False)
        self.assertFalse(state_path.exists())
        self.assertFalse((self.home/'.claude/skills/human-outcome-reporting/SKILL.md').exists())
        self.assertFalse(state_path.with_name('pending.json').exists())


if __name__=='__main__':
    unittest.main()
