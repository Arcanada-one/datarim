# Datarim + Jev + Claude Code — Quick Start

## Install

```bash
python3 plugins/dr-jev-control/scripts/install.py --scope user
export PATH="$HOME/.local/bin:$PATH"
export TYPESAFE_API_KEY='YOUR_NEW_KEY'
```

Optional if the repository has a stable path:

```bash
export DATARIM_JEV_HOME="$PWD/plugins/dr-jev-control"
```

## Verify

```bash
dr-jev doctor --api
```

## Run

Balanced is the default:

```bash
dr-claude-jev "Fix the failing tests and verify the result"
```

Explicit modes:

```bash
dr-claude-jev --mode economy "Update documentation"
dr-claude-jev --mode balanced "Implement this feature and test it"
dr-claude-jev --mode quality "Review and redesign this concurrency subsystem"
```

Inspect the decision without starting Claude:

```bash
dr-jev route "Implement OAuth callback handling"
dr-jev route --mode economy "Update documentation"
```

## Help

```bash
dr-jev help
dr-jev modes
dr-claude-jev --help
```

## Overrides

```bash
dr-claude-jev --model opus "task"
dr-claude-jev --no-route "task"
dr-claude-jev --print "task"
dr-claude-jev -- --help
```

The default mode is `balanced` unless `--mode` or `DATARIM_JEV_MODE` is set.
