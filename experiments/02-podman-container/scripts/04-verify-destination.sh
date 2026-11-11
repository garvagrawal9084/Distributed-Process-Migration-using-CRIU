#!/usr/bin/env bash
set -euo pipefail
NAME="${CONTAINER_NAME:-pdm-golang-new}"
PORT="${DEST_PORT:-8081}"
sudo podman inspect "$NAME" --format 'Name: {{.Name}} Running: {{.State.Running}}'
sudo podman port "$NAME"
curl --fail --silent --show-error "http://127.0.0.1:$PORT/" || {
  echo "HTTP check failed; inspect application port and container logs." >&2
  sudo podman logs "$NAME" --tail 30 || true
  exit 1
}
