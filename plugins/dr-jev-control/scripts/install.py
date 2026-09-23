#!/usr/bin/env python3
"""Install Jev through the project-only Datarim installer."""
from pathlib import Path
import os, sys
root = Path(__file__).resolve().parents[3]
os.execv(sys.executable, [sys.executable, str(root/'scripts/project_install.py'), '--with-jev', *sys.argv[1:]])
