# Test Reference: What Each Test Proves
## Quick-scan before you run

---

## CATEGORY 1: FILESYSTEM ISOLATION (8 tests)
*Can the sandbox see or modify files it shouldn't?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 1.1 Host /root visibility | Can agent code read admin files? | PASS with --contain | PASS by default |
| 1.2 Sensitive file read | Can it read secrets outside mount? | PASS with --contain | PASS by default |
| 1.3 /etc/shadow read | Password hash exposure? | PASS (both) | PASS (both) |
| 1.4 Write outside volume | Can it modify host filesystem? | PASS (writable-tmpfs) | PASS (--read-only) |
| 1.5 Other users' files | Multi-tenant data leak? | PASS with --contain | PASS by default |
| 1.6 Default mode FS leak | **KEY TEST**: What happens if admin forgets --contain? | Likely FAIL | PASS always |
| 1.7 Bind mount escape | Can it re-mount to escape jail? | PASS (both) | PASS (both) |
| 1.8 /proc/kallsyms | Kernel symbol exposure (exploitation aid) | May FAIL | PASS (masked) |

**Key finding**: Apptainer's isolation depends on correct flags. Podman is isolated by default.

---

## CATEGORY 2: PROCESS ISOLATION (4 tests)
*Can the sandbox see or affect host processes?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 2.1 Host process visibility | Information leak about what's running | Likely FAIL (shared PID ns) | PASS (own PID ns) |
| 2.2 Signal host PID 1 | Can it kill host init? | PARTIAL | PASS (PID 1 is container's) |
| 2.3 Fork bomb protection | Can runaway code exhaust PIDs? | FAIL (no native limit) | PASS (--pids-limit) |
| 2.4 /proc/self info leak | UID/PID namespace separation | PARTIAL | PASS |

**Key finding**: Podman's PID namespace is critical for sandboxing untrusted code.

---

## CATEGORY 3: NETWORK ISOLATION (5 tests)
*Can the sandbox make unauthorized network connections?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 3.1 Internet reachability | Can agent code exfiltrate data? | **FAIL** (host network) | PASS (--network=none) |
| 3.2 DNS resolution | Can it discover internal hosts? | **FAIL** (host DNS) | PASS (none = no DNS) |
| 3.3 Port visibility | Can it open services visible to host? | **FAIL** (shared ns) | PASS (isolated ns) |
| 3.4 Metadata endpoint | Cloud credential theft (SSRF)? | **FAIL** (host network) | PASS (none) |
| 3.5 Ease of config | How hard is network isolation? | No native option | Single flag |

**Key finding**: This is Apptainer's biggest weakness for sandboxing. No native network isolation.

---

## CATEGORY 4: USER & PRIVILEGE (5 tests)
*Can the sandbox escalate privileges?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 4.1 User identity | Who does code run as? | Calling user's UID | Root in userns (fake root) |
| 4.2 Root escalation | Can it become real root? | PASS (both) | PASS (userns root ≠ host root) |
| 4.3 Sysctl modification | Can it change kernel params? | PASS (both) | PASS (both) |
| 4.4 Linux capabilities | What kernel powers does it have? | Varies | Dropped by default |
| 4.5 Kernel modules | Can it load drivers? | PASS (both) | PASS (both) |

**Key finding**: Both are reasonably strong here. Podman's user namespace is slightly better.

---

## CATEGORY 5: RESOURCE LIMITS (4 tests)
*Can runaway code consume unbounded resources?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 5.1 Memory limit | OOM for memory hog? | **FAIL** (no native) | PASS (--memory) |
| 5.2 CPU limit | CPU starvation prevention? | **FAIL** (no native) | PASS (--cpus) |
| 5.3 Disk write limit | Fill-disk attack? | PARTIAL | PASS (tmpfs size) |
| 5.4 Runtime timeout | Infinite loop prevention? | PARTIAL (needs wrapper) | PASS (--timeout) |

**Key finding**: Apptainer has zero native resource limiting. On HPC this is OK (Slurm handles it), but for standalone sandbox use it's a gap.

---

## CATEGORY 6: ENVIRONMENT ISOLATION (4 tests)
*Do host secrets leak through environment variables or system info?*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 6.1 Env var leakage | API keys, passwords in env? | PASS with --cleanenv | PASS by default |
| 6.2 Hostname isolation | Host identity disclosure? | Likely FAIL | PASS (UTS ns) |
| 6.3 Kernel version | Shared kernel (expected) | N/A | N/A |
| 6.4 Forgot --cleanenv | **KEY TEST**: What if admin omits flag? | Likely FAIL (all env leaked) | PASS always |

**Key finding**: Apptainer's security is "opt-in" (must add flags). Podman's is "opt-out" (secure by default).

---

## CATEGORY 7: PERFORMANCE (6 tests)
*Speed, overhead, and resource efficiency*

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 7.1 Cold startup | How fast can a sandbox spin up? | ~100-300ms | ~500-1500ms |
| 7.2 Full sandbox startup | With all security flags | ~200-500ms | ~600-2000ms |
| 7.3 Python execution | Compute overhead inside? | Near zero | Near zero |
| 7.4 10 concurrent | Scale to many sandboxes? | Fast | Slower (more namespaces) |
| 7.5 Image size | Storage per image? | Smaller (compressed SIF) | Larger (layered OCI) |
| 7.6 Per-instance storage | Multi-tenant overhead? | Zero (shared SIF) | Overlay per container |

**Key finding**: Apptainer wins on performance and storage efficiency.

---

## CATEGORY 8: USABILITY & HPC (6 tests)

| Test | What It Proves | Apptainer Expected | Podman Expected |
|------|---------------|-------------------|----------------|
| 8.1 Slurm integration | Works with job schedulers? | Native | Needs config |
| 8.2 Image portability | Can you scp the image? | Single file | Needs registry |
| 8.3 OCI compatibility | Docker image support? | Converts to SIF | Native |
| 8.4 Multi-user deploy | Per-user admin overhead? | None | subuid/subgid + storage |
| 8.5 Parallel FS friendly | Works on Lustre/GPFS? | Excellent | Poor (metadata) |
| 8.6 Security config ease | All-in-one command? | Needs external tools | Single command |

**Key finding**: Apptainer is easier to deploy on HPC. Podman has better security ergonomics.

---

## THE BOTTOM LINE

### For Claude Code Sandboxes specifically:

```
                          Apptainer    Podman
                          ---------    ------
Filesystem isolation:     Good*        Excellent
Process isolation:        Weak         Excellent
Network isolation:        NONE native  Excellent
Resource limits:          NONE native  Excellent
Env isolation:            Good*        Excellent
Performance:              Excellent    Good
HPC integration:          Excellent    Fair
Admin overhead:           Low          Medium

* = requires correct flags; insecure if misconfigured
```

### Recommendation Matrix:

| Scenario | Use |
|----------|-----|
| HPC cluster, trusted researchers, Slurm manages resources | **Apptainer** |
| Untrusted/agent code, need strong isolation, standalone VM | **Podman** |
| HPC but need network isolation | **Podman** (or Apptainer + iptables wrapper) |
| Maximum security, maximum convenience | **Podman** |
| Already have Apptainer everywhere, can't install Podman | **Apptainer + hardening script** |

---

## Running the Tests

```bash
# On your Oblivus VM:
# 1. Upload and run setup
chmod +x setup-test-environment.sh
sudo ./setup-test-environment.sh

# 2. Run all tests
chmod +x run-all-tests.sh
sudo ./run-all-tests.sh

# 3. Results saved to test-results.csv
```
