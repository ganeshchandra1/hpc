# Apptainer vs Podman: Comprehensive Security & Performance Test Plan
## For Claude Code Sandbox Evaluation on HPC/Cloud VMs

---

## Overview

This guide provides **50+ tests** across 8 categories to evaluate Apptainer and Podman as sandbox environments for running Claude Code. Run all tests on the same Oblivus VM for a fair comparison.

## VM Requirements (Oblivus)

- **OS**: Ubuntu 24.04
- **vCPUs**: 4+
- **RAM**: 8GB+
- **Storage**: 80GB
- **No GPU needed** for these tests

---

## Categories Tested

| # | Category | What It Proves |
|---|----------|---------------|
| 1 | Setup & Installation | Admin overhead to deploy |
| 2 | Filesystem Isolation | Can the sandbox see/modify host files? |
| 3 | Process Isolation | Can processes escape or see host PIDs? |
| 4 | Network Isolation | Can the sandbox make unauthorized connections? |
| 5 | Resource Limits | CPU, memory, PID, disk constraints |
| 6 | User & Privilege Escalation | Can the sandbox gain root or host UID? |
| 7 | Environment Isolation | Env vars, hostname, DNS leaks |
| 8 | Performance & Usability | Startup time, overhead, developer experience |

---

## Test Results Template

For each test, record:
- **PASS**: Isolation holds, expected behavior
- **FAIL**: Isolation broken, security risk
- **PARTIAL**: Works but requires extra configuration
- **N/A**: Not applicable to this runtime

---
