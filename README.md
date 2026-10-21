# Distributed Process Migration using CRIU

# CRIU Process Migration using Ubuntu VMs (VMware Fusion)

This project demonstrates **process checkpoint and restore** using **CRIU (Checkpoint/Restore In Userspace)** across two Ubuntu virtual machines running on VMware Fusion.

The project contains two migration approaches:

1. **Linux process migration using CRIU**
2. **Container migration using Podman + CRIU**

---

# System Configuration

| Component            | Details                  |
| -------------------- | ------------------------ |
| Host OS              | macOS                    |
| Hypervisor           | VMware Fusion            |
| Guest OS             | Ubuntu 24.04.4 LTS ARM64 |
| Architecture         | ARM64 (Apple Silicon)    |
| Source VM            | VM1                      |
| Destination VM       | VM2                      |
| Programming Language | Python                   |
| Container Runtime    | Podman                   |
| Migration Tool       | CRIU                     |

---

# Project Structure

```text
Project/
│
├── number.py
├── dump/
│   └── demo/
│       ├── inventory.img
│       ├── files.img
│       ├── pstree.img
│       ├── ...
│
└── README.md
```

---

# 1. Installing CRIU

Update package lists:

```bash
sudo apt update
```

Install required packages:

```bash
sudo apt install -y \
git \
build-essential \
pkg-config \
libprotobuf-dev \
protobuf-c-compiler \
protobuf-compiler \
libprotobuf-c-dev \
python3-protobuf \
python3-future \
python3-yaml \
libnl-3-dev \
libcap-dev \
libaio-dev \
libnet-dev \
libbsd-dev \
uuid-dev
```

Clone CRIU:

```bash
git clone https://github.com/checkpoint-restore/criu.git
cd criu
```

Compile:

```bash
make -j$(nproc)
```

Install:

```bash
sudo make install DOCBOOK=no
```

Verify:

```bash
criu --version
```

---

# 2. Installing SSH

SSH is used to transfer checkpoint data between the two VMs.

On the destination VM:

```bash
sudo apt update
sudo apt install openssh-server
```

Enable SSH:

```bash
sudo systemctl enable --now ssh
```

Verify:

```bash
sudo systemctl status ssh
```

Find the VM IP:

```bash
hostname -I
```

Connect from the source VM:

```bash
ssh <username>@<VM2_IP>
```

Example:

```bash
ssh user@192.168.64.11
```

---

# 3. Direct Process Migration Using CRIU

This section demonstrates checkpoint and restore of a normal Linux process without a container.

## Run the Process

On VM1:

```bash
python3 number.py
```

Find the process ID:

```bash
pgrep -af number.py
```

Example:

```text
6075 python3 number.py
```

---

## Checkpoint the Process

Create the checkpoint directory:

```bash
mkdir -p dump/demo
```

Checkpoint the process:

```bash
sudo criu dump \
-t 6075 \
-D dump/demo \
--shell-job
```

CRIU creates checkpoint image files:

```text
dump/demo/
├── inventory.img
├── files.img
├── pstree.img
├── ...
```

---

## Transfer Checkpoint

Transfer the checkpoint directory to VM2:

```bash
scp -r dump \
<username>@<VM2_IP>:/home/<username>/Project/
```

Example:

```bash
scp -r dump \
user@192.168.64.11:/home/user/Project/
```

---

## Restore

On VM2:

```bash
cd ~/Project
```

Restore the process:

```bash
sudo criu restore \
-D dump/demo \
--shell-job
```

The process should continue from the checkpointed state.

---

# 4. AppArmor Configuration for CRIU

AppArmor provides security profiles that restrict the capabilities of processes and containers.

During CRIU checkpoint/restore experiments, AppArmor can interfere with restoring processes or containers because the security state of the destination environment may differ from the source.

For this experimental project, AppArmor can be disabled on both VMs.

## Check AppArmor Status

Run:

```bash
sudo apparmor_status
```

If AppArmor is active, the output contains:

```text
apparmor module is loaded.
```

It may also show profiles in:

```text
enforce mode
complain mode
unconfined mode
```

---

## Disable AppArmor

Edit the GRUB configuration:

```bash
sudo nano /etc/default/grub
```

Find:

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
```

Change it to:

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash apparmor=0"
```

Save the file and update GRUB:

```bash
sudo update-grub
```

Reboot:

```bash
sudo reboot
```

---

## Verify AppArmor Is Disabled

After reboot:

```bash
sudo apparmor_status
```

Also check:

```bash
cat /proc/cmdline
```

The kernel command line should contain:

```text
apparmor=0
```

The AppArmor status should indicate that the module is not loaded.

> **Note:** Disabling AppArmor reduces system security. This configuration should only be used on the controlled VMs used for this CRIU experiment.

---

# 5. Container Migration Using Podman + CRIU

This section demonstrates checkpointing and restoring a complete container using **Podman and CRIU**.

Podman provides native checkpoint and restore functionality backed by CRIU.

The container can be checkpointed on VM1, exported as an archive, transferred to VM2, and restored there.

---

# 6. Run the Container

On VM1:

```bash
sudo podman run \
-d \
--name pdm-golang-new \
-p 8081:8080 \
docker.io/garvagrawal9084/pdm-golang:latest
```

Check the running container:

```bash
sudo podman ps
```

