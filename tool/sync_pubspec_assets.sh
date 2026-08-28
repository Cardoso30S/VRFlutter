#!/usr/bin/env bash
#
# O Flutter nao inclui assets recursivamente: cada subpasta precisa aparecer
# em `pubspec.yaml`. Este script reescreve o bloco `assets:` com todas as
# pastas que realmente existem sob assets/.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIRS=$(find assets -type d | sort | sed 's|$|/|')

python3 - "$DIRS" <<'PY'
import re, sys, pathlib
dirs = [d for d in sys.argv[1].split() if d]
p = pathlib.Path('pubspec.yaml')
src = p.read_text()
block = "  assets:\n" + "".join(f"    - {d}\n" for d in dirs)
new, n = re.subn(r"  assets:\n(?:    - .*\n)+", block, src)
if n == 0:
    raise SystemExit("bloco 'assets:' nao encontrado no pubspec.yaml")
p.write_text(new)
print("pubspec.yaml atualizado com %d pastas de assets" % len(dirs))
PY
