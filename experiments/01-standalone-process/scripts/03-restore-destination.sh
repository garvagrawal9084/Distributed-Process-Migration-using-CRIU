#!/usr/bin/env bash
# Run on DESTINATION VM after script 02.
set -euo pipefail
DIR="/tmp/criu-process-demo"
cd "$DIR"
test -f "$DIR/images/inventory.img"
test -f "$DIR/counter.txt"
sha256sum -c SHA256SUMS
BEFORE="$(cat "$DIR/counter.txt")"
echo "Counter at checkpoint: $BEFORE"
echo "Restoring process in the background."
sudo criu restore -D "$DIR/images" --shell-job --restore-detached -v4 -o restore.log
sleep 3
AFTER="$(cat "$DIR/counter.txt")"
echo "Counter after restore: $AFTER"
if (( AFTER <= BEFORE )); then
  echo "Counter did not advance. See $DIR/images/restore.log" >&2
  exit 1
fi
echo "SUCCESS: process continued after CRIU restore."
