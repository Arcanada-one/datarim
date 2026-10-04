"""Offline locale checks use synthetic reports, not model translation evidence."""
from copy import deepcopy
import json
import re

import pytest

from test_human_reporting import case, hr, assess, write_json


@pytest.fixture(autouse=True)
def clean_preferences(tmp_path, monkeypatch):
    monkeypatch.setenv('HOME', str(tmp_path / 'home'))
    monkeypatch.setenv('XDG_CONFIG_HOME', str(tmp_path / 'config'))
    monkeypatch.delenv('DATARIM_REPLY_LANG', raising=False)
    monkeypatch.delenv('DATARIM_ARTIFACT_LANG', raising=False)


@pytest.mark.parametrize('language,heading,status,direction', [
    ('en', 'What was required', 'Verified', 'ltr'),
    ('ru', 'Что требовалось', 'Проверено', 'ltr'),
    ('fr', 'Ce qui était demandé', 'Vérifié', 'ltr'),
    ('ar', 'ما كان مطلوباً', 'تم التحقق', 'rtl'),
    ('ja', '要件', '検証済み', 'ltr'),
])
def test_complete_locale_preserves_source_and_protocol(case, language, heading, status, direction):
    c, r, _ = case
    result = assess(case)
    before = deepcopy((c, r, result))
    text = hr.render(c, r, result, language=language)
    assert '## ' + heading in text
    assert status in text
    assert c['task']['goal'] in text and r['outcomes'][0]['text'] in text
    assert r['checks'][0]['summary'] in text
    assert f'requested={language} catalog={language} direction={direction}' in text
    assert result['criteria']['ac1'] == 'met' and r['checks'][0]['status'] == 'passed'
    assert result['readiness'] == 'checks_complete'
    assert before == (c, r, result)
    assert not hr.UNSAFE_CONTROLS.search(text)


def test_default_is_english(case):
    text = hr.render(case[0], case[1], assess(case))
    assert '## What was required' in text and 'requested=en catalog=en' in text
    assert not re.search(r'[\u0400-\u04ff]', text)


def test_user_preferences_are_read_without_reinstall(case, tmp_path):
    path = tmp_path / 'config/datarim/config.yaml'
    path.parent.mkdir(parents=True)
    path.write_text('language:\n  replies: fr\n  artifacts: ja\n')
    assert '## Ce qui était demandé' in hr.render(case[0], case[1], assess(case))
    path.write_text('language:\n  replies: ru\n  artifacts: en\n')
    assert '## Что требовалось' in hr.render(case[0], case[1], assess(case))
    assert '## 要件' in hr.render(case[0], case[1], assess(case), language='ja')


def test_project_and_cli_override(case, tmp_path, capsys):
    path = tmp_path / 'project/datarim/config.local.yaml'
    path.parent.mkdir(parents=True)
    path.write_text('language:\n  replies: ar\n  artifacts: en\n')
    c, r, root = case
    assert '## ما كان مطلوباً' in hr.render(c, r, assess(case), project=path.parents[1])
    write_json(root/'contract.json', c)
    write_json(root/'report.json', r)
    assert hr.main(['render', '--contract', str(root/'contract.json'), '--report',
                    str(root/'report.json'), '--evidence-root', str(root),
                    '--project', str(path.parents[1]), '--language', 'fr']) == 0
    text = capsys.readouterr().out
    assert '## Ce qui était demandé' in text and 'catalog=fr' in text


@pytest.mark.parametrize('tag,base', [('fr-CA', 'fr'), ('ar-EG', 'ar'), ('ja-JP', 'ja')])
def test_region_uses_disclosed_primary_catalog(case, tag, base):
    text = hr.render(case[0], case[1], assess(case), language=tag)
    assert f'requested={tag} catalog={base}' in text
    assert 'unavailable' not in text


@pytest.mark.parametrize('tag', ['ko', 'sw-KE', 'zh-Hant', 'az-Latn-AZ', 'x-team', 'i-klingon'])
def test_unavailable_catalog_discloses_english_fallback(case, tag):
    text = hr.render(case[0], case[1], assess(case), language=tag)
    assert f'Presentation catalog for {tag} is unavailable' in text
    assert 'fixed labels use English. Source text is preserved without translation.' in text
    assert f'requested={tag} catalog=en direction=ltr' in text
    assert case[1]['outcomes'][0]['text'] in text
    assert '## What was required' in text