You can inspect the container with:

```bash
sudo podman inspect pdm-golang-new
```

---

# 7. Create a Container Checkpoint

Create and export the checkpoint:

```bash
sudo podman container checkpoint \
--leave-running \
-l \
--export=/tmp/cp.tar.gz
```

### Options

* `--leave-running` — keeps the original container running after checkpointing.
* `-l` — selects the latest container.
* `--export=/tmp/cp.tar.gz` — exports the checkpoint to a compressed archive.

Verify that the checkpoint exists:

```bash
ls -lh /tmp/cp.tar.gz
```

Example:

```text
-rw------- 1 root root 55K Aug 9 22:04 /tmp/cp.tar.gz
```

---

# 8. Transfer the Container Checkpoint

Transfer the checkpoint archive from VM1 to VM2:

```bash
sudo scp /tmp/cp.tar.gz \
<username>@<VM2_IP>:/tmp/
```

Example:

```bash
sudo scp /tmp/cp.tar.gz \
user@192.168.64.11:/tmp/
```

The file will be available on VM2 as:

```text
/tmp/cp.tar.gz
```

---

# 9. Verify the Checkpoint on VM2

On VM2:

```bash
ls -lh /tmp/cp.tar.gz
```

Make sure the archive exists before attempting the restore.

---

# 10. Restore the Container

The checkpoint archive should be passed directly to Podman using `--import`.

Do not manually extract the archive.

Run:

```bash
sudo podman container restore \
--import=/tmp/cp.tar.gz \
--name pdm-golang-new \
-p 8081:8080
```

The restored container can also use a different host port.

For example:

```bash
sudo podman container restore \
--import=/tmp/cp.tar.gz \
--name pdm-golang-new \
-p 8082:8080
```

Here:

```text
8082:8080
```

means:

```text
Host port 8082 → Container port 8080
```

---

# 11. Verify the Restored Container

Check running containers:

```bash
sudo podman ps
```

Check all containers:

```bash
sudo podman ps -a
```

Inspect the restored container:

```bash
sudo podman inspect pdm-golang-new
```

Check port mapping:

```bash
sudo podman port pdm-golang-new
```

Example:

```text
8080/tcp -> 0.0.0.0:8081
```

---

# 12. Complete Container Migration Workflow

The complete workflow is:

```text
                    VM1
                     │
                     │
             ┌───────▼────────┐
             │  Run Container │
             │     Podman     │
             └───────┬────────┘
                     │
                     │ CRIU checkpoint
                     ▼
             ┌────────────────┐
             │  cp.tar.gz     │
             │ /tmp/cp.tar.gz │
             └───────┬────────┘
                     │
                     │ SCP / SSH
                     ▼
             ┌────────────────┐
             │      VM2       │
             │ /tmp/cp.tar.gz │
             └───────┬────────┘
                     │
                     │ Podman restore
                     ▼
             ┌────────────────┐
             │    Restored    │
             │    Container   │
             └────────────────┘
```

---

# 13. Complete Podman Migration Commands

## VM1 — Run Container

```bash
sudo podman run -d \
  --name pdm-golang-new \
  -p 8081:8080 \
  docker.io/garvagrawal9084/pdm-golang:latest
```

## VM1 — Create Checkpoint

```bash
sudo podman container checkpoint \
  --leave-running \
  -l \
  --export=/tmp/cp.tar.gz
```

## VM1 — Verify Checkpoint

```bash
ls -lh /tmp/cp.tar.gz
```

## VM1 — Transfer Checkpoint

```bash
sudo scp /tmp/cp.tar.gz \
  <username>@<VM2_IP>:/tmp/
```

## VM2 — Verify

```bash
ls -lh /tmp/cp.tar.gz
```

## VM2 — Restore

```bash
sudo podman container restore \
  --import=/tmp/cp.tar.gz \
  --name pdm-golang-new \
  -p 8081:8080
```

---

# 14. Important Podman Migration Notes

## Checkpoint Filename

The checkpoint generated in this project is:

```text
/tmp/cp.tar.gz
```

Therefore, use:

```bash
scp /tmp/cp.tar.gz ...
```

Do not use:

```bash
scp /tmp/test.tar.gz ...
```

unless that file actually exists.

---

## Use an Absolute Path

Correct:

```bash
sudo podman container restore \
--import=/tmp/cp.tar.gz \
--name pdm-golang-new \
-p 8081:8080
```

Incorrect:

```bash
sudo podman container restore \
--import=tmp/cp.tar.gz
```

The second command searches for:

```text
./tmp/cp.tar.gz
```

instead of:

```text
/tmp/cp.tar.gz
```

---

## Use Two Normal Hyphens

Correct:

```text
--import
--name
```

Incorrect:

```text
—import
—name
```

The second form uses a Unicode em dash and is not recognized as a command-line option.

---

# 15. CRIU and Podman Compatibility

Check CRIU:

```bash
criu --version
```

Check Podman:

```bash
podman --version
```

Check Podman configuration:

```bash
sudo podman info
```

The source and destination machines should have compatible:

* Ubuntu versions
* Kernel versions/configuration
* CPU architecture
* CRIU versions
* Podman versions
* OCI runtime
* cgroup configuration
* Container configuration

---

# 16. Problems Encountered and Solutions

## 1. apt Could Not Locate CRIU

### Error

