#!/usr/bin/env python3
import json,sys
# No Jev call here by default: Stop hooks can recurse and cost/latency compound.
# Continuation decisions are exposed via `dr-jev route` for orchestrated loops.
def main():
    try: json.load(sys.stdin)
    except Exception: pass
    return 0
if __name__=='__main__':raise SystemExit(main())
