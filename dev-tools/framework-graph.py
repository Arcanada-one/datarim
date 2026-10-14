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

def plugin_component_id(plugin_id, category, path):
    relative = path.relative_to(ROOT)
    if category == 'skills':
        skill_root = ROOT/'plugins'/plugin_id/'skills'
        if path.name == 'SKILL.md':
            return 'skill:'+plugin_id+'/'+str(path.parent.relative_to(skill_root))
        if path.suffix == '.md':
            return 'fragment:'+str(relative)
    if category == 'templates':
        return 'template:'+str(relative)
    return 'plugin_asset:'+str(relative)

def plugin_packages():
    """Discover optional packages only from manifests and declared asset roots."""
    packages=[]; owners={}; component_ids=set()
    plugin_root=(ROOT/'plugins').resolve()
    for manifest in sorted((ROOT/'plugins').glob('*/plugin.yaml')):
        if manifest.is_symlink() or manifest.parent.is_symlink() or not manifest.resolve().is_relative_to(plugin_root):
            raise ValueError(f'plugin manifest escapes package root: {manifest.relative_to(ROOT)}')
        data=yaml.safe_load(manifest.read_text())
        if not isinstance(data,dict):
            raise ValueError(f'invalid plugin manifest: {manifest.relative_to(ROOT)}')
        plugin_id=data.get('id')
        if not isinstance(plugin_id,str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,31}',plugin_id):
            raise ValueError(f'invalid plugin id: {manifest.relative_to(ROOT)}')
        if manifest.parent.name != plugin_id:
            raise ValueError(f'plugin id does not match directory: {manifest.relative_to(ROOT)}')
        categories=data.get('categories') or []
        if (not isinstance(categories,list) or
                any(not isinstance(x,str) or not re.fullmatch(r'[a-z][a-z0-9-]*',x) for x in categories) or
                len(categories) != len(set(categories))):
            raise ValueError(f'invalid plugin categories: {manifest.relative_to(ROOT)}')
        if plugin_id in owners:
            raise ValueError(f'duplicate plugin id: {plugin_id}')
        owners[plugin_id]=str(manifest.relative_to(ROOT))
        default_enabled=data.get('default_enabled',False)
        if not isinstance(default_enabled,bool):
            raise ValueError(f'invalid default_enabled value: {manifest.relative_to(ROOT)}')
        assets=[]
        for category in sorted(categories):
            category_root=manifest.parent/category
            if category_root.is_symlink():
                raise ValueError(f'plugin category is a symlink: {category_root.relative_to(ROOT)}')
            if not category_root.is_dir():
                continue
            for path in sorted(category_root.rglob('*')):
                if path.is_symlink():
                    raise ValueError(f'plugin asset is a symlink: {path.relative_to(ROOT)}')
                if not path.is_file():
                    continue
                resolved=path.resolve()
                if not resolved.is_relative_to(category_root.resolve()):
                    raise ValueError(f'plugin asset escapes category root: {path.relative_to(ROOT)}')
                asset_path=str(path.relative_to(ROOT))
                component=plugin_component_id(plugin_id,category,path)
                if component in component_ids:
                    raise ValueError(f'duplicate plugin component id: {component}')
                component_ids.add(component)
                assets.append({'path':asset_path,'category':category,'component_id':component})
        packages.append({'id':plugin_id,'manifest':str(manifest.relative_to(ROOT)),
                         'default_enabled':default_enabled,
                         'default_state':'active' if default_enabled else 'disabled',
                         'categories':sorted(categories),'assets':assets})
    return packages

def plugin_owner_map(packages):
    return {asset['component_id']:package['id']
            for package in packages for asset in package['assets']}

def skill_roots():
    roots=[ROOT/'skills']
    for manifest in sorted((ROOT/'plugins').glob('*/plugin.yaml')):
        data=yaml.safe_load(manifest.read_text()) or {}
        root=manifest.parent/'skills'
        if 'skills' in (data.get('categories') or []) and root.is_dir():
            roots.append(root)
    return roots
def skill_files():
    return sorted((p for root in skill_roots() for p in root.rglob('*.md')), key=lambda p: str(p))
def skill_name(path):
    if path.is_relative_to(ROOT/'skills'):
        return str(path.parent.relative_to(ROOT/'skills'))
    for root in skill_roots()[1:]:
        if path.is_relative_to(root):
            return root.parent.name+'/'+str(path.parent.relative_to(root))
    raise ValueError(f'not a skill asset: {path}')