```text
Package 'criu' has no installation candidate
```

### Cause

Ubuntu ARM repositories did not provide the required CRIU package.

### Solution

Compiled CRIU from source.

---

## 2. apt Repository Timeout

### Error

```text
Connection failed
Could not connect to ports.ubuntu.com
```

### Cause

Repository mirror/network connection issue.

### Solution

Forced IPv4:

```bash
echo 'Acquire::ForceIPv4 "true";' | \
sudo tee /etc/apt/apt.conf.d/99force-ipv4
```

---

## 3. Package Lock

### Error

```text
Could not get lock
```

### Cause

Another apt process was running.

### Solution

Check:

```bash
ps aux | grep apt
```

If necessary:

```bash
sudo kill -9 PID
```

---

## 4. Missing Packages

### Error

```text
Compilation aborted.
Can not find required libraries.
```

### Solution

Installed:

```text
libprotobuf-dev
libprotobuf-c-dev
protobuf-c-compiler
protobuf-compiler
python3-protobuf
libnl-3-dev
libcap-dev
uuid-dev
python3-yaml
libaio-dev
```

---

## 5. make install Failed

### Error

```text
asciidoc: not found
```

### Cause

Documentation generation.

### Solution

```bash
sudo make install DOCBOOK=no
```

---

## 6. Disk Full

### Error

```text
No space left on device
```

### Cause

Installing documentation packages pulled large TeX dependencies.

### Solution

Removed unnecessary packages.

Avoid installing:

```text
asciidoc
xmlto
dblatex
texlive*
docbook*
```

when documentation is not required.

---

## 7. UTM Live ISO Reset

### Problem

Ubuntu reset every reboot.

### Cause

The VM was still booting from the installation ISO.

### Solution

Removed the installer ISO after Ubuntu installation.

Eventually switched to VMware Fusion.

---

## 8. SSH Not Running

### Error

```text
Active: inactive (dead)
```

### Solution

```bash
sudo systemctl enable --now ssh
```

---

## 9. pidof Did Not Find Python Script

### Error

```bash
pidof number.py
```

returned nothing.

### Solution

Use:

```bash
pgrep -af number.py
```

---

## 10. CRIU Refused Terminal Process

### Error

```text
Task attached to shell terminal.
```

### Solution

```bash
sudo criu dump \
-t PID \
-D dump/demo \
--shell-job
```

---

## 11. Missing Working Directory During Restore

### Error

```text
Can't open cwd
```

```text
No such file or directory
```

### Cause

Different usernames or directory structures on the source and destination VMs.

### Solution

Use identical directory structures on both VMs.

For example:

```text
/home/user/Project
```

on both VMs.

---

## 12. File Permission Mismatch

### Error

```text
bad mode 040755
expect 040775
```

### Solution

```bash
chmod 775 /home/user/Project
```

Alternatively:

```bash
sudo criu restore \
-D dump/demo \
--shell-job \
--skip-file-rwx-check
```

---

## 13. libnftables Warning

### Warning

```text
CRIU was built without libnftables support
```

### Explanation

This was treated as a non-blocking warning for the basic migration experiment.

---

## 14. cgroup Warning

### Error

```text
cg: cgroupd: recv req error
```

### Cause

Possible mismatch between checkpoint and restore environments.

### Solution

Ensure:

* Same Ubuntu version
* Compatible kernel configuration
* Same CRIU version
* Same Podman version
* Compatible OCI runtime
* Same CPU architecture
* Compatible cgroup configuration
* Same filesystem paths

---

## 15. VMware Networking

Both VMs were configured on the same virtual network.

Verify connectivity:

```bash
ping VM2_IP
```

Verify SSH:

```bash
ssh <username>@VM2_IP
```

---

## 16. AppArmor Enabled

### Problem

AppArmor was active during checkpoint/restore experiments.

Check:

```bash
sudo apparmor_status
```

If the output contains:

```text
apparmor module is loaded.
```

AppArmor is active.

### Solution

Add the following kernel parameter:

```text
apparmor=0
```

to:

```text
/etc/default/grub
```

