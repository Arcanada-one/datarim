"""Validated presentation catalogs; protocol values and caller prose stay unchanged."""
from __future__ import annotations

import json
import importlib.util
from pathlib import Path
import re
from string import Formatter

CATALOGS = Path(__file__).resolve().parents[1] / 'locales'
UNSAFE = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u061c\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]')
_spec = importlib.util.spec_from_file_location('presentation_language_preferences', Path(__file__).with_name('language.py'))
_language = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_language)


def _pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError('Duplicate presentation key')
        result[key] = value
    return result


def _load(language: str) -> dict[str, str]:
    """Only shipped, bounded UTF-8 JSON data enters the presentation surface."""
    path = CATALOGS / (language + '.json')
    if path.stat().st_size > 128 * 1024:
        raise ValueError('Presentation catalog exceeds size limit')
    data = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=_pairs)
    if not isinstance(data, dict) or not data:
        raise ValueError('Presentation catalog must be a nonempty object')
    if any(not isinstance(k, str) or not isinstance(v, str) or not v or
           UNSAFE.search(v) for k, v in data.items()):
        raise ValueError('Invalid presentation catalog value')
    return data


def _fields(value: str) -> set[str]:
    fields = set()
    for _, name, spec, conversion in Formatter().parse(value):
        if name is not None:
            if not re.fullmatch(r'[a-z_]+', name) or spec or conversion:
                raise ValueError('Invalid presentation placeholder')
            fields.add(name)
    return fields


class Presentation:
    """Localize fixed labels, with an explicit English notice on catalog fallback."""

    def __init__(self, language: str):
        self.requested = _language.language_tag(language)
        self.language = self.requested.split('-')[0]
        baseline = _load('en')
        self.fallback = not (CATALOGS / (self.language + '.json')).is_file()
        if self.fallback:
            self.language = 'en'
        self.direction = 'rtl' if self.language == 'ar' else 'ltr'
        self.messages = baseline if self.language == 'en' else _load(self.language)
        if self.messages.keys() != baseline.keys() or any(
            _fields(value) != _fields(baseline[key])
            for key, value in self.messages.items()
        ):
            raise ValueError('Presentation catalog keys or placeholders differ from English')

    def text(self, key: str, **values) -> str:
        return self.messages[key].format(**values)

    @property
    def notice(self) -> str:
        if not self.fallback:
            return ''
        return self.text('fallback', language=self.requested)
