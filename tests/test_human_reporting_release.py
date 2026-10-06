"""Native runtime payload and reproducible release verification; no live models."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

import pytest
import test_project_runtime as runtime_tests

ROOT=Path(__file__).resolve().parents[1]
SKILL=ROOT/'skills/human-outcome-reporting'

def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


def test_all_client_entrypoints_and_runtime_support_files():
    host=runtime_tests.InstallationLifecycleTests('runTest')
    host.setUp()
    original_ignore=(host.project/'.gitignore').read_bytes()
    try:
        shutil.copytree(SKILL,host.source/'skills/human-outcome-reporting',
                        ignore=shutil.ignore_patterns('__pycache__','*.pyc'),dirs_exist_ok=True)
        shutil.copy2(ROOT/'AGENTS.md',host.source/'AGENTS.md')
        for command in (ROOT/'commands').glob('*.md'):
            shutil.copy2(command,host.source/'commands'/command.name)
        runtime_tests.project_install.install(host.args)
        manifests=list((host.project/'.datarim-runtime').rglob('human-outcome-reporting/SKILL.md'))
        assert manifests, 'The native installer omitted the reporting skill.'
        installed=manifests[0].parent
        for name in ('SKILL.md','scripts/hr.py','scripts/native.py','scripts/language.py','scripts/presentation.py',
                     'locales/en.json','locales/ru.json','locales/fr.json','locales/ar.json','locales/ja.json',
                     'schemas/report.schema.json','references/re-explain.md','references/presentation.md'):
            assert (installed/name).read_bytes()==(SKILL/name).read_bytes()
        for command in (ROOT/'commands').glob('*.md'):
            paths=[host.project/'.claude/commands'/command.name,
                   host.project/'.agents/skills'/command.stem/'SKILL.md',
                   host.project/'.cursor/skills'/command.stem/'SKILL.md']
            for path in paths:
                assert path.is_file(), str(path)
                assert 'AGENTS.md' in path.read_text()
        assert (host.project/'AGENTS.md').read_text()=='# Original project rules\n'
        assert (host.project/'.gitignore').read_bytes()==original_ignore
        # Update only the disposable source fixture, never the real framework.
        target=host.source/'skills/human-outcome-reporting/SKILL.md'
        target.write_text(target.read_text()+'\n<!-- synthetic update fixture -->\n')
        runtime_tests.project_install.install(host.args)
        current=list((host.project/'.datarim-runtime').rglob('human-outcome-reporting/SKILL.md'))
        assert any(path.read_bytes()==target.read_bytes() for path in current)
        assert (host.project/'AGENTS.md').read_text()=='# Original project rules\n'
    finally:
        host.doCleanups()


def test_reusable_archive_matches_allowlisted_sources(tmp_path):
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_release_pack')
    output=tmp_path/'human-outcome-reporting-0.3.3.zip'
    receipt=pack.build(ROOT,output)
    second=tmp_path/'repeat.zip';pack.build(ROOT,second)
    assert output.read_bytes()==second.read_bytes()
    expected=pack.payload(ROOT)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist())==set(expected)|{'MANIFEST.json','SHA256SUMS'}
        assert all(archive.read(name)==data for name,data in expected.items())
        manifest=json.loads(archive.read('MANIFEST.json'))
        assert manifest['files']=={name:hashlib.sha256(data).hexdigest() for name,data in sorted(expected.items())}
        assert all('..' not in Path(name).parts and not Path(name).is_absolute() for name in archive.namelist())
        assert not any(name.endswith(('.pyc','.env')) or '__pycache__' in name for name in archive.namelist())
        (tmp_path/'MANIFEST.json').write_bytes(archive.read('MANIFEST.json'))
    (tmp_path/'archive-verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    with pytest.raises(ValueError):pack.build(ROOT,output)


def test_release_example_is_partial_and_matches_renderer():
    hr=load(SKILL/'scripts/hr.py','hr_release_example')
    example=ROOT/'documentation/human-reporting/examples/partial'
    contract=hr.load_json(example/'contract.json');report=hr.load_json(example/'report.json')
    result=hr.analyse(contract,report,example)
    assert result['valid'] and not result['ready']
    assert result['coverage']['required_met']==1
    assert result['coverage']['required_total']==2
    assert hr.render(contract,report,result,language='ru').split('\n\n<!-- human-reporting-presentation')[0]+'\n'==(example/'REPORT_RU.md').read_text()


def test_live_evaluations_are_not_claimed_as_executed():
    plan=json.loads((ROOT/'documentation/human-reporting/EVALUATION_PLAN.json').read_text())
    assert plan['status']=='not_run' and len(plan['cases'])==14
    assert all(case[client]=='not_run' for case in plan['cases'] for client in ('claude','codex','cursor','reader_study'))


def test_integration_archive_contains_exact_selected_sources(tmp_path):
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_full_release')
    target=tmp_path/'integration.zip'
    receipt=pack.build(ROOT,target,'integration')
    with zipfile.ZipFile(target) as archive:
        # Assert a required dependency independently of the packager allowlist.
        assert archive.read('repository-overlay/skills/datarim-system/language-preferences.md') == \
            (ROOT/'skills/datarim-system/language-preferences.md').read_bytes()
    repeat=tmp_path/'integration-repeat.zip'
    pack.build(ROOT,repeat,'integration')
    assert target.read_bytes()==repeat.read_bytes()
    assert receipt['kind']=='integration' and receipt['version']=='0.3.3'
    with zipfile.ZipFile(target) as archive:
        for name in pack.INTEGRATION_FILES:
            assert archive.read('repository-overlay/'+name)==(ROOT/name).read_bytes()
        assert archive.read('repository-overlay/skills/human-outcome-reporting/scripts/hr.py')==(SKILL/'scripts/hr.py').read_bytes()
        assert not any('/receipts/' in name or '/.git/' in name for name in archive.namelist())
        assert 'TECHNICAL_SPEC.md' in archive.namelist()
        assert 'ACCEPTANCE_REPORT.md' in archive.namelist()
    # Preserve the tested full archive and verify its text-only download transport.
    import base64
    import lzma
    transport=tmp_path/'integration-transport.json'
    pack.export_transport(target,transport,receipt)
    exported=json.loads(transport.read_text())
    assert lzma.decompress(base64.b64decode(''.join(exported['chunks']),validate=True))==target.read_bytes()
    (tmp_path/'archive-verification.json').write_text(json.dumps(receipt,indent=2)+'\n')


def test_text_transport_roundtrip_and_no_overwrite(tmp_path):
    import base64
    import lzma
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_transport')
    archive=tmp_path/'skill.zip'
    receipt=pack.build(ROOT,archive)
    target=tmp_path/'transport.json'
    export=pack.export_transport(archive,target,receipt)
    data=json.loads(target.read_text())
    raw=lzma.decompress(base64.b64decode(''.join(data['chunks']),validate=True))
    assert raw==archive.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==receipt['sha256']
    assert export['chunks']==len(data['chunks'])
    with pytest.raises(ValueError):pack.export_transport(archive,target,receipt)
    archive.write_bytes(b'changed after packaging')
    with pytest.raises(ValueError):pack.export_transport(archive,tmp_path/'other.json',receipt)


def test_packager_rejects_source_symlinks(tmp_path):
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_symlink_pack')
    source=tmp_path/'source';source.mkdir()
    outside=tmp_path/'outside.txt';outside.write_text('not a release source')
    (source/'link.txt').symlink_to(outside)
    with pytest.raises(ValueError):pack.read_source(source,'link.txt')


def test_release_requires_matching_engine_and_skill_versions(tmp_path,monkeypatch):
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_version_pack')
    files=pack.payload(ROOT)
    original=files['human-outcome-reporting/SKILL.md']
    assert b'version: "0.3.3"' in original
    files['human-outcome-reporting/SKILL.md']=original.replace(b'version: "0.3.3"',b'version: "9.9.9"')
    assert files['human-outcome-reporting/SKILL.md'] != original
    monkeypatch.setattr(pack,'payload',lambda *args:files)
    with pytest.raises(ValueError,match='versions differ'):
        pack.build(ROOT,tmp_path/'mismatch.zip')


@pytest.mark.parametrize('language,heading', [('en','What was required'), ('ar','ما كان مطلوباً'), ('ja','要件')])
def test_extracted_standalone_archive_renders_without_repository_imports(tmp_path, language, heading):
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_extracted_locale_pack')
    output=tmp_path/'standalone.zip'
    pack.build(ROOT,output)
    extracted=tmp_path/'extracted'
    # Extract only the test-produced allowlisted archive, never an external ZIP.
    with zipfile.ZipFile(output) as archive:
        for name in archive.namelist():
            destination=extracted/name
            destination.parent.mkdir(parents=True,exist_ok=True)
            destination.write_bytes(archive.read(name))
    example=extracted/'examples/partial'
    completed=subprocess.run([sys.executable, str(extracted/'human-outcome-reporting/scripts/hr.py'),
        'render','--contract',str(example/'contract.json'),'--report',str(example/'report.json'),
        '--evidence-root',str(example),'--project',str(extracted),'--language',language],
        cwd=extracted,capture_output=True,text=True,timeout=10)
    assert completed.returncode==0, completed.stderr
    assert '## '+heading in completed.stdout
    assert 'catalog='+language in completed.stdout
    if language=='en':
        assert 'Подтверждено' not in completed.stdout
    assert not (tmp_path/'mismatch.zip').exists()


def test_portable_archive_contains_executable_installer_and_working_guide(tmp_path):
    import subprocess
    import sys
    pack=load(ROOT/'dev-tools/package-human-reporting.py','hr_installer_pack')
    target=tmp_path/'portable.zip';pack.build(ROOT,target)
    with zipfile.ZipFile(target) as archive:
        assert archive.read('install.py')==(ROOT/'scripts/human_reporting_install.py').read_bytes()
        guide=archive.read('INSTALL.md').decode()
        assert '../../INSTALL.md' not in guide and 'https://github.com/Arcanada-one/datarim/blob/main/INSTALL.md' in guide
        extracted=tmp_path/'extracted';archive.extractall(extracted)
    home=tmp_path/'home';home.mkdir()
    cmd=[sys.executable,str(extracted/'install.py'),'install','--home',str(home)]
    completed=subprocess.run(cmd,capture_output=True,text=True,check=True)
    assert json.loads(completed.stdout)['verdict']=='installed'
    assert (home/'.agents/skills/human-outcome-reporting/SKILL.md').read_bytes()==(SKILL/'SKILL.md').read_bytes()
    subprocess.run([sys.executable,str(extracted/'install.py'),'check','--home',str(home)],capture_output=True,text=True,check=True)
