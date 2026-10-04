#!/usr/bin/env python3
"""Read-only assessment of task reports. No command execution or file mutation.

Python 3.10+, standard library. Evidence integrity is not executor authentication.
The caller owns source selection, native verification, and acceptance authority.
"""
from __future__ import annotations
import argparse
from collections import Counter, deque
from datetime import datetime, timezone, timedelta
import hashlib
import html
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
from typing import Any
import unicodedata


def _sibling(name):
    spec = importlib.util.spec_from_file_location('human_reporting_' + name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


presentation = _sibling('presentation')


def preferences(*, language=None, project=None):
    return _sibling('language').resolve_preferences(project=project, replies=language)

VERSION = '0.3.1'
BASE = Path(__file__).resolve().parents[1]
MAX_JSON = 2 * 1024 * 1024
MAX_EVIDENCE = 16 * 1024 * 1024
# Terminal commands and invisible direction controls can hide or reorder verdicts.
# Preserve normal whitespace and natural-language ZWNJ/ZWJ (U+200C/U+200D).
UNSAFE_CONTROLS = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u061c\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]')

class ReportError(ValueError):
    pass

def stamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')

def parse_time(value: str) -> datetime:
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})', value):
        raise ValueError('timestamp must use RFC3339 with timezone')
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)

def canonical_hash(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')
    return hashlib.sha256(raw).hexdigest()

def file_hash(path: Path, limit: int = MAX_EVIDENCE) -> str:
    if not path.is_file():
        raise ReportError('Evidence is not a regular file')
    h, size = hashlib.sha256(), 0
    with path.open('rb') as stream:
        while block := stream.read(65536):
            size += len(block)
            if size > limit:
                raise ReportError('Evidence exceeds the configured size limit')
            h.update(block)
    return h.hexdigest()

def _pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ReportError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result

def load_json(path: str | Path, limit: int = MAX_JSON) -> Any:
    path = Path(path)
    if path.stat().st_size > limit:
        raise ReportError('JSON input exceeds the configured size limit')
    def invalid_constant(value):
        raise ReportError(f'Non-finite JSON number: {value}')
    with path.open('r', encoding='utf-8') as stream:
        return json.load(stream, object_pairs_hook=_pairs, parse_constant=invalid_constant)

def schema_errors(value: Any, schema: dict, path: str = '$') -> list[str]:
    """Validate only the JSON Schema vocabulary used by the bundled schemas."""
    errors = []
    checks = {
        'object': lambda x: isinstance(x, dict), 'array': lambda x: isinstance(x, list),
        'string': lambda x: isinstance(x, str), 'boolean': lambda x: isinstance(x, bool),
        'integer': lambda x: isinstance(x, int) and not isinstance(x, bool),
        'number': lambda x: isinstance(x, (int, float)) and not isinstance(x, bool),
        'null': lambda x: x is None,
    }
    types = schema.get('type')
    if types:
        types = [types] if isinstance(types, str) else types
        if not any(checks[t](value) for t in types):
            return [f'{path}: expected {"|".join(types)}']
    if 'enum' in schema and value not in schema['enum']:
        errors.append(f'{path}: value is outside the allowed enumeration')
    if isinstance(value, dict):
        props = schema.get('properties', {})
        for key in schema.get('required', []):
            if key not in value:
                errors.append(f'{path}.{key}: required field is missing')
        for key, item in value.items():
            if key in props:
                errors.extend(schema_errors(item, props[key], f'{path}.{key}'))
            elif schema.get('additionalProperties') is False:
                errors.append(f'{path}.{key}: unknown field')
    elif isinstance(value, list):
        if len(value) < schema.get('minItems', 0) or len(value) > schema.get('maxItems', float('inf')):
            errors.append(f'{path}: array length is out of bounds')
        if schema.get('uniqueItems') and len({canonical_hash(x) for x in value}) != len(value):
            errors.append(f'{path}: duplicate array item')
        for i, item in enumerate(value):
            errors.extend(schema_errors(item, schema.get('items', {}), f'{path}[{i}]'))
    elif isinstance(value, str):
        if UNSAFE_CONTROLS.search(value):
            errors.append(f'{path}: terminal or invisible display control is not allowed')
        if len(value) < schema.get('minLength', 0) or len(value) > schema.get('maxLength', float('inf')):
            errors.append(f'{path}: string length is out of bounds')
        if schema.get('minLength', 0) and not value.strip():
            errors.append(f'{path}: whitespace-only text is not allowed')
        if 'pattern' in schema and not re.search(schema['pattern'], value):
            errors.append(f'{path}: string does not match the required pattern')
        if schema.get('format') == 'date-time':
            try:
                parse_time(value)
            except (ValueError, TypeError):
                errors.append(f'{path}: invalid RFC3339 timestamp or missing timezone')
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if value < schema.get('minimum', -float('inf')) or value > schema.get('maximum', float('inf')):
            errors.append(f'{path}: numeric value is out of bounds')
    return errors[:200]

def validate_shape(value: Any, name: str) -> list[str]:
    return schema_errors(value, load_json(BASE / 'schemas' / f'{name}.schema.json'))

def safe_evidence_path(root: Path, relative: str) -> Path:
    """Read regular local evidence only, never network or symlink targets."""
    if '\\' in relative or re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', relative):
        raise ReportError('Evidence must use a local relative POSIX path')
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ReportError('Evidence path escapes its root')
    root = root.resolve(strict=True)
    candidate = root
    for part in path.parts:
        if part in {'.ssh', '.gnupg', '.aws', '.env', 'credentials'} or part.startswith('.env.') or part.endswith(('.pem', '.key')):
            raise ReportError('Sensitive paths are not evidence inputs')
        candidate /= part
        if candidate.is_symlink():
            raise ReportError('Symlinked evidence is not accepted')
    resolved = candidate.resolve(strict=True)
    if not resolved.is_relative_to(root) or not resolved.is_file():
        raise ReportError('Evidence must be a regular file inside its root')
    return resolved

def index(items: list[dict], key: str, label: str, errors: list[str]) -> dict:
    counts = Counter(x[key] for x in items)
    for name, count in counts.items():
        if count > 1:
            errors.append(f'{label}: duplicate identifier {name}')
    return {x[key]: x for x in items}

def reference_errors(ids: list[str], target: dict, label: str, errors: list[str]) -> None:
    for name in ids:
        if name not in target:
            errors.append(f'{label}: dangling reference {name}')

def contract_errors(contract: dict) -> list[str]:
    errors = validate_shape(contract, 'task-contract')
    if errors:
        return errors
    req = index(contract['requirements'], 'id', 'requirements', errors)
    ac = index(contract['criteria'], 'id', 'criteria', errors)
    steps = index(contract['plan_steps'], 'id', 'plan_steps', errors)
    index(contract['questions'], 'id', 'questions', errors)
    index([v for c in ac.values() for v in c['verification']], 'id', 'verification', errors)
    if contract['approval']['state'] == 'confirmed':
        if not contract['approval']['by'].strip() or not contract['approval']['record'].strip():
            errors.append('confirmed baseline needs an approver and an approval record')
    for c in ac.values():
        if not c['requirement_ids']:
            errors.append(f'{c["id"]}: criterion needs a source requirement')
        reference_errors(c['requirement_ids'], req, c['id'], errors)
        if c['applicability'] == 'not_applicable' and 'exclusion' not in c:
            errors.append(f'{c["id"]}: exclusion needs reason, approver and record')
        if c['applicability'] == 'applicable' and 'exclusion' in c:
            errors.append(f'{c["id"]}: applicable criterion must not carry an exclusion')
    for s in steps.values():
        reference_errors(s['criterion_ids'], ac, s['id'], errors)
        reference_errors(s['depends_on'], steps, s['id'], errors)
    degree = {k: len(v['depends_on']) for k, v in steps.items()}
    dependents = {k: [] for k in steps}
    for key, s in steps.items():
        for dep in s['depends_on']:
            if dep in dependents:
                dependents[dep].append(key)
    queue = deque(k for k, value in degree.items() if not value)
    visited = 0
    while queue:
        node = queue.popleft()
        visited += 1
        for child in dependents[node]:
            degree[child] -= 1
            if degree[child] == 0:
                queue.append(child)
    if visited != len(steps):
        errors.append('plan_steps: dependency cycle or unresolved dependency')
    return errors

def analyse(contract: dict, report: dict, evidence_root: Path | None = None,
            expected_hash: str | None = None, max_age_hours: float | None = None,
            now: datetime | None = None) -> dict:
    errors = contract_errors(contract) + validate_shape(report, 'report')
    result = {'valid': False, 'ready': False, 'readiness': 'invalid', 'errors': errors,
              'warnings': [], 'criteria': {}, 'verification': {}, 'evidence': {},
              'unproven_outcomes': [], 'unfinished_steps': [], 'unanswered_questions': [],
              'unmapped_requirements': [], 'unplanned_criteria': [],
              'contract_sha256': canonical_hash(contract), 'baseline_pinned': expected_hash is not None}
    if max_age_hours is not None and (not isinstance(max_age_hours, (int, float)) or
                                    isinstance(max_age_hours, bool) or
                                    not math.isfinite(max_age_hours) or max_age_hours <= 0):
        errors.append('max_age_hours must be a finite positive number')
    if errors:
        return result
    result.update(subject_revision=report['subject_revision'], run_id=report['run_id'])
    now = now or datetime.now(timezone.utc)
    when = parse_time(report['generated_at'])
    if when > now + timedelta(minutes=5):
        errors.append('report timestamp is in the future')
    if report['task_id'] != contract['task']['id']:
        errors.append('report belongs to another task')
    if report['contract_sha256'] != result['contract_sha256']:
        errors.append('report references another baseline revision')
    if expected_hash is not None and expected_hash != result['contract_sha256']:
        errors.append('contract differs from the externally pinned baseline')
    ac = {c['id']: c for c in contract['criteria']}
    steps = {s['id']: s for s in contract['plan_steps']}
    questions = {q['id']: q for q in contract['questions']}
    verifications = {v['id']: {**v, 'criterion_id': c['id']} for c in ac.values() for v in c['verification']}
    checks = index(report['checks'], 'id', 'checks', errors)
    evidence = index(report['evidence'], 'id', 'evidence', errors)
    index(report['outcomes'], 'id', 'outcomes', errors)
    progress = index(report['plan_progress'], 'step_id', 'plan_progress', errors)
    answers = index(report['answers'], 'question_id', 'answers', errors)
    reference_errors(list(progress), steps, 'plan_progress', errors)
    reference_errors(list(answers), questions, 'answers', errors)
    pairs = Counter((c['verification_id'], c['attempt']) for c in checks.values())
    for pair, count in pairs.items():
        if count > 1:
            errors.append(f'checks: duplicate verification/attempt pair {pair}')
    for c in checks.values():
        reference_errors([c['verification_id']], verifications, c['id'], errors)
        reference_errors(c['evidence_ids'], evidence, c['id'], errors)
        reference_errors(c['supersedes'], checks, c['id'], errors)
        for old_id in c['supersedes']:
            old = checks.get(old_id)
            if old and (old['verification_id'] != c['verification_id'] or old['attempt'] >= c['attempt'] or
                        parse_time(old['observed_at']) > parse_time(c['observed_at'])):
                errors.append(f'{c["id"]}: invalid explicit supersession')
    for o in report['outcomes']:
        reference_errors(o['criterion_ids'], ac, o['id'], errors)
        reference_errors(o['plan_step_ids'], steps, o['id'], errors)
        reference_errors(o['evidence_ids'], evidence, o['id'], errors)
        if o['plan_step_ids']:
            linked = {cid for sid in o['plan_step_ids'] if sid in steps for cid in steps[sid]['criterion_ids']}
            if not set(o['criterion_ids']).issubset(linked):
                errors.append(f'{o["id"]}: outcome criteria are not covered by its plan steps')
    for a in report['next_actions']:
        reference_errors(a['criterion_ids'], ac, 'next_actions', errors)
    reference_errors(report['delivery']['evidence_ids'], evidence, 'delivery', errors)
    if errors:
        return result
    warnings = result['warnings']
    if not result['baseline_pinned']:
        warnings.append('Baseline identity is checked against the supplied file, not an external trust anchor.')
    if contract['approval']['state'] != 'confirmed':
        warnings.append('Acceptance baseline is proposed, not confirmed.')
    unplanned = {c['id'] for c in ac.values() if c['required'] and c['applicability'] == 'applicable'} - {cid for s in steps.values() for cid in s['criterion_ids']}
    orphan_req = {r['id'] for r in contract['requirements']} - {rid for c in ac.values() for rid in c['requirement_ids']}
    result['unplanned_criteria'] = sorted(unplanned)
    result['unmapped_requirements'] = sorted(orphan_req)
    if unplanned:
        warnings.append('Required criteria without a plan step: ' + ', '.join(sorted(unplanned)))
    if orphan_req:
        warnings.append('Requirements without acceptance criteria: ' + ', '.join(sorted(orphan_req)))
    for e in evidence.values():
        state = {'valid': True, 'reason': '', 'receipt': None}
        try:
            if e['run_id'] != report['run_id']:
                raise ReportError('Evidence is from another run')
            if e['subject_revision'] != report['subject_revision']:
                raise ReportError('Evidence is from another product revision')
            if evidence_root is None:
                raise ReportError('Evidence root was not supplied; file bytes were not checked')
            path = safe_evidence_path(evidence_root, e['path'])
            if file_hash(path) != e['sha256']:
                raise ReportError('Evidence hash does not match its bytes')
            if e['kind'] == 'execution':
                receipt = load_json(path)
                errs = validate_shape(receipt, 'execution-receipt')
                if errs:
                    raise ReportError('Invalid execution receipt: ' + '; '.join(errs[:3]))
                for key, expected in [('task_id', report['task_id']), ('contract_sha256', result['contract_sha256']),
                                      ('run_id', report['run_id']), ('subject_revision', report['subject_revision'])]:
                    if receipt[key] != expected:
                        raise ReportError('Execution receipt binding mismatch: ' + key)
                if parse_time(receipt['started_at']) > parse_time(receipt['ended_at']):
                    raise ReportError('Execution receipt has reversed timestamps')
                if parse_time(receipt['ended_at']) > when + timedelta(minutes=5):
                    raise ReportError('Execution receipt is newer than the report')
                if max_age_hours is not None and (now - parse_time(receipt['ended_at'])).total_seconds() > max_age_hours * 3600:
                    raise ReportError('Execution receipt is older than the permitted evidence age')
                state['receipt'] = receipt
        except (OSError, ValueError, TypeError, RecursionError) as exc:
            state.update(valid=False, reason=type(exc).__name__ + ': ' + str(exc))
            warnings.append(f'Evidence {e["id"]} is not verified: {state["reason"]}')
        result['evidence'][e['id']] = state
    superseded = {old for c in checks.values() for old in c['supersedes']}
    for vid, v in verifications.items():
        active = [c for c in checks.values() if c['verification_id'] == vid and c['id'] not in superseded]
        effective, details = [], []
        for c in active:
            status, reason = c['status'], c['summary']
            observed = parse_time(c['observed_at'])
            stale = c['subject_revision'] != report['subject_revision'] or c['environment'] != v['environment']
            stale = stale or observed > when + timedelta(minutes=5)
            if max_age_hours is not None:
                stale = stale or (now - observed).total_seconds() > max_age_hours * 3600
            if stale:
                status, reason = 'not_verified', 'Проверка относится к другой версии, среде или недопустимому времени.'
            elif status == 'passed':
                es = [evidence[eid] for eid in c['evidence_ids']]
                valid_es = [e for e in es if result['evidence'][e['id']]['valid']]
                required_kind = {'automated': 'execution', 'manual': 'manual_review', 'inspection': 'inspection', 'research': 'research_source'}[v['method']]
                suitable = [e for e in valid_es if e['kind'] == required_kind]
                if not es or len(valid_es) != len(es) or not suitable:
                    status, reason = 'not_verified', 'Заявлен успех, но подходящее подтверждение не проверено.'
                elif v['method'] == 'automated':
                    receipts = [result['evidence'][e['id']]['receipt'] for e in suitable]
                    matching = [r for r in receipts if r and r['verification_id'] == vid and r['environment'] == v['environment']]
                    if not matching or any(r['exit_code'] != 0 or r['timed_out'] or r['output_limit_exceeded'] for r in matching):
                        status, reason = 'not_verified', 'Квитанция запуска не подтверждает успешное завершение этой проверки.'
                if status == 'not_verified':
                    warnings.append(c['id'] + ': ' + reason)
            elif status in {'not_run', 'skipped'}:
                status = 'not_verified'
                prefix = 'Проверка не запускалась. ' if c['status'] == 'not_run' else 'Проверка пропущена; это не подтверждение выполнения. '
                reason = reason if c['status'] == 'not_run' and re.search(r'не запуск|не провод', reason, re.I) else prefix + reason
            effective.append(status)
            details.append({'check_id': c['id'], 'status': status, 'summary': reason})
        if 'passed' in effective and 'failed' in effective:
            status = 'conflict'
        elif 'failed' in effective:
            status = 'failed'
        elif 'blocked' in effective:
            status = 'blocked'
        elif effective and all(x == 'passed' for x in effective):
            status = 'passed'
        else:
            status = 'not_verified'
        result['verification'][vid] = {'status': status, 'details': details, 'environment': v['environment'], 'expectation': v['expectation']}
    for cid, c in ac.items():
        statuses = [result['verification'][v['id']]['status'] for v in c['verification']]
        if c['applicability'] == 'not_applicable':
            state = 'not_applicable'
        elif 'conflict' in statuses:
            state = 'conflict'
        elif 'failed' in statuses:
            state = 'failed'
        elif 'blocked' in statuses:
            state = 'blocked'
        elif statuses and all(s == 'passed' for s in statuses):
            state = 'met'
        elif 'passed' in statuses:
            state = 'partial'
        else:
            state = 'not_verified'
        result['criteria'][cid] = state
    for o in report['outcomes']:
        if o['kind'] == 'observed' and (not o['criterion_ids'] or not o['plan_step_ids'] or not o['evidence_ids'] or any(not result['evidence'][e]['valid'] for e in o['evidence_ids'])):
            result['unproven_outcomes'].append(o['id'])
    required = [c for c in ac.values() if c['required'] and c['applicability'] == 'applicable']
    met = sum(result['criteria'][c['id']] == 'met' for c in required)
    for sid, s in steps.items():
        relevant = any(ac[c]['required'] and ac[c]['applicability'] == 'applicable' for c in s['criterion_ids'])
        if relevant and progress.get(sid, {}).get('status') != 'done':
            result['unfinished_steps'].append(sid)
        if progress.get(sid, {}).get('status') == 'done' and any(progress.get(dep, {}).get('status') != 'done' for dep in s['depends_on']):
            warnings.append(f'Plan step {sid} is done while a dependency is not done.')
            if sid not in result['unfinished_steps']:
                result['unfinished_steps'].append(sid)
    result['unanswered_questions'] = [qid for qid, q in questions.items() if q['required'] and answers.get(qid, {}).get('status') != 'answered']
    delivery = report['delivery']['state']
    if delivery in {'staging', 'production'}:
        evid = report['delivery']['evidence_ids']
        if not evid or any(not result['evidence'][e]['valid'] for e in evid):
            delivery = 'unknown'
            warnings.append('Deployment was claimed, but its evidence was not verified.')
    result['delivery_state'] = delivery
    result['coverage'] = {'required_met': met, 'required_total': len(required),
                          'excluded': sum(c['applicability'] == 'not_applicable' for c in ac.values()),
                          'optional_total': sum(not c['required'] and c['applicability'] == 'applicable' for c in ac.values()),
                          'ratio': met / len(required) if required else None}
    blocking = bool(report['blockers'] or any(r['blocks_acceptance'] for r in report['risks']))
    incomplete = (met != len(required) or bool(result['unproven_outcomes']) or bool(result['unfinished_steps'])
                  or bool(result['unanswered_questions']) or bool(orphan_req) or bool(unplanned)
                  or (report['delivery']['state'] in {'staging', 'production'} and delivery == 'unknown'))
    if not required:
        readiness = 'no_criteria'
    elif blocking:
        readiness = 'blocked'
    elif contract['approval']['state'] != 'confirmed':
        readiness = 'proposed'
    elif incomplete:
        readiness = 'incomplete'
    else:
        readiness = 'checks_complete'
    result.update(valid=True, readiness=readiness, ready=readiness == 'checks_complete')
    return result

# Heuristic language checks are not a security boundary or grammar parser.
# These constants are match rules and replacement labels, never credential values.
REDACTION_RULES = [
    (r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----', '[REDACTED SECRET]'),
    (r'(?i)\b(authorization\s*:\s*bearer)\s+[^\s,;]+', r'\1 [REDACTED SECRET]'),
    (r'(?i)\b((?:api[_-]?key|access[_-]?token|password|secret|[a-z][a-z0-9_]*_token)\s*[=:]\s*)[^\s,;&]+', r'\1[REDACTED SECRET]'),
    (r'\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})\b', '[REDACTED SECRET]'),
]
POINTER_PATTERNS = [
    r'как\s+(?:мы\s+)?(?:обсуждали|договорились)',
    r'(?:из|в)\s+предыдущ(?:его|ем)\s+(?:контекст[ае]?|диалог[ае]?|чат[ае]?)',
    r'см\.?\s+(?:контекст|переписку|предыдущий ответ)',
    r'\b(?:thread_id|conversation_id|turn\d+(?:view|file|search)\d+)\b',
    r'(?:/Users/|/home/|/mnt/data/|\.ai-bridge/|\.datarim-runtime/)',
]

def redact(text: str) -> str:
    for pattern, replacement in REDACTION_RULES:
        text = re.sub(pattern, replacement, text, flags=re.DOTALL)
    return text

def human(text: str) -> str:
    # Defense for direct callers as well as schema-validated report rendering.
    # Expose rejected bytes visibly instead of silently changing their meaning.
    text = UNSAFE_CONTROLS.sub(lambda match: f'[unsafe-control U+{ord(match.group()):04X}]', text)
    value = html.escape(' '.join(redact(text).split()), quote=False)
    return re.sub(r'([\\`*_\[\]])', r'\\\1', value)

COUNT_UNIT_JOIN = re.compile(r'(?i)\d+(?:fitdays?|fits?|days?|jobs?|hosts?|files?|roles?|reports?)(?:/host)?')
SPACING_JOINS = re.compile(
    r'[\u0410-\u044f\u0401\u0451][0-9]|[0-9][\u0410-\u044f\u0401\u0451]|'
    r'(?i:\b\d+(?:fitdays?|fits?|days?|jobs?|hosts?|files?|roles?|reports?)(?:/host)?\b)|'
    r'(?i:\b(?:version|report|role|chapter|section|rapport|rôle)\d)|'
    r'(?i:\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
    r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\d{4}\b)')

def prose_spacing_join(text: str) -> bool:
    if SPACING_JOINS.search(text):
        return True
    spaced_scripts = ('CYRILLIC', 'GREEK', 'ARABIC', 'HEBREW', 'DEVANAGARI', 'BENGALI',
                      'GURMUKHI', 'GUJARATI', 'ORIYA', 'TAMIL', 'TELUGU', 'KANNADA', 'MALAYALAM')
    # Combining vowel/accent signs belong to the preceding letter, not a gap.
    letters = ''.join(char for char in text if not unicodedata.category(char).startswith('M'))
    for left, right in zip(letters, letters[1:]):
        letter = right if left.isdecimal() else left if right.isdecimal() else ''
        if letter.isalpha() and unicodedata.name(letter, '').startswith(spaced_scripts):
            return True
    # A lowercase Latin word with diacritics is prose; keep opaque Product2-style
    # names and existing ASCII identifier exemptions unchanged.
    for token in re.findall(r'[^\W_]+', text):
        if token[0].islower() and any(char.isdecimal() for char in token) and any(
            ord(char) > 127 and unicodedata.name(char, '').startswith('LATIN')
            for char in token
        ):
            return True
    return False

def spacing_prose(text: str) -> str:
    """Mask recognizable literal surfaces for advisory lint, never for rendering."""
    text = re.sub(r'(?s)<!-- gate:literal -->.*?(?:<!-- /gate:literal -->|\Z)', ' ', text)
    lines, fence = [], None
    for line in text.splitlines():
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
            lines.append('')
        elif marker:
            fence = marker[1]
            lines.append('')
        else:
            lines.append('' if line.startswith(('    ', '\t')) else line)
    text = '\n'.join(lines)
    text = re.sub(r'(?s)(`+)(?!`).*?(?<!`)\1(?!`)', ' ', text)
    text = re.sub(r'(?<=\])\([^\n]*?\)', ' ', text)
    text = re.sub(r'(?m)^ {0,3}\[[^\n]+\]:[^\n]*$', ' ', text)
    text = re.sub(r'(?s)<!--.*?-->|<[^>\n]+>', ' ', text)
    text = re.sub(r'\b(?:https?://|www\.)[^\s<>]+', ' ', text)
    # Relative paths are opaque, except the explicitly recognized human count unit.
    text = re.sub(r'(?<!\w)[\w.~:-]*[/\\][\w./\\~:-]+',
                  lambda m: m[0] if COUNT_UNIT_JOIN.fullmatch(m[0]) else ' ', text)
    text = re.sub(r'\b[\w-]+\.[a-zA-Z][\w.-]*\b', ' ', text)
    # Components exclude their separator, preventing ambiguous nested repetition.
    text = re.sub(r'\b[^\W_]+(?:\\?_[^\W_]+)+\b|\b[A-Z\u0400-\u04ff]+-\d+\b', ' ', text)
    return text

def lint(text: str, *, language: str = 'en') -> list[dict[str, str]]:
    messages = presentation.Presentation(language)
    findings = []
    if UNSAFE_CONTROLS.search(text):
        findings.append({'code': 'unsafe-control', 'severity': 'error', 'message': messages.text('lint.unsafe-control')})
    if redact(text) != text:
        findings.append({'code': 'secret-like', 'severity': 'error', 'message': messages.text('lint.secret-like')})
    for pattern in POINTER_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            findings.append({'code': 'context-pointer', 'severity': 'warning', 'message': messages.text('lint.context-pointer')})
    if re.search(r'\b(?:AC|REQ|STEP|EVIDENCE|RUN)[-_]\d+\b', text):
        findings.append({'code': 'naked-id', 'severity': 'warning', 'message': messages.text('lint.naked-id')})
    if re.search(r'(?i)\b(?:всё готово|все готово|полностью завершено|100\s*%\s*готов)', text):
        findings.append({'code': 'absolute-completion', 'severity': 'warning', 'message': messages.text('lint.absolute-completion')})
    if re.search(r'(?i)\b(?:в рамках|на текущий момент|следует отметить)\b', text):
        findings.append({'code': 'bureaucratic', 'severity': 'warning', 'message': messages.text('lint.bureaucratic')})
    if prose_spacing_join(spacing_prose(text)):
        findings.append({'code': 'prose-spacing', 'severity': 'warning', 'message': messages.text('lint.prose-spacing')})
    return findings

def has_blocking_lint(findings: list[dict[str, str]]) -> bool:
    """Spacing advice does not suppress reports; retain all existing lint gates."""
    return any(x['code'] != 'prose-spacing' for x in findings)

def trace_graph(contract: dict, report: dict) -> dict:
    """Task-local graph, not the native Datarim framework topology schema."""
    nodes, edges = [], []
    def node(kind, id_, label):
        nodes.append({'id': kind + ':' + id_, 'type': kind, 'label': label})
    def edge(a, relation, b):
        edges.append({'from': a, 'relation': relation, 'to': b})
    tid = contract['task']['id']
    node('task', tid, contract['task']['goal'])
    for r in contract['requirements']:
        node('requirement', r['id'], r['text']); edge('task:' + tid, 'requires', 'requirement:' + r['id'])
    for c in contract['criteria']:
        node('criterion', c['id'], c['text'])
        for r in c['requirement_ids']:
            edge('requirement:' + r, 'has_acceptance_criterion', 'criterion:' + c['id'])
        for v in c['verification']:
            node('verification', v['id'], v['expectation']); edge('criterion:' + c['id'], 'verified_by', 'verification:' + v['id'])
    for s in contract['plan_steps']:
        node('step', s['id'], s['title'])
        for c in s['criterion_ids']: edge('criterion:' + c, 'implemented_by', 'step:' + s['id'])
        for dep in s['depends_on']: edge('step:' + s['id'], 'depends_on', 'step:' + dep)
    for e in report['evidence']: node('evidence', e['id'], e['summary'])
    for c in report['checks']:
        node('check', c['id'], c['summary']); edge('verification:' + c['verification_id'], 'attempted_by', 'check:' + c['id'])
        for e in c['evidence_ids']: edge('check:' + c['id'], 'supported_by', 'evidence:' + e)
        for old in c['supersedes']: edge('check:' + c['id'], 'supersedes', 'check:' + old)
    for o in report['outcomes']:
        node('outcome', o['id'], o['text'])
        for c in o['criterion_ids']: edge('outcome:' + o['id'], 'addresses', 'criterion:' + c)
        for s in o['plan_step_ids']: edge('step:' + s, 'produced', 'outcome:' + o['id'])
        for e in o['evidence_ids']: edge('outcome:' + o['id'], 'supported_by', 'evidence:' + e)
    return {'schema': 'human-reporting-task-graph/1', 'task_id': tid, 'nodes': nodes, 'edges': edges}

def check_summary(detail: dict, source: dict, catalog) -> str:
    """Translate generated safety explanations, preserving submitted check prose."""
    summary = detail['summary']
    if summary == source['summary']:
        return human(summary)
    # The assessment JSON retains its historical messages and machine statuses.
    original = presentation.Presentation('ru')
    for key in ('stale', 'unsupported_success', 'receipt'):
        if summary == original.text('reason.' + key):
            return catalog.text('reason.' + key)
    for key in ('not_run', 'skipped'):
        if summary == original.text('reason.' + key) + source['summary']:
            return catalog.text('reason.' + key) + human(source['summary'])
    return human(summary)

def render(contract: dict, report: dict, result: dict, *, brief: bool = False, previous: dict | None = None,
           language: str | None = None, project: str | Path | None = None) -> str:
    if not result['valid']:
        raise ReportError('Cannot render a normal report with invalid bindings or structure; run validate.')
    resolved = preferences(language=language, project=project)
    catalog = presentation.Presentation(resolved['replies'])
    t = catalog.text
    checks = {check['id']: check for check in report['checks']}
    statuses = {key: t('status.' + key) for key in
                ('met', 'failed', 'blocked', 'partial', 'not_verified', 'conflict', 'not_applicable')}
    profile = report['profile'] if report['profile'] != 'auto' else contract['task']['type']
    coverage = result['coverage']
    first = t('headline.' + result['readiness'])
    if report['kind'] == 'progress':
        first = t('progress', stage=human(report['stage']))
    elif report['kind'] == 'blocked':
        first = t('stopped', headline=first)
    lines = [f'**{human(contract["task"]["title"])}.** {first}', '', '## ' + t('requirements'), '',
             human(contract['task']['context']), '', human(contract['task']['goal'])]
    if report['outcomes']:
        lines += ['', '## ' + t('profile.' + profile), '']
        outcomes = report['outcomes']
        if brief:
            priority = {o['id'] for o in outcomes if o['kind'] != 'observed' or o['id'] in result['unproven_outcomes']}
            priority.update(o['id'] for o in outcomes[:5])
            outcomes = [o for o in outcomes if o['id'] in priority]
        for o in outcomes:
            label = '' if o['kind'] == 'observed' else t(o['kind'])
            if o['id'] in result['unproven_outcomes']:
                label = t('unproven')
            lines += [human(label + o['text']) + ' ' + human(o['impact']), '']
        if len(outcomes) < len(report['outcomes']):
            lines += [t('more_outcomes', count=len(report['outcomes']) - len(outcomes)), '']
    if contract['criteria']:
        lines += ['', '## ' + t('checks'), '', t('coverage', met=coverage['required_met'], total=coverage['required_total'])]
        if coverage['excluded']:
            lines += ['', t('excluded', count=coverage['excluded'])]
        if coverage['optional_total']:
            lines += ['', t('optional', count=coverage['optional_total'])]
        chosen = contract['criteria']
        if report['kind'] == 'progress' and previous and previous.get('valid'):
            compatible = (previous.get('contract_sha256') == result['contract_sha256'] and
                          previous.get('subject_revision') == result.get('subject_revision'))
            if compatible:
                changed = {x['id'] for x in chosen if previous['criteria'].get(x['id']) != result['criteria'][x['id']]}
                # Unchanged negative conditions must remain visible in a delta update.
                chosen = [x for x in chosen if x['id'] in changed or result['criteria'][x['id']] not in {'met', 'not_applicable'}]
                if not changed:
                    lines += ['', t('unchanged') + (t('open_below') if chosen else '')]
            else:
                lines += ['', t('changed_identity')]
        selected = chosen
        if brief and len(chosen) > 8:
            priority = [c for c in chosen if result['criteria'][c['id']] not in {'met', 'not_applicable'}]
            positive = [c for c in chosen if result['criteria'][c['id']] in {'met', 'not_applicable'}]
            selected = priority + positive[:max(0, 8-len(priority))]
        for criterion in selected:
            state = result['criteria'][criterion['id']]
            suffix = '' if criterion['required'] else t('optional_suffix')
            lines += ['', '**' + human(criterion['text'].rstrip('.!? ')) + suffix + ' — ' + statuses[state] + '.**']
            if state == 'not_applicable':
                lines += [human(criterion['exclusion']['reason']) + t('decision_owner', owner=human(criterion['exclusion']['approved_by']))]
                continue
            for v in criterion['verification']:
                detail = result['verification'][v['id']]
                expectation = v['expectation'].strip().rstrip('.!?')
                if expectation != criterion['text'].strip().rstrip('.!?'):
                    lines += [t('checked', expectation=human(expectation))]
                lines += [t('environment', environment=human(v['environment'].rstrip('.!? ')))]
                if detail['details']:
                    lines += [check_summary(d, checks[d['check_id']], catalog) for d in detail['details']]
                else:
                    lines += [t('missing_check')]
            if not criterion['verification']:
                lines += [t('missing_method')]
        if len(selected) < len(chosen):
            lines += ['', t('more_criteria', count=len(chosen) - len(selected))]
            visible = {x['id'] for x in selected}
            omitted = Counter(result['criteria'][x['id']] for x in chosen if x['id'] not in visible)
            lines += [t('omitted', states='; '.join(statuses[k] + ' — ' + str(v) for k, v in sorted(omitted.items())))]
    if report['kind'] in {'progress', 'handoff'} and contract['plan_steps']:
        names = {s['id']: s['title'] for s in contract['plan_steps']}
        lines += ['', '## ' + t('plan'), '']
        for p in report['plan_progress']:
            lines += [human(names[p['step_id']]) + ' — ' + t('plan.' + p['status']) + '. ' + human(p['note']), '']
    if contract['questions']:
        answers = {x['question_id']: x for x in report['answers']}
        lines += ['', '## ' + t('questions'), '']
        for q in contract['questions']:
            answer = answers.get(q['id'])
            answer_text = answer['text'] if answer else t('missing_answer')
            label = t('unknown_answer') if answer and answer['status'] == 'unknown' else ''
            if answer and answer['status'] == 'not_applicable': label = t('not_applicable_answer')
            lines += ['**' + human(q['text']) + '** ' + human(label + answer_text), '']
    delivery = result['delivery_state']
    if delivery != 'not_applicable':
        lines += ['', '## ' + t('delivery'), '', t('delivery.' + delivery)]
        if delivery == report['delivery']['state']:
            lines += [human(report['delivery']['text'])]
    if (report['blockers'] or report['risks'] or result['unproven_outcomes'] or result['unfinished_steps']
            or result.get('unmapped_requirements') or result.get('unplanned_criteria')):
        lines += ['', '## ' + t('limitations'), '']
        requirements = {r['id']: r['text'] for r in contract['requirements']}
        criteria = {c['id']: c['text'] for c in contract['criteria']}
        for rid in result.get('unmapped_requirements', []):
            lines += [t('unmapped_requirement', requirement=human(requirements[rid])), '']
        for cid in result.get('unplanned_criteria', []):
            lines += [t('unplanned_criterion', criterion=human(criteria[cid])), '']
        for b in report['blockers']:
            lines += [human(b['text']) + ' ' + human(b['impact']) + t('continue', action=human(b['next_action']), owner=human(b['owner'])), '']
        for r in report['risks']:
            lines += [human(r['text']) + ' ' + human(r['impact']), '']
        if result['unproven_outcomes']:
            lines += [t('unproven_count', count=len(result['unproven_outcomes'])), '']
        if result['unfinished_steps']:
            names = {s['id']: s['title'] for s in contract['plan_steps']}
            lines += [t('unfinished', steps='; '.join(human(names[s].rstrip('.!? ')) for s in result['unfinished_steps'])), '']
    if report['usage']:
        lines += ['', '## ' + t('usage'), '']
        lines += [str(n) + '. ' + human(step) for n, step in enumerate(report['usage'], 1)]
    if report['next_actions']:
        lines += ['', '## ' + t('next_actions'), '']
        for action in report['next_actions']:
            lines += [human(action['text']) + t('owner', owner=human(action['owner'])), '']
    metadata = (f'<!-- human-reporting-presentation requested={catalog.requested} '
                f'catalog={catalog.language} direction={catalog.direction} '
                f'source={resolved["sources"]["replies"]} -->')
    lines += ['', metadata]
    if catalog.notice:
        lines += ['', catalog.notice]
    if resolved['warnings']:
        lines += ['', t('preference_warning', warning=human('; '.join(resolved['warnings'])))]
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(lines)).strip() + '\n'

def main(argv=None):
    """Read-only CLI; execution and artifact persistence belong to the caller."""
    ap = argparse.ArgumentParser(description='Read-only, traceable multilingual product reports')
    ap.add_argument('--version', action='version', version=VERSION)
    ap.add_argument('command', choices=('validate', 'gate', 'render', 'graph', 'hash', 'lint'))
    ap.add_argument('--contract')
    ap.add_argument('--report')
    ap.add_argument('--evidence-root')
    ap.add_argument('--expected-contract-sha256')
    ap.add_argument('--max-age-hours', type=float)
    ap.add_argument('--brief', action='store_true')
    ap.add_argument('--language', help='Reply language tag; overrides language preferences')
    ap.add_argument('--project', help='Project root for language preferences')
    ap.add_argument('--strict-human', action='store_true')
    ap.add_argument('--text-file')
    args = ap.parse_args(argv)
    try:
        if args.command == 'lint':
            if not args.text_file:
                ap.error('--text-file is required for lint')
            path = Path(args.text_file)
            if path.stat().st_size > MAX_JSON:
                raise ReportError('Text input exceeds the configured size limit')
            resolved = preferences(language=args.language, project=args.project)
            findings = lint(path.read_text(encoding='utf-8'), language=resolved['replies'])
            print(json.dumps(findings, ensure_ascii=False, indent=2))
            return 2 if has_blocking_lint(findings) else 0
        if not args.contract:
            ap.error('--contract is required')
        contract = load_json(args.contract)
        if args.command == 'hash':
            print(canonical_hash(contract))
            return 0
        if not args.report:
            ap.error('--report is required')
        if args.max_age_hours is not None and (not math.isfinite(args.max_age_hours) or args.max_age_hours <= 0):
            raise ReportError('--max-age-hours must be finite and positive')
        report = load_json(args.report)
        assessment = analyse(contract, report, Path(args.evidence_root) if args.evidence_root else None,
                             args.expected_contract_sha256, args.max_age_hours)
        if not assessment['valid']:
            print(json.dumps(assessment, ensure_ascii=False, indent=2))
            return 2
        if args.command == 'render':
            text = render(contract, report, assessment, brief=args.brief, language=args.language, project=args.project)
            resolved = preferences(language=args.language, project=args.project)
            findings = lint(text, language=resolved['replies']) if args.strict_human else []
            if findings:
                print(json.dumps({'language_findings': findings}, ensure_ascii=False), file=sys.stderr)
                if has_blocking_lint(findings):
                    return 2
            print(text)
        else:
            value = trace_graph(contract, report) if args.command == 'graph' else assessment
            print(json.dumps(value, ensure_ascii=False, indent=2))
        return 3 if args.command == 'gate' and not assessment['ready'] else 0
    except (OSError, ValueError, TypeError, RecursionError) as exc:
        print('Reporting input error: ' + str(exc), file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