For example:

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash apparmor=0"
```

Then:

```bash
sudo update-grub
sudo reboot
```

Verify:

```bash
cat /proc/cmdline
```

and:

```bash
sudo apparmor_status
```

---

## 17. Incorrect Checkpoint Filename

### Error

```text
scp: stat local "/tmp/test.tar.gz": No such file or directory
```

### Cause

The checkpoint was created as:

```text
/tmp/cp.tar.gz
```

but the SCP command referenced:

```text
/tmp/test.tar.gz
```

### Solution

```bash
scp /tmp/cp.tar.gz \
<username>@VM2_IP:/tmp/
```

---

## 18. Incorrect Checkpoint Path During Restore

### Error

```text
failed to open checkpoint archive tmp/cp.tar.gz
No such file or directory
```

### Cause

The path was written as:

```text
tmp/cp.tar.gz
```

instead of:

```text
/tmp/cp.tar.gz
```

### Solution

```bash
sudo podman container restore \
--import=/tmp/cp.tar.gz \
--name pdm-golang-new \
-p 8081:8080
```

---

# 17. Useful Commands

## Current IP

```bash
hostname -I
```

## SSH Status

```bash
sudo systemctl status ssh
```

## Find Process

```bash
pgrep -af number.py
```

## CRIU Version

```bash
criu --version
```

## Podman Version

```bash
podman --version
```

## AppArmor Status

```bash
sudo apparmor_status
```

## Kernel Parameters

```bash
cat /proc/cmdline
```

## Running Containers

```bash
sudo podman ps
```

## All Containers

```bash
sudo podman ps -a
```

## Podman Information

```bash
sudo podman info
```

## Checkpoint Process

```bash
sudo criu dump \
-t PID \
-D dump/demo \
--shell-job
```

## Restore Process

```bash
sudo criu restore \
-D dump/demo \
--shell-job
```

## Checkpoint Container

```bash
sudo podman container checkpoint \
--leave-running \
-l \
--export=/tmp/cp.tar.gz
```

## Transfer Container Checkpoint

```bash
scp /tmp/cp.tar.gz \
<username>@VM2_IP:/tmp/
```

## Restore Container

```bash
sudo podman container restore \
--import=/tmp/cp.tar.gz \
--name pdm-golang-new \
-p 8081:8080
```

---

# 18. Lessons Learned

* CRIU is sensitive to filesystem paths.
* Source and destination systems should be as similar as possible.
* Using the same username on both systems simplifies process migration.
* The working directory required by a checkpoint must exist on the destination.
* SSH simplifies transferring checkpoint images.
* AppArmor security policies can affect checkpoint/restore experiments.
* Podman provides native checkpoint and restore functionality using CRIU.
* Podman can export a container checkpoint as an archive.
* The checkpoint archive can be transferred between VMs using SCP.
* Podman can restore the exported checkpoint directly using `--import`.
* The restored container can be assigned a new name using `--name`.
* Port mappings can be changed during restore using `-p`.
* VMware Fusion provided a more reliable environment for this project than the earlier UTM setup.

---

# 19. Kubernetes/K3s Checkpoint and Restore Using the PodRestore Operator

This section documents a second migration path alongside the direct-process and native Podman workflows above. It uses the Kubernetes kubelet checkpoint API to create a container checkpoint and the [checkpoint-restore-operator](https://github.com/checkpoint-restore/checkpoint-restore-operator) `PodRestore` resource to restore it on a destination K3s node.

**Do not confuse this with `podman container checkpoint` / `podman container restore`.** In this workflow, a container is running inside a Pod in a K3s cluster; the checkpoint is requested through the kubelet API, and restoration is orchestrated by the `PodRestore` custom resource and a CRI proxy.

## 19.1 Tested Environment

The following combination completed the end-to-end test in this project:

| Component | Source (`Thalla`) | Destination (`checkpoint-restore-dest`) |
| --- | --- | --- |
| CPU architecture | `x86_64` | `x86_64` |
| Kernel | `6.8.0-138-generic` | `6.8.0-147-generic` |
| K3s | `v1.34.1+k3s1` inside Podman | `v1.34.1+k3s1` installed on the VM |
| Containerd | `v2.1.4-k3s2` | `v2.1.4-k3s2` |
| runc | `1.3.1` | `1.3.1` |
| CRIU | `4.2.1` | `4.2.1` |
| Test workload | Pod `checkpoint-demo`, container `checkpoint-demo` | Restored Pod `checkpoint-demo-restored-final` |

On the source, K3s was running in the Podman container named `k3s-server`. At test time the container image was `docker.io/rancher/k3s:latest`, but the binary inside it reported `v1.34.1+k3s1`. For reproducible future runs, pin a specific container image tag rather than relying on the mutable `latest` tag.

The source and destination kernel patch versions were not identical; both machines were `x86_64` and both passed the basic `criu check`. The successful test establishes that this specific configuration worked; it does not prove that matching versions alone caused the success.

## 19.2 Workflow Overview

1. Confirm the source Pod and container are running.
2. Confirm the actual K3s/containerd/runc/CRIU versions used by each node.
3. Ensure the destination K3s cluster, `PodRestore` CRD/controller, and CRI proxy are ready.
4. Request a fresh checkpoint from the source kubelet API.
5. Copy the archive from the source K3s container to the source host.
6. Transfer the archive to the destination with SSH/SCP and verify its SHA-256 checksum.
7. Install the archive in `/var/lib/kubelet/checkpoints` on the destination.
8. Create a `PodRestore` resource and wait for `Ready=True` with reason `Restored`.
9. Verify the application responds inside the restored Pod.

## 19.3 Step 1 — Confirm the Source K3s and Test Pod

In this setup, source K3s runs inside the Podman container `k3s-server`. Run commands against that cluster through `/bin/kubectl` inside the container:

```bash
sudo podman ps --filter name=k3s-server
sudo podman exec k3s-server /bin/k3s --version
sudo podman exec k3s-server /bin/kubectl get nodes -o wide
sudo podman exec k3s-server /bin/kubectl get pod checkpoint-demo -n default -o wide
```

The test Pod and the container to checkpoint are both named `checkpoint-demo` in namespace `default`. The Pod must be `Running` and its container must be ready before checkpointing.

The runtime tools inside this source container were at these paths:

```bash
sudo podman exec k3s-server /bin/ctr --address /run/k3s/containerd/containerd.sock version
sudo podman exec k3s-server /bin/runc --version
sudo podman exec k3s-server /usr/local/sbin/criu --version
```

`/bin/kubectl` is a symlink to the K3s binary in this image. The command `podman exec k3s-server /bin/k3s kubectl ...` failed in this setup; use `/bin/kubectl` instead.

## 19.4 Step 2 — Confirm the Destination Is Ready

Run on the destination VM:

```bash
sudo kubectl get nodes -o wide
sudo kubectl get crd podrestores.criu.org
sudo kubectl get pods -n checkpoint-restore-operator
sudo systemctl is-active cri-restore-proxy.socket
curl -fsS --max-time 3 http://127.0.0.1:18080/readyz
```

Required checks:

- The destination node is `Ready`.
- `podrestores.criu.org` exists.
- The operator controller Pod is `Running` and ready.
- The CRI proxy is installed and healthy; `/readyz` returns `ok`.
- The proxy upstream points to the destination's actual K3s containerd socket. In this setup that socket was `/run/k3s/containerd/containerd.sock`, not the generic `/run/containerd/containerd.sock` path.
- Kubelet is configured to use the CRI proxy socket as its container runtime and image service endpoint, as required by the operator's installation instructions.

If the operator/CRD is missing after a fresh K3s install, deploy it from the [checkpoint-restore-operator repository](https://github.com/checkpoint-restore/checkpoint-restore-operator), if it has not already been cloned:

```bash
git clone https://github.com/checkpoint-restore/checkpoint-restore-operator.git
cd checkpoint-restore-operator
sudo kubectl apply --server-side -k config/default
```

Use server-side apply; the `PodRestore` CRD includes a large Pod template and may exceed the client-side apply annotation limit. The CRI proxy is a separate host service. Follow the repository's [restore guide](https://github.com/checkpoint-restore/checkpoint-restore-operator/blob/main/docs/restore.md) to build/install it. In this K3s setup, configure its upstream socket to `/run/k3s/containerd/containerd.sock` and confirm the K3s kubelet uses the proxy socket.

## 19.5 Step 3 — Create a Fresh Checkpoint on the Source

The kubelet checkpoint API endpoint is:

```text
POST https://127.0.0.1:10250/checkpoint/<namespace>/<pod>/<container>
```

In this setup, `curl` was not installed inside the `k3s-server` image. The available BusyBox `wget` supported `--post-data`, but did not expose the client-certificate/private-key and custom-method options needed for this request. The working solution was to use the source host's `curl` inside the Podman's network namespace and temporarily copy the K3s client certificate/key from the container.

Run the following on the **source host** (`Thalla`). It extracts the returned archive path instead of assuming that the timestamped filename will stay the same:

```bash
set -eu

