# Same-line marker fixture

The line below is a fresh task-ID reference that is OUTSIDE any escape fence.
It must be caught by the gate regardless of any subsequent same-line bypass
attempt:

DEV-9999 — fresh provenance reference outside the fence.

A bypass attempt would look like:

<!-- gate:history-allowed -->TUNE-0099 sneaky inline<!-- /gate:history-allowed -->

The same-line marker is a known pitfall — opening matches, `next` fires, and
`skip=1` persists for the rest of the file (documented in the contract). This
fixture proves the gate STILL fails because the DEV-9999 line earlier in the
stream is matched before the strip's sticky-skip kicks in.
