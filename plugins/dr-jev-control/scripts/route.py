#!/usr/bin/env python3
import argparse,json,os,sys
from pathlib import Path
from jev_client import evaluate,JevError
from catalog import inventory,shortlist
from project_state import state_dir
import components

# Minimal config that keeps every consumer on its documented fail-open path when
# the real file is missing, unreadable, or corrupt. `routing.enabled: False`
# means "advise nothing", which is exactly what a broken control plane should do:
# Datarim and the host CLI must keep working with no Jev input at all.
_FALLBACK_CFG={
    "api":{"timeout_seconds":15,"retries":2,"connect_timeout_seconds":5,
           "hook_timeout_seconds":4,"hook_retries":0,"transport":"auto"},
    "routing":{"enabled":False,"default_model":"sonnet","default_mode":"balanced",
               "catalog_shortlist":12,"max_state_chars":18000,
               "risk_thresholds":{"advisory":0.55,"require_review":0.78,"deny_autonomous":0.94},
               "component_selection":{},"modes":{}},
    "live":{"enabled":False},
    "hooks":{"prompt_router":False,"pretool_risk":False,"enforce_jev_denials":False},
    "telemetry":{"enabled":False},
}

def kill_switch_reason():
    """Why the control plane is currently disabled, or None if it is active.

    Two operator-facing off switches, both usable without editing any config and
    without touching the installed hooks:
      * env `DATARIM_JEV_DISABLE=1`  -- per shell / per session
      * file `~/.datarim/jev/DISABLED` -- machine-wide, survives new shells
    The point is that turning the integration off must be easier and more
    reliable than the integration itself; an operator debugging a broken control
    plane should never have to hand-edit JSON to get plain Datarim back.
    """
    v=os.environ.get('DATARIM_JEV_DISABLE','').strip().lower()
    if v not in ('','0','false','no'): return f"env DATARIM_JEV_DISABLE={v}"
    flag=state_dir() / 'DISABLED'
    try:
        if flag.exists(): return f"flag file {flag}"
    except OSError:
        pass
    return None

def load_cfg(*, strict=False):
    """Load the control-plane config, degrading to a disabled-but-valid default.

    load_cfg() sits on the path of every hook the host CLI runs. A raised
    exception here exits the hook non-zero with a traceback on stderr, which is
    precisely the failure mode the fail-open design exists to prevent -- a
    corrupt config file would otherwise make the host CLI noisy or unusable.
    Callers that genuinely need to report a bad config (the `doctor`, the CLI)
    pass strict=True.

    The kill switch is honoured here so it covers every consumer at once,
    including any future one that forgets to check it.
    """
    off=kill_switch_reason()
    if off is not None:
        cfg=json.loads(json.dumps(_FALLBACK_CFG))
        cfg['disabled_reason']=off
        return cfg
    p=Path(os.environ.get('DATARIM_JEV_CONFIG',Path(__file__).resolve().parents[1]/'config/jev-control.json'))
    try:
        cfg=json.loads(p.read_text())
        if not isinstance(cfg,dict): raise ValueError("config root is not an object")
        return cfg
    except Exception:
        if strict: raise
        return json.loads(json.dumps(_FALLBACK_CFG))  # fresh copy per caller

def q_choice(prompt, options): return {"type":"choice","instructions":prompt,"criteria":options}
def q_noul(prompt,t="Yes",f="No"): return {"type":"noul","instructions":prompt,"criteria":{"true":t,"false":f}}
def q_score(prompt,levels): return {"type":"score","instructions":prompt,"criteria":levels}
def criteria(xs): return {x['name']:(x.get('description') or x.get('path')) for x in xs}

class RoutingDisabled(RuntimeError):
    """Routing is switched off by config or by the kill switch."""

