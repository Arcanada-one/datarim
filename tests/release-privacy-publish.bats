#!/usr/bin/env bats

@test "signed release assets pass the protected privacy gate before publication" {
    local workflow="$BATS_TEST_DIRNAME/../.github/workflows/release.yml"
    local helper="$BATS_TEST_DIRNAME/../.github/scripts/workflow/release-release-11-release-asset-privacy-gate.sh"
    python3 - "$workflow" "$helper" <<'PY'
from pathlib import Path
import sys
import yaml

workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
helper = Path(sys.argv[2]).read_text()
steps = workflow['jobs']['release']['steps']
names = [step.get('name', '') for step in steps]
sign = names.index('Cosign sign-blob (tarball + SBOM)')
gate = names.index('Release asset privacy gate')
publish = names.index('Publish GitHub Release')
assert sign < gate < publish
step = steps[gate]
assert 'secrets.PERSONAL_ID_OVERLAY_B64' in step['env']['PERSONAL_ID_OVERLAY_B64']
assert 'secrets.PERSONAL_ID_OVERLAY_REVISION' in step['env']['DATARIM_PERSONAL_ID_REVISION_ID']
assert 'secrets.PERSONAL_ID_OVERLAY_SHA256' in step['env']['DATARIM_PERSONAL_ID_OVERLAY_SHA256']
assert 'bash .github/scripts/workflow/release-release-11-release-asset-privacy-gate.sh' in step['run']
for required in ('base64 --decode', 'verify-personal-id-overlay-revision.py',
                 'release_privacy_scan.py', '.cosign.bundle', '--asset'):
    assert required in helper
assert 'test -n "${PERSONAL_ID_OVERLAY_B64:-}"' in helper
PY
}
