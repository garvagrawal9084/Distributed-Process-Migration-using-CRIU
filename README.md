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

# References

* [CRIU](https://criu.org/)
* [CRIU GitHub](https://github.com/checkpoint-restore/criu)
* [CRIU Manual](https://man7.org/linux/man-pages/man8/criu.8.html)
* [Podman Checkpoint Documentation](https://docs.podman.io/en/stable/markdown/podman-container-checkpoint.1.html)
* [Podman Restore Documentation](https://docs.podman.io/en/stable/markdown/podman-container-restore.1.html)
* [CRIU Process Migration Video](https://www.youtube.com/watch?v=votyhJo0-Kc)
