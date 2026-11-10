#!/usr/bin/env bash
# Run on the SOURCE Ubuntu host: K3s runs in ROOT-owned Podman "k3s-server".
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$HOME/minimeet-migration/v3"
mkdir -p "$WORK"
chmod 700 "$WORK"
k() { sudo podman exec -i k3s-server kubectl "$@"; }

sudo podman ps --format '{{.Names}}' | grep -Fx k3s-server
k get nodes
echo "Preparing fresh demo Secrets; existing Secrets are left untouched."
if ! k get secret minimeet-db-secret >/dev/null 2>&1; then
  DB_PASSWORD="$(openssl rand -hex 16)"
  k create secret generic minimeet-db-secret \
    --from-literal=POSTGRES_DB=minimeet \
    --from-literal=POSTGRES_USER=minimeet \
    --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD"
  k create secret generic minimeet-app-config \
    --from-literal="DATABASE_URL=postgresql://minimeet:${DB_PASSWORD}@postgres:5432/minimeet" \
    --from-literal="REDIS_URL=redis://redis:6379/0"
  unset DB_PASSWORD
else
  k get secret minimeet-app-config >/dev/null || {
    echo "Existing DB secret without app secret; reconcile manually, do not reset password" >&2
    exit 1
  }
fi

echo "Building the reference MiniMeet image (asyncio, no uvloop)."
sudo podman build -t localhost/minimeet-backend:v3 "$ROOT/lab/minimeet"
sudo podman save -o "$WORK/minimeet-backend-v3-image.tar" localhost/minimeet-backend:v3
sudo chown "$(id -un):$(id -gn)" "$WORK/minimeet-backend-v3-image.tar"
sudo podman exec k3s-server mkdir -p /var/lib/rancher/k3s/agent/images
sudo podman cp "$WORK/minimeet-backend-v3-image.tar" \
  k3s-server:/var/lib/rancher/k3s/agent/images/minimeet-backend-v3-image.tar
echo "Waiting for K3s's image importer to discover the tarball."
sleep 10

k apply -f - < "$ROOT/lab/k8s/source.yaml"
k rollout status deployment/postgres --timeout=300s
k rollout status deployment/redis --timeout=300s

echo "Creating MiniMeet schema (only if absent)."
k exec deployment/postgres -- psql -v ON_ERROR_STOP=1 -U minimeet -d minimeet -c \
  "CREATE TABLE IF NOT EXISTS meetings (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
  );"

k rollout status deployment/minimeet-backend --timeout=300s
k get pod -l app=minimeet-backend
echo "Source setup complete. Next: run migration checkpoint script after confirming health."
