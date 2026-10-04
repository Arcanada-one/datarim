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
    templates=sorted(str(p.relative_to(ROOT/'templates')) for p in (ROOT/'templates').rglob('*') if p.is_file())
    declarations=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())
    cg=declarations['commands']
    always=declarations.get('always_load_skills', [])
    edges=[]; broken=[]
    for c in commands:
        for s in always:
            (edges if s in skills else broken).append({'from':f'command:{c}','relation':'loads','to':f'skill:{s}','source':'AGENTS.md'})
        text=(ROOT/'commands'/f'{c}.md').read_text(errors='replace')
        for a in refs(text,'agent'):
            (edges if a in agents else broken).append({'from':f'command:{c}','relation':'delegates_to','to':f'agent:{a}','source':f'commands/{c}.md'})
        for s in refs(text,'skill'):
            (edges if s in skills else broken).append({'from':f'command:{c}','relation':'loads','to':f'skill:{s}','source':f'commands/{c}.md'})
    for a in agents:
        for s in always:
            (edges if s in skills else broken).append({'from':f'agent:{a}','relation':'loads','to':f'skill:{s}','source':'AGENTS.md'})
        text=(ROOT/'agents'/f'{a}.md').read_text(errors='replace')
        for s in refs(text,'skill'):
            (edges if s in skills else broken).append({'from':f'agent:{a}','relation':'loads','to':f'skill:{s}','source':f'agents/{a}.md'})
    # Skill routers also load fragments and other skills. Keep these edges in
    # the graph rather than reporting only the command/agent subset as complete.
    fragments = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'skills').rglob('*.md') if p.name != 'SKILL.md')
    for path in sorted((ROOT/'skills').rglob('*.md')):
        source = str(path.relative_to(ROOT))
        text = path.read_text()
        targets = {ROOT/'skills'/target for target in re.findall(
            r'(?<!local/)skills/([A-Za-z0-9._/-]+\.md)', text)}
        # Bare sibling Markdown links are portable with their skill bundle.
        # Resolve relative to the source file, not the consumer's cwd. Cross-skill
        # root references retain their existing extraction and edge identity.
        siblings = re.findall(
            r'\[[^\]\n]*\]\((?:\./)?([A-Za-z0-9][A-Za-z0-9._-]*\.md)(?:#[A-Za-z0-9._-]+)?\)', text)
        targets.update(path.parent/name for name in siblings)
        for full in sorted(targets):
            target = str(full.relative_to(ROOT/'skills'))
            is_skill = target.endswith('/SKILL.md')
            node = 'skill:'+target.removesuffix('/SKILL.md') if is_skill else 'fragment:skills/'+target
            edge = {'from': 'skill:'+str(path.parent.relative_to(ROOT/'skills')) if path.name == 'SKILL.md' else 'fragment:'+source,
                    'relation': 'loads', 'to': node, 'source': source}
            (edges if full.is_file() and full.resolve().is_relative_to(ROOT.resolve()) else broken).append(edge)
    # Templates are real runtime dependencies, not a separate decorative catalog.
    # Extract references from all instruction sources and connect the full asset
    # inventory. Match known names so punctuation/prose cannot become a path.
    sources = [(ROOT/'commands'/f'{c}.md', 'command:'+c) for c in commands]
    sources += [(ROOT/'agents'/f'{a}.md', 'agent:'+a) for a in agents]
    sources += [(p, 'skill:'+str(p.parent.relative_to(ROOT/'skills')) if p.name=='SKILL.md' else 'fragment:'+str(p.relative_to(ROOT))) for p in (ROOT/'skills').rglob('*.md') if p not in (MAP,CMDMAP)]
    sources += [(ROOT/'templates'/n, 'template:'+n) for n in templates if n.endswith(('.md','.sh','.yml','.yaml','.template'))]
    for path, node in sources:
        text=path.read_text(errors='replace')
        for target in templates:
            if re.search(r'(?<!datarim/)templates/'+re.escape(target)+r'(?![A-Za-z0-9._/-])', text):
                edges.append({'from':node,'relation':'uses_template','to':'template:'+target,'source':str(path.relative_to(ROOT))})
    # Declared delegation conditions annotate the derived command->agent edge.
    # The edge itself comes from the explicit reference in the command file; the
    # condition cannot be derived from a reference, so it is declared.
    conditions={(c,a):cond for c,meta in cg.items() for a,cond in (meta.get('delegates_when') or {}).items()}
    for e in edges:
        if e['relation']=='delegates_to':
            cond=conditions.get((e['from'][8:], e['to'][6:]))
            if cond: e['condition']=cond
    for c,meta in cg.items():
        for r in meta.get('requires',[]): edges.append({'from':f'command:{c}','relation':'requires','to':f'command:{r}','source':'dev-tools/command-graph.yaml'})
        for p in meta.get('precedes',[]): edges.append({'from':f'command:{c}','relation':'precedes','to':f'command:{p}','source':'dev-tools/command-graph.yaml'})
    edges=sorted({(e['from'],e['relation'],e['to'],e['source']):json.dumps(e,sort_keys=True) for e in edges}.values())
    edges=[json.loads(e) for e in edges]
    return {'schema_version':2,'generated':True,'inventory':{'commands':commands,'agents':agents,'skills':skills,'fragments':fragments,'templates':templates},'edges':edges,'broken_references':broken}
