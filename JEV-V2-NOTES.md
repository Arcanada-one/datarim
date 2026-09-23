# Jev integration v2

This build fixes macOS/user-scope launcher path resolution.

The launchers now:
- honor `DATARIM_JEV_HOME` first;
- resolve `~/.local/bin` symlinks correctly on macOS/Linux;
- make `dr-claude-jev` use the same resolved plugin home;
- keep the existing user-scope installer workflow.

For this checkout at `/Users/ug/code/datarim-jev-integrated`:

```bash
export DATARIM_JEV_HOME="/Users/ug/code/datarim-jev-integrated/plugins/dr-jev-control"
export TYPESAFE_API_KEY="..."
export PATH="$HOME/.local/bin:$PATH"
python3 plugins/dr-jev-control/scripts/install.py --scope user
dr-jev doctor
```
