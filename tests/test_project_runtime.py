"""Project isolation, lossless installation and CLI boundary regression tests."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from project_scope import ScopeError, project_root
import project_install


class ProjectScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()/'project'
        self.root.mkdir()

    def mark(self):
        runtime = self.root/'.datarim-runtime'
        runtime.mkdir()
        (runtime/'installation.json').write_text(json.dumps({'schema': 1, 'project': str(self.root)}))

    def test_no_home_or_neighbor_fallback(self):
        self.mark()
        sibling = self.root.parent/'project-elsewhere'
        sibling.mkdir()
        with self.assertRaises(ScopeError):
            project_root(sibling)

    def test_nested_repository_requires_explicit_context(self):
        self.mark()
        nested = self.root/'child'
        nested.mkdir()
        (nested/'.git').mkdir()
        with self.assertRaises(ScopeError):
            project_root(nested)
        manifest = self.root/'.datarim-runtime/installation.json'
        data = json.loads(manifest.read_text())
        data['contexts'] = ['child']
        manifest.write_text(json.dumps(data))
        self.assertEqual(project_root(nested), self.root)

    def test_scope_rejects_copied_installation(self):
        self.mark()
        moved = self.root.with_name('moved')
        self.root.rename(moved)
        with self.assertRaises(ScopeError):
            project_root(moved)

    def test_symlink_escape_cannot_write_credentials(self):
        outside = self.root.parent/'outside'
        outside.mkdir()
        (self.root/'config').symlink_to(outside)
        with self.assertRaises(ValueError):
            project_install.safe_path(self.root, 'config/credentials/jev/api-key')

    def test_rule_merge_preserves_foreign_instructions(self):
        original = '# Client rules\nKeep every production boundary.\n'
        once = project_install.replace_block(original, project_install.BEGIN+'\nnew\n'+project_install.END)
        twice = project_install.replace_block(once, project_install.BEGIN+'\nupdated\n'+project_install.END)
        self.assertIn('Keep every production boundary.', twice)
        self.assertEqual(twice.count(project_install.BEGIN), 1)
        self.assertNotIn('\nnew\n', twice)

    def test_no_task_state_in_product(self):
        self.assertFalse((ROOT/'datarim').exists())
        self.assertTrue((ROOT/'AGENTS.md').is_file())
        self.assertFalse((ROOT/'AGENTS.md').is_symlink())
        self.assertFalse((ROOT/'CLAUDE.md').exists())

    #: History that records what earlier releases did; not instructions.
    DOC_HISTORY = ('CHANGELOG.md', 'JEV-V2-NOTES.md', 'JEV-INTEGRATION-REPORT.md',
                   'documentation/archive/', 'documentation/plans/', 'documentation/evolution/',
                   'documentation/how-to/evolution-log.md')

    @staticmethod
    def pre_answered_install_commands(text):
        """Fresh-install commands in `text` that already carry an answer.

        A summarizing fetch keeps complete command lines and drops every "ask
        the user first" sentence around them: an agent copied one with
        --without-jev and never asked. Continuation lines are joined, inline
        code spans may wrap, and a trailing comment does not count. Update and
        uninstall commands, and lines marked `not a user install`, are exempt.
        """
        import re
        joined = re.sub(r'\\\n\s*', ' ', text)
        candidates = joined.splitlines() + [' '.join(m.split()) for m in re.findall(r'`([^`]+)`', joined)]
        found = []
        for line in candidates:
            if not re.search(r'(install\.sh|project_install\.py)\s', line) or '--project' not in line:
                continue
            if '--uninstall' in line or 'not a user install' in line or re.search(r'#\s*update\b', line):
                continue
            command = line.split(' #', 1)[0]
            if re.search(r'--with-jev|--without-jev|--client\b', command):
                found.append(line.strip())
        return found

    def test_no_doc_shows_a_fresh_install_command_with_the_answers(self):
        found = {}
        listed = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '*.md'], capture_output=True, text=True)
        names = listed.stdout.split() or [str(p.relative_to(ROOT)) for p in ROOT.rglob('*.md')]
        for name in names:
            if name.startswith(self.DOC_HISTORY):
                continue
            hits = self.pre_answered_install_commands((ROOT/name).read_text(errors='replace'))
            if hits:
                found[name] = hits
        self.assertEqual(found, {})

    def test_the_doc_scan_catches_the_shapes_that_leaked(self):
        leaked = ('./install.sh --project "$PROJECT" --init --without-jev',
                  'python3 scripts/project_install.py --project /p \\\n  --init --with-jev --host-jev',
                  'Run `./install.sh --project /p\n--with-jev` for this project',
                  './install.sh --project P --client claude')
        for text in leaked:
            self.assertTrue(self.pre_answered_install_commands(text), text)
        allowed = ('./install.sh --project "$PROJECT"   # prints the questions; flags: --with-jev',
                   './install.sh --project "$PROJECT" --uninstall',
                   './update.sh --project "$PROJECT" --without-jev',
                   './install.sh --project P --client all   # scratch test project, not a user install')
        for text in allowed:
            self.assertFalse(self.pre_answered_install_commands(text), text)

    def test_installer_rejects_global_flags(self):
        run = subprocess.run([str(ROOT/'install.sh'), '--with-claude'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn('--project', run.stderr)


class InstallationLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name).resolve()
        self.source, self.project = base/'source', base/'project'
        self.source.mkdir()
        self.project.mkdir()
        for name in ('agents', 'skills', 'commands'):
            (self.source/name).mkdir()
        (self.source/'skills/testing').mkdir()
        (self.source/'skills/testing/SKILL.md').write_text('---\nname: testing\n---\nTest behavior.\n')
        (self.source/'commands/dr-do.md').write_text('Run the task.\n')
        (self.source/'AGENTS.md').write_text('# Framework\n')
        (self.source/'VERSION').write_text('test\n')
        (self.project/'AGENTS.md').write_text('# Original project rules\n')
        (self.project/'.gitignore').write_text('/build/\n')
        self.args = Namespace(project=str(self.project), with_jev=False,
                              client=project_install.CLIENTS, context=[], dry_run=False, init=True)
        self.source_patch = patch.object(project_install, 'SOURCE', self.source)
        self.source_patch.start()
        self.addCleanup(self.source_patch.stop)

    def test_install_update_uninstall_leaves_shared_files_alone(self):
        project_install.install(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')
        self.assertEqual((self.project/'.gitignore').read_text(), '/build/\n')
        # Only the commands are entry points; framework skills load on demand.
        self.assertFalse((self.project/'.agents/skills/testing').exists())
        for name in ('.agents/skills/dr-do/SKILL.md', '.cursor/skills/dr-do/SKILL.md',
                     '.claude/commands/dr-do.md'):
            self.assertTrue((self.project/name).is_file(), name)
        self.assertFalse((self.project/'.claude/skills/dr-do').exists())
        manifest = self.project/'.datarim-runtime/installation.json'
        before = manifest.stat().st_mtime_ns
        project_install.install(self.args)
        self.assertEqual(manifest.stat().st_mtime_ns, before)
        (self.source/'VERSION').write_text('new version\n')
        project_install.install(self.args)
        project_install.uninstall(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')
        self.assertEqual((self.project/'.gitignore').read_text(), '/build/\n')
        self.assertFalse((self.project/'.agents/skills/dr-do/SKILL.md').exists())
        self.assertTrue((self.project/'datarim/tasks.md').is_file())
        self.assertEqual((self.project/'.datarim-uninstalled').stat().st_mode & 0o077, 0)

    def test_every_command_carries_the_runtime_and_keeps_its_frontmatter_first(self):
        (self.source/'commands/dr-plan.md').write_text('---\nname: dr-plan\ndescription: Plan.\n---\n\n# Plan\n')
        project_install.install(self.args)
        runtime = str(self.project/'.datarim-runtime')
        plan = (self.project/'.claude/commands/dr-plan.md').read_text()
        self.assertTrue(plan.startswith('---\nname: dr-plan\ndescription: Plan.\n---\n'))
        self.assertIn(f'`{runtime}/AGENTS.md`', plan)
        self.assertIn('# Plan', plan)
        do = (self.project/'.claude/commands/dr-do.md').read_text()
        self.assertTrue(do.startswith('> **Datarim**'))
        stub = (self.project/'.agents/skills/dr-do/SKILL.md').read_text()
        self.assertIn(f'`{runtime}/commands/dr-do.md`', stub)

    def test_expose_skills_is_opt_in_and_sticky(self):
        project_install.install(Namespace(**{**vars(self.args), 'expose_skills': True}))
        self.assertTrue((self.project/'.claude/skills/testing/SKILL.md').is_file())
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.args)
        self.assertTrue((self.project/'.claude/skills/testing/SKILL.md').is_file())

    def test_retiring_exposed_skills_leaves_no_empty_directories(self):
        """Measured on a real project: withdrawing the skills left 105 empty
        `.claude/skills/<name>/` directories behind."""
        project_install.install(Namespace(**{**vars(self.args), 'expose_skills': True}))
        manifest = json.loads((self.project/'.datarim-runtime/installation.json').read_text())
        manifest['expose_skills'] = False  # as recorded by a release before the flag
        (self.project/'.datarim-runtime/installation.json').write_text(json.dumps(manifest))
        (self.project/'.claude/skills/mine').mkdir()
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.args)
        self.assertFalse((self.project/'.claude/skills/testing').exists())
        self.assertTrue((self.project/'.claude/skills/mine').is_dir(), 'a directory we did not empty stays')
        self.assertTrue((self.project/'.claude').is_dir(), 'the client directory itself stays')

    def test_uninstall_leaves_no_empty_directories_it_created(self):
        project_install.install(self.args)
        project_install.uninstall(self.args)
        empty = [str(d.relative_to(self.project)) for d in self.project.rglob('*')
                 if d.is_dir() and d.parent != self.project and not any(d.iterdir())
                 and '.datarim-uninstalled' not in d.parts]  # the backup is kept whole
        self.assertEqual(empty, [])

    def test_an_older_install_releases_agents_md_and_gitignore_without_deleting_them(self):
        """Earlier releases managed both files; files that leave management are
        otherwise deleted. These two are the project's own and must survive."""
        project_install.install(self.args)
        runtime = self.project/'.datarim-runtime'
        agents = '# Original project rules\n\n' + project_install.BEGIN + '\nold block\n' + project_install.END + '\n'
        ignore = project_install.private_ignores('/build/\n')
        (self.project/'AGENTS.md').write_text(agents + 'Later operator line\n')
        (self.project/'.gitignore').write_text(ignore)
        manifest = json.loads((runtime/'installation.json').read_text())
        manifest['files']['AGENTS.md'] = project_install.digest((agents + 'Later operator line\n').encode())
        manifest['files']['.gitignore'] = project_install.digest(ignore.encode())
        (runtime/'installation.json').write_text(json.dumps(manifest))
        originals = json.loads((runtime/'original-files.json').read_text())
        originals.update({'AGENTS.md': '# Original project rules\n', '.gitignore': '/build/\n'})
        (runtime/'original-files.json').write_text(json.dumps(originals))
        (self.source/'VERSION').write_text('release\n')
        project_install.install(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(),
                         '# Original project rules\n\nLater operator line\n')
        self.assertEqual((self.project/'.gitignore').read_text(), '/build/\n')
        after = json.loads((runtime/'installation.json').read_text())['files']
        self.assertNotIn('AGENTS.md', after)
        self.assertNotIn('.gitignore', after)
        # Released means released: a later edit survives an uninstall.
        (self.project/'AGENTS.md').write_text('# Rewritten by the operator\n')
        project_install.uninstall(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Rewritten by the operator\n')

    def test_a_git_project_shows_nothing_in_status(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        subprocess.run(['git', '-C', str(self.project), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.project), '-c', 'user.email=t@t', '-c', 'user.name=t',
                        'commit', '-qm', 'init'], check=True)
        project_install.install(self.args)
        status = subprocess.run(['git', '-C', str(self.project), 'status', '--porcelain'],
                                capture_output=True, text=True, check=True).stdout
        self.assertEqual(status, '')
        project_install.uninstall(self.args)
        status = subprocess.run(['git', '-C', str(self.project), 'status', '--porcelain'],
                                capture_output=True, text=True, check=True).stdout
        # Keys, task state and the recovery bundle stay, and stay hidden.
        self.assertEqual(status, '')
        exclude = (self.project/'.git/info/exclude').read_text()
        self.assertIn('/datarim/', exclude)
        self.assertNotIn('/.claude/commands/dr-do.md', exclude)

    def test_a_project_inside_a_larger_repository_gets_prefixed_rules(self):
        repo = self.project.parent/'monorepo'
        sub = repo/'apps/site'
        sub.mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        project_install.install(Namespace(**{**vars(self.args), 'project': str(sub)}))
        exclude = (repo/'.git/info/exclude').read_text()
        self.assertIn('/apps/site/.datarim-runtime/', exclude)
        self.assertIn('/apps/site/.claude/commands/dr-do.md', exclude)
        status = subprocess.run(['git', '-C', str(repo), 'status', '--porcelain'],
                                capture_output=True, text=True, check=True).stdout
        self.assertEqual(status, '')

    def test_an_existing_claude_md_is_left_alone(self):
        (self.project/'CLAUDE.md').write_text('Always answer in French.\n')
        project_install.install(self.args)
        self.assertEqual((self.project/'CLAUDE.md').read_text(), 'Always answer in French.\n')

    # -- choosing clients ----------------------------------------------------

    def with_args(self, **changes):
        if changes.get('with_jev'):
            config = self.source/'plugins/dr-jev-control/config/jev-control.json'
            config.parent.mkdir(parents=True, exist_ok=True)
            config.write_text('{"telemetry": {}}\n')
        return Namespace(**{**vars(self.args), **changes})

    def test_client_selection_writes_only_that_clients_files_and_hooks(self):
        project_install.install(self.with_args(client=('codex',), with_jev=True))
        self.assertTrue((self.project/'.agents/skills/dr-do/SKILL.md').is_file())
        self.assertTrue((self.project/'.codex/hooks.json').is_file())
        for name in ('.claude/commands/dr-do.md', '.cursor/skills/dr-do/SKILL.md',
                     '.claude/settings.local.json', '.cursor/hooks.json'):
            self.assertFalse((self.project/name).exists(), name)
        manifest = json.loads((self.project/'.datarim-runtime/installation.json').read_text())
        self.assertEqual(manifest['clients'], ['codex'])

    def test_an_update_without_the_option_keeps_the_recorded_clients(self):
        project_install.install(self.with_args(client=('claude', 'cursor')))
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.with_args(client=None))
        self.assertTrue((self.project/'.claude/commands/dr-do.md').is_file())
        self.assertTrue((self.project/'.cursor/skills/dr-do/SKILL.md').is_file())
        self.assertFalse((self.project/'.agents/skills/dr-do/SKILL.md').exists())

    def test_an_install_recorded_before_the_option_means_all_clients(self):
        project_install.install(self.args)
        manifest_path = self.project/'.datarim-runtime/installation.json'
        manifest = json.loads(manifest_path.read_text())
        del manifest['clients']
        manifest_path.write_text(json.dumps(manifest))
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.args)
        for name in ('.claude/commands/dr-do.md', '.agents/skills/dr-do/SKILL.md', '.cursor/skills/dr-do/SKILL.md'):
            self.assertTrue((self.project/name).is_file(), name)

    def test_removing_a_client_removes_its_files_and_only_its_hooks(self):
        cursor_hooks = self.project/'.cursor/hooks.json'
        cursor_hooks.parent.mkdir()
        cursor_hooks.write_text(json.dumps({'version': 1, 'hooks': {'beforeShellExecution': [
            {'command': 'foreign-guard'}]}}))
        project_install.install(self.with_args(with_jev=True))
        self.assertIn('jev_hook.py', (self.project/'.claude/settings.local.json').read_text())
        project_install.install(self.with_args(with_jev=True, client=('codex',)))
        # Created by the install and holding only Jev entries: removed.
        self.assertFalse((self.project/'.claude/settings.local.json').exists())
        self.assertFalse((self.project/'.claude/commands/dr-do.md').exists())
        self.assertFalse((self.project/'.cursor/skills/dr-do/SKILL.md').exists())
        # The project's own file: Jev's entries leave, the foreign one stays.
        kept = json.loads(cursor_hooks.read_text())
        self.assertEqual(kept['hooks']['beforeShellExecution'], [{'command': 'foreign-guard'}])
        self.assertNotIn('jev_hook.py', cursor_hooks.read_text())
        self.assertIn('jev_hook.py', (self.project/'.codex/hooks.json').read_text())
        project_install.uninstall(self.args)
        self.assertEqual(json.loads(cursor_hooks.read_text())['hooks']['beforeShellExecution'],
                         [{'command': 'foreign-guard'}])

    def test_a_file_created_where_a_retired_one_was_survives_uninstall(self):
        project_install.install(self.args)
        project_install.install(self.with_args(client=('codex',)))
        mine = self.project/'.claude/commands/dr-do.md'
        mine.parent.mkdir(parents=True, exist_ok=True)
        mine.write_text('# My own command\n')
        project_install.uninstall(self.args)
        self.assertEqual(mine.read_text(), '# My own command\n')

    # -- remembered choices ---------------------------------------------------
    # An update without --with-jev used to withdraw the project's Jev hooks and
    # its jev-config.json; one without --context withdrew nested repositories.

    def update(self, **changes):
        (self.source/'VERSION').write_text(f'update {changes}\n')
        base = {k: v for k, v in vars(self.args).items() if k not in ('with_jev', 'context')}
        project_install.install(Namespace(**{**base, **changes}))

    def manifest(self):
        return json.loads((self.project/'.datarim-runtime/installation.json').read_text())

    def test_an_update_without_the_flag_keeps_jev(self):
        project_install.install(self.with_args(with_jev=True))
        self.update()
        self.assertTrue(self.manifest()['with_jev'])
        self.assertTrue((self.project/'.datarim-runtime/jev-config.json').is_file())
        for name in project_install.HOOK_CONFIGS:
            self.assertIn('jev_hook.py', (self.project/name).read_text(), name)

    def test_without_jev_withdraws_the_hooks_and_keeps_the_key(self):
        project_install.install(self.with_args(with_jev=True))
        key = self.project/'config/credentials/jev/api-key'
        self.assertTrue(key.is_file())
        self.update(with_jev=False)
        self.assertFalse(self.manifest()['with_jev'])
        self.assertFalse((self.project/'.datarim-runtime/jev-config.json').exists())
        for name in project_install.HOOK_CONFIGS:
            self.assertFalse((self.project/name).exists(), name)
        self.assertTrue(key.is_file())
        self.update()
        self.assertFalse(self.manifest()['with_jev'], 'turning Jev off is remembered too')

    def test_without_jev_keeps_foreign_hooks_in_a_shared_file(self):
        hooks = self.project/'.cursor/hooks.json'
        hooks.parent.mkdir()
        hooks.write_text(json.dumps({'version': 1, 'hooks': {'beforeShellExecution': [{'command': 'foreign-guard'}]}}))
        project_install.install(self.with_args(with_jev=True))
        self.update(with_jev=False)
        self.assertEqual(json.loads(hooks.read_text())['hooks']['beforeShellExecution'], [{'command': 'foreign-guard'}])

    def test_contexts_are_remembered_until_withdrawn(self):
        nested = self.project/'child'
        (nested/'.git').mkdir(parents=True)
        project_install.install(self.with_args(context=['child']))
        self.update()
        self.assertEqual(self.manifest()['contexts'], ['child'])
        self.update(no_context=True)
        self.assertEqual(self.manifest()['contexts'], [])

    def test_host_jev_needs_jev_even_when_remembered(self):
        with self.assertRaisesRegex(ValueError, 'requires --with-jev'):
            project_install.remembered_choices(Namespace(with_jev=None, host_jev=True, context=None), {})
        self.assertEqual(project_install.remembered_choices(
            Namespace(with_jev=None, host_jev=None, context=None),
            {'with_jev': True, 'host_jev': True, 'contexts': ['a']}), (True, True, ['a']))
        self.assertEqual(project_install.remembered_choices(
            Namespace(with_jev=False, host_jev=None, context=None),
            {'with_jev': True, 'host_jev': True}), (False, False, []))

    def test_the_command_line_remembers_jev_through_update_sh(self):
        project_install.install(self.with_args(with_jev=True))
        with patch.object(sys, 'argv', ['project_install.py', '--project', str(self.project)]):
            (self.source/'VERSION').write_text('cli\n')
            self.assertEqual(project_install.main(), 0)
        self.assertTrue(self.manifest()['with_jev'])
        with patch.object(sys, 'argv', ['project_install.py', '--project', str(self.project), '--without-jev']):
            self.assertEqual(project_install.main(), 0)
        self.assertFalse(self.manifest()['with_jev'])

    # -- a fresh install needs an explicit Jev choice --------------------------

    def fresh(self, **changes):
        base = {k: v for k, v in vars(self.args).items() if k != 'with_jev'}
        return Namespace(**{**base, **changes})

    def test_a_fresh_install_without_a_choice_is_refused_before_any_write(self):
        with self.assertRaisesRegex(project_install.ChoiceRequired, 'Ask the user these questions'):
            project_install.install(self.fresh())
        self.assertEqual(sorted(p.name for p in self.project.iterdir()), ['.gitignore', 'AGENTS.md'])
        self.assertFalse((self.project/'.datarim-runtime').exists())
        self.assertFalse((self.project/'datarim').exists())

    def test_a_dry_run_without_a_choice_is_refused_and_prints_no_plan(self):
        """An agent that copied a quick line read the printed plan as leave to
        install; a dry run must not stand in for the user's answer."""
        import contextlib, io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            with self.assertRaises(project_install.ChoiceRequired):
                project_install.install(self.fresh(dry_run=True))
        self.assertEqual(out.getvalue(), '')
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_the_printed_questions_match_install_md(self):
        text = project_install.CHOICE_QUESTIONS
        for needle in ('STOP.', 'Ask the user these questions and wait for the answers.',
                       'Do not choose for them.', 'works WITHOUT any key', '"no key" is not a reason',
                       '--without-jev', '--with-jev', '--host-jev', '--client', '--claude-import',
                       'jev permissions full', '--init', '--expose-skills', 'release tag', 'main',
                       'Rerun: ./install.sh --project <path> <flags from the answers>'):
            self.assertIn(needle, text)

    def test_a_jev_answer_without_a_client_list_is_refused_too(self):
        for changes in ({'with_jev': False, 'client': None}, {'with_jev': True, 'client': None},
                        {'with_jev': False, 'client': None, 'dry_run': True}):
            with self.subTest(**changes), self.assertRaises(project_install.ChoiceRequired):
                project_install.install(self.with_args(**changes))
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_a_client_list_without_a_jev_answer_is_refused(self):
        with self.assertRaises(project_install.ChoiceRequired):
            project_install.install(self.fresh(client=('claude',)))

    def test_an_update_needs_neither_answer(self):
        project_install.install(self.with_args(client=('codex',)))
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.fresh(client=None))
        self.assertEqual(self.manifest()['clients'], ['codex'])

    def test_an_update_without_a_choice_keeps_the_recorded_one(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.fresh())
        self.assertFalse(self.manifest()['with_jev'])

    def test_the_refusal_exits_non_zero_on_the_command_line(self):
        run = subprocess.run([sys.executable, str(ROOT/'scripts/project_install.py'), '--project',
                              str(self.project)], capture_output=True, text=True, timeout=120)
        self.assertEqual(run.returncode, 2)
        self.assertEqual(run.stdout, '')
        self.assertTrue(run.stderr.startswith('STOP. Nothing was installed.'), run.stderr[:80])
        self.assertNotIn('datarim install:', run.stderr)
        for text in ('--client claude,codex,cursor', 'jev permissions full', '--expose-skills'):
            self.assertIn(text, run.stderr)
        run = subprocess.run([sys.executable, str(ROOT/'scripts/project_install.py'), '--project',
                              str(self.project), '--without-jev', '--dry-run'],
                             capture_output=True, text=True, timeout=120)
        self.assertEqual((run.returncode, run.stdout), (2, ''))

    def test_a_jev_install_says_where_the_key_goes(self):
        import contextlib, io
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            project_install.install(self.with_args(with_jev=True))
        self.assertIn(str(self.project/'config/credentials/jev/api-key'), err.getvalue())
        self.assertIn('paste the key on one line', err.getvalue())

    # -- leftover client directories -------------------------------------------

    def test_dropping_a_client_removes_its_directory_when_the_install_created_it(self):
        project_install.install(self.args)
        self.assertEqual(self.manifest()['created_dirs'], ['.agents', '.claude', '.cursor'])
        project_install.install(self.with_args(client=('codex',)))
        self.assertFalse((self.project/'.cursor').exists())
        self.assertFalse((self.project/'.claude').exists())
        self.assertTrue((self.project/'.agents').is_dir())
        self.assertEqual(self.manifest()['created_dirs'], ['.agents'])

    def test_a_directory_that_existed_before_the_install_is_kept_even_when_empty(self):
        (self.project/'.cursor').mkdir()
        project_install.install(self.args)
        self.assertNotIn('.cursor', self.manifest()['created_dirs'])
        project_install.install(self.with_args(client=('codex',)))
        self.assertTrue((self.project/'.cursor').is_dir())

    def test_a_created_directory_holding_other_files_is_kept(self):
        project_install.install(self.args)
        (self.project/'.cursor/rules.mdc').write_text('mine\n')
        project_install.install(self.with_args(client=('codex',)))
        self.assertEqual((self.project/'.cursor/rules.mdc').read_text(), 'mine\n')
        self.assertFalse((self.project/'.cursor/skills').exists())

    def test_uninstall_removes_the_empty_directories_it_created(self):
        (self.project/'.claude').mkdir()
        project_install.install(self.args)
        project_install.uninstall(self.args)
        for name in ('.agents', '.cursor'):
            self.assertFalse((self.project/name).exists(), name)
        self.assertTrue((self.project/'.claude').is_dir(), 'existed before the install')

    def test_an_install_recorded_without_created_dirs_removes_nothing(self):
        project_install.install(self.args)
        path = self.project/'.datarim-runtime/installation.json'
        data = json.loads(path.read_text())
        del data['created_dirs']
        path.write_text(json.dumps(data))
        project_install.install(self.with_args(client=('codex',)))
        self.assertTrue((self.project/'.cursor').is_dir())

    def test_client_option_parsing(self):
        self.assertEqual(project_install.parse_clients(['codex,claude', 'codex']), ('claude', 'codex'))
        self.assertEqual(project_install.parse_clients(['all']), ('claude', 'codex', 'cursor'))
        self.assertEqual(project_install.parse_clients(None), ())
        with self.assertRaises(ValueError):
            project_install.parse_clients(['vim'])
        run = subprocess.run([sys.executable, str(ROOT/'scripts/project_install.py'), '--project',
                              str(self.project), '--client', 'vim', '--dry-run'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn('Unknown client', run.stderr)

    # -- Claude Code and AGENTS.md --------------------------------------------
    # Claude Code loads CLAUDE.md, not AGENTS.md. --claude-import links the
    # one to the other; a symlink rather than an `@AGENTS.md` import line,
    # because the import was observed to be ignored in sessions started in a
    # subdirectory, while the symlink was read there as well.

    def test_claude_import_links_keeps_and_removes_the_link(self):
        project_install.install(self.with_args(claude_import=True))
        link = self.project/'CLAUDE.md'
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), 'AGENTS.md')
        self.assertEqual(link.read_text(), '# Original project rules\n')
        # Sticky: an update without the flag keeps it.
        (self.source/'VERSION').write_text('next\n')
        project_install.install(self.args)
        self.assertTrue(link.is_symlink())
        project_install.uninstall(self.args)
        self.assertFalse(link.exists() or link.is_symlink())
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')

    def test_no_claude_import_removes_only_the_link_this_install_made(self):
        project_install.install(self.with_args(claude_import=True))
        project_install.install(self.with_args(claude_import=False))
        self.assertFalse((self.project/'CLAUDE.md').is_symlink())
        manifest = json.loads((self.project/'.datarim-runtime/installation.json').read_text())
        self.assertFalse(manifest['claude_import'])

    def test_claude_import_never_touches_an_existing_claude_md(self):
        (self.project/'CLAUDE.md').write_text('Always answer in French.\n')
        project_install.install(self.with_args(claude_import=True))
        self.assertEqual((self.project/'CLAUDE.md').read_text(), 'Always answer in French.\n')
        project_install.uninstall(self.args)
        self.assertEqual((self.project/'CLAUDE.md').read_text(), 'Always answer in French.\n')

    def test_a_link_the_operator_made_is_not_removed_on_uninstall(self):
        (self.project/'CLAUDE.md').symlink_to('AGENTS.md')
        project_install.install(self.with_args(claude_import=True))
        project_install.uninstall(self.args)
        self.assertTrue((self.project/'CLAUDE.md').is_symlink())

    def test_claude_import_needs_an_agents_md_and_the_claude_client(self):
        (self.project/'AGENTS.md').unlink()
        with self.assertRaisesRegex(ValueError, 'no AGENTS.md'):
            project_install.install(self.with_args(claude_import=True))
        (self.project/'AGENTS.md').write_text('# Rules\n')
        with self.assertRaisesRegex(ValueError, 'claude client'):
            project_install.install(self.with_args(claude_import=True, client=('codex',)))
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_without_the_flag_no_claude_md_is_created(self):
        project_install.install(self.args)
        self.assertFalse((self.project/'CLAUDE.md').exists() or (self.project/'CLAUDE.md').is_symlink())

    def test_the_link_is_hidden_from_git_status(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        subprocess.run(['git', '-C', str(self.project), 'add', '-A'], check=True)
        subprocess.run(['git', '-C', str(self.project), '-c', 'user.email=t@t', '-c', 'user.name=t',
                        'commit', '-qm', 'init'], check=True)
        project_install.install(self.with_args(claude_import=True))
        status = subprocess.run(['git', '-C', str(self.project), 'status', '--porcelain'],
                                capture_output=True, text=True, check=True).stdout
        self.assertEqual(status, '')

    def test_concurrent_change_during_copy_is_preserved(self):
        target = self.project/'.claude/commands/dr-do.md'
        original_copy = project_install.shutil.copytree
        touched = False
        def concurrent_copy(*args, **kwargs):
            nonlocal touched
            result = original_copy(*args, **kwargs)
            if not touched:
                touched = True
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('# Concurrent foreign command\n')
            return result
        with patch.object(project_install.shutil, 'copytree', side_effect=concurrent_copy):
            with self.assertRaisesRegex(ValueError, 'Concurrent modification'):
                project_install.install(self.args)
        self.assertEqual(target.read_text(), '# Concurrent foreign command\n')
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_persistent_file_restore_failure_still_restores_runtime(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('new version\n')
        name = '.claude/commands/dr-do.md'
        original_command = (self.project/name).read_bytes()
        # Force a changed proposal, so losing the prior bytes is observable.
        original_preamble = project_install.with_preamble
        real_write = project_install.atomic_bytes
        writes = 0
        def failing_write(target, data):
            nonlocal writes
            writes += 1
            if writes >= 2:
                raise OSError('injected persistent write failure')
            return real_write(target, data)
        with patch.object(project_install, 'atomic_bytes', side_effect=failing_write), patch.object(
                project_install, 'with_preamble', side_effect=lambda data, runtime: original_preamble(data, runtime)+b'Changed proposal\n'):
            with self.assertRaisesRegex(OSError, 'injected'):
                project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'test\n')
        bundles = list(self.project.glob('.datarim-recovery-*'))
        self.assertEqual(len(bundles), 1)
        self.assertEqual(bundles[0].stat().st_mode & 0o077, 0)
        saved = json.loads((bundles[0]/'rollback-files.json').read_text())
        self.assertEqual(saved[name].encode(), original_command)

    def test_rollback_preserves_foreign_edit_after_publication(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('new version\n')
        real_write = project_install.atomic_bytes
        writes = 0
        def racing_write(target, data):
            nonlocal writes
            writes += 1
            if writes == 2:
                (self.project/'AGENTS.md').write_text('# Foreign late edit\n')
                raise OSError('injected next-file failure')
            return real_write(target, data)
        with patch.object(project_install, 'atomic_bytes', side_effect=racing_write):
            with self.assertRaises(OSError):
                project_install.install(self.args)
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Foreign late edit\n')
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'test\n')

    def test_foreign_skill_conflict_has_no_partial_install(self):
        foreign = self.project/'.cursor/skills/dr-do/SKILL.md'
        foreign.parent.mkdir(parents=True)
        foreign.write_text('Foreign instructions')
        with self.assertRaisesRegex(ValueError, 'Unmanaged'):
            project_install.install(self.args)
        self.assertEqual(foreign.read_text(), 'Foreign instructions')
        self.assertFalse((self.project/'.datarim-runtime').exists())
        self.assertFalse((self.project/'.claude/commands/dr-do.md').exists())
        self.assertEqual((self.project/'AGENTS.md').read_text(), '# Original project rules\n')

    def test_nested_context_cannot_escape(self):
        self.args.context = ['../outside']
        with self.assertRaisesRegex(ValueError, 'relative subdirectories'):
            project_install.install(self.args)
        self.assertFalse((self.project/'.datarim-runtime').exists())

    def test_update_rejects_state_symlink_without_replacing_runtime(self):
        project_install.install(self.args)
        state = self.project/'.datarim-runtime/state'
        state.mkdir()
        (state/'escape').symlink_to(self.source)
        (self.source/'VERSION').write_text('new version\n')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'test\n')

    def test_repeated_updates_retire_owned_discovery_and_preserve_backups(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('second\n')
        project_install.install(self.args)
        (self.source/'commands/dr-do.md').unlink()
        (self.source/'VERSION').write_text('third\n')
        project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'third\n')
        self.assertEqual((self.project/'.datarim-runtime-previous/VERSION').read_text(), 'second\n')
        self.assertEqual(len(list((self.project/'.datarim-runtime-backups').iterdir())), 1)
        self.assertFalse((self.project/'.agents/skills/dr-do/SKILL.md').exists())
        self.assertFalse((self.project/'.claude/commands/dr-do.md').exists())

    def test_failed_preparation_does_not_restore_an_older_backup_over_current(self):
        project_install.install(self.args)
        (self.source/'VERSION').write_text('second\n')
        project_install.install(self.args)
        state = self.project/'.datarim-runtime/state'; state.mkdir()
        (state/'bad').symlink_to(self.source)
        (self.source/'VERSION').write_text('third\n')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            project_install.install(self.args)
        self.assertEqual((self.project/'.datarim-runtime/VERSION').read_text(), 'second\n')
        self.assertEqual((self.project/'.datarim-runtime-previous/VERSION').read_text(), 'test\n')

    def test_concurrent_installation_is_refused(self):
        with project_install.project_lock(self.project):
            with self.assertRaisesRegex(ValueError, 'Another installation'):
                project_install.install(self.args)
        self.assertFalse((self.project/'.datarim-runtime').exists())


