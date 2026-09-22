#!/usr/bin/env python3
import json,sys
# Intentionally local/cheap: avoid a Jev API call after every tool. The prompt router
# already predicts validation need; Datarim's existing QA gates remain authoritative.
def main():
    try:p=json.load(sys.stdin)
    except Exception:return 0
    # See hook_pre_tool: valid-JSON-non-object parses, then breaks at .get().
    if not isinstance(p,dict):return 0
    # `hooks.posttool_validation` advertised a switch that nothing read, so
    # setting it false changed nothing. A config key that names a control it
    # does not have is worse than no key: it tells the operator the hook is
    # off while it keeps firing. Read cheaply and fail open.
    try:
        from route import load_cfg
        if not (load_cfg().get('hooks',{}) or {}).get('posttool_validation',True):
            return 0
    except Exception:
        pass
    tool=str(p.get('tool_name',''))
    if tool in ('Write','Edit','MultiEdit','apply_patch'):
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"A file-changing tool ran. Preserve Datarim acceptance criteria and run the narrowest relevant validation before declaring completion."}}))
    return 0
if __name__=='__main__':raise SystemExit(main())
