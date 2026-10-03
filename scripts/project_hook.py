#!/usr/bin/env python3
"""Run optional Jev hooks only inside the installation that registered them."""
import os
from pathlib import Path
import sys

from project_scope import activate, project_root


def main():
    allowed = {'UserPromptSubmit': 'hook_user_prompt.py',
               'PreToolUse': 'hook_pre_tool.py', 'PostToolUse': 'hook_post_tool.py'}
    if len(sys.argv) != 2 or sys.argv[1] not in allowed:
        return 0
    try:
        root = project_root()
        runtime = root / '.datarim-runtime'
        if Path(__file__).resolve().parent.parent != runtime:
            return 0
        activate(root)
        hook = runtime / 'plugins/dr-jev-control/scripts' / allowed[sys.argv[1]]
        if not hook.is_file():
            return 0
    except (OSError, ValueError):
        return 0
    os.execv(sys.executable, [sys.executable, str(hook)])


if __name__ == '__main__':
    raise SystemExit(main())
