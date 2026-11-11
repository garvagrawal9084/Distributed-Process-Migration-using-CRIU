# Experiment 4 — Multi-container MiniMeet migration using K3s and CRIU

**Status:** the original experiment was successfully demonstrated on **10 November 2026**: three CRIU-restored processes, two restored external data services, and a new meeting processed on the destination. The **reconstructed reference application and automation scripts** in this directory have not yet been exercised together on a new pair of VMs.

This is a **quiesced checkpoint/restore** workflow, not zero-downtime transparent live migration. Source and destination run separate K3s clusters. Source MiniMeet must remain paused until destination verification and deliberate traffic cutover.

## Directory structure

```text
04-k3s-minimeet/
├── app/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── app.py
│   └── worker.py
├── manifests/
│   ├── source.yaml
│   └── destination.yaml
└── scripts/
    ├── 01-source-setup.sh
    ├── 02-checkpoint-transfer.sh
    ├── 03-destination-restore.sh
    └── 04-validate-destination.sh
```

The three containers share `/shared`: `backend` is FastAPI/Uvicorn (explicit `--loop asyncio`), `worker` consumes the Redis `meeting_jobs` queue, and `sidecar` tails `/shared/worker.log`. PostgreSQL 16 stores meeting rows. Redis 7 is initially RDB-restored and then converted to AOF persistence.

## Required environment

The successful configuration used:

| Component | Source VM | Destination VM |
| --- | --- | --- |
| CPU | x86_64 | x86_64 |
| K3s | v1.34.1+k3s1 inside **root-owned Podman** `k3s-server` | v1.34.1+k3s1 on the VM |
| containerd | v2.1.4-k3s2 | v2.1.4-k3s2 |
| runc | 1.3.1 | 1.3.1 |
| CRIU | 4.2.1 | 4.2.1 |
| PodRestore operator/CRI proxy | Kubelet checkpoint endpoint on source | **Installed, enabled and proxy wired into K3s**, on node `checkpoint-restore-dest` |
| Storage | K3s `local-path` | K3s `local-path` |

