# Experiment 1 — Standalone Linux process migration with CRIU

**Goal:** checkpoint a running Python counter on VM1, move its CRIU images and filesystem state over SSH, and restore the **same process state** on VM2. This is not starting a new counter from zero.

## Requirements

Two compatible Linux VMs of the **same architecture**, installed CRIU and Python 3, SSH from source to destination, and `sudo` privileges. Checkpoints can contain process memory and secrets. Both VMs must allow CRIU's required kernel features (`sudo criu check`). The destination should have the same numeric user IDs, filesystem path and permissions as the source.

If `apt install criu` is unavailable on Ubuntu/ARM64, see the [original source-build instructions](../../docs/full-experiment-notes.md#1-installing-criu). Do not disable AppArmor merely to avoid investigating a failed `criu check`.

## Copy-and-paste sequence

**On both VMs**, clone the repo and check CRIU:

```bash
git clone https://github.com/garvagrawal9084/Distributed-Process-Migration-using-CRIU.git
cd Distributed-Process-Migration-using-CRIU
bash experiments/01-standalone-process/scripts/00-check-prerequisites.sh
```

**On source VM** (this starts the counter):

```bash
bash experiments/01-standalone-process/scripts/01-start-source.sh
```

**On source VM**, set the destination address and SSH key and create a checkpoint. The source counter **stops** when the dump succeeds:

```bash
export DEST_HOST=192.168.122.118
export DEST_USER=garv
export SSH_KEY="$HOME/.ssh/checkpoint-transfer"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_HOST" 'hostname'
bash experiments/01-standalone-process/scripts/02-checkpoint-transfer.sh
```

**On destination VM**:

```bash
cd ~/Distributed-Process-Migration-using-CRIU
bash experiments/01-standalone-process/scripts/03-restore-destination.sh
bash experiments/01-standalone-process/scripts/04-verify-destination.sh
```

A successful restore reports that the counter increased **from the copied checkpoint value**, and `pgrep` locates the restored Python process. The working directory is fixed at `/tmp/criu-process-demo` on **both** VMs because CRIU restores absolute working-directory references.

## Failures found in the original work

- **`pidof number.py` does not identify Python scripts reliably:** use the process PID saved by the starter script, or `pgrep -af number.py`.
- **Terminal/session attachment:** `--shell-job` accommodates shell-launched jobs in this lab; the starter redirects standard streams.
- **Cannot open cwd / permission mismatch:** ensure `/tmp/criu-process-demo` exists on the destination with compatible ownership and permissions, and transfer the counter file along with the CRIU image directory.
- **CRIU compatibility / cgroups:** match user IDs, architecture and runtime/kernel capabilities; inspect `images/dump.log` and `images/restore.log` on failures.

> This is a controlled test. Neither a generic kernel nor any version mismatch is guaranteed to restore. Copy-paste commands are deterministic **after prerequisites are satisfied**.
