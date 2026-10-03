#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
from jev_client import diagnose
p=Path(os.environ.get('DATARIM_JEV_CONFIG',Path(__file__).resolve().parents[1]/'config/jev-control.json'))
cfg=json.loads(p.read_text()); r=diagnose(cfg)
print(json.dumps(r,indent=2,ensure_ascii=False)); sys.exit(0 if r.get('api',{}).get('ok') else 2)
