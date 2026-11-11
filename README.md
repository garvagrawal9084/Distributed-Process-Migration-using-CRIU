# Distributed Process Migration using CRIU

A four-experiment, two-VM lab repository demonstrating **checkpoint, transfer, restore, and post-restore verification** of Linux processes, Podman containers, and Kubernetes workloads using [CRIU](https://criu.org/).

The original demonstrations and detailed troubleshooting history are preserved in [full experiment notes](docs/full-experiment-notes.md). Each experiment now has its **own folder, README, and runnable shell scripts**, so you can follow one workflow independently.

## Experiments

| # | Experiment | Checkpoint mechanism | What success means | Instructions |
| --- | --- | --- | --- | --- |
| 1 | Standalone Python process | `criu dump` / `criu restore` | A restored counter advances from its checkpointed value | [Experiment 1](experiments/01-standalone-process/README.md) |
| 2 | Podman container | `podman container checkpoint/restore` | A restored Golang container is running and serves HTTP on destination | [Experiment 2](experiments/02-podman-container/README.md) |
| 3 | Single-container NGINX on K3s | Kubelet checkpoint API + CRIU `PodRestore` | Restored NGINX container is Ready and serves its page | [Experiment 3](experiments/03-k3s-single-container/README.md) |
| 4 | Three-container MiniMeet on K3s | Three kubelet checkpoints + `PodRestore` + data-service backups | Restored backend, worker and sidecar; existing meetings preserved and new job processed | [Experiment 4](experiments/04-k3s-minimeet/README.md) |

**Experiment 4 was successfully demonstrated on 10 November 2026**, with the restored Pod reaching `3/3 Running`, health returning HTTP 200, PostgreSQL and Redis connected, and a new meeting successfully processed by the restored worker. The reference application and automation scripts in the repository were reconstructed afterward; they have **not all been executed end-to-end on fresh machines**.

## Repository structure

```text
.
├── README.md
├── .gitignore
├── docs/
│   └── full-experiment-notes.md
└── experiments/
    ├── 01-standalone-process/
    │   ├── README.md
    │   ├── number.py
    │   └── scripts/       # 00 prerequisites, 01 start, 02 checkpoint+transfer,
    │                      # 03 restore, 04 verify
    ├── 02-podman-container/
    │   ├── README.md
    │   └── scripts/       # prerequisites, start, checkpoint, restore, verify
    ├── 03-k3s-single-container/
    │   ├── README.md
    │   ├── manifests/
    │   └── scripts/       # prerequisites, NGINX Pod, checkpoint, restore, verify
    └── 04-k3s-minimeet/
        ├── README.md
        ├── app/           # reconstructed FastAPI backend + Redis worker + Dockerfile
        ├── manifests/     # source/destination Kubernetes resources
        └── scripts/       # source setup, checkpoint+transfer,
                           # destination restore, end-to-end validation
```

## Quick start

**Choose one experiment, read its prerequisites, then run the commands in that experiment's README.** The commands distinguish **SOURCE** and **DESTINATION** VMs explicitly; do not execute both halves on the same machine.

Clone on **both VMs**:

```bash
git clone https://github.com/garvagrawal9084/Distributed-Process-Migration-using-CRIU.git
cd Distributed-Process-Migration-using-CRIU
```

For example, start the **standalone process experiment**:

```bash
# On SOURCE (after the prerequisites in Experiment 1)
bash experiments/01-standalone-process/scripts/00-check-prerequisites.sh
bash experiments/01-standalone-process/scripts/01-start-source.sh
```

For **Podman**, start here:

```bash
# On SOURCE
bash experiments/02-podman-container/scripts/00-check-prerequisites.sh
bash experiments/02-podman-container/scripts/01-start-source.sh
```

For **K3s NGINX**, start here:

```bash
# On SOURCE; K3s must already run under root-owned Podman "k3s-server"
bash experiments/03-k3s-single-container/scripts/00-check-prerequisites.sh
bash experiments/03-k3s-single-container/scripts/01-start-source.sh
```

For **MiniMeet**, start here:

```bash
# On SOURCE; compatible K3s / CRIU prerequisite environment required
bash experiments/04-k3s-minimeet/scripts/01-source-setup.sh
```

Then follow that experiment's README for **quiescence/checkpoint, SSH/SCP transfer, destination restore, and verification**. Every subsequent command is already shown in the linked guide; the commands above do **not** complete the experiments on their own.

## Setup requirements and limitations

- Use **two compatible Linux VMs**, matching CPU architecture and compatible kernel/CRIU/runtime behavior; install CRIU and verify with `sudo criu check`.
- Configure SSH access from source to destination. Set `DEST_HOST` for Experiments 1–3, or `DEST_IP` for Experiment 4, alongside `DEST_USER` and `SSH_KEY`.
- For the **K3s experiments**, source K3s runs inside **root-owned Podman `k3s-server`**. The destination has VM-native K3s, a `PodRestore` CRD/controller, the CRI restore proxy wired into kubelet, and a node called `checkpoint-restore-dest`. The tested runtime combination was K3s `v1.34.1+k3s1`, containerd `v2.1.4-k3s2`, runc `1.3.1`, CRIU `4.2.1`. Consult Experiment 3/4 setup docs before copying K3s commands.
- Checkpoints can contain passwords, memory contents and other secrets: **never commit checkpoint archives, database dumps, SSH private keys, exported Secrets or kubelet client keys**.
- These are *stop/quiesce-and-restore* lab workflows, **not** zero-downtime transparent live migration. External TCP connections do not move automatically; PostgreSQL, Redis, and shared volumes require independent migration.
- **No command sequence can guarantee error-free CRIU restoration on arbitrary hosts.** Scripts are provided as reproducible lab guidance, with explicit prerequisites and checks. Only the historical results are confirmed from completed VM runs; scripts added later require a clean-room test.

## Typical errors and fixes

The original investigation documented and resolved:

| Issue | Working approach |
| --- | --- |
| `criu` package unavailable, library/toolchain errors | Build CRIU from source and verify required kernel support |
| `pidof number.py` fails | Use saved PID or `pgrep -af number.py` |
| CRIU cwd/permission mismatch | Restore identical paths, ownership, and filesystem state |
| `sudo scp` SSH key failure | Transfer as the normal user with `scp -i` |
| Podman K3s container invisible | Run `sudo podman ...` (root-owned Podman) |
| Wrong nested `k3s kubectl` | Use `sudo podman exec k3s-server kubectl` |
| Version-dependent `criu failed: type RESTORE` | Match known-compatible runtime, use fresh archives, inspect proxy/operator logs |
| MiniMeet checkpoint blocked by `io_uring` | Uvicorn `--loop asyncio` instead of uvloop |
| Redis `BRPOP` timeouts | Bounded queue blocking and longer socket timeout |
| PostgreSQL/Redis PVC `Pending` | Wait for `local-path` first consumer |
| Redis RDB overridden by AOF | Seed RDB before Redis startup, verify load, then enable AOF |
| `spec.template.metadata.labels` rejected | Omit that unsupported `PodRestore` field |
| `2/3 Ready`, HTTP 503 after restore | Expected while the destination backend is intentionally paused |

For detailed terminal outputs, errors, and fixes, see [historical experiment notes](docs/full-experiment-notes.md). For a problem specific to one lab, open that experiment's README.

## Experiment outcomes

**Standalone CRIU, Podman, K3s single-container, and K3s MiniMeet** are documented as distinct migration approaches. The key additional evidence for the completed MiniMeet experiment is post-restore work: the destination backend returned `{"status":"healthy","database":true,"redis":true}`, and the new meeting `CRIU Migration Success Test` received a non-NULL `processed_at` timestamp, proving the checkpoint-restored worker consumed the queued job.

The source application was deliberately kept paused and unrouted during destination validation. Production ingress cutover, rollback procedures and downtime measurement were outside this lab's recorded successful run.

---

# References

### CRIU and Podman
- [CRIU project](https://criu.org/)
- [CRIU source code](https://github.com/checkpoint-restore/criu)
- [CRIU manual](https://man7.org/linux/man-pages/man8/criu.8.html)
- [Podman container checkpoint](https://docs.podman.io/en/stable/markdown/podman-container-checkpoint.1.html)
- [Podman container restore](https://docs.podman.io/en/stable/markdown/podman-container-restore.1.html)

### Kubernetes/K3s
- [Kubernetes container checkpointing](https://kubernetes.io/blog/2022/12/05/forensic-container-checkpointing-alpha/)
- [Checkpoint/Restore Operator](https://github.com/checkpoint-restore/checkpoint-restore-operator)
- [PodRestore and CRI proxy guide](https://github.com/checkpoint-restore/checkpoint-restore-operator/blob/main/docs/restore.md)
- [K3s documentation](https://docs.k3s.io/)
- [Kubernetes init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

### Data services
- [PostgreSQL `pg_dump`](https://www.postgresql.org/docs/16/app-pgdump.html)
- [PostgreSQL `pg_restore`](https://www.postgresql.org/docs/16/app-pgrestore.html)
- [Redis RDB/AOF persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)
- [FastAPI](https://fastapi.tiangolo.com/)
