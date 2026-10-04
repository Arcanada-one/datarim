# Jev integration v2

> **Historical: Datarim 2.x only. Do not follow these steps.** The `dr-jev` and `dr-claude-jev`
> launchers, `install.py --scope user`, and an exported `TYPESAFE_API_KEY` describe the retired
> user-scope integration. Datarim 3.x installs Jev per project or per host and reads the key from a
> private file: see [INSTALL.md](INSTALL.md) and the [Jev CLI reference](documentation/reference/jev-cli.md).

This build fixes macOS/user-scope launcher path resolution.

The launchers now:
- honor `DATARIM_JEV_HOME` first;
- resolve `~/.local/bin` symlinks correctly on macOS/Linux;
- make `dr-claude-jev` use the same resolved plugin home;
- keep the existing user-scope installer workflow.

For a checkout at `/path/to/datarim`:

```bash
export DATARIM_JEV_HOME="/path/to/datarim/plugins/dr-jev-control"
export TYPESAFE_API_KEY="..."
export PATH="$HOME/.local/bin:$PATH"
python3 plugins/dr-jev-control/scripts/install.py --scope user
dr-jev doctor
```
