# SSH-Deploy Scripts via Base64

**Problem:** SSH heredoc (`ssh host bash <<EOF ... EOF`) corrupts scripts that contain `jq`, `$(...)`, backticks, or escaped quotes — bash performs local expansion before transmission. Result: scripts fail on the remote host with cryptic syntax errors or act on local variables.

**Solution:** base64-encode the script locally, decode-execute remotely:

```bash
# Encode local script
CMD=$(base64 < my-script.sh | tr -d '\n')

# Execute on remote (no expansion, no escaping, handles special chars)
ssh user@host "echo '$CMD' | base64 -d | bash"

# With sudo:
ssh user@host "echo '$CMD' | base64 -d | sudo bash"

# With stdout capture:
ssh user@host "echo '$CMD' | base64 -d | bash" > local-output.log
```

**One-liner for ad-hoc commands:**
```bash
# Run a one-off command with complex quoting
CMD=$(echo 'jq -r ".[].name" data.json | sort -u' | base64)
ssh host "echo $CMD | base64 -d | bash"
```

**When to use:**
- Scripts with `jq`, `awk`, or bash special characters
- Multi-line scripts with embedded variable expansion
- Server-side automation (INFRA tasks, CI deploys, agent rollouts)

Source: INFRA-0008 reflection — heredoc approach broke on restic+B2 deploy scripts across arcana-www/prod/db. Base64 pattern resolved it universally.
