#!/usr/bin/env python3
"""Build and validate Datarim's canonical framework relationship graph.

Inventory is discovered from the repository; command sequencing is declared in
command-graph.yaml; command->agent and consumer->skill edges are extracted from
explicit repository references. Generated maps are deterministic and must not be
edited by hand.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dev-tools/framework-graph.yaml'
MAP=ROOT/'skills/visual-maps/framework-architecture.md'
CMDMAP=ROOT/'skills/visual-maps/command-dependencies.md'

def names(pattern): return sorted(p.stem for p in ROOT.glob(pattern) if p.is_file())
def skill_names(): return sorted(str(p.parent.relative_to(ROOT/'skills')) for p in (ROOT/'skills').glob('**/SKILL.md'))
def refs(text, kind):
    if kind=='agent': pat=r'(?:\$HOME/\.claude/)?agents/([A-Za-z0-9._-]+)\.md'
    else: pat=r'(?:\$HOME/\.claude/)?skills/([A-Za-z0-9._/-]+)/SKILL\.md'
    return sorted(set(re.findall(pat,text)))
def load():
    commands=names('commands/*.md'); agents=names('agents/*.md'); skills=skill_names()
    cg=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())['commands']
    edges=[]; broken=[]
    for c in commands:
        text=(ROOT/'commands'/f'{c}.md').read_text(errors='replace')
        for a in refs(text,'agent'):
            (edges if a in agents else broken).append({'from':f'command:{c}','relation':'delegates_to','to':f'agent:{a}','source':f'commands/{c}.md'})
        for s in refs(text,'skill'):
            (edges if s in skills else broken).append({'from':f'command:{c}','relation':'loads','to':f'skill:{s}','source':f'commands/{c}.md'})
    for a in agents:
        text=(ROOT/'agents'/f'{a}.md').read_text(errors='replace')
        for s in refs(text,'skill'):
            (edges if s in skills else broken).append({'from':f'agent:{a}','relation':'loads','to':f'skill:{s}','source':f'agents/{a}.md'})
    for c,meta in cg.items():
        for r in meta.get('requires',[]): edges.append({'from':f'command:{c}','relation':'requires','to':f'command:{r}','source':'dev-tools/command-graph.yaml'})
        for p in meta.get('precedes',[]): edges.append({'from':f'command:{c}','relation':'precedes','to':f'command:{p}','source':'dev-tools/command-graph.yaml'})
    edges=sorted({(e['from'],e['relation'],e['to'],e['source']):json.dumps(e,sort_keys=True) for e in edges}.values())
    edges=[json.loads(e) for e in edges]
    return {'schema_version':1,'generated':True,'inventory':{'commands':commands,'agents':agents,'skills':skills},'edges':edges,'broken_references':broken}
def validate(g):
    errs=[]; inv=g['inventory']; cg=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())['commands']
    disk=set(inv['commands']); declared=set(cg)
    if disk!=declared: errs.append(f'command inventory drift: files-only={sorted(disk-declared)} graph-only={sorted(declared-disk)}')
    if g['broken_references']: errs += ['broken reference: '+str(x) for x in g['broken_references']]
    for c,m in cg.items():
        for x in m.get('requires',[])+m.get('precedes',[]):
            if x not in declared: errs.append(f'{c} references unknown command {x}')
    return errs
def render(g):
    inv=g['inventory']; edges=g['edges']
    ca=[e for e in edges if e['relation']=='delegates_to']; ask=[e for e in edges if e['from'].startswith('agent:') and e['relation']=='loads']
    def id_(x): return re.sub(r'[^A-Za-z0-9_]','_',x)
    out=['# Framework Architecture — Generated Map','', '> **GENERATED FILE. DO NOT EDIT.** Source: repository inventory + `dev-tools/command-graph.yaml` + explicit references in commands/agents. Regenerate with `python3 dev-tools/framework-graph.py --write`.','',f"Inventory: **{len(inv['commands'])} commands · {len(inv['agents'])} agents · {len(inv['skills'])} skills**.",'','## Command → Agent graph','','```mermaid','graph LR']
    for e in ca: out.append(f"    C_{id_(e['from'][8:])}[\"/{e['from'][8:]}\"] --> A_{id_(e['to'][6:])}[\"{e['to'][6:]}\"]")
    if not ca: out.append('    none["No explicit command → agent references"]')
    out += ['```','','## Agent → Skill graph','','```mermaid','graph LR']
    for e in ask: out.append(f"    A_{id_(e['from'][6:])}[\"{e['from'][6:]}\"] --> S_{id_(e['to'][6:])}[\"{e['to'][6:]}\"]")
    out += ['```','','## Complete inventory','','### Commands','',', '.join(f'`/{x}`' for x in inv['commands']),'','### Agents','',', '.join(f'`{x}`' for x in inv['agents']),'','### Skills','',', '.join(f'`{x}`' for x in inv['skills']),'']
    return '\n'.join(out)
def render_cmd(g):
    cg=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())['commands']
    lines=['# Command Dependencies — Generated Map','', '> **GENERATED FILE. DO NOT EDIT.** Source: `dev-tools/command-graph.yaml`. Regenerate with `python3 dev-tools/framework-graph.py --write`.','',f"Full Command Inventory ({len(cg)} commands)",'','```mermaid','graph LR']
    emitted=set()
    for c,m in cg.items():
        if not m.get('precedes') and not m.get('requires'): lines.append(f'    {c}["/{c}"]')
        for p in m.get('precedes',[]):
            key=(c,p)
            if key not in emitted: lines.append(f'    {c}["/{c}"] --> {p}["/{p}"]'); emitted.add(key)
    lines += ['```','','## Inventory','']+[f'- `/{c}` — stage `{m.get("stage","unknown")}`'+(' · entry point' if m.get('entry') else '') for c,m in cg.items()]+['']
    return '\n'.join(lines)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--write',action='store_true'); ap.add_argument('--check',action='store_true'); a=ap.parse_args(); g=load(); errs=validate(g)
    if a.write:
        OUT.write_text(yaml.safe_dump(g,sort_keys=False,width=120)); MAP.write_text(render(g)); CMDMAP.write_text(render_cmd(g))
    if a.check or not a.write:
        expected=yaml.safe_dump(g,sort_keys=False,width=120)
        if OUT.exists() and OUT.read_text()!=expected: errs.append('dev-tools/framework-graph.yaml is stale; run --write')
        if MAP.exists() and MAP.read_text()!=render(g): errs.append('framework-architecture.md is stale; run --write')
        if CMDMAP.exists() and CMDMAP.read_text()!=render_cmd(g): errs.append('command-dependencies.md is stale; run --write')
    if errs:
        print('\n'.join('ERROR: '+e for e in errs),file=sys.stderr); return 1
    print(f"framework graph OK: {len(g['inventory']['commands'])} commands, {len(g['inventory']['agents'])} agents, {len(g['inventory']['skills'])} skills, {len(g['edges'])} edges")
    return 0
if __name__=='__main__': raise SystemExit(main())
