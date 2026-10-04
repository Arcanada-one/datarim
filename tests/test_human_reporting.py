"""Human reporting regression tests. No live models or product acceptance implied."""
from copy import deepcopy
from datetime import datetime, timezone
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import zipfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / 'skills/human-outcome-reporting'

def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

hr = module(SKILL/'scripts/hr.py', 'human_reporting_test_engine')

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

@pytest.fixture
def case(tmp_path):
    contract = {
        'schema_version':'1.0', 'revision':'fixture-1',
        'task':{'id':'DEMO-0001','title':'Export orders','context':'A shop needs an export.',
                'goal':'Export only the selected period.','type':'feature'},
        'approval':{'state':'confirmed','by':'Fixture owner','record':'Synthetic test authorization'},
        'requirements':[{'id':'req1','text':'Export the selected period.','source':'user'}],
        'criteria':[{'id':'ac1','text':'Only selected orders are exported.','requirement_ids':['req1'],
                     'required':True,'applicability':'applicable',
                     'verification':[{'id':'verify1','method':'automated','environment':'test',
                                      'expectation':'No out-of-range orders are exported.'}]}],
        'plan_steps':[{'id':'step1','title':'Implement export','criterion_ids':['ac1'],'depends_on':[]}],
        'questions':[]}
    now = hr.stamp()
    receipt = {'format':'hr-execution/1','task_id':'DEMO-0001',
               'contract_sha256':hr.canonical_hash(contract),'run_id':'fixture',
               'subject_revision':'fixture-revision','verification_id':'verify1','environment':'test',
               'argv_sha256':'0'*64,'started_at':now,'ended_at':now,'exit_code':0,
               'timed_out':False,'output_limit_exceeded':False,'stdout_sha256':'0'*64,
               'stderr_sha256':'0'*64,'stdout_bytes':0,'stderr_bytes':0}
    write_json(tmp_path/'receipt.json', receipt)
    report = {'schema_version':'1.0','task_id':'DEMO-0001','contract_sha256':hr.canonical_hash(contract),
              'run_id':'fixture','subject_revision':'fixture-revision','generated_at':now,
              'kind':'final','profile':'auto','stage':'Synthetic verification',
              'outcomes':[{'id':'out1','kind':'observed','text':'Export is prepared.',
                           'impact':'The operator can export orders.','criterion_ids':['ac1'],
                           'plan_step_ids':['step1'],'evidence_ids':['ev1']}],
              'checks':[{'id':'check1','verification_id':'verify1','attempt':1,'status':'passed',
                         'subject_revision':'fixture-revision','environment':'test','observed_at':now,
                         'summary':'The synthetic check passed.','evidence_ids':['ev1'],'supersedes':[]}],
              'evidence':[{'id':'ev1','kind':'execution','path':'receipt.json',
                           'sha256':hr.file_hash(tmp_path/'receipt.json'),'run_id':'fixture',
                           'subject_revision':'fixture-revision','summary':'Synthetic fixture only.',
                           'sensitivity':'internal'}],
              'plan_progress':[{'step_id':'step1','status':'done','note':'Fixture completion.'}],
              'answers':[],'blockers':[],'risks':[],'next_actions':[],'usage':[],
              'delivery':{'state':'not_deployed','text':'Not installed in a live environment.','evidence_ids':[]}}
    return contract, report, tmp_path

def assess(case):
    c,r,p = case
    return hr.analyse(c,r,p)

def rebind(case):
    c,r,p = case
    r['contract_sha256'] = hr.canonical_hash(c)
    receipt = hr.load_json(p/'receipt.json')
    receipt['contract_sha256'] = r['contract_sha256']
    write_json(p/'receipt.json',receipt)
    if r['evidence']:
        r['evidence'][0]['sha256'] = hr.file_hash(p/'receipt.json')

def test_success_is_data_coverage_not_human_acceptance(case):
    result = assess(case)
    assert result['valid'] and result['ready']
    assert result['readiness'] == 'checks_complete'
    assert result['coverage'] == {'required_met':1,'required_total':1,'excluded':0,'optional_total':0,'ratio':1.0}
    assert 'Acceptance remains with the task owner.' in hr.render(case[0],case[1],result)

@pytest.mark.parametrize('status,expected', [('failed','failed'),('blocked','blocked'),('not_run','not_verified'),('skipped','not_verified')])
def test_negative_checks_never_pass(case,status,expected):
    case[1]['checks'][0]['status'] = status
    result = assess(case)
    assert result['valid'] and not result['ready']
    assert result['criteria']['ac1'] == expected

