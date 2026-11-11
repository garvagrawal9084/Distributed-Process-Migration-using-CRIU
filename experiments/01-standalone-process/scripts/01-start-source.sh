#!/usr/bin/env bash
# Run on SOURCE VM. Does not overwrite a running demo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="/tmp/criu-process-demo"
mkdir -p "$DIR"
if [[ -f "$DIR/number.pid" ]] && kill -0 "$(cat "$DIR/number.pid")" 2>/dev/null; then
  echo "Existing process is active: $(cat "$DIR/number.pid")" >&2
  exit 1
fi
cp "$HERE/number.py" "$DIR/number.py"
printf '0\n' > "$DIR/counter.txt"
(
  cd "$DIR"
  nohup python3 -u "$DIR/number.py" </dev/null >/dev/null 2>&1 &
  echo "$!" > "$DIR/number.pid"
)
sleep 3
PID="$(cat "$DIR/number.pid")"
kill -0 "$PID"
echo "Source PID: $PID"
echo "Current counter: $(cat "$DIR/counter.txt")"
