#!/usr/bin/env bash
set -euo pipefail
python3 dev-tools/package-human-reporting.py --output human-outcome-reporting.zip
python3 dev-tools/package-human-reporting.py --kind integration --output datarim-human-reporting-integration.zip
sha256sum human-outcome-reporting.zip > human-outcome-reporting.zip.sha256
sha256sum datarim-human-reporting-integration.zip > datarim-human-reporting-integration.zip.sha256
