#!/usr/bin/env bash
set -euo pipefail
NAME="$(cat "$HOME/criu-k3s-nginx/restored-pod-name.txt")"
sudo k3s kubectl get podrestore "$NAME" -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.status}{" (reason="}{.reason}{")\n"}{end}'
sudo k3s kubectl get pod "$NAME" -o wide
sudo k3s kubectl exec "$NAME" -c checkpoint-demo -- wget -qO- http://127.0.0.1/ | head -n 8