def skill_path(name):
    if '/' in name:
        plugin, relative = name.split('/', 1)
        candidate=ROOT/'plugins'/plugin/'skills'/relative
        if candidate.is_dir(): return candidate
    return ROOT/'skills'/name
def skill_names(): return sorted(skill_name(p) for p in skill_files() if p.name=='SKILL.md')
def refs(text, kind):
    if kind=='agent':
        pat=r'(?:\$HOME/\.claude/)?agents/([A-Za-z0-9._-]+)\.md'
        return sorted(set(re.findall(pat,text)))
    plugin_pat=r'plugins/([A-Za-z0-9._-]+)/skills/([A-Za-z0-9._/-]+)/SKILL\.md'
    plugin_refs={plugin+'/'+relative for plugin,relative in re.findall(plugin_pat,text)}
    text=re.sub(plugin_pat,'',text)
    pat=r'(?:\$HOME/\.claude/)?skills/([A-Za-z0-9._/-]+)/SKILL\.md'
    return sorted(plugin_refs|set(re.findall(pat,text)))

def profile_condition_required(plugin_id, text):
    if plugin_id != 'product-discovery':
        return False
    return bool(re.search(r'product[- ]discovery.{0,120}profile|profile.{0,120}product[- ]discovery',text,re.I|re.S))

def plugin_condition(plugin_id, profile_required=False):
    condition={'plugin_enabled':plugin_id}
    if profile_required:
        condition['profile_selected']=plugin_id
    return condition

def plugin_template_mentions(text, templates):
    """Resolve explicit template names in plugin instructions to discovered files."""
    found=[]
    for target in templates:
        if not target.startswith('plugins/'):
            continue
        stem=Path(target).stem
        pieces=[re.escape(piece) for piece in re.split(r'[-_ ]+',stem)]
        pattern=r'(?<![A-Za-z0-9])'+r'[-_ ]?'.join(pieces)+r'(?![A-Za-z0-9])'
        if re.search(pattern,text,re.I):
            found.append(target)
    return sorted(found)

def runtime_fragment_refs(text):
    """Map installed local skill paths back to their checked-in plugin assets."""
    refs = set()
    pattern = r'\$\{DATARIM_RUNTIME[^}]*\}/local/skills/([A-Za-z0-9._-]+)/([A-Za-z0-9._/-]+\.md)'
    for plugin, relative in re.findall(pattern, text):
        if any(part in (".", "..") for part in Path(relative).parts):
            continue
        plugin_root = ROOT/'plugins'/plugin/'skills'
        candidate = plugin_root/relative
        if candidate.is_file() and candidate.resolve().is_relative_to(plugin_root.resolve()):
            refs.add(str(candidate.relative_to(ROOT)))
    return sorted(refs)
