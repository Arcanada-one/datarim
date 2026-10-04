# Preflight caller identity and public examples

The reusable preflight caller contract admits only repositories registered in the immutable `consumers.yml` of the pinned action commit. This revision ships a generic sample rather than internal consumer identities. It retains all fail-closed workflow, identity, dependency and secret-binding checks.

Existing callers pinned to an earlier action revision keep that revision's registry and behavior. Before upgrading a real consumer, maintainers must provide its binding through a private, immutable action overlay and verify the positive and negative contract tests. A caller-supplied mutable registry is not supported and must not be treated as authority. Updating the framework does not migrate a production workflow's pinned action.

The generic notification endpoint is a non-routable example. Before production use, configure the private overlay's immutable endpoint allowlist and consumer registry together, then verify matching notification checks. Do not replace the allowlist with an unrestricted caller-provided URL.
