#!/usr/bin/env bash
set -euo pipefail
python_bin="$RUNNER_TEMP/jev-venv/bin/python"
"$python_bin" -m unittest discover -s plugins/dr-jev-control/tests -v
for pattern in 'test_jev_*.py' 'test_project_*.py' 'test_framework_*.py'; do
  "$python_bin" -m unittest discover -s tests -p "$pattern" -v
done
