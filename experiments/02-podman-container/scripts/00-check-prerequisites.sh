#!/usr/bin/env bash
set -euo pipefail
command -v podman >/dev/null
command -v ssh >/dev/null
command -v scp >/dev/null
command -v sha256sum >/dev/null
command -v criu >/dev/null || { echo "Install CRIU first" >&2; exit 1; }
echo "OS and architecture: $(uname -srmo)"
podman --version
criu --version
sudo criu check
sudo podman info --format 'OCI runtime: {{.Host.OCIRuntime.Name}}'