def load():
    packages=plugin_packages(); owners=plugin_owner_map(packages)
    commands=names('commands/*.md'); agents=names('agents/*.md'); skills=skill_names()
    templates=sorted([str(p.relative_to(ROOT/'templates')) for p in (ROOT/'templates').rglob('*') if p.is_file()] +
                     [a['path'] for package in packages for a in package['assets'] if a['category']=='templates'])
    declarations=yaml.safe_load((ROOT/'dev-tools/command-graph.yaml').read_text())
    cg=declarations['commands']
    always=declarations.get('always_load_skills', [])
    edges=[]; broken=[]
    for package in packages:
        for asset in package['assets']:
            edges.append({'from':'plugin:'+package['id'],'relation':'contains',
                          'to':asset['component_id'],'source':package['manifest'],
                          'condition':plugin_condition(package['id'])})
    for c in commands:
        for s in always:
            (edges if s in skills else broken).append({'from':f'command:{c}','relation':'loads','to':f'skill:{s}','source':'AGENTS.md'})
        text=(ROOT/'commands'/f'{c}.md').read_text(errors='replace')
        for a in refs(text,'agent'):
            (edges if a in agents else broken).append({'from':f'command:{c}','relation':'delegates_to','to':f'agent:{a}','source':f'commands/{c}.md'})
        for s in refs(text,'skill'):
            target=f'skill:{s}'; owner=owners.get(target)
            if owner:
                edges.append({'from':f'command:{c}','relation':'loads','to':'plugin:'+owner,
                              'source':f'commands/{c}.md','condition':plugin_condition(owner,profile_condition_required(owner,text))})
            (edges if s in skills else broken).append({'from':f'command:{c}','relation':'loads','to':target,'source':f'commands/{c}.md',**({'condition':plugin_condition(owner,profile_condition_required(owner,text))} if owner else {})})
    for a in agents:
        for s in always:
            (edges if s in skills else broken).append({'from':f'agent:{a}','relation':'loads','to':f'skill:{s}','source':'AGENTS.md'})
        text=(ROOT/'agents'/f'{a}.md').read_text(errors='replace')
        for s in refs(text,'skill'):
            target=f'skill:{s}'; owner=owners.get(target)
            if owner:
                edges.append({'from':f'agent:{a}','relation':'loads','to':'plugin:'+owner,
                              'source':f'agents/{a}.md','condition':plugin_condition(owner,profile_condition_required(owner,text))})
            (edges if s in skills else broken).append({'from':f'agent:{a}','relation':'loads','to':target,'source':f'agents/{a}.md',**({'condition':plugin_condition(owner,profile_condition_required(owner,text))} if owner else {})})
        for target in runtime_fragment_refs(text):
            full = ROOT/target
            node = 'skill:'+skill_name(full) if full.name == 'SKILL.md' else 'fragment:'+target
            owner=owners.get(node)
            if owner:
                edges.append({'from':f'agent:{a}','relation':'loads','to':'plugin:'+owner,
                              'source':f'agents/{a}.md','condition':plugin_condition(owner,profile_condition_required(owner,text))})
            edges.append({'from':f'agent:{a}','relation':'loads','to':node,'source':f'agents/{a}.md',
                          **({'condition':plugin_condition(owner,profile_condition_required(owner,text))} if owner else {})})
    # Skill routers also load fragments and other skills. Keep these edges in
    # the graph rather than reporting only the command/agent subset as complete.
    fragments = sorted(str(p.relative_to(ROOT)) for p in skill_files() if p.name != 'SKILL.md')
    for path in skill_files():
        if path in (MAP, CMDMAP):
            continue
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
            target = skill_name(full)+'/SKILL.md' if full.name=='SKILL.md' and full.is_file() else str(full.relative_to(ROOT))
            is_skill = target.endswith('/SKILL.md')
            node = 'skill:'+target.removesuffix('/SKILL.md') if is_skill else 'fragment:'+target
            edge = {'from': 'skill:'+skill_name(path) if path.name == 'SKILL.md' else 'fragment:'+source,
                    'relation': 'loads', 'to': node, 'source': source}
            (edges if full.is_file() and full.resolve().is_relative_to(ROOT.resolve()) else broken).append(edge)
        for target in plugin_template_mentions(text,templates):
            owner=next((p['id'] for p in packages if target in [a['path'] for a in p['assets']]),None)
            node='template:'+target
            edges.append({'from':'skill:'+skill_name(path) if path.name=='SKILL.md' else 'fragment:'+source,
                          'relation':'uses_template','to':node,'source':source,
                          **({'condition':plugin_condition(owner)} if owner else {})})
    # Templates are real runtime dependencies, not a separate decorative catalog.
    # Extract references from all instruction sources and connect the full asset
    # inventory. Match known names so punctuation/prose cannot become a path.
    sources = [(ROOT/'commands'/f'{c}.md', 'command:'+c) for c in commands]
    sources += [(ROOT/'agents'/f'{a}.md', 'agent:'+a) for a in agents]
    sources += [(p, 'skill:'+skill_name(p) if p.name=='SKILL.md' else 'fragment:'+str(p.relative_to(ROOT))) for p in skill_files() if p not in (MAP,CMDMAP)]
    sources += [(ROOT/n if n.startswith('plugins/') else ROOT/'templates'/n, 'template:'+n)
                for n in templates if n.endswith(('.md','.sh','.yml','.yaml','.template'))]
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
    edges=sorted(json.dumps(e,sort_keys=True) for e in edges)
    edges=[json.loads(e) for e in edges]
    return {'schema_version':3,'generated':True,'inventory':{'commands':commands,'agents':agents,'skills':skills,'fragments':fragments,'templates':templates,'plugins':packages},'edges':edges,'broken_references':broken}
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
    nodes.update('plugin:'+p['id'] for p in inv.get('plugins',[]))
    nodes.update(a['component_id'] for p in inv.get('plugins',[]) for a in p['assets'])
    plugin_nodes={'plugin:'+p['id'] for p in inv.get('plugins',[])}
    plugin_asset_nodes={a['component_id'] for p in inv.get('plugins',[]) for a in p['assets']}
    for edge in g['edges']:
        if edge['from'] not in nodes or edge['to'] not in nodes:
            errs.append('edge references unknown node: '+str(edge))
        condition=edge.get('condition')
        if condition:
            if isinstance(condition,dict):
                known={p['id'] for p in inv.get('plugins',[])}
                if condition.get('plugin_enabled') not in known:
                    errs.append('conditional edge references unknown plugin: '+str(edge))
                if condition.get('profile_selected') and condition['profile_selected'] != condition.get('plugin_enabled'):
                    errs.append('conditional edge has inconsistent profile selector: '+str(edge))
                if edge['from'] not in plugin_nodes|plugin_asset_nodes and edge['to'] not in plugin_nodes|plugin_asset_nodes:
                    errs.append('conditional edge does not touch a plugin node: '+str(edge))
            elif not isinstance(condition,str):
                errs.append('edge condition must be text or a plugin condition mapping: '+str(edge))
    if inv.get('plugins') != plugin_packages():
        errs.append('plugin inventory is stale or hand-maintained; regenerate from plugin.yaml and declared asset directories')
    for skill in inv['skills']:
        skill_file=skill_path(skill)/'SKILL.md'
        text=skill_file.read_text()
        parts=text.split('---',2)
        metadata=yaml.safe_load(parts[1]) if len(parts)==3 and not parts[0].strip() else {}
        if not isinstance(metadata,dict):
            errs.append(f'{skill}: invalid frontmatter')
            continue
        plugin_names={root.parent.name for root in skill_roots()[1:]}
        expected_name=skill.rsplit('/',1)[-1] if skill.split('/',1)[0] in plugin_names else skill.replace('/', '-')
        if metadata.get('name') != expected_name:
            errs.append(f'{skill}: frontmatter name does not match directory')
        if not isinstance(metadata.get('description'),str) or len(metadata['description'].strip())<40:
            errs.append(f'{skill}: description must have at least 40 characters')
    for c,m in cg.items():
        for x in m.get('requires',[])+m.get('precedes',[]):
            if x not in declared: errs.append(f'{c} references unknown command {x}')
    legacy_nodes=nodes-plugin_nodes-plugin_asset_nodes
    full_legacy={(e['from'],e['relation'],e['to'],e['source']) for e in g['edges']
                 if e['from'] in legacy_nodes and e['to'] in legacy_nodes}
    off_legacy={(e['from'],e['relation'],e['to'],e['source']) for e in project(g,'off')['edges']
                 if e['from'] in legacy_nodes and e['to'] in legacy_nodes}
    if full_legacy != off_legacy:
        errs.append('profile-off changes legacy-to-legacy reachability edges')
    return errs