SOURCE_CONTAINER="k3s-server"
NAMESPACE="default"
POD="checkpoint-demo"
CONTAINER="checkpoint-demo"

CPID=$(sudo podman inspect --format '{{.State.Pid}}' "$SOURCE_CONTAINER")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sudo podman cp \
  "$SOURCE_CONTAINER:/var/lib/rancher/k3s/server/tls/client-admin.crt" \
  "$TMP/client-admin.crt"
sudo podman cp \
  "$SOURCE_CONTAINER:/var/lib/rancher/k3s/server/tls/client-admin.key" \
  "$TMP/client-admin.key"

HTTP_CODE=$(sudo nsenter -t "$CPID" -n curl \
  --silent --show-error --insecure \
  --cert "$TMP/client-admin.crt" \
  --key "$TMP/client-admin.key" \
  --request POST \
  --output "$TMP/response.json" \
  --write-out '%{http_code}' \
  "https://127.0.0.1:10250/checkpoint/$NAMESPACE/$POD/$CONTAINER?timeout=120")

cat "$TMP/response.json"
printf '\nHTTP status: %s\n' "$HTTP_CODE"

if [ "$HTTP_CODE" != "200" ]; then
  echo "Checkpoint request failed; do not transfer an old archive." >&2
  exit 1
fi

CHECKPOINT_PATH=$(python3 -c \
  'import json,sys; print(json.load(open(sys.argv[1]))["items"][0])' \
  "$TMP/response.json")
ARCHIVE=$(basename "$CHECKPOINT_PATH")

sudo podman cp "$SOURCE_CONTAINER:$CHECKPOINT_PATH" "/tmp/$ARCHIVE"
sudo chown "$(id -un):$(id -gn)" "/tmp/$ARCHIVE"
chmod 600 "/tmp/$ARCHIVE"

sha256sum "/tmp/$ARCHIVE"
printf '\nCheckpoint archive: %s\n' "$ARCHIVE"
```

A successful checkpoint request returns HTTP `200` and a JSON result containing the new `.tar` archive path. This run produced:

```text
checkpoint-checkpoint-demo_default-checkpoint-demo-2026-10-21T18:44:52Z.tar
```

That is an example from the completed run; a later checkpoint will have a different timestamp. Keep the archive name returned by the API and do not guess it. The checkpoint contains process memory and can contain sensitive data, so keep access restricted and never commit the archive, client certificate, or private key to Git. In a production environment, validate the kubelet server certificate against the correct CA instead of using `--insecure`; that option was used for this controlled lab request.

## 19.6 Step 4 — Transfer the Checkpoint Securely

Use the normal source login account for SCP, not `sudo scp`: the SSH key belongs to the normal user, and `sudo scp` may look for root's SSH keys instead.

If a dedicated key is not already set up on the source host:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/checkpoint-transfer -C checkpoint-transfer
cat ~/.ssh/checkpoint-transfer.pub
```

