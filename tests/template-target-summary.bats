#!/usr/bin/env bats
# Opt-in summary contract for the shipped-template target checker.

setup() {
    CHECKER="$BATS_TEST_DIRNAME/../dev-tools/check-template-targets.py"
    FIXTURE="$BATS_TEST_TMPDIR/project"
    mkdir -p "$FIXTURE/templates"
}

fixture_digest() {
    python3 - "$1" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
entries = []
for current, directories, files in os.walk(root, followlinks=False):
    directories.sort()
    files.sort()
    for name in directories + files:
        path = Path(current) / name
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            entries.append((relative, "symlink", os.readlink(path)))
        elif path.is_file():
            entries.append((relative, "file", hashlib.sha256(path.read_bytes()).hexdigest()))
        else:
            entries.append((relative, "directory", ""))
payload = json.dumps(entries, separators=(",", ":"), ensure_ascii=False).encode()
print(hashlib.sha256(payload).hexdigest())
PY
}

@test "summary reports valid core and manifest-declared plugin targets" {
    mkdir -p "$FIXTURE/plugins/example/templates"
    touch "$FIXTURE/templates/core.md" "$FIXTURE/plugins/example/templates/plugin.md"
    printf '%s\n' 'categories:' '  - templates' > "$FIXTURE/plugins/example/plugin.yaml"
    printf '%s\n' 'Use templates/core.md and templates/example/plugin.md.' > "$FIXTURE/README.md"
    local before after
    before=$(fixture_digest "$FIXTURE")

    run python3 "$CHECKER" --root "$FIXTURE" --summary-json
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimTemplateTargetValidationSummary/v1","result":"VALID","exit_code":0,"checked_count":2,"missing_count":0,"diagnostic_codes":[]}' ]

    run python3 "$CHECKER" --root "$FIXTURE"
    [ "$status" -eq 0 ]
    [[ "$output" == *'template targets: checked=2 missing=0' ]]
    after=$(fixture_digest "$FIXTURE")
    [ "$before" = "$after" ]
    printf 'fixture_sha256 before=%s after=%s\n' "$before" "$after"
}

@test "missing target summary redacts target, source path, and source text" {
    printf '%s\n' 'Private fixture payload: never disclose this sentence.' 'Use templates/opaque-private-marker.md.' > "$FIXTURE/README.md"
    local before after
    before=$(fixture_digest "$FIXTURE")

    run python3 "$CHECKER" --root "$FIXTURE" --summary-json
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimTemplateTargetValidationSummary/v1","result":"MISSING_TARGETS","exit_code":1,"checked_count":1,"missing_count":1,"diagnostic_codes":["MISSING_TEMPLATE_TARGETS"]}' ]
    [[ "$output" != *'opaque-private-marker'* ]]
    [[ "$output" != *'README.md'* ]]
    [[ "$output" != *'Private fixture payload'* ]]

    run python3 "$CHECKER" --root "$FIXTURE"
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing templates/'* ]]
    [[ "$output" == *'template targets: checked=1 missing=1' ]]
    after=$(fixture_digest "$FIXTURE")
    [ "$before" = "$after" ]
    printf 'fixture_sha256 before=%s after=%s\n' "$before" "$after"
}

@test "zero eligible targets returns the existing no-target exit and fixed code" {
    cat > "$FIXTURE/README.md" <<'EOF'
<!-- gate:history-allowed -->
Historical templates/old.md reference.
<!-- /gate:history-allowed -->
<!-- gate:example-only -->
```text
Example templates/example.md reference.
```
<!-- /gate:example-only -->
Placeholders: templates/no-extension and templates/directory/.
EOF
    local before after
    before=$(fixture_digest "$FIXTURE")

    run python3 "$CHECKER" --root "$FIXTURE" --summary-json
    [ "$status" -eq 2 ]
    [ "$output" = '{"schema":"DatarimTemplateTargetValidationSummary/v1","result":"NO_TARGETS","exit_code":2,"checked_count":0,"missing_count":0,"diagnostic_codes":["NO_TEMPLATE_TARGETS"]}' ]

    run python3 "$CHECKER" --root "$FIXTURE"
    [ "$status" -eq 2 ]
    [ "$output" = 'template targets: checked=0 missing=0' ]
    after=$(fixture_digest "$FIXTURE")
    [ "$before" = "$after" ]
    printf 'fixture_sha256 before=%s after=%s\n' "$before" "$after"
}

@test "summary preserves root containment for symlinked targets" {
    local outside="$BATS_TEST_TMPDIR/outside.md"
    printf '%s\n' 'outside fixture' > "$outside"
    ln -s "$outside" "$FIXTURE/templates/escaped.md"
    printf '%s\n' 'Use templates/escaped.md.' > "$FIXTURE/README.md"
    local before after
    before=$(fixture_digest "$FIXTURE")

    run python3 "$CHECKER" --root "$FIXTURE" --summary-json
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimTemplateTargetValidationSummary/v1","result":"MISSING_TARGETS","exit_code":1,"checked_count":1,"missing_count":1,"diagnostic_codes":["MISSING_TEMPLATE_TARGETS"]}' ]
    after=$(fixture_digest "$FIXTURE")
    [ "$before" = "$after" ]
    printf 'fixture_sha256 before=%s after=%s\n' "$before" "$after"
}
