#!/usr/bin/env bash
set -euo pipefail

runtime="${CUSTOMER_TEST_PYTHON_RUNTIME:-}"
dependency_site="${CUSTOMER_TEST_PYTHON_SITE:-}"
if [[ "$runtime" != /* || ! -x "$runtime" || -d "$runtime" \
    || "$dependency_site" != /* || ! -d "$dependency_site" || -L "$dependency_site" \
    || $# -lt 1 ]]; then
    printf 'ERROR: trusted test Python runtime and dependency site are required\n' >&2
    exit 126
fi

bootstrap=$'import os,sys\nsite=os.path.realpath(sys.argv[1])\nmode=sys.argv[2]\nsys.path.insert(0,site)\nif mode=="-c":\n program=sys.argv[3]\n sys.argv=["-c"]+sys.argv[4:]\n filename="<string>"\nelif mode=="-":\n program=sys.stdin.buffer.read()\n sys.argv=["-"]+sys.argv[3:]\n filename="<stdin>"\nelse:\n filename=os.path.realpath(mode)\n with open(filename,"rb") as handle:\n  program=handle.read()\n sys.argv=[mode]+sys.argv[3:]\n globals()["__file__"]=filename\nexec(compile(program,filename,"exec"),globals(),globals())'

exec /usr/bin/env -i LC_ALL=C "$runtime" -I -S -c "$bootstrap" \
    "$dependency_site" "$@"
