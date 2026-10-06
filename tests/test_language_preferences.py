"""Behavioral preference resolution, parser and write-boundary controls."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'skills/human-outcome-reporting/scripts/language.py'
SPEC = importlib.util.spec_from_file_location('datarim_language', SCRIPT)
language = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(language)


class LanguagePreferencesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name).resolve()
        self.project = self.home / 'project'
        self.project.mkdir()
        (self.project / '.git').mkdir()
        self.env = {'HOME': str(self.home)}

    def tearDown(self):
        self.temp.cleanup()

    def resolve(self, **kw):
        return language.resolve_preferences(project=self.project, environ=self.env, **kw)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def user(self, text):
        return self.write(self.home / '.config/datarim/config.yaml', text)

    def shared(self, text):
        return self.write(self.project / 'datarim/config.yaml', text)

    def test_fresh_standalone_defaults_without_creating_framework_or_config(self):
        before = sorted(str(p) for p in self.home.rglob('*'))
        got = self.resolve()
        self.assertEqual((got['replies'], got['artifacts']), ('en', 'en'))
        self.assertEqual(got['sources'], {'replies': 'default', 'artifacts': 'default'})
        self.assertEqual(sorted(str(p) for p in self.home.rglob('*')), before)

    def test_personal_ru_en_and_changes_without_reinstallation(self):
        p = self.user('language:\n  replies: ru\n  artifacts: en\n')
        self.assertEqual(self.resolve()['replies'], 'ru')
        p.write_text('language:\n  replies: fr-CA\n  artifacts: ja\n')
        got = self.resolve()
        self.assertEqual((got['replies'], got['artifacts']), ('fr-CA', 'ja'))

    def test_reply_personal_wins_project_document_project_wins_personal(self):
        self.user('language:\n  replies: fr\n  artifacts: ja\n')
        self.shared('language:\n  replies: de\n  artifacts: en\n')
        got = self.resolve()
        self.assertEqual((got['replies'], got['artifacts']), ('fr', 'en'))
        self.assertEqual(got['sources'], {'replies': 'user', 'artifacts': 'project'})

    def test_private_project_override_is_independent_and_explicit_request_highest(self):
        self.user('language:\n  replies: ru\n  artifacts: en\n')
        self.write(self.project / 'datarim/config.local.yaml', 'language:\n  replies: ar\n')
        got = self.resolve(artifacts='zh-Hant')
        self.assertEqual((got['replies'], got['artifacts']), ('ar', 'zh-Hant'))
        self.assertEqual(got['direction'], {'replies': 'rtl', 'artifacts': 'ltr'})
        self.assertEqual(self.resolve(replies='es')['sources']['replies'], 'explicit')

    def test_delegate_environment_not_machine_locale(self):
        self.env.update({'LANG': 'ru_RU.UTF-8', 'LC_ALL': 'ar', 'DATARIM_REPLY_LANG': 'pt-br', 'DATARIM_ARTIFACT_LANG': 'en'})
        self.assertEqual(self.resolve()['replies'], 'pt-BR')
        self.env.pop('DATARIM_REPLY_LANG')
        self.assertEqual(self.resolve()['replies'], 'en')

    def test_explicit_language_override_changes_only_requested_scope(self):
        personal = self.user('language:\n  replies: fr\n  artifacts: de\n')
        before = personal.read_bytes()
        document = self.resolve(artifacts='ru')
        self.assertEqual((document['replies'], document['artifacts']), ('fr', 'ru'))
        self.assertEqual(document['sources'], {'replies': 'user', 'artifacts': 'explicit'})
        reply = self.resolve(replies='ar')
        self.assertEqual((reply['replies'], reply['artifacts']), ('ar', 'de'))
        self.assertEqual(reply['sources'], {'replies': 'explicit', 'artifacts': 'user'})
        for preferences in (document, reply):
            context = language.context(preferences)
            self.assertIn('ALL user-visible prose outside reusable artifacts MUST', context)
            self.assertIn('first visible sentence', context)
            self.assertIn('narration before and after tool calls', context)
            self.assertIn('incoming prompt language does not select either preference', context)
            self.assertIn('explicit document-language request changes only the requested artifact', context)
            self.assertIn('explicit reply-language request changes only reply prose', context)
            self.assertIn('override of one scope never changes the other', context)
        self.assertEqual(personal.read_bytes(), before)

    def test_xdg_location_and_nested_project_discovery(self):
        xdg = self.home / 'preferences'
        self.env['XDG_CONFIG_HOME'] = str(xdg)
        self.write(xdg / 'datarim/config.yaml', 'language:\n  replies: ko\n')
        nested = self.project / 'src/component'
        nested.mkdir(parents=True)
        got = language.resolve_preferences(project=nested, environ=self.env)
        self.assertEqual(got['replies'], 'ko')
        self.assertFalse((nested / 'datarim').exists())

    def local_only_child(self, text='language:\n  replies: fr\n  artifacts: de\n'):
        child = self.project / 'standalone'
        child.mkdir()
        local = self.write(child / 'datarim/config.local.yaml', text)
        return child, local

    def test_local_only_child_is_anchor_below_framework_ancestor(self):
        (self.project / '.git').rmdir()
        (self.project / '.datarim-runtime').mkdir()
        self.shared('language:\n  replies: en\n  artifacts: en\n')
        child, local = self.local_only_child()
        nested = child / 'src/component'
        nested.mkdir(parents=True)
        before = local.read_bytes()
        for start in (child, nested):
            with self.subTest(start=start):
                got = language.resolve_preferences(project=start, environ=self.env)
                self.assertEqual(language.project_root(start), child)
                self.assertEqual((got['replies'], got['artifacts']), ('fr', 'de'))
                self.assertEqual(got['sources'], {'replies': 'project_local', 'artifacts': 'project_local'})
        for cwd, project_args in ((nested, []), (self.project, ['--project', str(child)])):
            result = subprocess.run([sys.executable, str(SCRIPT), 'resolve', *project_args,
                                     '--user-config', str(self.home / 'absent.yaml')],
                                    cwd=cwd, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            got = json.loads(result.stdout)
            self.assertEqual((got['replies'], got['artifacts']), ('fr', 'de'))
        self.assertEqual(local.read_bytes(), before)

    def test_cli_local_only_child_configure_preserves_ancestor_configuration(self):
        ancestor = self.write(self.project / 'datarim/config.local.yaml', 'language:\n  replies: en\n  artifacts: ja\n')
        before = ancestor.read_bytes()
        child, local = self.local_only_child()
        result = subprocess.run([sys.executable, str(SCRIPT), 'configure', '--scope',
                                 'local', '--project', str(child), '--replies', 'ar'],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ancestor.read_bytes(), before)
        self.assertEqual(language.parse_config(local.read_text()), {'replies': 'ar', 'artifacts': 'de'})
        self.assertFalse((child / 'datarim/config.yaml').exists())

    def test_local_only_anchor_keeps_explicit_shared_config_and_precedence(self):
        self.user('language:\n  replies: ru\n  artifacts: en\n')
        child, _ = self.local_only_child('language:\n  replies: fr\n')
        explicit = self.write(self.home / 'selected.yaml', 'language:\n  replies: es\n  artifacts: ja\n')
        got = language.resolve_preferences(project=child, project_config=explicit, environ=self.env)
        self.assertEqual((got['replies'], got['artifacts']), ('fr', 'ja'))
        self.assertEqual(got['sources'], {'replies': 'project_local', 'artifacts': 'project'})
        got = language.resolve_preferences(project=child, project_config=explicit,
                                           replies='ko', artifacts='ar', environ=self.env)
        self.assertEqual((got['replies'], got['artifacts']), ('ko', 'ar'))

    def test_malformed_local_only_child_does_not_fall_back_to_ancestor(self):
        self.shared('language:\n  replies: en\n  artifacts: en\n')
        child, _ = self.local_only_child('language:\n  replies: not_a_tag\n')
        with self.assertRaises(language.PreferenceError):
            language.resolve_preferences(project=child, environ=self.env)

    def test_invalid_local_only_marker_refuses_ancestor_fallback_and_write(self):
        ancestor = self.write(self.project / 'datarim/config.local.yaml', 'language:\n  replies: en\n')
        before = ancestor.read_bytes()
        for kind in ('broken_symlink', 'directory', 'fifo'):
            with self.subTest(kind=kind):
                child = self.project / kind
                local = child / 'datarim/config.local.yaml'
                local.parent.mkdir(parents=True)
                if kind == 'broken_symlink':
                    local.symlink_to(self.home / 'missing.yaml')
                elif kind == 'directory':
                    local.mkdir()
                else:
                    language.os.mkfifo(local)
                with self.assertRaises(language.PreferenceError):
                    language.resolve_preferences(project=child, environ=self.env)
                result = subprocess.run([sys.executable, str(SCRIPT), 'configure', '--scope',
                                         'local', '--project', str(child), '--replies', 'ar'],
                                        capture_output=True, text=True, timeout=3, check=False)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(ancestor.read_bytes(), before)

    def test_local_only_child_symlink_configure_refuses_without_ancestor_write(self):
        ancestor = self.write(self.project / 'datarim/config.local.yaml', 'language:\n  replies: en\n')
        protected = self.write(self.home / 'protected.yaml', 'language:\n  replies: fr\n')
        child, local = self.local_only_child()
        local.unlink()
        local.symlink_to(protected)
        before = (ancestor.read_bytes(), protected.read_bytes())
        result = subprocess.run([sys.executable, str(SCRIPT), 'configure', '--scope',
                                 'local', '--project', str(child), '--replies', 'ar'],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual((ancestor.read_bytes(), protected.read_bytes()), before)
        self.assertTrue(local.is_symlink())

    def test_nested_directory_without_local_anchor_keeps_existing_project_root(self):
        self.shared('language:\n  artifacts: ja\n')
        nested = self.project / 'src/component'
        nested.mkdir(parents=True)
        self.assertEqual(language.project_root(nested), self.project)
        self.assertEqual(language.resolve_preferences(project=nested, environ=self.env)['artifacts'], 'ja')

    def test_local_only_anchor_reads_its_legacy_artifact_directive(self):
        child, _ = self.local_only_child('language:\n  replies: fr\n')
        self.write(child / 'AGENTS.md', 'Artifact language: de\n')
        got = language.resolve_preferences(project=child, environ=self.env)
        self.assertEqual((got['replies'], got['artifacts']), ('fr', 'de'))
        self.assertEqual(got['sources']['artifacts'], 'legacy_instruction')

    def test_legacy_artifact_instruction_and_explicit_conflict(self):
        self.write(self.project / 'AGENTS.md', '# Project\nArtifact language: de\n')
        self.assertEqual(self.resolve()['artifacts'], 'de')
        self.assertEqual(self.resolve()['sources']['artifacts'], 'legacy_instruction')
        self.shared('language:\n  artifacts: en\n')
        with self.assertRaisesRegex(language.PreferenceError, 'conflicts'):
            self.resolve()

    def test_legacy_fenced_configuration_snippet_preserves_explicit_override(self):
        self.write(self.project/'AGENTS.md', '# Project\n```\nArtifact language: ja\n```\n')
        self.assertEqual(self.resolve()['artifacts'], 'ja')

    def test_deep_json_is_bounded_without_recursion_traceback(self):
        text = '{"unrelated":' + '[' * 1100 + '0' + ']' * 1100 + '}'
        with self.assertRaisesRegex(language.PreferenceError, 'nesting'):
            language.parse_config(text)
        self.assertEqual(language.parse_config('{"unrelated":"' + '['*100 + '","language":{"replies":"fr"}}')['replies'], 'fr')

    def test_config_growth_during_read_is_bounded_and_nonregular_file_refused(self):
        config = self.user('language:\n  replies: fr\n')
        original = language.os.fstat
        def grow(fd):
            info = original(fd)
            config.write_bytes(b'x' * (language.MAX_CONFIG_BYTES * 2))
            return info
        with patch.object(language.os, 'fstat', side_effect=grow), self.assertRaisesRegex(language.PreferenceError, 'exceeds'):
            language._read(config)
        fifo = self.home/'fifo'
        language.os.mkfifo(fifo)
        with self.assertRaisesRegex(language.PreferenceError, 'regular file'):
            language._read(fifo)

    def test_malformed_language_mapping_and_legacy_value_are_not_silent_defaults(self):
        for text in ['language\n  replies: fr\n', '\tlanguage:\n  replies: fr\n',
                     '[{"language":{"replies":"fr"}}]']:
            with self.subTest(text=text), self.assertRaises(language.PreferenceError):
                language.parse_config(text)
        self.write(self.project/'AGENTS.md', 'Artifact language: not_a_tag\n')
        with self.assertRaises(language.PreferenceError):
            self.resolve()

    def test_parent_swap_cannot_redirect_atomic_write_to_external_configuration(self):
        parent = self.home/'owned'; parent.mkdir()
        target = parent/'config.yaml'; target.write_text('language:\n  replies: fr\n')
        held = self.home/'renamed-owned'
        external = self.home/'external'; external.mkdir()
        protected = external/'config.yaml'; protected.write_text('Protected external bytes\n')
        replace = language.os.replace
        def swap(source, destination, **kwargs):
            parent.rename(held)
            parent.symlink_to(external, target_is_directory=True)
            if not kwargs:
                # Reproduces the old vulnerable absolute-path replacement.
                (external/Path(source).name).write_bytes((held/Path(source).name).read_bytes())
            return replace(source, destination, **kwargs)
        with patch.object(language.os, 'replace', side_effect=swap), self.assertRaises(language.PreferenceError):
            language.configure(target, artifacts='en')
        self.assertEqual(protected.read_text(), 'Protected external bytes\n')

    def test_destination_swap_cannot_read_or_copy_protected_bytes(self):
        config = self.shared('language:\n  replies: fr\n')
        protected = self.home/'private'; protected.write_text('secret_payload: SYNTHETIC_PRIVATE_VALUE\nlanguage:\n  replies: fr\n')
        actual = language._read_at
        def swap(directory, name):
            config.unlink(); config.symlink_to(protected)
            return actual(directory, name)
        with patch.object(language, '_read_at', side_effect=swap), self.assertRaises(OSError):
            language.configure(config, artifacts='en')
        self.assertEqual(protected.read_text(), 'secret_payload: SYNTHETIC_PRIVATE_VALUE\nlanguage:\n  replies: fr\n')

    def test_arbitrary_tags_scripts_regions_and_private_use_without_language_whitelist(self):
        for tag in ['bn', 'sw', 'is', 'sr-Latn', 'zh-Hant-TW', 'ar-EG', 'x-team']:
            self.assertEqual(self.resolve(replies=tag)['replies'], tag)
        self.assertEqual(language.text_direction('az-Arab'), 'rtl')
        self.assertEqual(language.text_direction('ku-Latn'), 'ltr')

    def test_injection_duplicate_unknown_and_nested_language_fields_refused(self):
        for text in [
            'language:\n  replies: en; touch /tmp/injected\n',
            'language:\n  replies: !!python/object:danger\n',
            'language:\n  replies: en\n  replies: ru\n',
            'language:\n  replies: en\nlanguage:\n  artifacts: ru\n',
            'language:\n  country: XX\n',
            'language:\n  replies:\n    nested: en\n',
            '{"language":{"replies":"en","replies":"ru"}}',
        ]:
            with self.subTest(text=text), self.assertRaises((ValueError, language.PreferenceError)):
                language.parse_config(text)
        self.assertEqual(language.parse_config('peer_review:\n  provider: sonnet\nlanguage:\n  replies: "fr-CA" # personal\n'), {'replies': 'fr-CA'})

    def test_configure_preserves_unrelated_owner_and_other_language(self):
        p = self.shared('# Project settings\npeer_review:\n  provider: sonnet\nlanguage:\n  replies: ru\nother:\n  keep: true\n')
        language.configure(p, artifacts='en')
        self.assertIn('peer_review:\n  provider: sonnet\n', p.read_text())
        self.assertIn('other:\n  keep: true\n', p.read_text())
        self.assertEqual(language.parse_config(p.read_text()), {'replies': 'ru', 'artifacts': 'en'})
        before = p.read_bytes()
        with self.assertRaises(language.PreferenceError):
            language.configure(p, replies='$(bad)')
        self.assertEqual(p.read_bytes(), before)

    def test_language_fields_are_siblings_and_unrelated_nested_language_is_preserved(self):
        for text in ['language:\n  replies: fr\n    artifacts: ja\n',
                     'language:\n    replies: fr\n  artifacts: ja\n']:
            with self.subTest(text=text), self.assertRaises(language.PreferenceError):
                language.parse_config(text)
        p = self.shared('unrelated:\n  language: en\nlanguage:\n  replies: fr\n')
        language.configure(p, artifacts='ja')
        self.assertIn('unrelated:\n  language: en\n', p.read_text())
        self.assertEqual(language.parse_config(p.read_text()), {'replies': 'fr', 'artifacts': 'ja'})

    def test_configure_refuses_fifo_without_waiting_or_mutating_it(self):
        p = self.home/'config.yaml'
        language.os.mkfifo(p)
        result = subprocess.run([sys.executable, str(SCRIPT), 'configure', '--user-config',
                                 str(p), '--replies', 'fr'], capture_output=True,
                                text=True, timeout=3, check=False)
        self.assertEqual(2, result.returncode, result.stderr)
        self.assertIn('regular file', result.stderr)
        self.assertTrue(language.stat.S_ISFIFO(p.stat().st_mode))

    def test_json_configuration_preserved_and_new_file_private(self):
        p = self.user('{"peer_review":{"provider":"sonnet"},"language":{"artifacts":"en"}}')
        language.configure(p, replies='fr')
        self.assertEqual(json.loads(p.read_text())['peer_review']['provider'], 'sonnet')
        new = self.home / 'new/config.yaml'
        language.configure(new, replies='ja', artifacts='en')
        self.assertEqual(new.stat().st_mode & 0o777, 0o600)

    def test_symlink_destination_or_parent_cannot_overwrite_external_file(self):
        target = self.home / 'protected'; target.write_text('Unrelated\n')
        link = self.home / 'config.yaml'; link.symlink_to(target)
        with self.assertRaises(language.PreferenceError):
            language.configure(link, replies='en')
        external = self.home / 'external'; external.mkdir()
        parent = self.home / 'link'; parent.symlink_to(external, target_is_directory=True)
        with self.assertRaises(language.PreferenceError):
            language.configure(parent / 'config.yaml', replies='en')
        self.assertEqual(target.read_text(), 'Unrelated\n')
        self.assertEqual(list(external.iterdir()), [])

    def test_large_config_and_invalid_xdg_refused_without_fallback(self):
        self.user('x' * (language.MAX_CONFIG_BYTES + 1))
        with self.assertRaises(language.PreferenceError):
            self.resolve()
        self.env['XDG_CONFIG_HOME'] = 'relative'
        with self.assertRaises(language.PreferenceError):
            self.resolve()

    def test_cli_scope_local_and_machine_protocol(self):
        out = subprocess.run([sys.executable, str(SCRIPT), 'configure', '--scope', 'local', '--project', str(self.project), '--replies', 'ar', '--artifacts', 'en'], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(out.stdout)['language'], {'replies': 'ar', 'artifacts': 'en'})
        configured = (self.project / 'datarim/config.local.yaml').read_bytes()
        out = subprocess.run([sys.executable, str(SCRIPT), 'resolve', '--project', str(self.project), '--user-config', str(self.home/'absent'), '--format', 'context'], capture_output=True, text=True, check=True)
        self.assertIn('Resolved reply language: ar', out.stdout)
        self.assertIn('resolved artifact language: en', out.stdout)
        self.assertIn('authored inside replies use artifact language', out.stdout)
        self.assertIn('do not add an unrequested translated example', out.stdout)
        self.assertIn('Human explanation outside the artifact uses reply language', out.stdout)
        self.assertIn('including bilingual or translation requests', out.stdout)
        self.assertIn('Preserve verbatim input, code and machine identifiers', out.stdout)
        self.assertEqual((self.project / 'datarim/config.local.yaml').read_bytes(), configured)


if __name__ == '__main__':
    unittest.main()
