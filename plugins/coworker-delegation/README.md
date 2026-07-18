# Coworker Delegation Plugin

`coworker-delegation` is a trusted, metadata-only Datarim plugin. It is enabled by default and controls whether workspace instructions and the hook guard require bulk I/O delegation through `coworker`.

Run `dr-plugin disable coworker-delegation` to permit native agent I/O in the current workspace. Run `dr-plugin enable coworker-delegation` to restore the delegation mandate. The command only updates `datarim/enabled-plugins.md`; it does not install, remove, configure, or call `coworker` or any provider.

One exact `- coworker-delegation` entry under `## Disabled Defaults` resolves `disabled`. Missing, duplicate, malformed, indented, whitespace-altered, misplaced, or substring state resolves `enabled`.