def validate(g):
    errs=[]; inv=g['inventory']; cg=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())['commands']
    declarations=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())
    global_path=ROOT/'AGENTS.md'
    global_rules=global_path.read_text() if global_path.is_file() else ''
    for skill in declarations.get('always_load_skills', []):
        if f'skills/{skill}/SKILL.md' not in global_rules:
            errs.append(f'always-loaded skill is not declared in AGENTS.md: {skill}')
    disk=set(inv['commands']); declared=set(cg)
    if disk!=declared: errs.append(f'command inventory drift: files-only={sorted(disk-declared)} graph-only={sorted(declared-disk)}')
    if g['broken_references']: errs += ['broken reference: '+str(x) for x in g['broken_references']]
    nodes={kind+':'+name for kind,items in [('command',inv['commands']),('agent',inv['agents']),('skill',inv['skills']),('fragment',inv['fragments']),('template',inv['templates'])] for name in items}
    for edge in g['edges']:
        if edge['from'] not in nodes or edge['to'] not in nodes:
            errs.append('edge references unknown node: '+str(edge))
    for skill in inv['skills']:
        text=(ROOT/'skills'/skill/'SKILL.md').read_text()
        parts=text.split('---',2)
        metadata=yaml.safe_load(parts[1]) if len(parts)==3 and not parts[0].strip() else {}
        if not isinstance(metadata,dict):
            errs.append(f'{skill}: invalid frontmatter')
            continue
        if metadata.get('name') != skill.replace('/', '-'):
            errs.append(f'{skill}: frontmatter name does not match directory')
        if not isinstance(metadata.get('description'),str) or len(metadata['description'].strip())<40:
            errs.append(f'{skill}: description must have at least 40 characters')
    for c,m in cg.items():
        for x in m.get('requires',[])+m.get('precedes',[]):
            if x not in declared: errs.append(f'{c} references unknown command {x}')
    return errs
def render(g):
    inv=g['inventory']; edges=g['edges']
    ca=[e for e in edges if e['relation']=='delegates_to']; ask=[e for e in edges if e['from'].startswith('agent:') and e['relation']=='loads']
    def id_(x): return re.sub(r'[^A-Za-z0-9_]','_',x)
    out=['# Framework Architecture — Generated Map','', '> **GENERATED FILE. DO NOT EDIT.** Source: repository inventory + `dev-tools/command-graph.yaml` + explicit references in commands/agents. Regenerate with `python3 dev-tools/framework-graph.py --write`.','',f"Inventory: **{len(inv['commands'])} commands · {len(inv['agents'])} agents · {len(inv['skills'])} skills · {len(inv['templates'])} template assets**.",'','## Command → Agent graph','','```mermaid','graph LR']
    for e in ca:
        arrow = f'-.->|"{e["condition"]}"|' if e.get('condition') else '-->'
        out.append(f"    C_{id_(e['from'][8:])}[\"/{e['from'][8:]}\"] {arrow} A_{id_(e['to'][6:])}[\"{e['to'][6:]}\"]")
    if not ca: out.append('    none["No explicit command → agent references"]')
    out += ['```','','## Agent → Skill graph','','```mermaid','graph LR']
    for e in ask: out.append(f"    A_{id_(e['from'][6:])}[\"{e['from'][6:]}\"] --> S_{id_(e['to'][6:])}[\"{e['to'][6:]}\"]")
    out += ['```','','## Complete inventory','','### Commands','',', '.join(f'`/{x}`' for x in inv['commands']),'','### Agents','',', '.join(f'`{x}`' for x in inv['agents']),'','### Skills','',', '.join(f'`{x}`' for x in inv['skills']),'']
    out += ['## Template dependencies', '', '| Consumer | Template |', '|----------|----------|']
    out += [f"| `{e['from']}` | `{e['to'][9:]}` |" for e in edges if e['relation']=='uses_template']
    out += ['', '### Template assets', '', ', '.join(f'`{x}`' for x in inv['templates']), '']
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
        if not OUT.is_file() or OUT.read_text()!=expected: errs.append('dev-tools/framework-graph.yaml is missing or stale; run --write')
        if not MAP.is_file() or MAP.read_text()!=render(g): errs.append('framework-architecture.md is missing or stale; run --write')
        if not CMDMAP.is_file() or CMDMAP.read_text()!=render_cmd(g): errs.append('command-dependencies.md is missing or stale; run --write')
    if errs:
        print('\n'.join('ERROR: '+e for e in errs),file=sys.stderr); return 1
    print(f"framework graph OK: {len(g['inventory']['commands'])} commands, {len(g['inventory']['agents'])} agents, {len(g['inventory']['skills'])} skills, {len(g['edges'])} edges")
    return 0
if __name__=='__main__': raise SystemExit(main())
