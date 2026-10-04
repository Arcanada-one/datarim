"""Negative controls for template existence and the relationship graph."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'dev-tools'/file)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


targets = module('template_targets', 'check-template-targets.py')
graph = module('framework_graph', 'framework-graph.py')


class IntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ('templates', 'skills/testing', 'commands', 'agents', 'dev-tools'):
            (self.root/name).mkdir(parents=True)
        (self.root/'skills/testing/SKILL.md').write_text(
            '---\nname: testing\ndescription: Verify observable behavior at each affected integration boundary.\n---\n')
        (self.root/'commands/dr-do.md').write_text('Read skills/testing/SKILL.md.\n')
        (self.root/'dev-tools/command-graph.yaml').write_text('commands:\n  dr-do: {}\n')

    def test_qualified_missing_template_fails_until_asset_is_supplied(self):
        (self.root/'AGENTS.md').write_text('Use `${DATARIM_RUNTIME:?}/templates/security-workflow.yml`.\n')
        count, errors = targets.check(self.root)
        self.assertEqual(count, 1)
        self.assertEqual(len(errors), 1)
        (self.root/'templates/security-workflow.yml').write_text('name: Security\n')
        self.assertEqual(targets.check(self.root), (1, []))

    def test_example_marker_does_not_hide_subsequent_real_reference(self):
        (self.root/'AGENTS.md').write_text(
            '<!-- gate:example-only -->\n```sh\ncat templates/example.yml\n```\n'
            'Read `${DATARIM_RUNTIME:?}/templates/missing.yml`.\n')
        count, errors = targets.check(self.root)
        self.assertEqual(count, 1)
        self.assertIn('missing.yml', errors[0])

    def test_template_symlink_cannot_resolve_outside_source(self):
        (self.root/'AGENTS.md').write_text('Read templates/escape.yml\n')
        (self.root/'templates/escape.yml').symlink_to(Path(__file__).resolve())
        self.assertEqual(len(targets.check(self.root)[1]), 1)

    def test_skill_fragment_broken_edge_is_detected(self):
        skill = self.root/'skills/testing/SKILL.md'
        skill.write_text(skill.read_text()+'Read skills/testing/missing.md\n')
        with patch.object(graph, 'ROOT', self.root):
            errors = graph.validate(graph.load())
        self.assertTrue(any('missing.md' in error for error in errors))
        (self.root/'skills/testing/missing.md').write_text('A real fragment.\n')
        with patch.object(graph, 'ROOT', self.root):
            self.assertEqual(graph.validate(graph.load()), [])

    def test_portable_sibling_link_retains_canonical_edge_and_deduplicates(self):
        skill = self.root/'skills/testing/SKILL.md'
        skill.write_text(skill.read_text() +
                         '[local](language-preferences.md) [anchor](./language-preferences.md#usage)\n'
                         'Read skills/testing/language-preferences.md too.\n')
        (skill.parent/'language-preferences.md').write_text('A portable instruction fragment.\n')
        with patch.object(graph, 'ROOT', self.root):
            result = graph.load()
            self.assertEqual(graph.validate(result), [])
        edge = {'from': 'skill:testing', 'relation': 'loads',
                'to': 'fragment:skills/testing/language-preferences.md',
                'source': 'skills/testing/SKILL.md'}
        self.assertEqual(result['edges'].count(edge), 1)

    def test_sibling_links_in_fragments_resolve_from_the_source_directory(self):
        fragment = self.root/'skills/testing/entry.md'
        fragment.write_text('[detail](detail.md)\n')
        (fragment.parent/'detail.md').write_text('Detailed portable instructions.\n')
        with patch.object(graph, 'ROOT', self.root):
            result = graph.load()
            self.assertEqual(graph.validate(result), [])
        self.assertIn({'from': 'fragment:skills/testing/entry.md', 'relation': 'loads',
                       'to': 'fragment:skills/testing/detail.md',
                       'source': 'skills/testing/entry.md'}, result['edges'])

    def test_missing_and_external_symlink_siblings_remain_broken(self):
        skill = self.root/'skills/testing/SKILL.md'
        skill.write_text(skill.read_text() + '[local](missing.md)\n')
        with patch.object(graph, 'ROOT', self.root):
            result = graph.load()
            self.assertTrue(any('missing.md' in error for error in graph.validate(result)))
        # The basename looks safe; its real target must still stay inside ROOT.
        (skill.parent/'missing.md').symlink_to(Path(__file__).resolve())
        with patch.object(graph, 'ROOT', self.root):
            result = graph.load()
            self.assertTrue(any('missing.md' in error for error in graph.validate(result)))
            self.assertFalse(any(edge['to'] == 'fragment:skills/testing/missing.md'
                                 for edge in result['edges']))

    def test_template_dependency_is_in_inventory_and_edge_set(self):
        (self.root/'templates/report.md').write_text('Explain the observed outcome.\n')
        command = self.root/'commands/dr-do.md'
        command.write_text(command.read_text()+'Read `${DATARIM_RUNTIME:?}/templates/report.md`.\n')
        with patch.object(graph, 'ROOT', self.root):
            result = graph.load()
            self.assertEqual(graph.validate(result), [])
            self.assertIn('report.md', result['inventory']['templates'])
            self.assertIn({'from':'command:dr-do','relation':'uses_template','to':'template:report.md','source':'commands/dr-do.md'}, result['edges'])
            result['inventory']['templates'] = []
            self.assertTrue(any('unknown node' in error for error in graph.validate(result)))

    def test_global_reporting_applies_to_agents_and_commands(self):
        (self.root/'AGENTS.md').write_text('Read skills/testing/SKILL.md.\n')
        (self.root/'agents/developer.md').write_text('Return facts through the native handoff.\n')
        (self.root/'dev-tools/command-graph.yaml').write_text('always_load_skills: [testing]\ncommands:\n  dr-do: {}\n')
        with patch.object(graph, 'ROOT', self.root):
            result=graph.load()
            self.assertEqual(graph.validate(result), [])
            for origin in ('command:dr-do','agent:developer'):
                self.assertIn({'from':origin,'relation':'loads','to':'skill:testing','source':'AGENTS.md'},result['edges'])

    def test_wrong_skill_name_is_a_resolution_failure(self):
        skill = self.root/'skills/testing/SKILL.md'
        skill.write_text(skill.read_text().replace('name: testing', 'name: typo'))
        with patch.object(graph, 'ROOT', self.root):
            errors = graph.validate(graph.load())
        self.assertTrue(any('name does not match' in error for error in errors))


if __name__ == '__main__':
    unittest.main()
