# Safety floor categories

`destructive_reason` returns one of the reason strings in this table, or no
reason when the command is allowed. The first column is the exact string. A
plugin test fails when that set and the strings the function returns differ.

A denial appends one `safety_floor_deny` ledger event when the ledger location
can be resolved and telemetry is enabled. The event's `command` is passed
through the ledger redaction helper before it is stored, and `reason` is the
string from this table. The command stays denied when that append fails.

| Reason | What the floor refuses |
| --- | --- |
| recursive delete of a protected path | Recursive `rm` of a protected root, or of the home directory (`~`, `$HOME`, `${HOME}`, or the expanded home path) |
| raw write to a block device | `dd` whose `of=` operand is a whole disk or partition |
| filesystem format of a block device | `mkfs` or `mkfs.<type>` aimed at a block device |
| SQL DROP DATABASE/SCHEMA | Command text that contains `DROP DATABASE` or `DROP SCHEMA` |
| git force push | `git push` with `--force`, `-f`, or a refspec that starts with `+` |
| git reset --hard | `git reset --hard` |
| nested shell exceeds deterministic inspection depth | A `bash`, `sh`, `zsh`, `dash`, or `ksh` `-c` script nested five levels deep, past the four levels the floor inspects |
