#!/usr/bin/env python3
"""Read-only binding of a reporting projection to explicitly selected task sources.

Prints JSON or a human report. Does not write files, run checks, discover unrelated
projects, change task frontmatter, or grant authority to a glossary's contents.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone, timedelta
import importlib.util
import json
from pathlib import Path
import re
import sys

_spec = importlib.util.spec_from_file_location('hr_native_engine', Path(__file__).with_name('hr.py'))
hr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hr)
ROLES = {'task_brief', 'task_description', 'plan', 'prd', 'expectations', 'verification', 'glossary'}
REQUIRED = {'task_brief', 'task_description'}

def selection_errors(contract: dict, selection: dict) -> list[str]:
    errors = hr.contract_errors(contract)
    if errors:
        return errors
    if not isinstance(selection, dict) or set(selection) != {'sources', 'requirement_sources'}:
        return ['Selection must contain exactly sources and requirement_sources.']
    sources, mappings = selection['sources'], selection['requirement_sources']
    if not isinstance(sources, list) or not 1 <= len(sources) <= 200:
        return ['Select between 1 and 200 explicit source files.']
    paths, roles = set(), set()
    for item in sources:
        if not isinstance(item, dict) or set(item) != {'path', 'role'}:
            errors.append('Each source needs exactly path and role.');continue
        if not isinstance(item['path'], str) or not item['path'] or len(item['path']) > 2000:
            errors.append('Invalid source path.');continue
        if not isinstance(item['role'], str) or item['role'] not in ROLES:
            errors.append('Unknown source role.');continue
        if item['path'] in paths:
            errors.append('Duplicate source path.')
        paths.add(item['path']);roles.add(item['role'])
    needed = REQUIRED | ({'plan'} if contract['plan_steps'] else set())
    if not needed <= roles:
        errors.append('Missing canonical source role: '+', '.join(sorted(needed-roles)))
    expected = {r['id'] for r in contract['requirements']}
    if not isinstance(mappings, dict) or set(mappings) != expected:
        errors.append('Every requirement needs an explicit source mapping; unknown requirements are rejected.')
    else:
        allowed = {s['path'] for s in sources if isinstance(s, dict) and s.get('role') != 'glossary' and isinstance(s.get('path'), str)}
        for rid, refs in mappings.items():
            if not isinstance(refs, list) or not refs or any(not isinstance(p, str) or p not in allowed for p in refs):
                errors.append('Requirement source mapping is missing, unknown, or points only to terminology: '+rid)
    return errors

def snapshot(project: Path, contract: dict, selection: dict) -> dict:
    errors = selection_errors(contract, selection)
    if errors:
        raise hr.ReportError('; '.join(errors))
    sources = []
    for item in selection['sources']:
        path = hr.safe_evidence_path(project, item['path'])
        sources.append({**item, 'sha256': hr.file_hash(path, hr.MAX_JSON)})
    return {'schema':'hr-source-snapshot/1', 'task_id':contract['task']['id'],
            'contract_sha256':hr.canonical_hash(contract), 'created_at':hr.stamp(),
            'sources':sources, 'requirement_sources':selection['requirement_sources']}

def verify(project: Path, contract: dict, manifest: dict) -> list[str]:
    errors = []
    expected = {'schema','task_id','contract_sha256','created_at','sources','requirement_sources'}
    if not isinstance(manifest, dict) or set(manifest) != expected:
        return ['Invalid source snapshot fields.']
    if manifest['schema'] != 'hr-source-snapshot/1':
        errors.append('Unsupported source snapshot version.')
    try:
        if hr.parse_time(manifest['created_at']) > datetime.now(timezone.utc)+timedelta(minutes=5):
            errors.append('Source snapshot timestamp is in the future.')
    except (TypeError, ValueError):
        errors.append('Invalid source snapshot timestamp.')
    if hr.contract_errors(contract):
        return errors + hr.contract_errors(contract)
    if manifest['task_id'] != contract['task']['id'] or manifest['contract_sha256'] != hr.canonical_hash(contract):
        errors.append('Task or baseline differs from the source snapshot.')
    if not isinstance(manifest['sources'], list):
        return errors + ['Snapshot sources must be an array.']
    selection = {'sources':[], 'requirement_sources':manifest['requirement_sources']}
    for item in manifest['sources']:
        if not isinstance(item, dict) or set(item) != {'path','role','sha256'}:
            errors.append('Invalid source snapshot entry.');continue
        selection['sources'].append({'path':item['path'],'role':item['role']})
        try:
            if not isinstance(item['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', item['sha256']):
                raise hr.ReportError('Invalid source digest.')
            path = hr.safe_evidence_path(project, item['path'])
            if hr.file_hash(path, hr.MAX_JSON) != item['sha256']:
                errors.append('Canonical source changed: '+item['path'])
        except (OSError, TypeError, ValueError) as exc:
            errors.append('Source could not be verified: '+str(exc))
    return errors + selection_errors(contract, selection)

def main(argv=None):
    parser = argparse.ArgumentParser(description='Read-only Datarim source binding and report finalization')
    parser.add_argument('command', choices=('snapshot','verify','finalize'))
    parser.add_argument('--project', required=True)
    parser.add_argument('--contract', required=True)
    parser.add_argument('--selection')
    parser.add_argument('--snapshot')
    parser.add_argument('--report')
    parser.add_argument('--evidence-root')
    args = parser.parse_args(argv)
    try:
        project = Path(args.project).resolve(strict=True)
        contract = hr.load_json(hr.safe_evidence_path(project, args.contract))
        if args.command == 'snapshot':
            if not args.selection:parser.error('--selection is required')
            selection = hr.load_json(hr.safe_evidence_path(project, args.selection))
            print(json.dumps(snapshot(project,contract,selection),ensure_ascii=False,indent=2));return 0
        if not args.snapshot:parser.error('--snapshot is required')
        manifest = hr.load_json(hr.safe_evidence_path(project,args.snapshot))
        errors = verify(project,contract,manifest)
        if errors or args.command == 'verify':
            print(json.dumps({'valid':not errors,'errors':errors},ensure_ascii=False,indent=2))
            return 2 if errors else 0
        if not args.report:parser.error('--report is required')
        report = hr.load_json(hr.safe_evidence_path(project,args.report))
        root = Path(args.evidence_root).resolve(strict=True) if args.evidence_root else project
        if not root.is_relative_to(project):raise hr.ReportError('Evidence root must be within the selected project.')
        result = hr.analyse(contract,report,root,expected_hash=manifest['contract_sha256'])
        if not result['valid']:
            print(json.dumps(result,ensure_ascii=False,indent=2));return 2
        text = hr.render(contract,report,result)
        findings = hr.lint(text)
        if findings:
            print(json.dumps({'language_findings':findings},ensure_ascii=False),file=sys.stderr);return 2
        print(text)
        return 0 if result['ready'] else 3
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        print('Source binding error: '+str(exc),file=sys.stderr);return 2

if __name__ == '__main__':
    raise SystemExit(main())
