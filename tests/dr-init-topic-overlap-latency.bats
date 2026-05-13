#!/usr/bin/env bats
# dr-init-topic-overlap-latency.bats — AC-4 regression spec.
# Asserts /dr-init Step 2.5b detector finishes <=300ms on a 500-item backlog.
# Latency measured via python3 perf_counter (portable across macOS / Linux,
# unlike `date +%s%N` which lacks ns precision on BSD-derived systems).

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-topic-overlap.py"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/topic-overlap/backlog-500-items.md"

@test "latency <=300 ms on 500-item backlog" {
    elapsed_ms="$(python3 -c '
import subprocess, sys, time
script, fixture = sys.argv[1], sys.argv[2]
start = time.perf_counter()
r = subprocess.run(
    ["python3", script, "--task-description", "-", "--backlog", fixture],
    input="topic overlap detection system for pending backlog items",
    text=True, capture_output=True,
)
elapsed = (time.perf_counter() - start) * 1000
if r.returncode != 0:
    sys.stderr.write(r.stderr)
    sys.exit(2)
print(int(elapsed))
' "$SCRIPT" "$FIXTURE")"
    echo "elapsed_ms=$elapsed_ms"
    [ -n "$elapsed_ms" ]
    [ "$elapsed_ms" -le 300 ]
}
