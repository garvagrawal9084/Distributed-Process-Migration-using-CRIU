#!/usr/bin/env bash
# Run on SOURCE. Requires DEST_HOST and DEST_USER; process stops at checkpoint.
set -euo pipefail
: "${DEST_HOST:?Set DEST_HOST, e.g. 192.168.122.118}"
DEST_USER="${DEST_USER:-garv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/checkpoint-transfer}"
DIR="/tmp/criu-process-demo"
PID="$(cat "$DIR/number.pid")"
kill -0 "$PID" || { echo "Source counter is not running" >&2; exit 1; }
test -d "$DIR"
mkdir -p "$DIR/images"
echo "Checkpointing PID=$PID (the source process will stop)."
sudo criu dump -t "$PID" -D "$DIR/images" --shell-job -v4 -o dump.log
if kill -0 "$PID" 2>/dev/null; then
  echo "Warning: PID is still visible; check process state before starting destination." >&2
  ps -o pid,stat,args -p "$PID" || true
fi
(
  cd "$DIR"
  sha256sum number.py counter.txt images/*.img > SHA256SUMS
)
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" \
  'mkdir -p /tmp/criu-process-demo'
scp -i "$SSH_KEY" -o IdentitiesOnly=yes -rp \
  "$DIR/number.py" "$DIR/counter.txt" "$DIR/SHA256SUMS" "$DIR/images" \
  "$DEST_USER@$DEST_HOST:/tmp/criu-process-demo/"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" \
  'cd /tmp/criu-process-demo && sha256sum -c SHA256SUMS'
echo "Checkpoint transferred. Source should remain stopped; proceed to destination restore."
