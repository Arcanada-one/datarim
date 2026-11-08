#!/usr/bin/env bash
set -euo pipefail
python3 -m pytest -q tests/test_human_reporting*.py tests/test_language_preferences.py tests/test_language_framework.py
python3 -m unittest discover -s skills/human-outcome-reporting/tests -v
python3 -m unittest discover -s tests -p 'test_framework_*.py' -v
python3 dev-tools/framework-graph.py --check
python3 dev-tools/check-template-targets.py