Prepare these **before** using the scripts. Read [the operator restore guide](https://github.com/checkpoint-restore/checkpoint-restore-operator/blob/main/docs/restore.md), [Experiment 3 prerequisites](../03-k3s-single-container/README.md), and [historical troubleshooting](../../docs/full-experiment-notes.md#20-additional-problems-encountered-and-solutions-in-the-k3s-workflow).

The source must have `sudo podman`, `curl`, `nsenter`, `python3`, `openssl`, Git, SSH/SCP, image registry access, and a compatible CRIU environment. The destination must have `sudo k3s kubectl`, the `PodRestore` CRD/controller, ready CRI proxy (HTTP `http://127.0.0.1:18080/readyz`) and compatible runtime. Never run against an existing database/PVC that holds valuable data.

## Copy-and-paste runbook

**On both VMs**, clone the repository once:

```bash
git clone https://github.com/garvagrawal9084/Distributed-Process-Migration-using-CRIU.git
cd Distributed-Process-Migration-using-CRIU
```

**On source VM (Thalla):**

```bash
sudo podman exec k3s-server kubectl get nodes
bash experiments/04-k3s-minimeet/scripts/01-source-setup.sh
sudo podman exec k3s-server kubectl get pods
```

Populate two source meetings and wait until processed (the same example commands are provided in the [historical walkthrough](../../docs/full-experiment-notes.md#23-full-copy-and-paste-minimeet-migration-flow-fresh-compatible-lab)):

```bash
for TITLE in "CRIU Migration Test" "Worker v2 Test"; do
  sudo podman exec k3s-server kubectl exec deployment/minimeet-backend -c backend -- \
    python -c 'import sys,json,urllib.request; b=json.dumps({"title":sys.argv[1]}).encode(); q=urllib.request.Request("http://127.0.0.1:8000/meetings",data=b,headers={"Content-Type":"application/json"},method="POST");print(urllib.request.urlopen(q,timeout=10).read().decode())' "$TITLE"
done
sudo podman exec k3s-server kubectl exec deployment/postgres -- \
  psql -U minimeet -d minimeet -c \
  'SELECT id,title,processed_at FROM meetings ORDER BY id;'
```

Both timestamps should be non-NULL before continuing.

**Still on source VM**, configure SSH. Replace the IP/username with your actual reachable destination:

```bash
export DEST_IP=192.168.122.118
export DEST_USER=garv
export SSH_KEY="$HOME/.ssh/checkpoint-transfer"
test -f "$SSH_KEY" || ssh-keygen -t ed25519 -f "$SSH_KEY" -C checkpoint-transfer
ssh-copy-id -i "$SSH_KEY.pub" "$DEST_USER@$DEST_IP"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$DEST_USER@$DEST_IP" \
  'sudo k3s kubectl get nodes && sudo k3s kubectl get crd podrestores.criu.org && curl -fsS http://127.0.0.1:18080/readyz'
```

**Checkpoint and transfer from source** (this disables source Service routing and leaves source paused):

```bash
cd ~/Distributed-Process-Migration-using-CRIU
bash experiments/04-k3s-minimeet/scripts/02-checkpoint-transfer.sh
```

The script drains the application, backs up PostgreSQL, Redis and `/shared`, checkpoints all three containers via the source kubelet API, transfers exact timestamped archives, verifies SHA-256, and transfers Kubernetes Secrets without printing credentials. Backups are in `~/minimeet-migration/v3/`.

**On destination VM**, with the destination cluster already prepared:

```bash
cd ~/Distributed-Process-Migration-using-CRIU
bash experiments/04-k3s-minimeet/scripts/03-destination-restore.sh
```

The script installs archives in `/var/lib/kubelet/checkpoints/`, imports MiniMeet image, restores PostgreSQL into a fresh PVC, restores Redis RDB before enabling AOF, seeds the shared `emptyDir` with `minimeet.pause` in an init container, creates the three-container `PodRestore`, checks that processes are paused, then unpauses **destination only** and waits for 3/3 readiness.

**Validate end-to-end on destination VM**:

```bash
bash experiments/04-k3s-minimeet/scripts/04-validate-destination.sh
sudo k3s kubectl get podrestore -o wide
sudo k3s kubectl get pods -o wide
sudo k3s kubectl exec deployment/postgres -- \
  psql -U minimeet -d minimeet \
  -c 'SELECT id,title,created_at,processed_at FROM meetings ORDER BY id;'
```

The verification script creates a new meeting against the **restored backend**, waits for its `processed_at` timestamp to become non-NULL in PostgreSQL, and checks Redis `PONG`. This tests **backend → Redis → restored worker → PostgreSQL**.

For a port-forward, on destination:

```bash
sudo k3s kubectl port-forward \
  "pod/$(cat ~/minimeet-migration/v3/restored-pod-name.txt)" 8000:8000
```

In another destination terminal, use `curl http://127.0.0.1:8000/health` or open `/docs` in a browser accessible to that port.

## What failed in the original experiment (and the fixes)

| Failure | Reason / working fix |
| --- | --- |
| CRIU `io_uring` error on backend | Switch Uvicorn to `--loop asyncio` instead of uvloop; build new image/checkpoint. |
| Redis `BRPOP` timeout | Bound `BRPOP` and use longer Redis socket timeout, retry on failure. |
| Unquiesced network connections | Pause backend and worker, drain requests, close DB/Redis connections. |
| Root-owned K3s container not found | Use `sudo podman exec k3s-server kubectl`. |
| `unknown command kubectl for kubectl` | Do not nest `k3s kubectl` inside the source Podman `kubectl` entrypoint. |
| `postgres-data`/`redis-data` Pending | Local-path `WaitForFirstConsumer`; the PVC binds when Pod is scheduled. |
| PostgreSQL `ContainerCreating` | Initial image download; inspect Pod events and wait. |
| Redis RDB could be shadowed by empty AOF | Load RDB with AOF off, then convert to AOF, check rewrite, persist startup flag. |
| `spec.template.metadata.labels` rejected | The installed PodRestore schema accepts `spec.template.spec` but rejected this metadata field; omit it. |
| Restored backend HTTP 503 / Pod 2/3 Ready | Expected while `minimeet.pause` exists; resume only after verifying paused process state. |

The historical November run restored three containers without restarts; backend returned HTTP 200 and the third meeting was processed on destination on **2026-11-10 at 16:24:53 UTC**. These results pertain to the real VM experiment, **not to a newly verified run of the reference scripts**.

## Safety and limitations

- **Quiesced, not transparent live migration.** No claim of zero downtime, no automatic client TCP session preservation.
- Database, Redis and `emptyDir` restoration is **separate** from CRIU process restore.
- Secrets, checkpoints and DB dumps are sensitive. Do not commit runtime artifacts or private SSH/kubelet keys.
- Use a fresh isolated K3s lab, compatible versions, working CRI proxy and a single writer. The source remains paused and its Service selector disabled until deliberate cutover.
- The reference code is a **reconstruction** from the observed source architecture and may need environment-specific adjustments. Do not expect all environments to work simply by pasting commands without prerequisites.
