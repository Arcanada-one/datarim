# Same-line marker fixture

A bypass attempt with no earlier sentinel looks like:

<!-- gate:history-allowed -->TUNE-0099 sneaky inline<!-- /gate:history-allowed -->

The malformed marker itself must fail. It must also never suppress the later
real violation:

DEV-9999 — fresh provenance reference after the malformed fence.