Add the displayed **public key** as one line in the destination account's `~/.ssh/authorized_keys`. On the destination, ensure permissions are correct:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Then test the connection from source to destination:

```bash
ssh -i ~/.ssh/checkpoint-transfer -o IdentitiesOnly=yes \
  <destination-user>@<destination-ip> 'hostname; id'
```

On the source, set `ARCHIVE` to the exact filename printed by Step 3, then create and transfer a checksum alongside the archive:

```bash
ARCHIVE="<exact-checkpoint-filename-from-step-3>"
sha256sum "/tmp/$ARCHIVE" | awk '{print $1}' > "/tmp/$ARCHIVE.sha256"

scp -i ~/.ssh/checkpoint-transfer -o IdentitiesOnly=yes \
  "/tmp/$ARCHIVE" "/tmp/$ARCHIVE.sha256" \
  <destination-user>@<destination-ip>:/tmp/
```

In the tested lab, `<destination-user>` was `garv` and `<destination-ip>` was `192.168.122.118`. Replace those values if the destination address or username changes.

## 19.7 Step 5 — Verify and Install the Archive on the Destination

On the destination, set `ARCHIVE` to the same exact filename used above:

```bash
ARCHIVE="<exact-checkpoint-filename-from-step-3>"
EXPECTED=$(cat "/tmp/$ARCHIVE.sha256")
ACTUAL=$(sha256sum "/tmp/$ARCHIVE" | awk '{print $1}')

printf 'Expected: %s\nActual:   %s\n' "$EXPECTED" "$ACTUAL"
test "$ACTUAL" = "$EXPECTED" || {
  echo "Checksum mismatch; do not restore this archive." >&2
  exit 1
}

echo "Checkpoint checksum verified."

sudo mkdir -p /var/lib/kubelet/checkpoints
sudo install -o root -g root -m 600 \
  "/tmp/$ARCHIVE" "/var/lib/kubelet/checkpoints/$ARCHIVE"

sudo sha256sum "/var/lib/kubelet/checkpoints/$ARCHIVE"
```

The installed archive must be in the checkpoint directory on the **target node**. Use the absolute path and exact filename; do not type a shortened or old timestamped filename. Keep the archive in place while the `PodRestore` is active.

## 19.8 Step 6 — Apply a PodRestore Resource

On the destination, set `ARCHIVE` to the exact transferred filename. The command below uses a unique resource name so repeated test runs do not collide with an existing immutable `PodRestore`:

```bash
ARCHIVE="<exact-checkpoint-filename-from-step-3>"
RESTORE_NAME="checkpoint-demo-restored-$(date +%s)"

cat > "/tmp/${RESTORE_NAME}.yaml" <<EOF
apiVersion: criu.org/v1
kind: PodRestore
metadata:
  name: ${RESTORE_NAME}
  namespace: default
spec:
  targetNode: checkpoint-restore-dest
  checkpoints:
    - container: checkpoint-demo
      path: /var/lib/kubelet/checkpoints/${ARCHIVE}
  template:
    spec:
      containers:
        - name: checkpoint-demo
          image: docker.io/library/nginx:alpine
EOF

sudo kubectl apply --server-side -f "/tmp/${RESTORE_NAME}.yaml"
```

The names must line up: the checkpoint list's `container` value must be the source container name `checkpoint-demo`, and the template container name should match it. `targetNode` must equal the destination Kubernetes Node name, which was `checkpoint-restore-dest` in this run.

The operator's `PodRestore` template and target/checkpoint fields are immutable. If a manifest was applied with the wrong path, node or template, create a new `PodRestore` resource with a new name instead of trying to patch those fields.

## 19.9 Step 7 — Wait for Restore and Verify the Application

Use the `RESTORE_NAME` set in the same destination shell:

```bash
sudo kubectl wait --for=condition=Ready \
  "podrestore/$RESTORE_NAME" -n default --timeout=180s

sudo kubectl get podrestore "$RESTORE_NAME" -n default \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{" message="}{.message}{"\n"}{end}'

POD_NAME=$(sudo kubectl get podrestore "$RESTORE_NAME" -n default \
  -o jsonpath='{.status.podName}')

sudo kubectl wait --for=condition=Ready "pod/$POD_NAME" \
  -n default --timeout=180s
sudo kubectl get pod "$POD_NAME" -n default -o wide
sudo kubectl exec -n default "$POD_NAME" -- wget -qO- http://127.0.0.1/ | head -5
```

The tested final restore produced:

```text
Ready=True reason=Restored message=Restored Pod is running
```

The in-container HTTP request returned the NGINX welcome page. These checks confirmed that the restored Pod was `Running`, `Ready=True`, had zero restarts, and served HTTP. Since this test used the stock NGINX image, it verifies a successful runtime restore and application response; a separate stateful test program would be needed to demonstrate a custom in-memory counter or other application-specific state continuation.

# 20. Additional Problems Encountered and Solutions in the K3s Workflow

This section supplements (rather than replaces) the direct-process and native Podman troubleshooting above.

## 20.1 `StartError: criu failed: type RESTORE errno 0`

**Observed error:**

