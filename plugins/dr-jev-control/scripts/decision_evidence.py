"""Privacy-safe links between an advisory request and native consumer observations.

Digests identify bytes, not truth or authorization. Runtime acknowledgement is
not a measurement of the provider's underlying generation model.
"""
import hashlib
import json
import re
import uuid


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def model_label(value):
    # Only public JEV model labels; never copy arbitrary provider strings/objects.
    return value if isinstance(value, str) and re.fullmatch(r'jev-[a-z0-9.-]{1,60}', value) else None


def request_facts(payload):
    wire = json.loads(payload)
    return {'decision_id': uuid.uuid4().hex,
            'request_sha256': hashlib.sha256(payload).hexdigest(),
            'questions_sha256': digest(wire['questions']),
            'requested_model': model_label(wire.get('model'))}


def bind(provenance, *, policy, candidates, recommendation):
    """Hash only; no candidate descriptions, paths, state or policy values escape."""
    return dict(provenance, schema='JevDecisionEvidence/v1',
                policy_sha256=digest(policy), candidates_sha256=digest(candidates),
                recommendation_sha256=digest(recommendation))


def switch_outcome(verdict):
    """Conservative reader for both new observations and immutable old records."""
    if verdict.get('tier_uncertain'):
        return 'uncertain'
    if verdict.get('deferred'):
        return 'dispatched' if verdict.get('took_effect') else 'deferred'
    if (verdict.get('outcome') == 'applied' and verdict.get('applied') is True
            and verdict.get('confirmation') == 'runtime_control_ack'):
        return 'applied'
    if verdict.get('outcome') == 'refused':
        return 'refused'
    return 'not_measured'
