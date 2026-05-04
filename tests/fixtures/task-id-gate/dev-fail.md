# DEV-fail fixture

Documents a CLI parsing pattern. The original write-up cited DEV-1183 inline,
which the gate must catch.

## Rule (with provenance pollution)

When parsing rate-limit output, prefer the machine-readable epoch field over
human-readable strings. DEV-1183 surfaced this when "resets 5pm (UTC)" turned
out to ship locale-fragile parsing.
