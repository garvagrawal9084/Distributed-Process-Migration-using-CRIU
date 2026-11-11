# Experiment 2 — Podman container migration with CRIU

**Goal:** checkpoint an entire Podman-managed container on one Linux VM, transfer its checkpoint archive using SCP, and **restore** it on the other VM using `podman container restore --import`.

This uses the original public demonstration image `docker.io/garvagrawal9084/pdm-golang:latest`. The published image is a *mutable* tag; for rigorous repeatability pin its immutable digest, and run this only with compatible OS/runtime/architecture.

## Prerequisites

CRIU and rootful Podman on **both** VMs, working SSH from source to destination, compatible architectures and runc/CRIU versions, network reachability, and enough disk for the archive. The container may have host-specific network dependencies; external services/volumes require separate migration. Run `00-check-prerequisites.sh` on both VMs.

## Copy/paste commands

**Both VMs**, if not already cloned:

```bash
git clone https://github.com/garvagrawal9084/Distributed-Process-Migration-using-CRIU.git
cd Distributed-Process-Migration-using-CRIU
bash experiments/02-podman-container/scripts/00-check-prerequisites.sh
```

**Source VM:**

```bash
bash experiments/02-podman-container/scripts/01-start-source.sh
export DEST_HOST=192.168.122.118
export DEST_USER=garv
export SSH_KEY="$HOME/.ssh/checkpoint-transfer"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" hostname
bash experiments/02-podman-container/scripts/02-checkpoint-transfer.sh
```

The checkpoint command intentionally **stops** the source. Do not restart it while the destination copy is active.

**Destination VM:**

```bash
cd ~/Distributed-Process-Migration-using-CRIU
bash experiments/02-podman-container/scripts/03-restore-destination.sh
bash experiments/02-podman-container/scripts/04-verify-destination.sh
```

The final test checks Podman process state, port mapping, and HTTP on destination port 8081. Override `DEST_PORT`, `SOURCE_PORT`, `CONTAINER_NAME` or `CONTAINER_IMAGE` as environment variables if needed.

## Historical pitfalls and fixes

- **Wrong archive filename:** transfer the generated `pdm-golang-new-checkpoint.tar.gz` rather than guessing `/tmp/test.tar.gz`.
- **Wrong archive path:** always use `--import=/absolute/path/to/checkpoint.tar.gz`.
- **`sudo scp` uses root's SSH identity:** the script changes ownership of the root-generated checkpoint archive and uses regular `scp -i`.
- **`Can't open cwd`, cgroup or filesystem permissions:** ensure the restored container's mounted paths, runtime, cgroup configuration and required external data are compatible across hosts.
- **AppArmor or kernel features:** inspect `sudo criu check` and the Podman restore error before changing machine security settings.

> This is a checkpoint-based, short-downtime migration. It does **not** automatically transfer external database state or live TCP connections. A compatible runtime is mandatory; these commands cannot guarantee successful restore on unrelated systems.

See [original troubleshooting notes](../../docs/full-experiment-notes.md#16-problems-encountered-and-solutions).