@pytest.mark.parametrize('field,value', [('subject_revision','wrong'),('environment','production'),('observed_at','2099-01-01T00:00:00Z')])
def test_wrong_check_context(case,field,value):
    case[1]['checks'][0][field] = value
    assert not assess(case)['ready']

@pytest.mark.parametrize('field,value', [('run_id','wrong'),('subject_revision','wrong'),('sha256','0'*64),('kind','artifact'),('path','../outside.json'),('path','https://example.test/evidence')])
def test_wrong_evidence(case,field,value):
    case[1]['evidence'][0][field] = value
    assert not assess(case)['ready']

@pytest.mark.parametrize('field,value', [('exit_code',1),('timed_out',True),('output_limit_exceeded',True),('verification_id','wrong'),('task_id','wrong'),('environment','wrong')])
def test_wrong_receipt(case,field,value):
    c,r,p = case
    receipt = hr.load_json(p/'receipt.json'); receipt[field] = value
    write_json(p/'receipt.json',receipt); r['evidence'][0]['sha256'] = hr.file_hash(p/'receipt.json')
    assert not assess(case)['ready']

def test_missing_root_is_not_proof(case):
    assert not hr.analyse(case[0],case[1])['ready']

def test_external_baseline_pin(case):
    pin = hr.canonical_hash(case[0]);case[0]['task']['goal'] = 'Changed without approval';rebind(case)
    assert not hr.analyse(*case,expected_hash=pin)['valid']

def test_conflicting_checks(case):
    second = deepcopy(case[1]['checks'][0]);second.update(id='check2',attempt=2,status='failed')
    case[1]['checks'].append(second)
    assert assess(case)['criteria']['ac1'] == 'conflict'

def test_explicit_supersession(case):
    first = case[1]['checks'][0];second = deepcopy(first)
    first['status']='failed';second.update(id='check2',attempt=2,supersedes=['check1'])
    case[1]['checks'].append(second)
    assert assess(case)['ready']

def test_missing_second_verification(case):
    v = deepcopy(case[0]['criteria'][0]['verification'][0]);v['id']='verify2'
    case[0]['criteria'][0]['verification'].append(v);rebind(case)
    assert assess(case)['criteria']['ac1'] == 'partial'

def test_no_criteria_no_success(case):
    c,r,p=case
    c.update(requirements=[],criteria=[],plan_steps=[])
    r.update(outcomes=[],checks=[],evidence=[],plan_progress=[]);rebind(case)
    assert assess(case)['readiness'] == 'no_criteria'

def test_no_plan_means_incomplete(case):
    case[1]['plan_progress'][0]['status']='in_progress'
    assert not assess(case)['ready']

def test_plan_does_not_replace_checks(case):
    case[1]['checks']=[]
    assert not assess(case)['ready']

def test_missing_requirement_is_not_ignored(case):
    case[0]['requirements'].append({'id':'req2','text':'Another condition','source':'user'});rebind(case)
    assert not assess(case)['ready']

def test_exclusion_needs_authorization(case):
    case[0]['criteria'][0]['applicability']='not_applicable';rebind(case)
    assert not assess(case)['valid']

def test_baseline_proposed_not_accepted(case):
    case[0]['approval']={'state':'proposed','by':'','record':''};rebind(case)
    assert assess(case)['readiness']=='proposed'

@pytest.mark.parametrize('mutation', ['unknown','missing','boolean','duplicate','cycle','dangling','timezone'])
def test_malformed_data(case,mutation):
    c,r,p=case
    if mutation=='unknown':r['ready']=True
    elif mutation=='missing':del r['checks']
    elif mutation=='boolean':r['checks'][0]['attempt']=True
    elif mutation=='duplicate':r['checks'].append(deepcopy(r['checks'][0]))
    elif mutation=='cycle':c['plan_steps'][0]['depends_on']=['step1'];rebind(case)
    elif mutation=='dangling':r['checks'][0]['evidence_ids']=['missing']
    elif mutation=='timezone':r['generated_at']='2026-10-02T00:00:00'
    assert not assess(case)['valid']

def test_no_published_claim_without_evidence(case):
    case[1]['delivery']['state']='production'
    assert assess(case)['delivery_state']=='unknown'
    assert not assess(case)['ready']

