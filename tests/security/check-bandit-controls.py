#!/usr/bin/env python3
"""Require exact unsafe Bandit findings and a clean control at the CI threshold."""
import json
from pathlib import Path
import subprocess
import sys

FIXTURES = Path(__file__).resolve().parent / 'fixtures'


def check_control(name, expected_ids, expected_status):
    fixture = FIXTURES / name
    result = subprocess.run(['bandit', '-ll', '-ii', '-f', 'json', str(fixture)],
                            capture_output=True, text=True, check=False)
    try:
        report = json.loads(result.stdout)
    except ValueError:
        raise SystemExit(f'Bandit control {name}: missing JSON, exit={result.returncode}') from None
    if not isinstance(report, dict) or not isinstance(report.get('errors'), list) or not isinstance(report.get('results'), list):
        raise SystemExit(f'Bandit control {name}: invalid report structure')
    if report.get('errors'):
        raise SystemExit(f'Bandit control {name}: scanner error')
    findings = report.get('results', [])
    ids = {finding['test_id'] for finding in findings}
    if result.returncode != expected_status or ids != expected_ids:
        raise SystemExit(f'Bandit control {name}: exit={result.returncode}, findings={sorted(ids)}')
    if any(Path(finding['filename']).resolve() != fixture.resolve() for finding in findings):
        raise SystemExit(f'Bandit control {name}: finding came from another source')
    if any(finding['issue_severity'] not in ('MEDIUM', 'HIGH') or
           finding['issue_confidence'] not in ('MEDIUM', 'HIGH') for finding in findings):
        raise SystemExit(f'Bandit control {name}: wrong threshold')
    return {'fixture': str(fixture.relative_to(FIXTURES.parent)),
            'exit_code': result.returncode, 'finding_ids': sorted(ids)}


def main():
    controls = [check_control('sast-unsafe.py', {'B602', 'B307'}, 1),
                check_control('sast-clean.py', set(), 0)]
    print(json.dumps({'status': 'PASS', 'threshold': '-ll -ii', 'controls': controls},
                     sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
