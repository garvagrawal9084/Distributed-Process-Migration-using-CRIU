#!/usr/bin/env bash
# SOURCE VM. Demonstration uses the same Golang image as the historical experiment.
set -euo pipefail
NAME="${CONTAINER_NAME:-pdm-golang-new}"
IMAGE="${CONTAINER_IMAGE:-docker.io/garvagrawal9084/pdm-golang:latest}"
PORT="${SOURCE_PORT:-8081}"
if sudo podman container exists "$NAME"; then
  echo "Refusing to overwrite an existing container named $NAME" >&2
  exit 1
fi
sudo podman run -d --name "$NAME" -p "$PORT:8080" "$IMAGE"
sudo podman ps --filter "name=$NAME"
echo "Source HTTP service is mapped to localhost:$PORT (if the image serves HTTP)."
