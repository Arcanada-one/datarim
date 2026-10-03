"""Regression checks for complete human explanations, freshness and delta identity.

All evidence is synthetic. These tests do not measure live model behavior.
"""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from test_human_reporting import case, hr, rebind, assess, write_json

ROOT = Path(__file__).resolve().parents[1]


def test_unmapped_requirement_explains_why_result_is_incomplete(case):
    c, r, _ = case
    c['requirements'].append({'id': 'req2', 'text': 'Separate tenant records.', 'source': 'user'})
    rebind(case)
    result = assess(case)
    text = hr.render(c, r, result)
    assert not result['ready']
    assert result['unmapped_requirements'] == ['req2']
    assert 'Separate tenant records.' in text
    assert 'ещё не определены критерии приёмки' in text
    assert 'req2' not in text


def test_unplanned_condition_has_a_human_explanation(case):
    c, r, _ = case
    c['plan_steps'] = []
    r['plan_progress'] = []
    r['outcomes'] = []
    rebind(case)
    result = assess(case)
    assert result['valid'] and not result['ready']
    assert result['unplanned_criteria'] == ['ac1']
    assert 'не указан шаг плана' in hr.render(c, r, result)


def test_unchanged_negative_condition_survives_delta(case):
    c, r, _ = case
    r['checks'][0]['status'] = 'failed'
    r['checks'][0]['summary'] = 'The selected period still includes another day.'
    r['kind'] = 'progress'
    previous = deepcopy(assess(case))
    current = assess(case)
    text = hr.render(c, r, current, brief=True, previous=previous)
    assert c['criteria'][0]['text'].rstrip('.') in text
    assert r['checks'][0]['summary'] in text
    assert 'Проверка выявила ошибку' in text


@pytest.mark.parametrize('field', ['contract_sha256', 'subject_revision'])
def test_delta_rejects_a_different_baseline_or_product(case, field):
    c, r, _ = case
    r['kind'] = 'progress'
    current = assess(case)
    previous = deepcopy(current)
    previous[field] = 'a-different-identity'
    text = hr.render(c, r, current, previous=previous)
    assert 'показана полная проверка' in text
    assert c['criteria'][0]['text'].rstrip('.') in text


def test_positive_unchanged_delta_does_not_claim_open_conditions(case):
    c, r, _ = case
    r['kind'] = 'progress'
    result = assess(case)
    text = hr.render(c, r, result, previous=deepcopy(result))
    assert 'Состояния критериев не изменились.' in text
    assert 'Открытые условия перечислены ниже.' not in text


@pytest.mark.parametrize('age', [float('nan'), float('inf'), -float('inf'), 0, -1, True, '24'])
def test_age_limit_must_be_a_finite_positive_number(case, age):
    result = hr.analyse(*case, max_age_hours=age)
    assert not result['valid'] and not result['ready']
    assert any('finite positive' in error for error in result['errors'])


def test_fresh_claim_cannot_refresh_an_old_execution_receipt(case):
    c, r, root = case
    old = (datetime.now(timezone.utc) - timedelta(hours=48)).isoformat()
    receipt = hr.load_json(root / 'receipt.json')
    receipt['started_at'] = receipt['ended_at'] = old
    write_json(root / 'receipt.json', receipt)
    r['evidence'][0]['sha256'] = hr.file_hash(root / 'receipt.json')
    result = hr.analyse(c, r, root, max_age_hours=24)
    assert result['valid'] and not result['ready']
    assert not result['evidence']['ev1']['valid']
    assert 'older than' in result['evidence']['ev1']['reason']


@pytest.mark.parametrize('command', ['dr-qa', 'dr-compliance', 'dr-archive'])
def test_legacy_commands_cannot_reintroduce_a_hard_word_cap(command):
    text = (ROOT / 'commands' / (command + '.md')).read_text()
    assert 'no hard word cap' in text
    assert 'Length budget: 150' not in text
    assert 'skills/human-summary/SKILL.md' in text


def test_legacy_adapter_preserves_sections_without_forced_compression():
    text = (ROOT / 'skills/human-summary/SKILL.md').read_text()
    assert 'no hard word cap' in text
    assert 'drop detail; never extend' not in text
    assert 'Hard upper bound' not in text
    assert 'ALL_PASS stage verdict alone' in text
    for heading in ['Что было сделано', 'Что получилось', 'Что не получилось', 'Что дальше']:
        assert heading in text
