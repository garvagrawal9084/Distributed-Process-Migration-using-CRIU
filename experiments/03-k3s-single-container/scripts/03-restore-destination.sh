#!/usr/bin/env bash
# DESTINATION: install exact checkpoint archive and launch PodRestore.
set -euo pipefail
DIR="$HOME/criu-k3s-nginx"
cd "$DIR"
sha256sum -c SHA256SUMS
test "$(sudo k3s kubectl get node "${TARGET_NODE:-checkpoint-restore-dest}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True
sudo k3s kubectl get crd podrestores.criu.org >/dev/null
sudo systemctl is-active --quiet cri-restore-proxy.socket
curl -fsS http://127.0.0.1:18080/readyz
ARCHIVE="$(cat checkpoint-name.txt)"
[[ "$ARCHIVE" =~ ^checkpoint-[A-Za-z0-9_.:-]+\.tar$ ]] || { echo "Unexpected archive name" >&2; exit 1; }
sudo install -m 600 "$DIR/$ARCHIVE" "/var/lib/kubelet/checkpoints/$ARCHIVE"
sudo k3s crictl pull docker.io/library/nginx:alpine
RESTORE_NAME="checkpoint-demo-restored-$(date +%s)"
cat > "$DIR/$RESTORE_NAME.yaml" <<YAML
apiVersion: criu.org/v1
kind: PodRestore
metadata:
  name: $RESTORE_NAME
  namespace: default
spec:
  targetNode: ${TARGET_NODE:-checkpoint-restore-dest}
  checkpoints:
    - container: checkpoint-demo
      path: /var/lib/kubelet/checkpoints/$ARCHIVE
  template:
    spec:
      containers:
        - name: checkpoint-demo
          image: docker.io/library/nginx:alpine
YAML
sudo k3s kubectl apply --dry-run=server -f "$DIR/$RESTORE_NAME.yaml"
sudo k3s kubectl apply -f "$DIR/$RESTORE_NAME.yaml"
sudo k3s kubectl wait --for=condition=Ready "podrestore/$RESTORE_NAME" --timeout=300s
sudo k3s kubectl wait --for=condition=Ready "pod/$RESTORE_NAME" --timeout=300s
printf '%s\n' "$RESTORE_NAME" > "$DIR/restored-pod-name.txt"
sudo k3s kubectl get podrestore "$RESTORE_NAME" -o wide
sudo k3s kubectl get pod "$RESTORE_NAME" -o wide
