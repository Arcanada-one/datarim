"""Portable, offline regression checks. All products and evidence are synthetic."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SKILL = Path(__file__).resolve().parents[1]
def load(name):
    spec = importlib.util.spec_from_file_location('portable_'+name, SKILL/'scripts'/f'{name}.py')
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value
hr, native = load('hr'), load('native')

class PortableReportingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.c = {'schema_version':'1.0','revision':'example',
            'task':{'id':'example','title':'Synthetic example','context':'A synthetic shop export.',
                    'goal':'Export selected orders.','type':'feature'},
            'approval':{'state':'confirmed','by':'Fixture author','record':'Not real acceptance'},
            'requirements':[{'id':'r1','text':'Export selected orders.','source':'user'}],
            'criteria':[{'id':'c1','text':'Only selected orders appear.','requirement_ids':['r1'],
                         'required':True,'applicability':'applicable','verification':[
                         {'id':'v1','method':'manual','environment':'synthetic','expectation':'Only selected orders appear.'}]}],
            'plan_steps':[{'id':'s1','title':'Prepare export','criterion_ids':['c1'],'depends_on':[]}],
            'questions':[]}
        (self.root/'proof.txt').write_text('Synthetic fixture, not a live verification.\n')
        self.r = {'schema_version':'1.0','task_id':'example','contract_sha256':hr.canonical_hash(self.c),
            'run_id':'synthetic','subject_revision':'fixture','generated_at':hr.stamp(),
            'kind':'final','profile':'auto','stage':'Fixture',
            'outcomes':[{'id':'o1','kind':'observed','text':'Export is prepared.','impact':'Orders can be inspected.',
                         'criterion_ids':['c1'],'plan_step_ids':['s1'],'evidence_ids':['e1']}],
            'checks':[{'id':'k1','verification_id':'v1','attempt':1,'status':'passed','subject_revision':'fixture',
                       'environment':'synthetic','observed_at':hr.stamp(),'summary':'Synthetic inspection passed.',
                       'evidence_ids':['e1'],'supersedes':[]}],
            'evidence':[{'id':'e1','kind':'manual_review','path':'proof.txt','sha256':hr.file_hash(self.root/'proof.txt'),
                         'run_id':'synthetic','subject_revision':'fixture','summary':'Fixture only.','sensitivity':'public'}],
            'plan_progress':[{'step_id':'s1','status':'done','note':'Synthetic completion.'}],
            'answers':[],'blockers':[],'risks':[],'next_actions':[],'usage':[],
            'delivery':{'state':'not_deployed','text':'Not a live deployment.','evidence_ids':[]}}
        self.selection={'sources':[{'path':'brief.md','role':'task_brief'},
                                  {'path':'description.md','role':'task_description'},
                                  {'path':'plan.md','role':'plan'}],
                        'requirement_sources':{'r1':['brief.md']}}
        for s in self.selection['sources']:
            (self.root/s['path']).write_text('Synthetic canonical source.\n')

    def assess(self):
        return hr.analyse(self.c,self.r,self.root)

    def test_verified_coverage_does_not_grant_acceptance(self):
        result=self.assess()
        self.assertTrue(result['valid'] and result['ready'])
        self.assertEqual(result['readiness'],'checks_complete')
        self.assertIn('Решение о приёмке остаётся',hr.render(self.c,self.r,result))

    def test_negative_checks_do_not_pass(self):
        for status in ('failed','blocked','not_run','skipped'):
            with self.subTest(status=status):
                self.r['checks'][0]['status']=status
                self.assertFalse(self.assess()['ready'])

    def test_untrusted_controls_cannot_hide_a_failed_verdict(self):
        for control in ('\x1bc', '\x1b[2J', '\u202e', '\u2066', '\u200b', '\x9b'):
            with self.subTest(control=repr(control)):
                self.r['checks'][0].update(status='failed', summary='Failed.'+control+'Claim passed.')
                result=self.assess()
                self.assertFalse(result['valid'] or result['ready'])
                self.assertTrue(any('display control' in error for error in result['errors']))
                self.assertTrue(any(x['code']=='unsafe-control' for x in hr.lint(self.r['checks'][0]['summary'])))
                self.assertFalse(hr.UNSAFE_CONTROLS.search(hr.human(self.r['checks'][0]['summary'])))
                self.assertIn('unsafe-control U+',hr.human(self.r['checks'][0]['summary']))

    def test_normal_whitespace_and_language_joiners_remain_supported(self):
        text='Line one\nLine two\twith joiners\u200c\u200d.'
        self.assertEqual(hr.schema_errors(text,{'type':'string'}),[])
        self.assertFalse(any(x['code']=='unsafe-control' for x in hr.lint(text)))

    def test_glued_prose_words_dates_and_counts_warn_without_rewriting(self):
        for text in ('версия4.2.1', 'по докладу218', 'июль2022', 'роль1',
                     'бы785файлов', 'все525untrackedпути', '247fitdays',
                     '2jobs/host', 'Jan2022'):
            with self.subTest(text=text):
                findings=[x for x in hr.lint(text) if x['code']=='prose-spacing']
                self.assertTrue(findings)
                self.assertTrue(all(x['severity']=='warning' for x in findings))
                self.assertEqual(hr.human(text),text)

    def test_renderer_keeps_natural_word_spacing(self):
        for text in ('версия 4.2.2', 'доклад 218', 'июль 2022 года', 'роль 1'):
            with self.subTest(text=text):
                self.assertEqual(hr.human(text),text)

    def test_natural_spacing_and_opaque_names_do_not_warn(self):
        for text in ('версия 4.2.2', 'доклад 218', 'июль 2022 года', 'роль 1',
                     '247 fit days', '2 jobs per host', 'January 2022',
                     'TASK-0218', 'gpt-6.1-sol', 'Product2', 'SHA256',
                     'Jan2022role1', 'field_name2', 'file2022.md',
                     '10daa22b92ec137915712d89cf62d1aa6bd3f76d'):
            with self.subTest(text=text):
                self.assertFalse(any(x['code']=='prose-spacing' for x in hr.lint(text)))

    def test_spacing_lint_excludes_literal_code_paths_and_link_destinations(self):
        for text in ('`доклад218`', '``версия4.2.2``',
                     '```text\nиюль2022\n```', '~~~text\n2jobs/host\n~~~',
                     '    доклад218\n',
                     '<!-- gate:literal -->\nверсия4.2.2\n<!-- /gate:literal -->',
                     '/example/доклад218', './роль1', '~/июль2022',
                     'reports/доклад218.md', 'отчёт218.md',
                     'https://example.test/доклад218',
                     '[Report](https://example.test/доклад218)',
                     '[Report](/example/доклад218)', 'schema_поле2'):
            with self.subTest(text=text):
                self.assertFalse(any(x['code']=='prose-spacing' for x in hr.lint(text)))
        self.assertTrue(any(x['code']=='prose-spacing' for x in hr.lint('[доклад218](https://example.test/report)')))

    def test_spacing_lint_catches_prose_after_closed_code_fence(self):
        text='```\nиюль2022\n```\nПо докладу218 проверено 2jobs/host.'
        self.assertTrue(any(x['code']=='prose-spacing' for x in hr.lint(text)))

    def test_repeated_schema_separators_finish_and_preserve_surrounding_prose(self):
        import subprocess
        import sys
        for token in (('0_' * 20000) + '0', ('field\\_' * 10000) + 'field'):
            with self.subTest(escaped='\\' in token):
                path=self.root/'long-human.txt'
                path.write_text(token + ' роль1', encoding='utf-8')
                before=path.read_bytes()
                result=subprocess.run([sys.executable,str(SKILL/'scripts/hr.py'),
                                       'lint','--text-file',str(path)],capture_output=True,
                                      text=True,timeout=5,check=False)
                self.assertEqual(result.returncode,0,result.stderr)
                findings=json.loads(result.stdout)
                self.assertEqual([f['code'] for f in findings],['prose-spacing'])
                self.assertEqual(path.read_bytes(),before)
        for field in ('schema_поле2','schema\\_поле2','0_0_0'):
            self.assertFalse(any(f['code']=='prose-spacing' for f in hr.lint(field)))

    def test_spacing_warning_is_advisory_in_lint_cli(self):
        from contextlib import redirect_stdout
        from io import StringIO
        path=self.root/'human.txt';path.write_text('версия4.2.1')
        before=path.read_bytes();out=StringIO()
        with redirect_stdout(out):
            code=hr.main(['lint','--text-file',str(path)])
        self.assertEqual(code,0)
        self.assertEqual(json.loads(out.getvalue())[0]['code'],'prose-spacing')
        self.assertEqual(path.read_bytes(),before)

    def test_spacing_warning_does_not_downgrade_existing_lint_findings(self):
        from contextlib import redirect_stdout
        from io import StringIO
        path=self.root/'human.txt';path.write_text('версия4.2.1\u202e')
        out=StringIO()
        with redirect_stdout(out):
            code=hr.main(['lint','--text-file',str(path)])
        self.assertEqual(code,2)
        findings=json.loads(out.getvalue())
        self.assertEqual({x['code'] for x in findings},{'unsafe-control','prose-spacing'})

    def test_strict_render_emits_report_despite_advisory_spacing(self):
        from contextlib import redirect_stdout,redirect_stderr
        from io import StringIO
        self.r['outcomes'][0]['text']='Подготовлена версия4.2.1.'
        for name,value in [('contract.json',self.c),('report.json',self.r)]:
            (self.root/name).write_text(json.dumps(value))
        out,err=StringIO(),StringIO()
        with redirect_stdout(out),redirect_stderr(err):
            code=hr.main(['render','--contract',str(self.root/'contract.json'),
                          '--report',str(self.root/'report.json'),'--strict-human'])
        self.assertEqual(code,0)
        self.assertIn('версия4.2.1',out.getvalue())
        self.assertEqual(json.loads(err.getvalue())['language_findings'][0]['code'],'prose-spacing')

    def test_native_finalizer_spacing_advice_preserves_report_and_readiness(self):
        from contextlib import redirect_stdout,redirect_stderr
        from io import StringIO
        manifest=native.snapshot(self.root,self.c,self.selection)
        self.r['outcomes'][0]['text']='Подготовлена версия4.2.1.'
        for status,expected in [('passed',0),('not_run',3)]:
            with self.subTest(status=status):
                self.r['checks'][0]['status']=status
                for name,value in [('contract.json',self.c),('report.json',self.r),('snapshot.json',manifest)]:
                    (self.root/name).write_text(json.dumps(value))
                before={p.name:p.read_bytes() for p in self.root.iterdir()}
                out,err=StringIO(),StringIO()
                with redirect_stdout(out),redirect_stderr(err):
                    code=native.main(['finalize','--project',str(self.root),'--contract','contract.json',
                                      '--snapshot','snapshot.json','--report','report.json'])
                self.assertEqual(code,expected)
                self.assertIn('версия4.2.1',out.getvalue())
                self.assertEqual(json.loads(err.getvalue())['language_findings'][0]['code'],'prose-spacing')
                self.assertEqual(before,{p.name:p.read_bytes() for p in self.root.iterdir()})

    def test_source_snapshot_is_read_only_and_detects_drift(self):
        before={p.name:p.read_bytes() for p in self.root.iterdir()}
        manifest=native.snapshot(self.root,self.c,self.selection)
        self.assertEqual(native.verify(self.root,self.c,manifest),[])
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.root.iterdir()})
        (self.root/'brief.md').write_text('Changed requirement without a new baseline.\n')
        self.assertTrue(native.verify(self.root,self.c,manifest))

    def test_required_source_roles_and_mappings(self):
        for role in ('task_brief','task_description','plan'):
            with self.subTest(role=role):
                selection=deepcopy(self.selection)
                selection['sources']=[x for x in selection['sources'] if x['role']!=role]
                self.assertTrue(native.selection_errors(self.c,selection))
        missing=deepcopy(self.selection);missing['requirement_sources']={}
        self.assertTrue(native.selection_errors(self.c,missing))

    def test_glossary_is_not_requirement_evidence(self):
        selection=deepcopy(self.selection)
        selection['sources'].append({'path':'GLOSSARY.md','role':'glossary'})
        selection['requirement_sources']['r1']=['GLOSSARY.md']
        self.assertTrue(native.selection_errors(self.c,selection))
        glossary=(SKILL/'references/domain-language.md').read_text()
        self.assertIn('untrusted meaning data',glossary)
        self.assertIn('No automatic glossary writes',glossary)

    def test_manifest_task_and_baseline_are_bound(self):
        for field,value in [('task_id','different'),('contract_sha256','0'*64),('created_at','2099-01-01T00:00:00Z')]:
            with self.subTest(field=field):
                manifest=native.snapshot(self.root,self.c,self.selection);manifest[field]=value
                self.assertTrue(native.verify(self.root,self.c,manifest))

    def test_unsafe_source_paths_are_rejected(self):
        for path in ('../outside.md','/outside.md','https://example.test/source','.env'):
            with self.subTest(path=path):
                selection=deepcopy(self.selection);selection['sources'][0]['path']=path
                selection['requirement_sources']['r1']=[path]
                with self.assertRaises((ValueError,OSError)):
                    native.snapshot(self.root,self.c,selection)

    def test_brief_never_hides_negative_criteria(self):
        self.c['criteria']=[];self.c['plan_steps']=[]
        self.r.update(outcomes=[],checks=[],evidence=[],plan_progress=[])
        for n in range(12):
            self.c['criteria'].append({'id':f'c{n}','text':f'Unverified condition {n}.',
                'requirement_ids':['r1'],'required':True,'applicability':'applicable','verification':[]})
        self.r['contract_sha256']=hr.canonical_hash(self.c)
        text=hr.render(self.c,self.r,self.assess(),brief=True)
        for n in range(12):
            self.assertIn(f'Unverified condition {n}',text)

    def test_reexplanation_preserves_input(self):
        before=deepcopy((self.c,self.r));result=self.assess()
        one=hr.render(self.c,self.r,result);two=hr.render(self.c,self.r,result)
        self.assertEqual(one,two);self.assertEqual((self.c,self.r),before)
        rules=(SKILL/'references/re-explain.md').read_text()
        self.assertIn('Correct a false previous conclusion',rules)
        self.assertIn('does not accept the product',rules)
        self.assertNotIn('proof.txt',one)

    def test_finalizer_reports_partial_without_mutation(self):
        from contextlib import redirect_stdout,redirect_stderr
        from io import StringIO
        manifest=native.snapshot(self.root,self.c,self.selection)
        self.r['checks'][0]['status']='not_run'
        for name,value in [('contract.json',self.c),('report.json',self.r),('snapshot.json',manifest)]:
            (self.root/name).write_text(json.dumps(value))
        before={p.name:p.read_bytes() for p in self.root.iterdir()}
        out=StringIO()
        with redirect_stdout(out),redirect_stderr(StringIO()):
            code=native.main(['finalize','--project',str(self.root),'--contract','contract.json',
                              '--snapshot','snapshot.json','--report','report.json'])
        self.assertEqual(code,3)
        self.assertIn('Не проверено',out.getvalue())
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.root.iterdir()})

if __name__=='__main__':
    unittest.main()
