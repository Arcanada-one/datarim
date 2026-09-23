#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from route import route,load_cfg

def main():
    try: payload=json.load(sys.stdin)
    except Exception:return 0
    # See hook_pre_tool: valid-JSON-non-object parses, then breaks at .get().
    if not isinstance(payload,dict):return 0
    prompt=payload.get('prompt') or payload.get('user_prompt') or payload.get('message') or ''
    if not isinstance(prompt,str) or len(prompt.strip())<3:return 0
    cfg=load_cfg()
    if not cfg.get('hooks',{}).get('prompt_router',True):return 0
    api=cfg.get('api',{})
    budget={"timeout_seconds":api.get('hook_timeout_seconds',4),"retries":api.get('hook_retries',0)}
    try:
        from prompt_cache import consume
        r=consume(prompt) or route(prompt,cfg,os.environ.get('DATARIM_JEV_MODE') or None,budget=budget)
    except Exception:return 0
    if not r.get('ok'):return 0
    a=r['answers']; sel=r.get('selection',{}) or {}
    getn=lambda k:round(float(a.get(k,{}).get('noul',0)),3)

    def fmt_multi(kind):
        # Several components can apply at once; only those above the apply
        # threshold are named as selected. Below-threshold candidates are
        # withheld rather than presented as decisions -- a weak pick that gets
        # loaded costs context and misdirects the agent.
        s=sel.get(kind) or {}
        apply=s.get('apply') or []
        if not apply: return "none above confidence threshold"
        return ", ".join(f"{x['name']} ({x['score']:.2f})" for x in apply)

    def fmt_single(kind):
        s=sel.get(kind) or {}
        choice=s.get('choice','none')
        if not choice or choice=='none': return "none"
        conf=s.get('confidence',0.0)
        return f"{choice} ({conf:.2f})" if s.get('applied') else f"{choice} ({conf:.2f}, low confidence - advisory only, do not treat as a decision)"

    ctx=("JEV ROUTING ADVICE (System-One advisory; operator and project instructions remain authoritative):\n"
         f"- mode: {r.get('mode','balanced')} | suggested model tier for delegated/subagent work: {r['model']}\n"
         f"- max suggested agent fan-out: {r.get('profile',{}).get('max_agents',3)} | context budget: {r.get('profile',{}).get('context_budget','medium')} | validation policy: {r.get('profile',{}).get('validation','risk_based')}\n"
         f"- needs substantial reasoning: {getn('needs_system2')} | production risk: {getn('production_risk')} | validation needed: {getn('needs_validation')} | parallelizable: {getn('parallelizable')}\n"
         "Use these as routing hints, not facts. This advice does not switch the running model.")
    if any(r.get('candidates', {}).values()):
        ctx += (f"\nProject catalog: skills: {fmt_multi('skills')}; agent: {fmt_single('agents')}; "
                f"command: {fmt_single('commands')}; template: {fmt_single('templates')}. "
                "Load only relevant selected components; a suggestion does not authorize delegation.")
    print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":ctx}},ensure_ascii=False))
    return 0
if __name__=='__main__':raise SystemExit(main())
