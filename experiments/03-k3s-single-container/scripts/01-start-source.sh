#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo podman exec -i k3s-server kubectl apply -f - < "$HERE/manifests/nginx-pod.yaml"
sudo podman exec k3s-server kubectl wait pod/checkpoint-demo --for=condition=Ready --timeout=300s
sudo podman exec k3s-server kubectl get pod checkpoint-demo -o wide
