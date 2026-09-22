#!/usr/bin/env python3
import json,os,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
# The safety floor is imported FIRST and on its own: it has no dependency
# beyond the standard library, so an import failure anywhere in the advisory
# stack (jev_client, route) must not be able to take the guard down with it.
from safety_floor import destructive_reason

# The advisory-layer imports are wrapped so a broken control plane degrades to
# "floor only" rather than "no hook at all". They stay module-level names so
# they remain patchable by tests.
try:
    from jev_client import evaluate
    from route import load_cfg,log
except Exception:  # pragma: no cover - exercised by the degraded-import test
    evaluate=load_cfg=log=None

def main():
    try:p=json.load(sys.stdin)
    except Exception:return 0
    # Valid JSON that is not an object (null, a list, a bare scalar) parses
    # fine and then fails at .get(). A hook must never exit non-zero: that is
    # the fail-open contract, and a traceback here would surface as a broken
    # hook in the host CLI.
    if not isinstance(p,dict):return 0
    tool=str(p.get('tool_name','')); inp=p.get('tool_input',{})
    s=json.dumps({"tool":tool,"input":inp},ensure_ascii=False)[:12000]

    # Hard local floor FIRST, before any config is consulted.
    # It is deterministic and local, so it must not depend on the control
    # plane's state: disabling Jev, or a corrupt config, tunes the ADVISORY
    # layer off and must never silently remove a destructive-command guard.
    # (Ordering regression found 2026-09-21: with the config check first,
    # DATARIM_JEV_DISABLE=1 let a recursive root delete through unblocked.)
    # Matching lives in safety_floor.py and runs on a normalised argv, because
    # literal-spelling patterns missed trivial variants -- see that module.
    cmd=str(inp.get('command','')) if isinstance(inp,dict) else ''
    reason=destructive_reason(cmd)
    if reason:
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":f"Datarim deterministic safety floor blocked a destructive command ({reason})."}}));return 0

    # Advisory layer. Absent (import failed) means the floor above has already
    # had its say and there is nothing further to add.
    if load_cfg is None or evaluate is None:return 0
    cfg=load_cfg()
    if not cfg.get('hooks',{}).get('pretool_risk',True):return 0
    # Cost guard: only ask Jev about calls with a plausible mutation/external-risk signal.
    # Ordinary reads, tests, grep, git diff/status/log, and normal source edits do not pay an API round-trip.
    low=(tool.lower() in ('read','grep','glob','view') or (tool.lower() in ('bash','shell','exec_command') and not re.search(r'\b(rm|mv|chmod|chown|sudo|ssh|scp|rsync|curl|wget|kubectl|helm|terraform|ansible|docker|podman|npm\s+publish|git\s+(push|reset|clean|checkout|switch|rebase|merge)|gh\s+|aws\s+|gcloud\s+|az\s+|psql|mysql|redis-cli)\b|>\s*[^&]|sed\s+-i',cmd,re.I)))
    path=str(inp.get('file_path',inp.get('path',''))) if isinstance(inp,dict) else ''
    ordinary_edit=tool.lower() in ('write','edit','multiedit','apply_patch') and not re.search(r'(\.env|secret|credential|production|prod\.|migration|deploy|settings\.json)',path,re.I)
    if low or ordinary_edit:return 0
    q={"risky":{"type":"noul","instructions":"Is this proposed tool call destructive, irreversible, security-sensitive, secret-exposing, production-changing, externally mutating, or otherwise deserving explicit review before autonomous execution?"}}
    api=cfg.get('api',{})
    budget={"timeout_seconds":api.get('hook_timeout_seconds',4),"retries":api.get('hook_retries',0)}
    try:r=evaluate(s,q,cfg,budget=budget); risk=float(r['answers']['risky']['noul']); log(cfg,'pretool',s,{"risk":risk,"tool":tool,"usage":r.get('usage',{})})
    except Exception:return 0
    th=cfg.get('routing',{}).get('risk_thresholds',{}); enforce=cfg.get('hooks',{}).get('enforce_jev_denials',False)
    if enforce and risk>=float(th.get('deny_autonomous',.94)):
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":f"Jev risk gate={risk:.3f}; explicit review requested."}}))
    elif risk>=float(th.get('require_review',.78)):
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":f"Jev risk advisory: {risk:.3f}. Re-check scope, reversibility, secrets, external effects, and validation before executing."}}))
    return 0
if __name__=='__main__':raise SystemExit(main())
