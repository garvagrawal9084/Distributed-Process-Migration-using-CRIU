#!/usr/bin/env bash
# SOURCE: root-owned Podman K3s. Destination: VM-native K3s + CRI proxy/operator.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v sudo >/dev/null
command -v python3 >/dev/null
command -v curl >/dev/null
command -v nsenter >/dev/null
command -v ssh >/dev/null
command -v scp >/dev/null
sudo podman exec k3s-server kubectl get nodes -o wide
sudo podman exec k3s-server /bin/k3s --version
echo "Inspect dest with: sudo k3s kubectl get nodes; sudo k3s kubectl get crd podrestores.criu.org"
echo "Read $HERE/README.md for matching runtime/CRI proxy prerequisites."
