# Choose an experiment

Each experiment is a self-contained folder with its own README and scripts. **Always follow the instructions for both SOURCE and DESTINATION VMs.**

| # | Experiment | Entry point |
| --- | --- | --- |
| 01 | Python counter checkpoint / restore | [Standalone process](01-standalone-process/README.md) |
| 02 | Podman container checkpoint / restore | [Podman container](02-podman-container/README.md) |
| 03 | NGINX on K3s (kubelet checkpoints + PodRestore) | [Single-container Kubernetes](03-k3s-single-container/README.md) |
| 04 | Three-container MiniMeet + PostgreSQL + Redis | [Multi-container application](04-k3s-minimeet/README.md) |

Use the [repository overview](../README.md) for architecture and prerequisites and the [original complete notes](../docs/full-experiment-notes.md) for diagnostics and historical terminal outputs.

**Compatibility warning:** Restore is dependent on compatible kernels/CPU architecture, CRIU and container runtimes, and (for K3s) the checkpoint-restore operator plus a functioning CRI proxy. The new scripts should be tested on fresh isolated VMs before relying on them for other systems.