@pytest.mark.parametrize('tag,normalized,base', [
    ('FR-ca', 'fr-CA', 'fr'), ('aR-arAb-eG', 'ar-Arab-EG', 'ar'),
    ('ja-JPAN-jp', 'ja-Jpan-JP', 'ja'),
])
def test_catalog_and_resolver_normalize_tags_consistently(case, tag, normalized, base):
    catalog = hr.presentation.Presentation(tag)
    assert catalog.requested == normalized and catalog.language == base
    text = hr.render(case[0], case[1], assess(case), language=tag)
    assert f'requested={normalized} catalog={base}' in text


@pytest.mark.parametrize('tag', ['../ru', 'en<script>', 'ru\u202e', '', 'ru en'])
def test_unsafe_language_tag_rejected(case, tag):
    with pytest.raises(ValueError):
        hr.render(case[0], case[1], assess(case), language=tag)


@pytest.mark.parametrize('language', ['en', 'ru', 'fr', 'ar', 'ja', 'ko'])
def test_invalid_bindings_cannot_render_in_any_language(case, language):
    case[1]['contract_sha256'] = '0' * 64
    result = assess(case)
    assert not result['valid'] and not result['ready']
    with pytest.raises(hr.ReportError, match='invalid bindings'):
        hr.render(case[0], case[1], result, language=language)


@pytest.mark.parametrize('language', ['en', 'ru', 'fr', 'ar', 'ja'])
@pytest.mark.parametrize('status', ['not_run', 'skipped', 'stale', 'unsupported_success', 'receipt'])
def test_generated_negative_check_reason_is_localized(case, language, status):
    c, r, root = case
    if status == 'stale':
        r['checks'][0]['environment'] = 'production'
    elif status == 'unsupported_success':
        r['checks'][0]['evidence_ids'] = []
    elif status == 'receipt':
        receipt = hr.load_json(root/'receipt.json')
        receipt['exit_code'] = 1
        write_json(root/'receipt.json', receipt)
        r['evidence'][0]['sha256'] = hr.file_hash(root/'receipt.json')
    else:
        r['checks'][0]['status'] = status
    result = assess(case)
    assert result['valid'] and not result['ready']
    key = 'reason.' + status
    assert hr.presentation.Presentation(language).text(key).strip() in hr.render(c, r, result, language=language)
    assert result['criteria']['ac1'] == 'not_verified'


@pytest.mark.parametrize('text', ['έκδοση2', 'الدور١', 'תפקיד2', 'भूमिका२', 'équipe2', 'rôle1',
                                 'version4.3.0', 'report218', 'role1', 'rapport218'])
def test_unicode_spaced_prose_warns_without_mutation(text):
    assert any(f['code'] == 'prose-spacing' for f in hr.lint(text))
    assert hr.human(text) == text


@pytest.mark.parametrize('text', ['版本2', '第2版', '版本２', '2件', '役割1', 'Product2', '`الدور١`'])
def test_unspaced_scripts_and_literal_identifiers_do_not_warn(text):
    assert not any(f['code'] == 'prose-spacing' for f in hr.lint(text))


@pytest.mark.parametrize('language', ['en', 'ru', 'fr', 'ar', 'ja'])
def test_catalog_does_not_change_lint_machine_codes(language):
    findings = hr.lint('роль1\u202e', language=language)
    assert {f['code'] for f in findings} == {'unsafe-control', 'prose-spacing'}
    assert hr.has_blocking_lint(findings)
    assert findings[0]['message'] == hr.presentation.Presentation(language).text('lint.unsafe-control')


def test_catalog_validation_fails_closed_for_missing_or_unsafe_values(tmp_path, monkeypatch):
    module = hr.presentation
    monkeypatch.setattr(module, 'CATALOGS', tmp_path)
    en = json.loads((hr.BASE/'locales/en.json').read_text())
    write_json(tmp_path/'en.json', en)
    bad = dict(en)
    bad.pop('status.failed')
    write_json(tmp_path/'fr.json', bad)
    with pytest.raises(ValueError, match='keys or placeholders'):
        module.Presentation('fr')
    bad = dict(en)
    bad['coverage'] = '{total.__class__}'
    write_json(tmp_path/'fr.json', bad)
    with pytest.raises(ValueError, match='placeholder'):
        module.Presentation('fr')
    bad = dict(en)
    bad['status.failed'] = 'Passed\u202e'
    write_json(tmp_path/'fr.json', bad)
    with pytest.raises(ValueError, match='catalog value'):
        module.Presentation('fr')
