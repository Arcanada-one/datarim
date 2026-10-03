# Datarim and Jev quick start

Install Datarim and Jev with [INSTALL.md](INSTALL.md), the one install guide.
Background and day-to-day use:

- [Initialize Datarim](documentation/tutorials/initialize-datarim.md)
- [Initialize Datarim with Jev](documentation/tutorials/initialize-datarim-with-jev.md)
- [Configure and use Jev](documentation/how-to/configure-and-use-jev.md)
- [CLI reference](documentation/reference/jev-cli.md)

The entrypoints are `jevcodex`, `jevclaude`, `jevcursor`, and
`jev --agent={codex,claude,cursor}`. All share the same project boundary.
Global installation, shell startup edits, and exported API-key literals are
replaced by explicit project installation and a protected per-host key file.
