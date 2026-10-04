"""Multilingual runtime presentation with legacy machine-contract compatibility."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK_SPEC = importlib.util.spec_from_file_location(
    'language_stop_hook', ROOT / 'dev-tools/hooks/dr-output-stop.py')
HOOK = importlib.util.module_from_spec(HOOK_SPEC)
HOOK_SPEC.loader.exec_module(HOOK)


class LanguageFrameworkTests(unittest.TestCase):
    def summary(self, language='fr'):
        labels = {'fr': ['Rapport', 'Travail effectué', 'Résultats confirmés',
                         'Points ouverts', 'Prochaine étape'],
                  'ar': ['التقرير', 'ما تم إنجازه', 'ما نجح', 'ما بقي', 'الخطوة التالية']}
        words = labels[language]
        return (f'## {words[0]} <!-- datarim:operator-summary -->\n\n'
                '**QA-0001 · Example**\n\n' + '\n\n'.join(
                    f'**{label}** <!-- datarim:summary:{key} -->\nEvidence.'
                    for label, key in zip(words[1:], HOOK.HS_SEMANTIC_IDS)))

    def test_localized_summary_and_legacy_are_accepted(self):
        for language in ('fr', 'ar'):
            with self.subTest(language=language):
                section = HOOK.extract_operator_summary_section(self.summary(language))
                self.assertIsNotNone(section)
                self.assertEqual([], HOOK.validate_human_summary(section))
        legacy = '**QA-0001 · Example**\n\n' + '\n\n'.join(HOOK.HS_SUBHEADINGS)
        self.assertEqual([], HOOK.validate_human_summary(legacy))

    def test_localized_summary_keeps_structural_rejections(self):
        section = HOOK.extract_operator_summary_section(self.summary())
        self.assertIn('duplicate_subheading', HOOK.validate_human_summary(
            section + '\n**Encore** <!-- datarim:summary:worked -->'))
        self.assertIn('fifth_subheading', HOOK.validate_human_summary(
            section + '\n**Autre section**'))
        self.assertIn('missing_subheading_2', HOOK.validate_human_summary(
            section.replace('datarim:summary:worked', 'datarim:summary:unrecognized')))
        reordered = section.replace('summary:done', 'summary:temporary').replace(
            'summary:worked', 'summary:done').replace('summary:temporary', 'summary:worked')
        self.assertIn('wrong_order', HOOK.validate_human_summary(reordered))

    def test_summary_marker_in_code_is_not_a_report(self):
        self.assertIsNone(HOOK.extract_operator_summary_section('```markdown\n' +
                                                               self.summary() + '\n```'))

    def expectation(self, heading='Attentes <!-- datarim:expectations -->'):
        return f'''---
task_id: QA-0001
artifact: expectations
schema_version: 4
captured_at: 2026-10-04
captured_by: /dr-plan
status: canonical
agent: planner
parent_init_task: QA-0001-init-task.md
---
## {heading}

- **1. Le résultat demandé est vérifié.**
  - wish_id: resultat-verifie
  - wish: Un résultat vérifiable.
  - success_criterion: HTTP https://example.invalid returns the expected page.
  - linked_ac: V-AC-1
  - customer_derived: false
  - evidence_type: empirical
  - #### status_history
    - 2026-10-04T12:00:00Z / 12:00 · /dr-plan · pending → met · reason: observation retained
  - #### current_status
    - met
'''

    def check_expectation(self, body, verify=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            task = root / 'datarim/tasks/QA-0001-expectations.md'
            task.parent.mkdir(parents=True)
            task.write_text(body)
            return subprocess.run(['bash', str(ROOT / 'dev-tools/check-expectations-checklist.sh'),
                                   '--root', str(root), '--verify' if verify else '--task', 'QA-0001'],
                                  capture_output=True, text=True, check=False)

    def test_translated_expectation_markers_and_stable_fields(self):
        for heading in ('Expectations', 'Attentes <!-- datarim:expectations -->',
                        'التوقعات <!-- datarim:expectations -->'):
            with self.subTest(heading=heading):
                result = self.check_expectation(self.expectation(heading))
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn('ADVISORY', result.stderr)  # success_criterion still parsed

    def test_legacy_expectation_is_accepted(self):
        body = self.expectation('Ожидания')
        for key, alias in [('wish:', 'Что хочу проверить:'),
                           ('success_criterion:', 'Как проверить (success criterion):'),
                           ('linked_ac:', 'Связанный AC из PRD:'),
                           ('status_history', 'История статусов'),
                           ('current_status', 'Текущий статус')]:
            body = body.replace(key, alias)
        result = self.check_expectation(body)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_translated_expectation_cannot_bypass_structure_or_status(self):
        for body in (self.expectation().replace('    - met\n', '    - invalid_status\n'),
                     self.expectation() + '\n## Autres <!-- datarim:expectations -->\n',
                     '```markdown\n' + self.expectation() + '\n```'):
            result = self.check_expectation(body)
            self.assertEqual(1, result.returncode, result.stderr)

    def test_localized_partial_wish_still_blocks_verified_admission(self):
        result = self.check_expectation(
            self.expectation().replace('    - met\n', '    - partial\n'), verify=True)
        self.assertEqual(1, result.returncode, result.stderr)
        self.assertIn('BLOCKED', result.stdout)
        self.assertIn('resultat-verifie', result.stdout)

    def test_language_specific_prose_check(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / 'report.md'
            artifact.write_text('The deploy completed; the rollback remains available.\n')
            for language, expected in [('en', 0), ('fr', 0), ('ar', 0), ('ru', 1), ('en;false', 2)]:
                result = subprocess.run(['bash', str(ROOT / 'dev-tools/check-banlist-on-prose.sh'),
                                         '--file', str(artifact), '--language', language],
                                        capture_output=True, text=True, check=False)
                self.assertEqual(expected, result.returncode, (language, result.stderr))


    def test_prose_language_grammar_matches_the_resolver(self):
        spec = importlib.util.spec_from_file_location(
            'framework_language_preferences',
            ROOT / 'skills/human-outcome-reporting/scripts/language.py')
        resolver = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = resolver
        spec.loader.exec_module(resolver)
        tags = ['en', 'fr', 'ar', 'RU', 'ru-Cyrl-RU', 'x-private', 'i-klingon',
                'I-default', 'en' + '-abcdefgh' * 6 + '-abcdef',
                'x', 'a', 'en_US', 'en--US', 'en;false', 'en\n',
                'en' + '-abcdefgh' * 7]
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / 'report.md'
            artifact.write_text('A deploy completed.\n')
            for tag in tags:
                with self.subTest(tag=tag):
                    try:
                        resolver.language_tag(tag)
                        valid = True
                    except resolver.PreferenceError:
                        valid = False
                    result = subprocess.run(
                        ['bash', str(ROOT / 'dev-tools/check-banlist-on-prose.sh'),
                         '--file', str(artifact), '--language', tag],
                        capture_output=True, text=True, check=False)
                    self.assertEqual(valid, result.returncode != 2, result.stderr)
                    if valid:
                        self.assertEqual(1 if tag.lower().startswith('ru') else 0,
                                         result.returncode, result.stderr)

    def test_legacy_cyrillic_wish_id_is_preserved_and_new_ids_are_ascii(self):
        body = self.expectation().replace('resultat-verifie', 'результат-проверен')
        result = self.check_expectation(body, verify=True)
        self.assertEqual(0, result.returncode, result.stderr)
        pending = self.check_expectation(body.replace('    - met\n', '    - partial\n'), verify=True)
        self.assertEqual(1, pending.returncode, pending.stderr)
        self.assertIn('результат-проверен', pending.stdout)
        for relative in ['templates/expectations-template.md',
                         'skills/expectations-checklist/SKILL.md',
                         'skills/artifact-context/SKILL.md', 'commands/dr-init.md',
                         'commands/dr-prd.md', 'commands/dr-plan.md']:
            text = (ROOT / relative).read_text()
            self.assertIn('ASCII', text, relative)
            self.assertRegex(text, r'(?i)(preserve|never translate|existing).*?(legacy|IDs|identifiers)',
                             relative)

    def test_platform_languages_and_localized_summary_are_explicit(self):
        # Guard the previously conflicting consumer instructions, rather than
        # merely proving the common preference policy exists.
        sources = {path: (ROOT / path).read_text() for path in [
            'agents/writer.md', 'commands/dr-publish.md',
            'skills/publishing/SKILL.md', 'skills/human-summary/SKILL.md',
            'commands/dr-quick.md']}
        forbidden = ['LinkedIn (English)', 'Telegram (RU)', 'X (EN)',
                     'headings remain bilingual', 'Short English title', 'its single RU article URL']
        for path, source in sources.items():
            for phrase in forbidden:
                self.assertNotIn(phrase, source, (path, phrase))
        self.assertIn('explicit author/channel audience language', sources['agents/writer.md'])
        self.assertIn('configured channel language', sources['commands/dr-publish.md'])
        self.assertIn('explicitly requested bilingual bundle (including RU+EN)',
                      sources['skills/publishing/SKILL.md'])
        self.assertIn('stable semantic markers', sources['skills/human-summary/SKILL.md'])
        self.assertIn('resolved artifact language', sources['commands/dr-quick.md'])


class CustomerLocaleMatrixTests(unittest.TestCase):
    """Production validator function seam, not signed full-delivery admission."""
    def setUp(self):
        source = (ROOT / 'dev-tools/check-customer-delivery.sh').read_text()
        start = source.index('def validate_live_evidence_edge(')
        end = source.index('\ndef validate_customer_disposition_edge(', start)
        # Trusted checked-out production source is executed by the Python CLI.
        # This isolates the changed edge from unrelated signing/host dependencies.
        self.function_source = source[start:end]
        scope = {'locales': ['fr', 'ar'], 'viewports': ['mobile', 'desktop'],
                 'themes': ['light', 'dark'], 'painted_matrix_applicable': True}
        self.acceptance = {'applicability': scope, 'visitor_visible': True,
                           'product': 'example', 'surface': 'page',
                           'surface_class': 'VISITOR_VISIBLE', 'predicate_id': 'readable'}
        self.live = dict(self.acceptance, painted_matrix_applicable=True,
                         observed_at='2026-01-02T13:00:00Z',
                         painted_matrix=[{'locale': locale, 'viewport': viewport, 'theme': theme,
                                          'evidence_ref': 'image.png', 'observed_at': '2026-01-02T12:30:00Z'}
                                         for locale in scope['locales']
                                         for viewport in scope['viewports'] for theme in scope['themes']])
        self.chain = {'implementation_delta': {'visitor_visible_count': 1,
                                              'visitor_visible_changes': ['page changed']},
                      'deployed_revision': {'deployed_at': '2026-01-02T12:00:00Z'},
                      'customer_disposition': {'recorded_at': '2026-01-02T14:00:00Z'},
                      'live_evidence': self.live}

    def findings(self, acceptance=None, chain=None):
        prelude = ('import json,sys\nfrom datetime import datetime\n'
                   'findings=[]\nadd=findings.append\n'
                   'def scope_equal(a,b): return a == b\n'
                   'def parse_time(value,label): return datetime.fromisoformat(value.replace("Z","+00:00"))\n')
        program = prelude + self.function_source + '\na,c=json.load(sys.stdin)\n' + \
                  'validate_live_evidence_edge("req-0001",a,c)\nprint(json.dumps(findings))\n'
        result = subprocess.run([sys.executable, '-c', program],
                                input=json.dumps([acceptance or self.acceptance, chain or self.chain]),
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_declared_french_arabic_and_legacy_matrices_pass(self):
        self.assertEqual([], self.findings())
        for obj in (self.acceptance, self.live):
            obj['applicability']['locales'] = ['ru', 'en']
        for cell in self.live['painted_matrix']:
            cell['locale'] = {'fr': 'ru', 'ar': 'en'}[cell['locale']]
        self.assertEqual([], self.findings())

    def test_missing_extra_duplicate_and_reduced_device_matrix_fail(self):
        for mutation in ('missing', 'extra', 'duplicate', 'reduced'):
            with self.subTest(mutation=mutation):
                acceptance = copy.deepcopy(self.acceptance)
                chain = copy.deepcopy(self.chain)
                matrix = chain['live_evidence']['painted_matrix']
                if mutation == 'missing': matrix.pop()
                elif mutation == 'extra': matrix.append(dict(matrix[0], locale='en'))
                elif mutation == 'duplicate': matrix.append(dict(matrix[0]))
                else:
                    acceptance['applicability']['viewports'] = ['mobile']
                    chain['live_evidence']['applicability']['viewports'] = ['mobile']
                    chain['live_evidence']['painted_matrix'] = [c for c in matrix if c['viewport'] == 'mobile']
                self.assertIn('painted_matrix_incomplete:req-0001', self.findings(acceptance, chain))

    def test_scope_and_timestamp_checks_still_apply(self):
        chain = copy.deepcopy(self.chain)
        chain['live_evidence']['applicability']['locales'] = ['fr']
        self.assertIn('applicability_mismatch:req-0001', self.findings(chain=chain))
        chain = copy.deepcopy(self.chain)
        chain['live_evidence']['painted_matrix'][0]['observed_at'] = '2026-01-02T11:30:00Z'
        self.assertIn('painted_matrix_timestamp_mismatch:req-0001', self.findings(chain=chain))


if __name__ == '__main__':
    unittest.main()