```text
failed to restore containerd task: failed to create shim task:
OCI runtime restore failed: criu failed: type RESTORE errno 0
```

**What we found:** the first destination ran K3s `v1.37.1+k3s1`, containerd `v2.3.4-k3s1`, and runc `1.4.2`. The source K3s actually ran inside Podman and reported K3s `v1.34.1+k3s1`, containerd `v2.1.4-k3s2`, and runc `1.3.1`. Both used CRIU `4.2.1`.

**Solution used for the successful run:** use a destination test environment with K3s `v1.34.1+k3s1`, containerd `v2.1.4-k3s2`, runc `1.3.1`, and CRIU `4.2.1`; reinstall the restore operator/CRD and make sure the CRI proxy is healthy; create a **fresh** checkpoint; transfer it with checksum verification; and restore that checkpoint.

**Important limitation:** multiple variables changed between the failed and successful attempts, including destination setup and checkpoint freshness. The successful run proves this final combination worked, but it does not isolate runtime-version mismatch as the single root cause.

## 20.2 Host K3s and Podman K3s Tried to Use the Same Port

**Observed error:**

```text
failed to listen on 127.0.0.1:6444: bind: address already in use
```

The source already had a Podman container named `k3s-server` running and publishing `127.0.0.1:6444->6443/tcp`. Starting the separate host `k3s.service` caused it to collide with the container's listener.

**Solution:** verify who owns the port before stopping anything:

```bash
sudo ss -ltnp '( sport = :6444 )'
sudo podman ps --filter name=k3s-server
sudo systemctl status k3s --no-pager -l
```

For this topology, stop the conflicting host service only if the source cluster to preserve is the Podman-managed `k3s-server`:

```bash
sudo systemctl stop k3s
```

Keep the Podman `k3s-server` container running. Do not blindly kill its `k3s server` process or stop the container; it is the actual source cluster.

## 20.3 Host K3s Version Did Not Match the Source Cluster Version

**Problem:** running `sudo k3s --version` on `Thalla` reported the host-installed binary `v1.36.5+k3s1`, while the checkpoint source cluster inside Podman reported `v1.34.1+k3s1`.

**Solution:** inspect the actual cluster and runtime from inside the container:

```bash
sudo podman exec k3s-server /bin/k3s --version
sudo podman exec k3s-server /bin/ctr --address /run/k3s/containerd/containerd.sock version
sudo podman exec k3s-server /bin/runc --version
sudo podman exec k3s-server /usr/local/sbin/criu --version
```

Do not infer the source runtime versions solely from binaries installed on the host. Also avoid using a mutable `latest` image tag for a reproducible deployment.

## 20.4 `kubectl` Was Invoked Through the Wrong Command

**Observed error:**

```text
error: unknown command "kubectl" for "kubectl"
```

**Solution:** in the tested K3s container, `/bin/kubectl` was a symlink to `/bin/k3s`. Use:

```bash
sudo podman exec k3s-server /bin/kubectl get nodes -o wide
sudo podman exec k3s-server /bin/kubectl get pod checkpoint-demo -n default -o wide
```

## 20.5 `Permission denied` Reading `/proc/<PID>/environ`

**Cause:** shell input redirection such as `sudo tr ... < /proc/$PID/environ` is opened by the current shell before `sudo` runs.

**Solution:** let a privileged command open the file:

```bash
sudo cat "/proc/$PID/environ" | tr '\0' '\n' | grep '^PATH='
```

This was a diagnostic-command permission issue, not evidence that `tar` was missing.

## 20.6 `tar` and `runc` Were Not Found by a Plain Command

The destination had a K3s-bundled `tar` symlink to `busybox`, and `runc` was bundled inside K3s even though the shell could not find a system-wide `runc` command.

**Solution:** inspect the bundled executables before installing replacements:

```bash
ls -l /var/lib/rancher/k3s/data/current/bin/tar
sudo /var/lib/rancher/k3s/data/current/bin/runc --version
```

The presence of these binaries did not explain the original restore failure. Do not replace symlinks or modify `PATH` without evidence that the executable itself is the problem.

## 20.7 `curl` Was Missing Inside the Source K3s Container

**Observed conditions:** `curl` was not installed in `k3s-server`; `/bin/wget` was BusyBox Wget and did not provide the needed client certificate/private key options. The kubelet checkpoint API required a client-authenticated HTTPS POST.

**Solution:** use the source host's `curl`, enter the Podman's network namespace with `nsenter -n`, and temporarily copy the source K3s client certificate/key out of the container. See Section 19.5 for the complete tested command. Keep the client key private and remove temporary copies after the request.

## 20.8 SCP Failed with `Permission denied (publickey)`

**Cause:** the destination did not accept a public key for the source user's SSH connection. Using `sudo scp` can also cause SSH to look for a key belonging to root rather than the normal user.

**Solution:** generate a dedicated key, add its public key to the destination user's `~/.ssh/authorized_keys`, ensure `~/.ssh` is mode `700` and `authorized_keys` is mode `600`, test SSH, and use the normal source account:

```bash
ssh -i ~/.ssh/checkpoint-transfer -o IdentitiesOnly=yes \
  <destination-user>@<destination-ip> 'hostname; id'

scp -i ~/.ssh/checkpoint-transfer -o IdentitiesOnly=yes \
  /tmp/<checkpoint-file>.tar \
  <destination-user>@<destination-ip>:/tmp/
```

