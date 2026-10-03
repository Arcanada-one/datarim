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
