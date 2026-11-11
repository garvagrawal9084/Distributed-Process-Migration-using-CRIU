#!/usr/bin/env bash
# Syntax checks for repository shell and Python sources; not a full integration test.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
echo "=== Bash syntax ==="
while IFS= read -r -d '' f; do
  bash -n "$f"
  printf 'OK %s\n' "$f"
done < <(find experiments -type f -name '*.sh' -print0)
echo "=== Python syntax ==="
python3 - <<'PY'
import ast
from pathlib import Path
for path in Path('experiments').rglob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
    print('OK', path)
PY
echo "Syntax checks passed. These do NOT verify live CRIU or Kubernetes compatibility."
