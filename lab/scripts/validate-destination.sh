#!/usr/bin/env bash
# Run ON DESTINATION after destination-restore.sh succeeds.
set -euo pipefail
DIR="$HOME/minimeet-migration/v3"
POD="$(cat "$DIR/restored-pod-name.txt")"
k() { sudo k3s kubectl "$@"; }
echo "=== RESTORE STATUS ==="
k get podrestore "$POD" -o wide
k get pod "$POD" -o wide
echo "=== HEALTH ==="
k exec "$POD" -c backend -- python -c \
  'import urllib.request;print(urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=8).read().decode())'
echo "=== CREATE MEETING VIA RESTORED BACKEND ==="
CREATED="$(k exec "$POD" -c backend -- python -c '
import json, urllib.request
data=json.dumps({"title":"CRIU Destination Migration Test"}).encode()
request=urllib.request.Request(
    "http://127.0.0.1:8000/meetings",data=data,
    headers={"Content-Type":"application/json"},method="POST")
with urllib.request.urlopen(request,timeout=10) as response:
    print(response.read().decode())
')"
echo "$CREATED"
MEETING_ID="$(printf '%s\n' "$CREATED" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo "=== WAIT FOR RESTORED WORKER TO PROCESS MEETING $MEETING_ID ==="
PROCESSED=""
for attempt in $(seq 1 40); do
  PROCESSED="$(k exec deployment/postgres -- psql -U minimeet -d minimeet -Atc \
    "SELECT processed_at IS NOT NULL FROM meetings WHERE id = $MEETING_ID")"
  if [ "$PROCESSED" = t ]; then break; fi
  sleep 2
done
test "$PROCESSED" = t || { echo "Worker did not process meeting" >&2; exit 1; }
k exec deployment/postgres -- psql -U minimeet -d minimeet \
  -c 'SELECT id,title,created_at,processed_at FROM meetings ORDER BY id'
k exec deployment/redis -c redis -- redis-cli PING
echo "SUCCESS: restored backend -> Redis -> restored worker -> PostgreSQL."
echo "Source remains paused; external traffic cutover and downtime benchmarking are separate."
