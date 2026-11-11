#!/usr/bin/env bash
# Run on SOURCE after source-setup.sh and after destination CRIU proxy/operator are ready.
# Usage: DEST_IP=... DEST_USER=... SSH_KEY=~/.ssh/... bash experiments/04-k3s-minimeet/scripts/02-checkpoint-transfer.sh
set -euo pipefail
: "${DEST_IP:?Set DEST_IP to reachable destination IPv4}"
DEST_USER="${DEST_USER:-garv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/checkpoint-transfer}"
WORK="$HOME/minimeet-migration/v3"
SOURCE_CONTAINER=k3s-server
mkdir -p "$WORK"
chmod 700 "$WORK"
k() { sudo podman exec -i "$SOURCE_CONTAINER" kubectl "$@"; }
ssh_dest() { ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${DEST_USER}@${DEST_IP}" "$@"; }
POD="$(k get pods -l app=minimeet-backend -o jsonpath='{.items[0].metadata.name}')"
test -n "$POD"
test -f "$WORK/minimeet-backend-v3-image.tar"
echo "Source Pod: $POD"

# Stop new ingress, drain active work, and prevent connections before checkpoint.
k patch service minimeet-backend --type=merge \
  -p '{"spec":{"selector":{"app":"minimeet-backend-quiesced"}}}'
k exec "$POD" -c backend -- touch /shared/minimeet.pause
for attempt in $(seq 1 120); do
  BACK="$(k exec "$POD" -c backend -- cat /shared/backend.quiesce.status 2>/dev/null || true)"
  WORKER="$(k exec "$POD" -c worker -- cat /shared/worker.quiesce.status 2>/dev/null || true)"
  if [ "$BACK" = PAUSED ] && [ "$WORKER" = PAUSED ]; then break; fi
  sleep 1
done
test "${BACK:-}" = PAUSED && test "${WORKER:-}" = PAUSED || {
  echo "Application did not quiesce; checkpoint aborted" >&2
  exit 1
}
echo "Backend and worker PAUSED. Do not resume the source until after cutover."
echo "Confirm zero queued Redis jobs (the demo queue must be drained):"
QUEUED="$(k exec deployment/redis -- redis-cli LLEN meeting_jobs)"
test "$QUEUED" = 0 || { echo "Redis queue still has jobs: $QUEUED" >&2; exit 1; }

echo "Backing up PostgreSQL (custom-format dump)."
k exec deployment/postgres -- pg_dump -U minimeet -d minimeet -Fc > "$WORK/minimeet-db-quiesced.dump"
test -s "$WORK/minimeet-db-quiesced.dump"

echo "Backing up Redis as an RDB snapshot (including empty databases)."
k exec deployment/redis -- redis-cli --rdb /tmp/minimeet-quiesced.rdb
k exec deployment/redis -- cat /tmp/minimeet-quiesced.rdb > "$WORK/redis-dump-quiesced.rdb"
test -s "$WORK/redis-dump-quiesced.rdb"

echo "Backing up the shared emptyDir including minimeet.pause."
k exec "$POD" -c sidecar -- tar -C /shared -cf - . > "$WORK/minimeet-shared-asyncio-quiesced.tar"
tar -tf "$WORK/minimeet-shared-asyncio-quiesced.tar" | grep -Fx './minimeet.pause'

echo "Checkpointing each container through the source kubelet HTTPS API."
CPID="$(sudo podman inspect --format '{{.State.Pid}}' "$SOURCE_CONTAINER")"
TMP="$(mktemp -d)"
cleanup() { sudo rm -rf "$TMP"; }
trap cleanup EXIT
sudo podman cp "$SOURCE_CONTAINER:/var/lib/rancher/k3s/server/tls/client-admin.crt" "$TMP/client-admin.crt"
sudo podman cp "$SOURCE_CONTAINER:/var/lib/rancher/k3s/server/tls/client-admin.key" "$TMP/client-admin.key"
: > "$WORK/checkpoints.tsv"
for CONTAINER in backend worker sidecar; do
  HTTP_CODE="$(sudo nsenter -t "$CPID" -n curl --silent --show-error \
    --insecure --cert "$TMP/client-admin.crt" --key "$TMP/client-admin.key" \
    -X POST -o "$TMP/response.json" -w '%{http_code}' \
    "https://127.0.0.1:10250/checkpoint/default/$POD/$CONTAINER?timeout=120")"
  if [ "$HTTP_CODE" != 200 ]; then
    echo "Checkpoint $CONTAINER failed: HTTP $HTTP_CODE" >&2
    cat "$TMP/response.json" >&2; exit 1
  fi
  FILEPATH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["items"][0])' "$TMP/response.json")"
  NAME="$(basename "$FILEPATH")"
  sudo podman cp "$SOURCE_CONTAINER:$FILEPATH" "$WORK/$NAME"
  sudo chown "$(id -un):$(id -gn)" "$WORK/$NAME"
  chmod 600 "$WORK/$NAME"
  printf '%s\t%s\n' "$CONTAINER" "$NAME" >> "$WORK/checkpoints.tsv"
  echo "$CONTAINER: $NAME"
done
(cd "$WORK" && sha256sum *.tar *.dump *.rdb > SHA256SUMS)
ssh_dest 'mkdir -p "$HOME/minimeet-migration" && chmod 700 "$HOME/minimeet-migration"'
scp -i "$SSH_KEY" -o IdentitiesOnly=yes -r "$WORK" "${DEST_USER}@${DEST_IP}:minimeet-migration/"
ssh_dest 'cd "$HOME/minimeet-migration/v3" && sha256sum -c SHA256SUMS'

echo "Copying only sanitized Kubernetes Secret data; values are not logged."
for NAME in minimeet-db-secret minimeet-app-config; do
  k get secret "$NAME" -o json | python3 -c '
import json,sys
s=json.load(sys.stdin)
print(json.dumps(dict(apiVersion="v1",kind="Secret",
  metadata=dict(name=s["metadata"]["name"], namespace="default"),
  type=s["type"], data=s["data"])))
' | ssh_dest 'sudo k3s kubectl apply -f -'
done
echo "Transfer complete. Keep source paused and Service selector disabled."