Only the public key goes into `authorized_keys`; never copy the private key to the destination.

## 20.9 Old or Wrong Checkpoint Filename / Archive Path

Each checkpoint filename contains a timestamp. An earlier test archive from October 19 failed, so the successful test used a **fresh** archive created on October 21. Do not reuse a hard-coded old filename for later runs.

**Solution:** use the file path returned by the checkpoint API, derive the basename from that response, transfer that exact archive, verify its SHA-256, and place it under the destination's `/var/lib/kubelet/checkpoints/`. The `PodRestore.spec.checkpoints[].path` must be the absolute destination path to the exact filename.

## 20.10 `podrestores.criu.org` Was `NotFound` After Destination Reinstallation

A fresh K3s install does not automatically contain project-specific CRDs or the restore controller.

**Solution:** redeploy the operator, using server-side apply, and verify the CRD and controller Pod:

```bash
sudo kubectl apply --server-side -k config/default
sudo kubectl get crd podrestores.criu.org
sudo kubectl get pods -n checkpoint-restore-operator
```

Also verify the CRI proxy service/socket and its readiness endpoint. A healthy `/readyz` alone is not a substitute for checking that the CRD and controller exist.

## 20.11 `ContainerCreating` Did Not Immediately Mean Restore Failed

The final restored Pod initially displayed `ContainerCreating` while the destination downloaded `nginx:alpine`. It later reached `Running` and `Ready=True` without restarts.

**Solution:** inspect the events and wait for the restore condition before treating it as a failure:

```bash
sudo kubectl describe pod <restored-pod-name> -n default
sudo kubectl get podrestore <podrestore-name> -n default -o yaml
sudo kubectl get events -n default --sort-by=.lastTimestamp | tail -20
```

If it fails, inspect the containerd log and operator logs. The original `dump.log` found under the restore directory was the checkpoint's dump log and ended with `Dumping finished successfully`; it was not a detailed restore log. Searching for `restore.log` did not find a separate CRIU restore log in the tested locations.

## 20.12 `criu check --extra` Reported Missing Optional Features

Both machines passed the basic `sudo criu check`, while `sudo criu check --extra` warned that nftables-based locking required libnftables and set-concatenation support and that some kernel features were missing.

**Solution:** record the warning, but do not treat it as the root cause without matching it to an actual failed CRIU operation. The same warning appeared on both systems and the final restore succeeded. Do not disable AppArmor, modify nftables, or change the kernel merely because this generic warning appears.

## 20.13 A Shell Error Appeared After HTTP 200

One command sequence printed `bash: _WARP_GENERATOR_COMMAND: unbound variable` after the checkpoint API had already returned HTTP `200` and the archive was visible on disk.

**Resolution:** verify the HTTP status, response JSON, archive existence, size, and checksum before retrying. In that run, the checkpoint had been created successfully; the trailing shell/wrapper error was not the CRIU restore error.

# 21. Final Known-Good K3s Migration Checklist

Before repeating the successful flow, confirm every item below:

- [ ] The source Pod is `Running` and the container name/namespace are correct.
- [ ] The source K3s instance is the intended one (inside `k3s-server` in this setup), and there is no conflicting host K3s service binding its published port.
- [ ] Source and destination versions are recorded from the **actual** K3s/containerd/runc instances, not from an unrelated host binary.
- [ ] Destination node is `Ready`.
- [ ] `podrestores.criu.org` exists and the operator controller is `Running`.
- [ ] CRI proxy service/socket are installed, use the correct K3s containerd socket, and `/readyz` returns `ok`.
- [ ] The checkpoint request returns HTTP `200` and returns a new timestamped archive path.
- [ ] The exact archive is copied out of the source container and transferred using the correct SSH identity.
- [ ] The source and destination SHA-256 hashes match.
- [ ] The archive is installed with root ownership and restricted permissions in `/var/lib/kubelet/checkpoints/` on the target node.
- [ ] The `PodRestore` points to the exact archive path, uses the correct target node and container name, and is applied with `--server-side`.
- [ ] Restore is verified by `Ready=True`, reason `Restored`, the Pod `Ready=True`, and a successful application-level request.

## 21.1 Successful Run Result

The final tested restore returned:

```text
CheckpointsPinned=True reason=Pinned
Ready=True reason=Restored message=Restored Pod is running
```

The restored Pod had `Status: Running`, `Ready: True`, `Restart Count: 0`, and an HTTP request to `http://127.0.0.1/` returned the NGINX welcome page.

The specific failed-to-successful sequence changed multiple variables (runtime versions, destination installation/controller setup, and checkpoint freshness). Therefore, this project records the above as the **known-good procedure**, but does not claim that any single one of those changes was conclusively the sole fix.

---

# References

* [CRIU](https://criu.org/)
* [CRIU GitHub](https://github.com/checkpoint-restore/criu)
* [CRIU Manual](https://man7.org/linux/man-pages/man8/criu.8.html)
* [Podman Checkpoint Documentation](https://docs.podman.io/en/stable/markdown/podman-container-checkpoint.1.html)
* [Podman Restore Documentation](https://docs.podman.io/en/stable/markdown/podman-container-restore.1.html)
* [CRIU Process Migration Video](https://www.youtube.com/watch?v=votyhJo0-Kc)
