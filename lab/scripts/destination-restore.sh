#!/usr/bin/env bash
# Run ON DESTINATION after checkpoint-transfer.sh, on a fresh K3s cluster
# with compatible CRIU/containerd/runc and the PodRestore operator/CRI proxy installed.
# This script is intentionally non-idempotent; it refuses existing app resources.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$HOME/minimeet-migration/v3"
k() { sudo k3s kubectl "$@"; }
test -f "$DIR/checkpoints.tsv"
test -f "$DIR/SHA256SUMS"
(cd "$DIR" && sha256sum -c SHA256SUMS)
k get crd podrestores.criu.org >/dev/null
k get node checkpoint-restore-dest >/dev/null
systemctl is-active --quiet cri-restore-proxy.socket
curl -fsS http://127.0.0.1:18080/readyz
k get secret minimeet-db-secret minimeet-app-config
for resource in deployment/postgres deployment/redis pod/minimeet-restored-v3; do
  if k get "$resource" >/dev/null 2>&1; then
    echo "Refusing to overwrite existing $resource. Use a new empty lab cluster." >&2
    exit 1
  fi
done
echo "Importing the MiniMeet image into destination K3s."
sudo mkdir -p /var/lib/rancher/k3s/agent/images
sudo install -m 600 "$DIR/minimeet-backend-v3-image.tar" \
  /var/lib/rancher/k3s/agent/images/minimeet-backend-v3-image.tar
for attempt in $(seq 1 90); do
  if sudo k3s crictl images | grep -q 'localhost/minimeet-backend'; then break; fi
  sleep 2
done
sudo k3s crictl images | grep 'localhost/minimeet-backend'
sudo k3s crictl pull docker.io/library/busybox:1.36

echo "Staging Redis and shared-volume snapshots."
k create configmap minimeet-redis-rdb --from-file="dump.rdb=$DIR/redis-dump-quiesced.rdb"
k create secret generic minimeet-shared-backup \
  --from-file="shared.tar=$DIR/minimeet-shared-asyncio-quiesced.tar"
k apply -f "$ROOT/lab/k8s/destination.yaml"
k rollout status deployment/postgres --timeout=360s
k rollout status deployment/redis --timeout=360s
test "$(k exec deployment/postgres -- psql -U minimeet -d minimeet -Atc \
  "SELECT to_regclass('public.meetings') IS NULL")" = t || {
  echo "Database is not empty; refusing import" >&2; exit 1;
}
cat "$DIR/minimeet-db-quiesced.dump" | \
  k exec -i deployment/postgres -- pg_restore -U minimeet -d minimeet \
    --no-owner --no-acl --single-transaction --exit-on-error
k exec deployment/postgres -- psql -U minimeet -d minimeet \
  -c "SELECT id,title,processed_at FROM meetings ORDER BY id"

echo "Confirming Redis RDB load before enabling AOF."
k logs deployment/redis -c redis --tail=30
test "$(k exec deployment/redis -c redis -- redis-cli PING)" = PONG
k exec deployment/redis -c redis -- redis-cli CONFIG SET appendonly yes
for attempt in $(seq 1 90); do
  PERSIST="$(k exec deployment/redis -c redis -- redis-cli INFO persistence | tr -d '\r')"
  if printf '%s\n' "$PERSIST" | grep -qx 'aof_rewrite_in_progress:0' && \
     printf '%s\n' "$PERSIST" | grep -qx 'aof_last_bgrewrite_status:ok'; then break; fi
  sleep 2
done
printf '%s\n' "$PERSIST" | grep -qx 'aof_last_bgrewrite_status:ok'
k patch deployment redis --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args/6","value":"yes"}]'
k rollout status deployment/redis --timeout=360s
k exec deployment/redis -c redis -- redis-cli PING
k exec deployment/redis -c redis -- redis-cli INFO persistence | grep aof_enabled

