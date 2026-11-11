#!/usr/bin/env bash
set -euo pipefail
DIR="/tmp/criu-process-demo"
echo "Counter now: $(cat "$DIR/counter.txt")"
sleep 3
echo "Counter later: $(cat "$DIR/counter.txt")"
echo "Process:"
pgrep -af '/tmp/criu-process-demo/number.py' || true
