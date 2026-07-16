# Distributed-Process-Migration-using-CRIU

# CRIU Process Migration using Ubuntu VMs (VMware Fusion)

This project demonstrates **process checkpoint and restore** using **CRIU (Checkpoint/Restore In Userspace)** across two Ubuntu virtual machines running on VMware Fusion.

---

# System Configuration

| Component | Details |
|-----------|---------|
| Host OS | macOS |
| Hypervisor | VMware Fusion |
| Guest OS | Ubuntu 24.04.4 LTS ARM64 |
| Architecture | ARM64 (Apple Silicon) |
| Source VM | VM1 (garv) |
| Destination VM | VM2 (garv) |
| Programming Language | Python |
| Migration Tool | CRIU |

---

# Project Structure

```
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

# Installing CRIU

Update package lists

```bash
sudo apt update
```

Install required packages

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

Clone CRIU

```bash
git clone https://github.com/checkpoint-restore/criu.git
cd criu
```

Compile

```bash
make -j$(nproc)
```

Install

```bash
sudo make install DOCBOOK=no
```

Verify

```bash
criu --version
```

---

# Installing SSH

Destination VM

```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

Verify

```bash
sudo systemctl status ssh
```

Find IP

```bash
hostname -I
```

Connect from source VM

```bash
ssh username@VM2_IP
```

---

# Running the Process

```bash
python3 number.py
```

Find PID

```bash
pgrep -af number.py
```

Example

```
6075 python3 number.py
```

---

# Checkpoint

```bash
mkdir -p dump/demo

sudo criu dump \
-t 6075 \
-D dump/demo \
--shell-job
```

---

# Transfer Checkpoint

```bash
scp -r dump \
garv@VM2_IP:/home/garv/Project/
```

---

# Restore

```bash
sudo criu restore \
-D dump/demo \
--shell-job
```

---

# Problems Encountered and Solutions

---

## 1. apt could not locate CRIU

### Error

```
Package 'criu' has no installation candidate
```

### Cause

Ubuntu ARM repositories did not provide CRIU package.

### Solution

Compiled CRIU from source.

---

## 2. apt repository timeout

### Error

```
Connection failed
Could not connect to ports.ubuntu.com
```

### Cause

Mirror connection issue.

### Solution

Forced IPv4.

```bash
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4
```

---

## 3. Package Lock

### Error

```
Could not get lock
```

### Cause

Another apt process running.

### Solution

```bash
ps aux | grep apt
sudo kill -9 PID
```

---

## 4. Missing Packages

### Error

```
Compilation aborted.
Can not find required libraries.
```

### Solution

Installed

```
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

## 5. make install failed

### Error

```
asciidoc: not found
```

### Cause

Documentation generation.

### Solution

Skipped documentation.

```bash
sudo make install DOCBOOK=no
```

---

## 6. Disk Full

### Error

```
No space left on device
```

### Cause

Installing documentation packages pulled huge TeX dependencies.

### Solution

Removed unnecessary packages.

Avoid installing

```
asciidoc
xmlto
dblatex
texlive*
docbook*
```

---

## 7. UTM Live ISO Reset

### Problem

Ubuntu reset every reboot.

### Cause

Still booting from ISO.

### Solution

Removed installer ISO after Ubuntu installation.

Eventually switched to VMware Fusion.

---

## 8. SSH Not Running

### Error

```
Active: inactive (dead)
```

### Solution

```bash
sudo systemctl enable --now ssh
```

---

## 9. pidof did not find Python script

### Error

```bash
pidof number.py
```

returned nothing.

### Solution

Use

```bash
pgrep -af number.py
```

---

## 10. CRIU refused terminal process

### Error

```
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

```
Can't open cwd
```

```
No such file or directory
```

### Cause

Different usernames.

VM1

```
/home/garv/Project
```

VM2

```
/home/vm2/Project
```

### Solution

Use identical directory structure.

Recommended

```
/home/garv/Project
```

on both VMs.

---

## 12. File Permission Mismatch

### Error

```
bad mode 040755
expect 040775
```

### Solution

Either

```bash
chmod 775 /home/garv/Project
```

or

```bash
sudo criu restore \
-D dump/demo \
--shell-job \
--skip-file-rwx-check
```

---

## 13. libnftables Warning

### Warning

```
CRIU was built without libnftables support
```

### Solution

Non-blocking warning.

Can be ignored.

---

## 14. cgroup Warning

### Error

```
cg: cgroupd: recv req error
```

### Cause

Restore environment mismatch.

### Solution

Ensure

- Same Ubuntu version
- Same CRIU version
- Same directory structure
- Same user
- Same kernel configuration

---

## 15. VMware Networking

Configured both VMs on the same virtual network.

Verified connectivity

```bash
ping VM2_IP
```

Verified SSH

```bash
ssh garv@VM2_IP
```

---

# Useful Commands

Current IP

```bash
hostname -I
```

Running SSH

```bash
sudo systemctl status ssh
```

Find Process

```bash
pgrep -af number.py
```

Checkpoint

```bash
sudo criu dump \
-t PID \
-D dump/demo \
--shell-job
```

Restore

```bash
sudo criu restore \
-D dump/demo \
--shell-job
```

Transfer

```bash
scp -r dump \
garv@VM2_IP:/home/garv/Project/
```

---

# Lessons Learned

- CRIU is extremely sensitive to filesystem paths.
- Source and destination systems should be nearly identical.
- Using the same username on both systems avoids many restore issues.
- Documentation packages are not required for CRIU.
- SSH simplifies transferring checkpoint images.
- VMware Fusion provided a more reliable environment than UTM for this project.

---

# References

- https://criu.org/
- https://github.com/checkpoint-restore/criu
- https://man7.org/linux/man-pages/man8/criu.8.html

---