def project(g, profile):
    """Return reachable graph state with product-discovery explicitly on or off."""
    enabled={p['id'] for p in g['inventory'].get('plugins',[]) if p['default_enabled']}
    if profile == 'on':
        enabled.add('product-discovery')
    elif profile == 'off':
        enabled.discard('product-discovery')
    else:
        raise ValueError(f'unknown product-discovery profile state: {profile}')
    eligible=[]
    for edge in g['edges']:
        condition=edge.get('condition') or {}
        if isinstance(condition,str):
            eligible.append(edge)
            continue
        plugin_id=condition.get('plugin_enabled')
        if plugin_id and plugin_id not in enabled:
            continue
        profile_id=condition.get('profile_selected')
        if profile_id and (profile_id != 'product-discovery' or profile != 'on'):
            continue
        eligible.append(edge)
    inv=g['inventory']; optional={'plugin:'+p['id'] for p in inv.get('plugins',[])}
    optional.update(a['component_id'] for p in inv.get('plugins',[]) for a in p['assets'])
    roots={kind+':'+name for kind,items in [('command',inv['commands']),('agent',inv['agents']),
             ('skill',inv['skills']),('fragment',inv['fragments']),('template',inv['templates'])] for name in items}
    roots-=optional
    outgoing={}
    for edge in eligible:
        outgoing.setdefault(edge['from'],[]).append(edge['to'])
    reachable=set(roots); pending=list(roots)
    while pending:
        node=pending.pop()
        for target in outgoing.get(node,[]):
            if target not in reachable:
                reachable.add(target); pending.append(target)
    return {'nodes':reachable,'edges':[e for e in eligible if e['from'] in reachable and e['to'] in reachable]}
