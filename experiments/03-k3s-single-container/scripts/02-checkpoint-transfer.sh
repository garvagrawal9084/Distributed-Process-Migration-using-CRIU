#!/usr/bin/env bash
# SOURCE. Takes checkpoint via kubelet HTTPS API; transfers the precise dynamic tar name.
set -euo pipefail
: "${DEST_HOST:?Set DEST_HOST}"
DEST_USER="${DEST_USER:-garv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/checkpoint-transfer}"
NAME=checkpoint-demo
DIR="$HOME/criu-k3s-nginx"
mkdir -p "$DIR"
chmod 700 "$DIR"
sudo podman exec k3s-server kubectl get pod "$NAME" -o jsonpath='{.status.phase}' | grep -Fx Running
PID="$(sudo podman inspect -f '{{.State.Pid}}' k3s-server)"
TMP="$(mktemp -d)"
trap 'sudo rm -rf "$TMP"' EXIT
sudo podman cp k3s-server:/var/lib/rancher/k3s/server/tls/client-admin.crt "$TMP/client-admin.crt"
sudo podman cp k3s-server:/var/lib/rancher/k3s/server/tls/client-admin.key "$TMP/client-admin.key"
CODE="$(sudo nsenter -t "$PID" -n curl -sS --insecure \
  --cert "$TMP/client-admin.crt" --key "$TMP/client-admin.key" \
  -X POST -o "$TMP/response.json" -w '%{http_code}' \
  "https://127.0.0.1:10250/checkpoint/default/$NAME/$NAME?timeout=120")"
if [[ "$CODE" != 200 ]]; then
  echo "Checkpoint HTTP $CODE" >&2
  cat "$TMP/response.json" >&2
  exit 1
fi
ARCHIVE_PATH="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["items"][0])' "$TMP/response.json")"
FILE="$(basename "$ARCHIVE_PATH")"
sudo podman cp "k3s-server:$ARCHIVE_PATH" "$DIR/$FILE"
sudo chown "$(id -u):$(id -g)" "$DIR/$FILE"
chmod 600 "$DIR/$FILE"
printf '%s\n' "$FILE" > "$DIR/checkpoint-name.txt"
(cd "$DIR" && sha256sum "$FILE" > SHA256SUMS)
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" \
  'mkdir -p "$HOME/criu-k3s-nginx"'
scp -i "$SSH_KEY" -o IdentitiesOnly=yes \
  "$DIR/$FILE" "$DIR/checkpoint-name.txt" "$DIR/SHA256SUMS" \
  "$DEST_USER@$DEST_HOST:criu-k3s-nginx/"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" \
  'cd "$HOME/criu-k3s-nginx" && sha256sum -c SHA256SUMS'
echo "Checkpoint transferred: $FILE"
echo "Stop or scale down the source workload before routing traffic to the destination."
