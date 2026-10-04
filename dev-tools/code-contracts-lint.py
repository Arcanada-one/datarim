#!/usr/bin/env python3
"""Dependency-free Datarim validator for directory-scoped Code Contracts.

Validates CONTRACTS files using the upstream core grammar needed by Datarim.
It intentionally does not pretend to semantically prove prose contracts. If the
upstream `cc-check` CLI is installed, CI/operators may run it additionally for
supported source-language declaration contracts.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

DIRECTIVE = re.compile(r"^@cc(?:\s+\[([^\]]+)\])?\s+([^\s,:\[\]]+)$")
TOKEN = re.compile(r"^[^\s,:\[\]]+$")

def parse_file(path: Path):
    errors=[]; contracts=[]; current=None
    lines=path.read_text(encoding="utf-8").splitlines()
    for no,line in enumerate(lines,1):
        if line.startswith("@cc"):
            m=DIRECTIVE.match(line)
            if not m:
                errors.append((no,"malformed directive")); current=None; continue
            meta,cid=m.groups()
            if not TOKEN.match(cid): errors.append((no,"invalid contract id"))
            attrs=[]
            if meta:
                for raw in meta.split(','):
                    if ':' not in raw:
                        errors.append((no,f"malformed metadata attribute: {raw}")); continue
                    k,v=raw.split(':',1)
                    if not TOKEN.match(k) or not TOKEN.match(v):
                        errors.append((no,f"invalid metadata token: {raw}"))
                    attrs.append((k,v))
            current={"id":cid,"line":no,"metadata":attrs,"prose":[]}; contracts.append(current)
        elif current is not None:
            current["prose"].append(line)
    seen={}
    for c in contracts:
        if not any(x.strip() for x in c["prose"]): errors.append((c["line"],f"contract {c['id']} has empty prose"))
        if c["id"] in seen: errors.append((c["line"],f"duplicate contract id {c['id']} (first at line {seen[c['id']]})"))
        else: seen[c["id"]]=c["line"]
    return contracts,errors

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("root",nargs="?",default="."); ap.add_argument("--json",action="store_true")
    a=ap.parse_args(); root=Path(a.root).resolve()
    files=sorted(p for p in root.rglob("CONTRACTS") if p.is_file() and not p.is_symlink() and ".git" not in p.parts and "node_modules" not in p.parts)
    all_errors=[]; count=0; parsed={}
    for f in files:
        cs,errs=parse_file(f); parsed[f]=cs; count += len(cs)
        for line,msg in errs: all_errors.append({"file":str(f.relative_to(root)),"line":line,"message":msg})
    # Upstream identity rule for directory contracts: IDs must also be unique
    # across ancestor CONTRACTS scopes applicable to a descendant directory.
    for f,cs in parsed.items():
        ancestor_ids={}
        parent=f.parent.parent
        while parent == root or root in parent.parents:
            af=parent / "CONTRACTS"
            if af in parsed:
                for c in parsed[af]: ancestor_ids.setdefault(c["id"],af)
            if parent == root: break
            parent=parent.parent
        for c in cs:
            if c["id"] in ancestor_ids:
                all_errors.append({"file":str(f.relative_to(root)),"line":c["line"],"message":f"contract id {c['id']} duplicates ancestor scope {ancestor_ids[c['id']].relative_to(root)}"})
    result={"files":len(files),"contracts":count,"errors":all_errors,"status":"invalid" if all_errors else "clean" if count else "not_measured"}
    if a.json: print(json.dumps(result,ensure_ascii=False))
    else:
        for e in all_errors: print(f"{e['file']}:{e['line']}: {e['message']}",file=sys.stderr)
        print(f"code-contracts: {result['status']} files={len(files)} contracts={count}",file=sys.stderr)
    return 1 if all_errors else 0 if count else 2
if __name__ == "__main__": raise SystemExit(main())