def render(g):
    inv=g['inventory']; edges=g['edges']
    ca=[e for e in edges if e['relation']=='delegates_to']; ask=[e for e in edges if e['from'].startswith('agent:') and e['relation']=='loads']
    def id_(x): return re.sub(r'[^A-Za-z0-9_]','_',x)
    def target(kind_name):
        kind, name = kind_name.split(':', 1)
        node_prefix = {'skill': 'S', 'fragment': 'F'}.get(kind, kind.upper())
        return f'{node_prefix}_{id_(name)}', name
    out=['# Framework Architecture — Generated Map','', '> **GENERATED FILE. DO NOT EDIT.** Source: repository inventory + `dev-tools/command-graph.yaml` + explicit references in commands/agents. Regenerate with `python3 dev-tools/framework-graph.py --write`.','',f"Inventory: **{len(inv['commands'])} commands · {len(inv['agents'])} agents · {len(inv['skills'])} skills · {len(inv['templates'])} template assets**.",'','## Command → Agent graph','','```mermaid','graph LR']
    for e in ca:
        arrow = f'-.->|"{e["condition"]}"|' if e.get('condition') else '-->'
        out.append(f"    C_{id_(e['from'][8:])}[\"/{e['from'][8:]}\"] {arrow} A_{id_(e['to'][6:])}[\"{e['to'][6:]}\"]")
    if not ca: out.append('    none["No explicit command → agent references"]')
    out += ['```','','## Agent → Skill graph','','```mermaid','graph LR']
    for e in ask:
        target_id, target_label = target(e['to'])
        out.append(f"    A_{id_(e['from'][6:])}[\"{e['from'][6:]}\"] --> {target_id}[\"{target_label}\"]")
    out += ['```','','## Complete inventory','','### Commands','',', '.join(f'`/{x}`' for x in inv['commands']),'','### Agents','',', '.join(f'`{x}`' for x in inv['agents']),'','### Skills','',', '.join(f'`{x}`' for x in inv['skills']),'']
    out += ['## Optional plugin packages', '', '| Plugin | Default state | Categories | Assets | Availability |', '|--------|---------------|------------|--------|--------------|']
    for package in inv.get('plugins',[]):
        availability=f"conditional on enabling `{package['id']}`"
        if package['id']=='product-discovery':
            availability += ' and selecting the product-discovery profile'
        out.append(f"| `{package['id']}` | {package['default_state']} | {', '.join(package['categories']) or 'none'} | {len(package['assets'])} | {availability} |")
    out += ['', '## Template dependencies', '', '| Consumer | Template |', '|----------|----------|']
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
    ap=argparse.ArgumentParser(); ap.add_argument('--write',action='store_true'); ap.add_argument('--check',action='store_true')
    profile=ap.add_mutually_exclusive_group(); profile.add_argument('--profile-off',action='store_true'); profile.add_argument('--profile-on',action='store_true')
    a=ap.parse_args()
    if (a.profile_off or a.profile_on) and not a.check:
        ap.error('--profile-off/--profile-on require --check')
    g=load(); errs=validate(g)
    if a.write:
        OUT.write_text(yaml.safe_dump(g,sort_keys=False,width=120)); MAP.write_text(render(g)); CMDMAP.write_text(render_cmd(g))
    if a.check or not a.write:
        expected=yaml.safe_dump(g,sort_keys=False,width=120)
        if not OUT.is_file() or OUT.read_text()!=expected: errs.append('dev-tools/framework-graph.yaml is missing or stale; run --write')
        if not MAP.is_file() or MAP.read_text()!=render(g): errs.append('framework-architecture.md is missing or stale; run --write')
        if not CMDMAP.is_file() or CMDMAP.read_text()!=render_cmd(g): errs.append('command-dependencies.md is missing or stale; run --write')
    if errs:
        print('\n'.join('ERROR: '+e for e in errs),file=sys.stderr); return 1
    print(f"framework graph OK: {len(g['inventory']['commands'])} commands, {len(g['inventory']['agents'])} agents, {len(g['inventory']['skills'])} skills, {len(g['edges'])} edges, {len(g['inventory'].get('plugins',[]))} plugins")
    if a.profile_off or a.profile_on:
        state='on' if a.profile_on else 'off'; result=project(g,state)
        package=next((p for p in g['inventory'].get('plugins',[]) if p['id']=='product-discovery'),None)
        plugin_node='plugin:product-discovery'
        if package and ((state=='on') != (plugin_node in result['nodes'])):
            print(f'ERROR: product-discovery profile-{state} reachability is inconsistent',file=sys.stderr); return 1
        label='enabled and selected' if state=='on' else 'disabled or unselected'
        print(f"product-discovery profile-{state}: {label}; {len(result['nodes'])} reachable nodes, {len(result['edges'])} reachable edges")
    return 0
if __name__=='__main__': raise SystemExit(main())
