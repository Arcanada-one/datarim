# Retired Coworker hook setup

The former global Coworker delegation hooks are retired. Do not install their
launchers, trust entries, or instruction overrides. Historical implementation
is available in Git history.

Use [project-local Datarim initialization](../tutorials/initialize-datarim.md)
and [Jev configuration](configure-and-use-jev.md). To classify work across a
host without enabling Datarim globally, use the
[independent host Jev installation](host-jev-with-project-datarim.md).

Preserve unrelated hooks when removing legacy entries. Codex hook trust must
be confirmed through the client's native trust interface; installation alone
is not evidence that the hook ran.
