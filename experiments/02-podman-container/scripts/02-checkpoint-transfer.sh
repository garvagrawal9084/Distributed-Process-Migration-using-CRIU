#!/usr/bin/env bash
# SOURCE VM. Checkpoint stops the source to prevent concurrent active copies.
set -euo pipefail
: "${DEST_HOST:?Set DEST_HOST to the destination VM address}"
DEST_USER="${DEST_USER:-garv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/checkpoint-transfer}"
NAME="${CONTAINER_NAME:-pdm-golang-new}"
DIR="$HOME/criu-podman-transfer"
mkdir -p "$DIR"
chmod 700 "$DIR"
sudo podman container exists "$NAME"
test "$(sudo podman inspect -f '{{.State.Running}}' "$NAME")" = true
echo "Checkpointing and stopping source container: $NAME"
sudo podman container checkpoint "$NAME" --export "$DIR/$NAME-checkpoint.tar.gz"
sudo chown "$(id -u):$(id -g)" "$DIR/$NAME-checkpoint.tar.gz"
chmod 600 "$DIR/$NAME-checkpoint.tar.gz"
(
  cd "$DIR"
  sha256sum "$NAME-checkpoint.tar.gz" > SHA256SUMS
)
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" \
  'mkdir -p "$HOME/criu-podman-transfer" && chmod 700 "$HOME/criu-podman-transfer"'
scp -i "$SSH_KEY" -o IdentitiesOnly=yes \
  "$DIR/$NAME-checkpoint.tar.gz" "$DIR/SHA256SUMS" \
  "$DEST_USER@$DEST_HOST:criu-podman-transfer/"
echo "Transferred checkpoint; source was stopped by Podman."
