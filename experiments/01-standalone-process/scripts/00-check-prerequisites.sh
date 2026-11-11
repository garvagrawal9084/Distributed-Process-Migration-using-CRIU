#!/usr/bin/env bash
set -euo pipefail
command -v python3 >/dev/null
command -v criu >/dev/null || { echo "CRIU is missing; install it first (see README)." >&2; exit 1; }
command -v sha256sum >/dev/null
command -v ssh >/dev/null
command -v scp >/dev/null
echo "CRIU version: $(criu --version)"
echo "Machine: $(uname -m), kernel: $(uname -r)"
sudo criu check