class IgnoredSourceTests(unittest.TestCase):
    """The installer ships what the repository holds, not what the disk holds."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.src = Path(self.tmp.name).resolve()/'src'
        (self.src/'skills/real').mkdir(parents=True)
        (self.src/'skills/real/SKILL.md').write_text('---\nname: real\n---\n')
        (self.src/'skills/.system/imagegen').mkdir(parents=True)
        (self.src/'skills/.system/imagegen/SKILL.md').write_text('---\nname: imagegen\n---\n')
        (self.src/'.gitignore').write_text('skills/.system/\n')
        subprocess.run(['git', 'init', '-q', str(self.src)], check=True)

    def test_an_ignored_directory_is_reported_and_its_files_are_skipped(self):
        ignored = project_install.git_ignored(self.src)
        self.assertIn('skills/.system', ignored)
        self.assertTrue(project_install.is_ignored(
            self.src/'skills/.system/imagegen/SKILL.md', ignored, self.src))

    def test_a_tracked_sibling_with_a_shared_prefix_is_not_skipped(self):
        """`skills/.system` must not swallow `skills/.systematic`."""
        (self.src/'skills/.systematic').mkdir()
        (self.src/'skills/.systematic/SKILL.md').write_text('---\nname: s\n---\n')
        ignored = project_install.git_ignored(self.src)
        self.assertFalse(project_install.is_ignored(
            self.src/'skills/.systematic/SKILL.md', ignored, self.src))
        self.assertFalse(project_install.is_ignored(
            self.src/'skills/real/SKILL.md', ignored, self.src))

    def test_a_source_that_is_not_a_git_checkout_ignores_nothing(self):
        plain = Path(self.tmp.name).resolve()/'plain'
        plain.mkdir()
        self.assertEqual(project_install.git_ignored(plain), frozenset())

    def test_the_installed_file_list_carries_no_ignored_skill(self):
        """End to end against this repository: a dry run lists no `.system` skill
        whether or not this checkout happens to hold one."""
        target = Path(self.tmp.name).resolve()/'project'
        target.mkdir()
        subprocess.run(['git', 'init', '-q', str(target)], check=True)
        result = subprocess.run([sys.executable, str(ROOT/'scripts/project_install.py'), '--project',
                                 str(target), '--init', '--without-jev', '--client', 'all', '--dry-run'], capture_output=True,
                                text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        files = json.loads(result.stdout.strip().splitlines()[-1])["files"]
        # Installed skill directories are named after the source path with '/'
        # turned into '-', so `skills/.system/imagegen` would land as `.system-imagegen`.
        leaked = [f for f in files if '/.system' in f]
        self.assertEqual(leaked, [])


class JevTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(ROOT/'plugins/dr-jev-control/scripts'))

    def test_curl_keeps_key_out_of_argv(self):
        import jev_client
        response = subprocess.CompletedProcess([], 0, b'{"answers":{}}\n__DRJEV_HTTP__:200\n', b'')
        key = 'synthetic-credential-for-test'
        with patch.object(jev_client.subprocess, 'run', return_value=response) as run:
            jev_client._curl('https://example.invalid/api', key, b'{"state":"test"}', 1, 1)
        args = run.call_args
        self.assertNotIn(key, ' '.join(args.args[0]))
        self.assertIn(key.encode(), args.kwargs['input'])

    def test_cursor_refuses_missing_session_continuation(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        self.assertFalse(runtime.send_turn('continue'))

    def test_cursor_session_change_is_an_error(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        runtime._translate({'type': 'system', 'session_id': 'original'})
        events = runtime._translate({'type': 'system', 'session_id': 'different'})
        self.assertEqual(events[0]['kind'], 'error')
        self.assertEqual(runtime.thread_id, 'original')

    def test_cursor_does_not_claim_unmapped_tier_applied(self):
        from runtimes import CursorRuntime
        runtime = CursorRuntime('sonnet')
        with patch.dict(os.environ, {}, clear=True):
            ok, reason = runtime.apply_tier('opus')
        self.assertFalse(ok)
        self.assertEqual(reason['reason'], 'cursor_model_mapping_missing')


if __name__ == '__main__':
    unittest.main()
