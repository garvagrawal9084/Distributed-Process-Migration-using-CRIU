#!/usr/bin/env python3
"""Stateful counter for a Linux CRIU checkpoint/restore demonstration.

All paths are intentionally stable across the two VMs.
"""
import pathlib
import time

ROOT = pathlib.Path("/tmp/criu-process-demo")
STATE = ROOT / "counter.txt"
ROOT.mkdir(parents=True, exist_ok=True)
counter = int(STATE.read_text().strip()) if STATE.exists() else 0

while True:
    counter += 1
    STATE.write_text(str(counter) + "\n")
    time.sleep(1)