def route(task,cfg=None,mode=None,*,budget=None):
    cfg=cfg or load_cfg(); mode=mode or cfg['routing'].get('default_mode','balanced')
    # `routing.enabled` is load-bearing, not decorative: the kill switch and the
    # fallback config both express "advise nothing" by clearing it, so anything
    # that reaches the API must check it or the switch would be bypassable by a
    # caller that builds its own cfg. Callers catch this and fail open.
    if not cfg.get('routing',{}).get('enabled',True):
        raise RoutingDisabled(cfg.get('disabled_reason') or 'routing.enabled is false')
    modes=cfg['routing'].get('modes',{}); profile=modes.get(mode,modes.get('balanced',{}))
    inv=inventory(); n=int(cfg['routing'].get('catalog_shortlist',12)); state=task[:int(cfg['routing'].get('max_state_chars',18000))]
    picks={k:shortlist(v,state,n) for k,v in inv.items()}
    mode_note=f"Operating mode: {mode}. {profile.get('description','')}"
    questions={
      "model_tier":q_choice(mode_note+" Choose the Claude model tier that best follows this mode while reliably completing the task. Prefer haiku for simple bounded work, sonnet for normal software engineering, opus only for genuinely difficult architecture, ambiguous multi-step reasoning, or high-stakes work.",{"haiku":"Simple, bounded, low-risk work","sonnet":"Normal engineering requiring meaningful reasoning","opus":"Very difficult, ambiguous, architectural, or high-stakes reasoning"}),
      "complexity":q_score("Rate implementation/reasoning complexity.",["Trivial","Simple","Moderate","Complex","Very complex"]),
      "needs_system2":q_noul("Does successful completion require substantial multi-step reasoning rather than a fast classification or mechanical operation?"),
      "production_risk":q_noul("Could an incorrect execution plausibly cause destructive, security-sensitive, production, data-loss, secret-exposure, irreversible, or externally visible effects?"),
      "needs_validation":q_noul("Should the result be independently validated with tests, review, static checks, or another verifier before it is accepted?"),
      "parallelizable":q_noul("Can meaningful independent subtasks be delegated in parallel without creating likely edit conflicts?"),
    }
    for kind,label in (("skills","skill"),("agents","agent"),("commands","command"),("templates","template")):
        opts=criteria(picks[kind]); opts["none"]="No listed component is materially useful"
        questions[f"{label}_choice"]=q_choice(f"Which single Datarim {label} is most useful for this task? Choose none when no candidate is materially useful.",opts)
    # Per-candidate applicability probes for kinds where several components can
    # apply at once. Batched into the same request: the API evaluates questions
    # in parallel, so these cost tokens but almost no extra latency.
    for kind in components.MULTI_KINDS:
        questions.update(components.build_probes(kind,picks[kind],cfg))
    res=evaluate(state,questions,cfg,budget=budget); a=res.get('answers',{})
    model=a.get('model_tier',{}).get('choice',cfg['routing'].get('default_model','sonnet'))
    # Deterministic mode guardrails: Jev advises within a policy envelope.
    if mode=='economy' and model=='opus': model='sonnet'
    if mode=='quality' and model=='haiku': model='sonnet'
    sel={}
    for kind in components.MULTI_KINDS:
        sel[kind]=components.resolve(kind,picks[kind],a,cfg)
    for kind,label in (("agents","agent"),("commands","command"),("templates","template")):
        sel[kind]=components.single_choice(a.get(f"{label}_choice"),cfg)
    out={"ok":True,"mode":mode,"profile":profile,"model":model,"answers":a,"selection":sel,
         "usage":res.get('usage',{}),"candidates":{k:[x['name'] for x in v] for k,v in picks.items()}}
    log(cfg,"route",task,out); return out

def log(cfg,event,text,data):
    # Single ledger implementation lives in ledger.py (adds secret redaction and
    # 0600 mode); this wrapper keeps the existing call sites and import path.
    from ledger import log_event
    log_event(cfg,event,text,data)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('task',nargs='?'); ap.add_argument('--stdin',action='store_true'); ap.add_argument('--pretty',action='store_true')
    ap.add_argument('--summary',action='store_true',help='compact operator-facing decision summary')
    ap.add_argument('--explain',action='store_true',help='summary plus the full probability JSON')
    ap.add_argument('--mode',choices=['economy','balanced','quality'],default=None); args=ap.parse_args()
    task=sys.stdin.read() if args.stdin else (args.task or '')
    off=kill_switch_reason()
    if off is not None:
        # Say so out loud rather than routing on defaults: an operator running
        # the CLI wants to know the control plane is switched off.
        print(json.dumps({"ok":False,"disabled":True,"reason":off,
                          "model":_FALLBACK_CFG['routing']['default_model']},ensure_ascii=False,
                         indent=2 if (args.pretty or args.explain) else None))
        return 3
    # The interactive CLI is strict about the config on purpose: silently routing
    # on built-in defaults would hide a broken control plane from the operator.
    # Hooks take the opposite path (see load_cfg) because there the priority is
    # keeping the host CLI usable.
    try: out=route(task,load_cfg(strict=True),mode=args.mode)
    except Exception as e:
        try: fallback_model=load_cfg()['routing'].get('default_model','sonnet')
        except Exception: fallback_model='sonnet'
        out={"ok":False,"error":str(e),"model":fallback_model}
    if (args.summary or args.explain) and out.get('ok'):
        from live_supervisor import render_summary
        print(render_summary(out))
        if args.explain: print(json.dumps(out,ensure_ascii=False,indent=2))
    else:
        print(json.dumps(out,ensure_ascii=False,indent=2 if (args.pretty or args.explain) else None))
    return 0 if out.get('ok') else 2
if __name__=='__main__':raise SystemExit(main())
