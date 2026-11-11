#!/usr/bin/env bash
# DESTINATION VM.
set -euo pipefail
DIR="$HOME/criu-podman-transfer"
NAME="${CONTAINER_NAME:-pdm-golang-new}"
PORT="${DEST_PORT:-8081}"
(
  cd "$DIR"
  sha256sum -c SHA256SUMS
)
sudo podman container exists "$NAME" && {
  echo "Destination container $NAME already exists; refusing to overwrite it" >&2
  exit 1
}
echo "Restoring process state from native Podman checkpoint archive."
sudo podman container restore \
  --import="$DIR/$NAME-checkpoint.tar.gz" \
  --name "$NAME" -p "$PORT:8080"
sudo podman ps --filter "name=$NAME"
sudo podman port "$NAME"
