#!/usr/bin/env python3
import os,re
from pathlib import Path

def root():
    return Path(os.environ.get("DATARIM_ROOT", Path(__file__).resolve().parents[3]))

def _summary(p):
    try: text=p.read_text(errors="ignore")[:5000]
    except Exception: return ""
    m=re.search(r'(?mi)^description:\s*["\']?(.+?)["\']?\s*$',text)
    if m:return m.group(1)[:280]
    for line in text.splitlines():
        s=line.strip().lstrip('#').strip()
        if len(s)>20 and not s.startswith(('---','name:','id:')): return s[:280]
    return ""

def inventory():
    r=root(); out={"skills":[],"agents":[],"commands":[],"templates":[]}
    specs=[("skills",r/'skills','SKILL.md'),("agents",r/'agents','*.md'),("commands",r/'commands','*.md'),("templates",r/'templates','*')]
    for kind,base,pat in specs:
        if not base.exists(): continue
        files=base.rglob(pat) if pat=='SKILL.md' else base.glob(pat)
        for p in files:
            if not p.is_file(): continue
            name=p.parent.name if kind=='skills' else p.stem
            out[kind].append({"name":name,"description":_summary(p),"path":str(p.relative_to(r))})
    return out

def shortlist(items,text,n=12):
    words=set(re.findall(r'[a-zA-Z0-9_+-]{3,}',text.lower()))
    def score(x):
        hay=(x['name']+' '+x.get('description','')).lower()
        return sum(3 if w in x['name'].lower() else 1 for w in words if w in hay)
    ranked=sorted(items,key=lambda x:(score(x),x['name']),reverse=True)
    positive=[x for x in ranked if score(x)>0]
    return (positive or ranked)[:n]