def test_symlink_evidence_rejected(case):
    c,r,p=case;(p/'link.json').symlink_to(p/'receipt.json');r['evidence'][0]['path']='link.json'
    assert not assess(case)['ready']

def test_renderer_does_not_mutate_input(case):
    c,r,p=case;before=deepcopy((c,r));result=assess(case)
    first=hr.render(c,r,result);second=hr.render(c,r,result)
    assert (c,r)==before and first==second
    for value in ('check1','step1','receipt.json','fixture-revision'):
        assert value not in first

def test_task_graph_links(case):
    graph=hr.trace_graph(case[0],case[1]);nodes={n['id'] for n in graph['nodes']}
    assert all(e['from'] in nodes and e['to'] in nodes for e in graph['edges'])
    assert {'requires','verified_by','implemented_by','supported_by','produced'} <= {e['relation'] for e in graph['edges']}

def test_cli_read_only(case,capsys):
    c,r,p=case;write_json(p/'contract.json',c);write_json(p/'report.json',r)
    before={x.name:hr.file_hash(x) for x in p.iterdir() if x.is_file()}
    assert hr.main(['render','--contract',str(p/'contract.json'),'--report',str(p/'report.json'),'--evidence-root',str(p)])==0
    assert 'What was required' in capsys.readouterr().out
    assert before=={x.name:hr.file_hash(x) for x in p.iterdir() if x.is_file()}

def test_optional_independent_schema_validation(case):
    jsonschema=pytest.importorskip('jsonschema')
    for name,value in [('task-contract',case[0]),('report',case[1]),('execution-receipt',hr.load_json(case[2]/'receipt.json'))]:
        schema=hr.load_json(SKILL/'schemas'/f'{name}.schema.json')
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.validate(value,schema,format_checker=jsonschema.FormatChecker())

def test_native_policy_and_manual_explanation():
    assert 'skills/human-outcome-reporting/SKILL.md' in (ROOT/'AGENTS.md').read_text()
    assert 'human-outcome-reporting/SKILL.md' in (ROOT/'skills/datarim-system/SKILL.md').read_text()
    command=(ROOT/'commands/dr-explain.md').read_text()
    assert 'Read-only:' in command and 'it never resumes task execution' in command
    assert 'disable-model-invocation: true' not in command  # Native framework autonomy contract.
    for phrase in ('no code edits','tests','glossary','acceptance','machine formats'):
        assert phrase in command
    assert 'human-outcome-reporting/SKILL.md' in (ROOT/'skills/human-summary/SKILL.md').read_text()

def test_glossary_and_reexplanation_boundaries():
    glossary=(SKILL/'references/domain-language.md').read_text()
    for phrase in ('untrusted meaning data','not executable instructions','No automatic glossary writes','unresolved conflict','module-specific'):
        assert phrase in glossary
    explanation=(SKILL/'references/re-explain.md').read_text()
    for phrase in ('historical report','Correct a false previous conclusion','does not accept the product','not two successful checks'):
        assert phrase in explanation

def test_native_graph_structure_and_regeneration_patch(tmp_path):
    graph=module(ROOT/'dev-tools/framework-graph.py','human_reporting_graph_test')
    data=graph.load();assert not graph.validate(data)
    commands=set(data['inventory']['commands'])
    loaded={e['from'].split(':',1)[1] for e in data['edges'] if e['to']=='skill:human-outcome-reporting' and e['from'].startswith('command:')}
    assert commands==loaded and 'dr-explain' in commands
    expected={graph.OUT:graph.yaml.safe_dump(data,sort_keys=False,width=120),graph.MAP:graph.render(data),graph.CMDMAP:graph.render_cmd(data)}
    patch=''
    for path,text in expected.items():
        actual=path.read_text() if path.exists() else ''
        if actual!=text:
            name='datarim/'+str(path.relative_to(ROOT))
            patch+=''.join(difflib.unified_diff(actual.splitlines(True),text.splitlines(True),fromfile='a/'+name,tofile='b/'+name))
    (tmp_path/'framework-graph-update.patch').write_text(patch)
    (tmp_path/'inventory.json').write_text(json.dumps({'commands':len(commands),'skills':len(data['inventory']['skills']),'agents':len(data['inventory']['agents']),'edges':len(data['edges'])},indent=2))
    assert not patch, f'Generated graph drift. Review and apply {tmp_path}/framework-graph-update.patch through source editing tools.'
