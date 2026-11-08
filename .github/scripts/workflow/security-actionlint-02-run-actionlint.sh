#!/usr/bin/env bash
set -euo pipefail
actionlint -color -ignore 'label "ci-general" is unknown'