echo "Installing three checkpoint archives at exact node-local paths."
declare -A CP
while IFS=$'\t' read -r CONTAINER FILENAME; do
  [[ "$CONTAINER" =~ ^(backend|worker|sidecar)$ ]]
  [[ "$FILENAME" =~ ^checkpoint-[a-zA-Z0-9_.:-]+\.tar$ ]]
  sudo install -m 600 "$DIR/$FILENAME" "/var/lib/kubelet/checkpoints/$FILENAME"
  CP["$CONTAINER"]="$FILENAME"
done < "$DIR/checkpoints.tsv"
for C in backend worker sidecar; do test -n "${CP[$C]:-}"; done

RESTORE_NAME="minimeet-restored-v3-$(date +%s)"
MANIFEST="$DIR/$RESTORE_NAME.yaml"
cat > "$MANIFEST" <<YAML
apiVersion: criu.org/v1
kind: PodRestore
metadata:
  name: $RESTORE_NAME
  namespace: default
spec:
  targetNode: checkpoint-restore-dest
  checkpoints:
    - container: backend
      path: /var/lib/kubelet/checkpoints/${CP[backend]}
    - container: worker
      path: /var/lib/kubelet/checkpoints/${CP[worker]}
    - container: sidecar
      path: /var/lib/kubelet/checkpoints/${CP[sidecar]}
  template:
    spec:
      initContainers:
        - name: restore-shared
          image: docker.io/library/busybox:1.36
          command: ["sh", "-ec"]
          args:
            - |
              tar -xf /backup/shared.tar -C /shared
              test -f /shared/minimeet.pause
              test -f /shared/backend.quiesce.status
              test -f /shared/worker.quiesce.status
              echo "Shared volume restored; pause file present"
          volumeMounts:
            - {name: shared-data, mountPath: /shared}
            - {name: shared-backup, mountPath: /backup, readOnly: true}
      containers:
        - name: backend
          image: localhost/minimeet-backend:v3
          imagePullPolicy: IfNotPresent
          command: ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--loop", "asyncio"]
          envFrom:
            - secretRef: {name: minimeet-app-config}
          ports: [{containerPort: 8000}]
          volumeMounts: [{name: shared-data, mountPath: /shared}]
          readinessProbe:
            httpGet: {path: /health, port: 8000}
            initialDelaySeconds: 10
            periodSeconds: 5
        - name: worker
          image: localhost/minimeet-backend:v3
          imagePullPolicy: IfNotPresent
          command: ["python", "worker.py"]
          envFrom:
            - secretRef: {name: minimeet-app-config}
          volumeMounts: [{name: shared-data, mountPath: /shared}]
        - name: sidecar
          image: docker.io/library/busybox:1.36
          command: ["sh", "-c", "touch /shared/worker.log && tail -F /shared/worker.log"]
          volumeMounts: [{name: shared-data, mountPath: /shared}]
      volumes:
        - {name: shared-data, emptyDir: {}}
        - name: shared-backup
          secret: {secretName: minimeet-shared-backup}
YAML
echo "Server-side validation:"
k apply --dry-run=server -f "$MANIFEST"
k apply -f "$MANIFEST"
k wait --for=condition=Ready "podrestore/$RESTORE_NAME" --timeout=360s
k get podrestore "$RESTORE_NAME" -o wide
k get pod "$RESTORE_NAME" -o wide
k logs "$RESTORE_NAME" -c restore-shared
k exec "$RESTORE_NAME" -c backend -- sh -c \
  'test -f /shared/minimeet.pause && test "$(cat /shared/backend.quiesce.status)" = PAUSED'
k exec "$RESTORE_NAME" -c worker -- sh -c \
  'test -f /shared/minimeet.pause && test "$(cat /shared/worker.quiesce.status)" = PAUSED'

echo "Restored Pod is paused. Remove pause ONLY on the destination."
k exec "$RESTORE_NAME" -c backend -- rm /shared/minimeet.pause
k wait --for=condition=Ready "pod/$RESTORE_NAME" --timeout=180s
k exec "$RESTORE_NAME" -c backend -- python -c \
  'import urllib.request;print(urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=5).read().decode())'
echo "$RESTORE_NAME" > "$DIR/restored-pod-name.txt"
echo "Ready: $RESTORE_NAME. Keep SOURCE paused; run validate-destination.sh for end-to-end test."
