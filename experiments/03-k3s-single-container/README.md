# Experiment 3 — Single-container Kubernetes/K3s CRIU restore (NGINX)

**Goal:** checkpoint an NGINX container running inside a Kubernetes Pod in source K3s (inside root-owned Podman), move the kubelet checkpoint to the destination node, then restore it using a `PodRestore` custom resource and the CRI restore proxy.

This is **not** Podman's native `podman container checkpoint`. CRIU restores the running NGINX process through containerd/runc.

## Prerequisites

Two compatible Linux VMs of the same architecture. Successful lab environment:

- Source: Podman `k3s-server`, K3s `v1.34.1+k3s1`.
- Destination: K3s `v1.34.1+k3s1`, node named `checkpoint-restore-dest`.
- Both: containerd `v2.1.4-k3s2`, runc `1.3.1`, CRIU `4.2.1`.
- Destination: working [checkpoint-restore-operator](https://github.com/checkpoint-restore/checkpoint-restore-operator), `PodRestore` CRD, and **CRI proxy wired into K3s**. See the [upstream restore instructions](https://github.com/checkpoint-restore/checkpoint-restore-operator/blob/main/docs/restore.md) and [historical installation notes](../../docs/full-experiment-notes.md#194-step-2--confirm-the-destination-is-ready).
- SSH key accepted by the destination, source host with `curl` and `nsenter`, and `sudo` access. The kubelet's client-admin key and checkpoint archives are sensitive.

## Copy/paste sequence

**Both VMs:** clone the repository (if necessary).

```bash
git clone https://github.com/garvagrawal9084/Distributed-Process-Migration-using-CRIU.git
cd Distributed-Process-Migration-using-CRIU
```

**Source VM:**

```bash
bash experiments/03-k3s-single-container/scripts/00-check-prerequisites.sh
bash experiments/03-k3s-single-container/scripts/01-start-source.sh
export DEST_HOST=192.168.122.118
export DEST_USER=garv
export SSH_KEY="$HOME/.ssh/checkpoint-transfer"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" 'hostname'
bash experiments/03-k3s-single-container/scripts/02-checkpoint-transfer.sh
```

**Destination VM:**

```bash
cd ~/Distributed-Process-Migration-using-CRIU
bash experiments/03-k3s-single-container/scripts/03-restore-destination.sh
bash experiments/03-k3s-single-container/scripts/04-verify-destination.sh
```

The restore scripts derive the actual **timestamped checkpoint archive name** from the source kubelet API response. They verify its SHA-256, install it in `/var/lib/kubelet/checkpoints`, generate a new immutable `PodRestore` name and verify that the restored NGINX serves HTTP.

## Observed problems and fixes

- `StartError: criu failed: type RESTORE errno 0`: a previous destination setup differed from source K3s/containerd/runc versions. A compatible rebuilt destination and fresh checkpoint succeeded; this did **not** isolate version mismatch as the sole root cause.
- `error: unknown command "kubectl" for "kubectl"`: use `sudo podman exec k3s-server kubectl`, **not** nested `k3s kubectl`.
- `kubelet checkpoint` requires authenticated HTTPS; the script uses the host's `curl` in Podman's network namespace. `--insecure` is only appropriate for this isolated lab; validate the server CA in production.
- K3s host daemon colliding with Podman K3s at port 6444: use the intended source cluster; do not start a second host K3s that conflicts with it.
- `ContainerCreating` while pulling images isn't immediately a restore error: inspect events and wait for the restored Pod to become Ready.
- Avoid hardcoding old filenames or attempting to patch immutable `PodRestore.spec` fields.

> NGINX is stateless here. HTTP availability proves runtime restoration but not a custom in-memory counter. See Experiment 1 for persistent process-state behavior, and Experiment 4 for a real backend/worker/Redis/PostgreSQL workflow.
