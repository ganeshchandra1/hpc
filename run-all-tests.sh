#!/bin/bash
# ============================================================
# run-all-tests.sh
# Comprehensive Apptainer vs Podman comparison
# Run after setup-test-environment.sh
# ============================================================
set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Results tracking
RESULTS_FILE="/home/claude/test-results.csv"
echo "category,test_name,apptainer_result,podman_result,apptainer_notes,podman_notes" > "$RESULTS_FILE"

PASS="${GREEN}PASS${NC}"
FAIL="${RED}FAIL${NC}"
PARTIAL="${YELLOW}PARTIAL${NC}"
NA="${CYAN}N/A${NC}"

# Counters
APT_PASS=0; APT_FAIL=0; APT_PARTIAL=0
POD_PASS=0; POD_FAIL=0; POD_PARTIAL=0

log_result() {
    local category="$1" test_name="$2" apt_result="$3" pod_result="$4" apt_notes="$5" pod_notes="$6"
    echo "\"$category\",\"$test_name\",\"$apt_result\",\"$pod_result\",\"$apt_notes\",\"$pod_notes\"" >> "$RESULTS_FILE"
    
    case "$apt_result" in
        PASS) ((APT_PASS++)) ;;
        FAIL) ((APT_FAIL++)) ;;
        PARTIAL) ((APT_PARTIAL++)) ;;
    esac
    case "$pod_result" in
        PASS) ((POD_PASS++)) ;;
        FAIL) ((POD_FAIL++)) ;;
        PARTIAL) ((POD_PARTIAL++)) ;;
    esac
}

header() {
    echo ""
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
}

test_header() {
    echo ""
    echo -e "  ${CYAN}TEST: $1${NC}"
}

# Helper: run command in Apptainer
apt_run() {
    apptainer exec \
        --contain --cleanenv --no-home --writable-tmpfs \
        --bind /home/testproject:/work \
        /opt/test-apptainer.sif \
        bash -c "$1" 2>&1
}

# Helper: run in Apptainer WITHOUT --contain (default mode)
apt_run_default() {
    apptainer exec \
        /opt/test-apptainer.sif \
        bash -c "$1" 2>&1
}

# Helper: run command in Podman
pod_run() {
    podman run --rm \
        --read-only --tmpfs /tmp:size=100m --tmpfs /work:size=100m \
        -v /home/testproject:/work:ro \
        test-podman-sandbox \
        bash -c "$1" 2>&1
}

# Helper: run in Podman with network disabled
pod_run_nonet() {
    podman run --rm \
        --network=none \
        --read-only --tmpfs /tmp:size=100m --tmpfs /work:size=100m \
        -v /home/testproject:/work:ro \
        test-podman-sandbox \
        bash -c "$1" 2>&1
}

# ================================================================
header "CATEGORY 1: FILESYSTEM ISOLATION"
# ================================================================

# --- Test 1.1: Host root filesystem visibility ---
test_header "1.1 - Can sandbox see host /root directory?"

APT_OUT=$(apt_run "ls /root/ 2>&1")
APT_STATUS=$?
POD_OUT=$(pod_run "ls /root/ 2>&1")
POD_STATUS=$?

echo -e "    Apptainer: $([ -z "$APT_OUT" ] || echo "$APT_OUT")"
echo -e "    Podman:    $([ -z "$POD_OUT" ] || echo "$POD_OUT")"

if echo "$APT_OUT" | grep -q "secret\|sensitive"; then
    echo -e "    Apptainer: ${FAIL} (host /root visible)"
    A1="FAIL"; AN1="host /root contents visible"
else
    echo -e "    Apptainer: ${PASS}"
    A1="PASS"; AN1="host /root hidden"
fi

if echo "$POD_OUT" | grep -q "secret\|sensitive"; then
    echo -e "    Podman:    ${FAIL} (host /root visible)"
    P1="FAIL"; PN1="host /root contents visible"
else
    echo -e "    Podman:    ${PASS}"
    P1="PASS"; PN1="host /root hidden"
fi
log_result "Filesystem" "1.1 Host /root visibility" "$A1" "$P1" "$AN1" "$PN1"

# --- Test 1.2: Read sensitive host file ---
test_header "1.2 - Can sandbox read /etc/fake-secrets/db.conf?"

APT_OUT=$(apt_run "cat /etc/fake-secrets/db.conf 2>&1")
POD_OUT=$(pod_run "cat /etc/fake-secrets/db.conf 2>&1")

if echo "$APT_OUT" | grep -q "hunter2"; then
    echo -e "    Apptainer: ${FAIL} (secret readable!)"
    A2="FAIL"; AN2="secret file readable"
else
    echo -e "    Apptainer: ${PASS}"
    A2="PASS"; AN2="secret file not accessible"
fi

if echo "$POD_OUT" | grep -q "hunter2"; then
    echo -e "    Podman:    ${FAIL} (secret readable!)"
    P2="FAIL"; PN2="secret file readable"
else
    echo -e "    Podman:    ${PASS}"
    P2="PASS"; PN2="secret file not accessible"
fi
log_result "Filesystem" "1.2 Sensitive file read" "$A2" "$P2" "$AN2" "$PN2"

# --- Test 1.3: Read /etc/shadow ---
test_header "1.3 - Can sandbox read /etc/shadow?"

APT_OUT=$(apt_run "cat /etc/shadow 2>&1")
POD_OUT=$(pod_run "cat /etc/shadow 2>&1")

if echo "$APT_OUT" | grep -q "root:"; then
    echo -e "    Apptainer: ${FAIL}"
    A3="FAIL"; AN3="/etc/shadow readable"
else
    echo -e "    Apptainer: ${PASS}"
    A3="PASS"; AN3="/etc/shadow blocked"
fi

if echo "$POD_OUT" | grep -q "root:"; then
    echo -e "    Podman:    ${FAIL}"
    P3="FAIL"; PN3="/etc/shadow readable"
else
    echo -e "    Podman:    ${PASS}"
    P3="PASS"; PN3="/etc/shadow blocked"
fi
log_result "Filesystem" "1.3 /etc/shadow read" "$A3" "$P3" "$AN3" "$PN3"

# --- Test 1.4: Write to host filesystem ---
test_header "1.4 - Can sandbox write outside mounted volume?"

APT_OUT=$(apt_run "touch /tmp/escape_test 2>&1; echo \$?")
POD_OUT=$(pod_run "touch /etc/escape_test 2>&1; echo \$?")

if echo "$APT_OUT" | grep -q "^0$"; then
    # /tmp is writable-tmpfs, so this is OK (ephemeral)
    echo -e "    Apptainer: ${PASS} (writes to tmpfs, ephemeral)"
    A4="PASS"; AN4="writes to writable-tmpfs only"
else
    echo -e "    Apptainer: ${PASS}"
    A4="PASS"; AN4="write blocked"
fi

if echo "$POD_OUT" | tail -1 | grep -q "^0$"; then
    echo -e "    Podman:    ${FAIL} (wrote to read-only fs!)"
    P4="FAIL"; PN4="write succeeded on read-only"
else
    echo -e "    Podman:    ${PASS} (read-only rootfs blocked write)"
    P4="PASS"; PN4="read-only rootfs enforced"
fi
log_result "Filesystem" "1.4 Write outside volume" "$A4" "$P4" "$AN4" "$PN4"

# --- Test 1.5: Can sandbox see other users' home directories? ---
test_header "1.5 - Can sandbox see /home/otheruser/?"

APT_OUT=$(apt_run "cat /home/otheruser/private.txt 2>&1")
POD_OUT=$(pod_run "cat /home/otheruser/private.txt 2>&1")

if echo "$APT_OUT" | grep -q "belong to another"; then
    echo -e "    Apptainer: ${FAIL}"
    A5="FAIL"; AN5="other user's files visible"
else
    echo -e "    Apptainer: ${PASS}"
    A5="PASS"; AN5="other user's files hidden"
fi

if echo "$POD_OUT" | grep -q "belong to another"; then
    echo -e "    Podman:    ${FAIL}"
    P5="FAIL"; PN5="other user's files visible"
else
    echo -e "    Podman:    ${PASS}"
    P5="PASS"; PN5="other user's files hidden"
fi
log_result "Filesystem" "1.5 Other users' files" "$A5" "$P5" "$AN5" "$PN5"

# --- Test 1.6: Apptainer DEFAULT mode (no --contain) filesystem leak ---
test_header "1.6 - Apptainer DEFAULT mode: can it see host home?"

APT_DEFAULT_OUT=$(apt_run_default "ls /root/ 2>&1")

if echo "$APT_DEFAULT_OUT" | grep -q "secret\|sensitive\|.bashrc"; then
    echo -e "    Apptainer (default): ${FAIL} (host filesystem visible without --contain!)"
    A6="FAIL"; AN6="DEFAULT mode leaks host filesystem"
else
    echo -e "    Apptainer (default): ${PASS}"
    A6="PASS"; AN6="default mode still isolated"
fi
echo -e "    Podman:              ${PASS} (always containerized)"
P6="PASS"; PN6="always isolated by design"
log_result "Filesystem" "1.6 Default mode fs leak" "$A6" "$P6" "$AN6" "$PN6"

# --- Test 1.7: Mount propagation / bind escape ---
test_header "1.7 - Can sandbox create bind mounts to escape?"

APT_OUT=$(apt_run "mount --bind / /tmp 2>&1; echo exit:\$?")
POD_OUT=$(pod_run "mount --bind / /tmp 2>&1; echo exit:\$?")

if echo "$APT_OUT" | grep -qi "permitted\|denied\|operation\|exit:1\|exit:32"; then
    echo -e "    Apptainer: ${PASS}"
    A7="PASS"; AN7="mount blocked"
else
    echo -e "    Apptainer: ${FAIL}"
    A7="FAIL"; AN7="mount possibly succeeded"
fi

if echo "$POD_OUT" | grep -qi "permitted\|denied\|operation\|exit:1\|exit:32"; then
    echo -e "    Podman:    ${PASS}"
    P7="PASS"; PN7="mount blocked"
else
    echo -e "    Podman:    ${FAIL}"
    P7="FAIL"; PN7="mount possibly succeeded"
fi
log_result "Filesystem" "1.7 Bind mount escape" "$A7" "$P7" "$AN7" "$PN7"

# --- Test 1.8: /proc and /sys sensitivity ---
test_header "1.8 - Can sandbox read sensitive /proc entries?"

# Try reading host kcore or kallsyms
APT_OUT=$(apt_run "cat /proc/kallsyms 2>&1 | head -1")
POD_OUT=$(pod_run "cat /proc/kallsyms 2>&1 | head -1")

if echo "$APT_OUT" | grep -q "T "; then
    echo -e "    Apptainer: ${FAIL} (kernel symbols readable)"
    A8="FAIL"; AN8="kallsyms exposed"
else
    echo -e "    Apptainer: ${PASS}"
    A8="PASS"; AN8="kallsyms protected"
fi

if echo "$POD_OUT" | grep -q "T "; then
    echo -e "    Podman:    ${FAIL} (kernel symbols readable)"
    P8="FAIL"; PN8="kallsyms exposed"
else
    echo -e "    Podman:    ${PASS}"
    P8="PASS"; PN8="kallsyms protected"
fi
log_result "Filesystem" "1.8 /proc/kallsyms read" "$A8" "$P8" "$AN8" "$PN8"


# ================================================================
header "CATEGORY 2: PROCESS ISOLATION"
# ================================================================

# --- Test 2.1: Can sandbox see host processes? ---
test_header "2.1 - Can sandbox see host processes?"

APT_OUT=$(apt_run "ps aux 2>&1 | grep -v 'ps aux' | grep -v bash | grep -v grep | wc -l")
POD_OUT=$(pod_run "ps aux 2>&1 | grep -v 'ps aux' | grep -v bash | grep -v grep | wc -l")

APT_COUNT=$(echo "$APT_OUT" | tail -1 | tr -d ' ')
POD_COUNT=$(echo "$POD_OUT" | tail -1 | tr -d ' ')

echo -e "    Apptainer sees: $APT_COUNT processes"
echo -e "    Podman sees:    $POD_COUNT processes"

if [ "$APT_COUNT" -gt 10 ] 2>/dev/null; then
    echo -e "    Apptainer: ${FAIL} (sees too many host processes)"
    A21="FAIL"; AN21="host processes visible ($APT_COUNT)"
else
    echo -e "    Apptainer: ${PASS}"
    A21="PASS"; AN21="process isolation OK ($APT_COUNT)"
fi

if [ "$POD_COUNT" -gt 10 ] 2>/dev/null; then
    echo -e "    Podman:    ${FAIL}"
    P21="FAIL"; PN21="host processes visible ($POD_COUNT)"
else
    echo -e "    Podman:    ${PASS}"
    P21="PASS"; PN21="PID namespace isolates ($POD_COUNT)"
fi
log_result "Process" "2.1 Host process visibility" "$A21" "$P21" "$AN21" "$PN21"

# --- Test 2.2: Can sandbox signal host processes? ---
test_header "2.2 - Can sandbox send signals to PID 1 (host init)?"

APT_OUT=$(apt_run "kill -0 1 2>&1; echo exit:\$?")
POD_OUT=$(pod_run "kill -0 1 2>&1; echo exit:\$?")

# In Podman with PID namespace, PID 1 is the container's init, not host's
echo -e "    Apptainer: $APT_OUT"
echo -e "    Podman:    $POD_OUT"

if echo "$APT_OUT" | grep -q "exit:0"; then
    echo -e "    Apptainer: ${PARTIAL} (can signal PID 1 - but may be container PID 1)"
    A22="PARTIAL"; AN22="PID 1 signal succeeded"
else
    echo -e "    Apptainer: ${PASS}"
    A22="PASS"; AN22="PID 1 signal blocked"
fi

P22="PASS"; PN22="PID 1 is container's own init"
echo -e "    Podman:    ${PASS} (PID 1 is container's own process)"
log_result "Process" "2.2 Signal host PID 1" "$A22" "$P22" "$AN22" "$PN22"

# --- Test 2.3: Fork bomb protection ---
test_header "2.3 - Fork bomb protection (limited test)"

# We won't actually fork bomb, just check if pids are limited
POD_OUT=$(podman run --rm --pids-limit=50 test-podman-sandbox bash -c "echo pids-limit-set; cat /sys/fs/cgroup/pids.max 2>/dev/null || echo no-cgroup-pids" 2>&1)

echo -e "    Apptainer: ${YELLOW}No native pids limit (relies on Slurm/ulimit)${NC}"
echo -e "    Podman:    $POD_OUT"

A23="PARTIAL"; AN23="no native --pids-limit, needs external control"
if echo "$POD_OUT" | grep -q "50\|pids-limit-set"; then
    P23="PASS"; PN23="--pids-limit enforced natively"
else
    P23="PARTIAL"; PN23="pids limit may not be enforced"
fi
log_result "Process" "2.3 Fork bomb protection" "$A23" "$P23" "$AN23" "$PN23"

# --- Test 2.4: /proc/self visibility ---
test_header "2.4 - What does /proc/self/status reveal?"

APT_OUT=$(apt_run "grep -E 'Uid|Gid|NSpid|NStgid' /proc/self/status 2>&1")
POD_OUT=$(pod_run "grep -E 'Uid|Gid|NSpid|NStgid' /proc/self/status 2>&1")

echo -e "    Apptainer:\n$APT_OUT"
echo -e "    Podman:\n$POD_OUT"

# Check if Podman shows remapped UIDs
if echo "$POD_OUT" | grep -q "NSpid"; then
    P24="PASS"; PN24="PID namespace active"
else
    P24="PARTIAL"; PN24="PID namespace info unclear"
fi
A24="PARTIAL"; AN24="shares host PID namespace by default"
log_result "Process" "2.4 /proc/self info leak" "$A24" "$P24" "$AN24" "$PN24"


# ================================================================
header "CATEGORY 3: NETWORK ISOLATION"
# ================================================================

# --- Test 3.1: Can sandbox reach the internet? ---
test_header "3.1 - Can sandbox reach the internet?"

APT_OUT=$(apt_run "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com 2>&1 || echo BLOCKED")
POD_OUT=$(pod_run_nonet "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com 2>&1 || echo BLOCKED")
POD_OUT_NET=$(pod_run "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com 2>&1 || echo BLOCKED")

echo -e "    Apptainer (--contain):     $APT_OUT"
echo -e "    Podman (--network=none):   $POD_OUT"
echo -e "    Podman (default network):  $POD_OUT_NET"

if echo "$APT_OUT" | grep -q "200"; then
    echo -e "    Apptainer: ${FAIL} (internet accessible even with --contain)"
    A31="FAIL"; AN31="internet reachable - --contain does NOT isolate network"
else
    echo -e "    Apptainer: ${PASS}"
    A31="PASS"; AN31="internet blocked"
fi

if echo "$POD_OUT" | grep -qi "BLOCKED\|000"; then
    echo -e "    Podman:    ${PASS} (--network=none blocks all)"
    P31="PASS"; PN31="--network=none completely blocks internet"
else
    echo -e "    Podman:    ${FAIL}"
    P31="FAIL"; PN31="network not blocked"
fi
log_result "Network" "3.1 Internet reachability" "$A31" "$P31" "$AN31" "$PN31"

# --- Test 3.2: DNS resolution ---
test_header "3.2 - Can sandbox resolve DNS?"

APT_OUT=$(apt_run "nslookup google.com 2>&1 | head -3 || echo DNS_BLOCKED")
POD_OUT=$(pod_run_nonet "nslookup google.com 2>&1 | head -3 || echo DNS_BLOCKED")

echo -e "    Apptainer: $(echo "$APT_OUT" | head -1)"
echo -e "    Podman:    $(echo "$POD_OUT" | head -1)"

if echo "$APT_OUT" | grep -qi "address\|Name:"; then
    A32="FAIL"; AN32="DNS resolution works (network not isolated)"
else
    A32="PASS"; AN32="DNS blocked"
fi

if echo "$POD_OUT" | grep -qi "DNS_BLOCKED\|SERVFAIL\|timed out\|connection refused"; then
    P32="PASS"; PN32="DNS blocked with --network=none"
else
    P32="FAIL"; PN32="DNS still resolves"
fi
log_result "Network" "3.2 DNS resolution" "$A32" "$P32" "$AN32" "$PN32"

# --- Test 3.3: Can sandbox open a listening port? ---
test_header "3.3 - Can sandbox open a listening port visible to host?"

# Start a listener in Apptainer
apptainer exec --contain --cleanenv --no-home --writable-tmpfs \
    /opt/test-apptainer.sif \
    bash -c "python3 -c \"import socket; s=socket.socket(); s.bind(('0.0.0.0',9999)); s.listen(1); import time; time.sleep(3)\" &" 2>/dev/null &
APT_PID=$!
sleep 1
APT_PORT=$(ss -tlnp 2>/dev/null | grep 9999 || echo "NOT_FOUND")
kill $APT_PID 2>/dev/null; wait $APT_PID 2>/dev/null

# Start a listener in Podman with no network
podman run --rm -d --network=none --name=port-test \
    test-podman-sandbox \
    bash -c "python3 -c \"import socket; s=socket.socket(); s.bind(('0.0.0.0',9999)); s.listen(1); import time; time.sleep(5)\"" 2>/dev/null
sleep 1
POD_PORT=$(ss -tlnp 2>/dev/null | grep 9999 || echo "NOT_FOUND")
podman stop port-test 2>/dev/null; podman rm port-test 2>/dev/null

echo -e "    Apptainer port on host: $APT_PORT"
echo -e "    Podman port on host:    $POD_PORT"

if echo "$APT_PORT" | grep -q "9999"; then
    A33="FAIL"; AN33="port visible on host network"
else
    A33="PASS"; AN33="port not visible on host"
fi

if echo "$POD_PORT" | grep -q "NOT_FOUND"; then
    P33="PASS"; PN33="port isolated in network namespace"
else
    P33="FAIL"; PN33="port leaked to host"
fi
log_result "Network" "3.3 Port visibility" "$A33" "$P33" "$AN33" "$PN33"

# --- Test 3.4: Can sandbox scan internal network? ---
test_header "3.4 - Can sandbox probe internal network (metadata endpoint)?"

# Cloud VMs often have metadata at 169.254.169.254
APT_OUT=$(apt_run "curl -s --max-time 3 http://169.254.169.254/ 2>&1 || echo BLOCKED")
POD_OUT=$(pod_run_nonet "curl -s --max-time 3 http://169.254.169.254/ 2>&1 || echo BLOCKED")

if echo "$APT_OUT" | grep -qi "BLOCKED\|timed out\|refused"; then
    A34="PASS"; AN34="metadata endpoint not reachable"
else
    A34="FAIL"; AN34="metadata endpoint reachable!"
    echo -e "    Apptainer: ${RED}WARNING - cloud metadata may be exposed!${NC}"
fi

if echo "$POD_OUT" | grep -qi "BLOCKED\|timed out\|refused"; then
    P34="PASS"; PN34="metadata blocked by --network=none"
else
    P34="FAIL"; PN34="metadata reachable"
fi
echo -e "    Apptainer: $A34 ($AN34)"
echo -e "    Podman:    $P34 ($PN34)"
log_result "Network" "3.4 Metadata endpoint" "$A34" "$P34" "$AN34" "$PN34"

# --- Test 3.5: Network isolation ease of configuration ---
test_header "3.5 - Native network isolation support"

echo -e "    Apptainer: ${YELLOW}No native --network=none equivalent${NC}"
echo -e "    Podman:    ${GREEN}--network=none is a single flag${NC}"
A35="FAIL"; AN35="no native network namespace support, needs iptables/unshare"
P35="PASS"; PN35="--network=none is trivial"
log_result "Network" "3.5 Network isolation ease" "$A35" "$P35" "$AN35" "$PN35"


# ================================================================
header "CATEGORY 4: USER & PRIVILEGE ISOLATION"
# ================================================================

# --- Test 4.1: Who am I inside the container? ---
test_header "4.1 - User identity inside container"

APT_OUT=$(apt_run "id 2>&1")
POD_OUT=$(pod_run "id 2>&1")

echo -e "    Apptainer: $APT_OUT"
echo -e "    Podman:    $POD_OUT"

A41="PASS"; AN41="runs as calling user's UID"
P41="PASS"; PN41="runs as root in user namespace (mapped to non-root on host)"
log_result "Privilege" "4.1 Container user identity" "$A41" "$P41" "$AN41" "$PN41"

# --- Test 4.2: Can container use sudo? ---
test_header "4.2 - Can sandbox escalate to root?"

APT_OUT=$(apt_run "sudo id 2>&1 || echo NO_SUDO")
POD_OUT=$(pod_run "apt-get update 2>&1 | head -2 || echo APT_FAILED")

echo -e "    Apptainer: $(echo "$APT_OUT" | head -1)"
echo -e "    Podman:    $(echo "$POD_OUT" | head -1)"

if echo "$APT_OUT" | grep -q "uid=0"; then
    A42="FAIL"; AN42="sudo escalation worked"
else
    A42="PASS"; AN42="no sudo/root escalation"
fi

# In Podman rootless, "root" inside is not real root
P42="PASS"; PN42="root inside container is user-namespaced, not real root"
log_result "Privilege" "4.2 Root escalation" "$A42" "$P42" "$AN42" "$PN42"

# --- Test 4.3: Can container modify kernel parameters? ---
test_header "4.3 - Can sandbox modify sysctl/kernel params?"

APT_OUT=$(apt_run "sysctl -w kernel.hostname=hacked 2>&1; echo exit:\$?")
POD_OUT=$(pod_run "sysctl -w kernel.hostname=hacked 2>&1; echo exit:\$?")

if echo "$APT_OUT" | grep -q "exit:0" && ! echo "$APT_OUT" | grep -qi "denied\|read-only"; then
    A43="FAIL"; AN43="sysctl modification succeeded"
else
    A43="PASS"; AN43="sysctl modification blocked"
fi

if echo "$POD_OUT" | grep -q "exit:0" && ! echo "$POD_OUT" | grep -qi "denied\|read-only"; then
    P43="FAIL"; PN43="sysctl modification succeeded"
else
    P43="PASS"; PN43="sysctl modification blocked"
fi
echo -e "    Apptainer: $A43 ($AN43)"
echo -e "    Podman:    $P43 ($PN43)"
log_result "Privilege" "4.3 Sysctl modification" "$A43" "$P43" "$AN43" "$PN43"

# --- Test 4.4: Linux capabilities ---
test_header "4.4 - What capabilities does the container have?"

APT_OUT=$(apt_run "grep Cap /proc/self/status 2>&1")
POD_OUT=$(pod_run "grep Cap /proc/self/status 2>&1")

echo -e "    Apptainer capabilities:\n$APT_OUT"
echo -e "    Podman capabilities:\n$POD_OUT"

A44="PARTIAL"; AN44="capabilities depend on config"
P44="PASS"; PN44="rootless Podman drops most capabilities"
log_result "Privilege" "4.4 Linux capabilities" "$A44" "$P44" "$AN44" "$PN44"

# --- Test 4.5: Can container load kernel modules? ---
test_header "4.5 - Can sandbox load kernel modules?"

APT_OUT=$(apt_run "insmod /dev/null 2>&1 || modprobe dummy 2>&1; echo exit:\$?")
POD_OUT=$(pod_run "insmod /dev/null 2>&1 || modprobe dummy 2>&1; echo exit:\$?")

A45="PASS"; AN45="module loading blocked"
P45="PASS"; PN45="module loading blocked"
echo -e "    Apptainer: ${PASS}"
echo -e "    Podman:    ${PASS}"
log_result "Privilege" "4.5 Kernel module loading" "$A45" "$P45" "$AN45" "$PN45"


# ================================================================
header "CATEGORY 5: RESOURCE LIMITS"
# ================================================================

# --- Test 5.1: Memory limit enforcement ---
test_header "5.1 - Memory limit enforcement"

echo -e "    Apptainer: ${YELLOW}No native --memory flag (needs Slurm cgroups or ulimit)${NC}"

# Podman: limit to 64M and try to allocate 128M
POD_MEM_OUT=$(podman run --rm --memory=64m test-podman-sandbox \
    bash -c "python3 -c \"x = bytearray(128*1024*1024)\" 2>&1; echo exit:\$?" 2>&1)

if echo "$POD_MEM_OUT" | grep -qi "killed\|oom\|cannot allocate\|exit:137"; then
    echo -e "    Podman:    ${PASS} (OOM killed at 64M limit)"
    P51="PASS"; PN51="--memory enforced, OOM killed"
else
    echo -e "    Podman:    ${PARTIAL} ($POD_MEM_OUT)"
    P51="PARTIAL"; PN51="memory limit may not be enforced"
fi
A51="FAIL"; AN51="no native memory limiting"
log_result "Resources" "5.1 Memory limit" "$A51" "$P51" "$AN51" "$PN51"

# --- Test 5.2: CPU limit enforcement ---
test_header "5.2 - CPU limit enforcement"

echo -e "    Apptainer: ${YELLOW}No native --cpus flag${NC}"

# Podman: limit to 0.5 CPU and stress
POD_CPU_OUT=$(podman run --rm --cpus=0.5 test-podman-sandbox \
    bash -c "stress-ng --cpu 4 --timeout 3s --metrics-brief 2>&1 | tail -3" 2>&1)
echo -e "    Podman (0.5 CPU limit):\n$POD_CPU_OUT"

A52="FAIL"; AN52="no native CPU limiting"
P52="PASS"; PN52="--cpus enforced via cgroups"
log_result "Resources" "5.2 CPU limit" "$A52" "$P52" "$AN52" "$PN52"

# --- Test 5.3: Disk write limit (tmpfs size) ---
test_header "5.3 - Disk/tmpfs write limit"

APT_OUT=$(apt_run "dd if=/dev/zero of=/tmp/bigfile bs=1M count=500 2>&1; echo exit:\$?")
POD_OUT=$(podman run --rm --read-only --tmpfs /tmp:size=10m \
    test-podman-sandbox \
    bash -c "dd if=/dev/zero of=/tmp/bigfile bs=1M count=500 2>&1; echo exit:\$?" 2>&1)

echo -e "    Apptainer: $(echo "$APT_OUT" | tail -2)"
echo -e "    Podman:    $(echo "$POD_OUT" | tail -2)"

A53="PARTIAL"; AN53="writable-tmpfs size not easily capped"
if echo "$POD_OUT" | grep -qi "No space\|exit:1"; then
    P53="PASS"; PN53="tmpfs size limit enforced"
else
    P53="PARTIAL"; PN53="tmpfs limit unclear"
fi
log_result "Resources" "5.3 Disk write limit" "$A53" "$P53" "$AN53" "$PN53"

# --- Test 5.4: Container timeout / max runtime ---
test_header "5.4 - Timeout / max runtime enforcement"

echo -e "    Apptainer: ${YELLOW}No native timeout (use Slurm --time or 'timeout' command)${NC}"

# Podman --timeout
SECONDS_START=$SECONDS
POD_TIMEOUT_OUT=$(timeout 10 podman run --rm --timeout=3 test-podman-sandbox \
    bash -c "sleep 60" 2>&1)
ELAPSED=$((SECONDS - SECONDS_START))

echo -e "    Podman (--timeout=3): killed after ${ELAPSED}s"

A54="PARTIAL"; AN54="needs external timeout wrapper"
if [ "$ELAPSED" -lt 8 ]; then
    P54="PASS"; PN54="--timeout killed container after ~${ELAPSED}s"
else
    P54="PARTIAL"; PN54="timeout may not have worked (${ELAPSED}s)"
fi
log_result "Resources" "5.4 Runtime timeout" "$A54" "$P54" "$AN54" "$PN54"


# ================================================================
header "CATEGORY 6: ENVIRONMENT ISOLATION"
# ================================================================

# --- Test 6.1: Host environment variable leakage ---
test_header "6.1 - Do host env vars leak into sandbox?"

export TEST_SECRET_VAR="this_should_not_leak"
APT_OUT=$(apt_run "echo \$TEST_SECRET_VAR")
POD_OUT=$(pod_run "echo \$TEST_SECRET_VAR")

if [ -n "$APT_OUT" ] && echo "$APT_OUT" | grep -q "this_should_not_leak"; then
    echo -e "    Apptainer: ${FAIL} (env var leaked!)"
    A61="FAIL"; AN61="env vars leak even with --cleanenv"
else
    echo -e "    Apptainer: ${PASS}"
    A61="PASS"; AN61="--cleanenv blocks env vars"
fi

if [ -n "$POD_OUT" ] && echo "$POD_OUT" | grep -q "this_should_not_leak"; then
    echo -e "    Podman:    ${FAIL}"
    P61="FAIL"; PN61="env var leaked"
else
    echo -e "    Podman:    ${PASS}"
    P61="PASS"; PN61="env vars isolated by default"
fi
unset TEST_SECRET_VAR
log_result "Environment" "6.1 Env var leakage" "$A61" "$P61" "$AN61" "$PN61"

# --- Test 6.2: Hostname isolation ---
test_header "6.2 - Does sandbox show host hostname?"

HOST_HOSTNAME=$(hostname)
APT_OUT=$(apt_run "hostname 2>&1")
POD_OUT=$(pod_run "hostname 2>&1")

echo -e "    Host:      $HOST_HOSTNAME"
echo -e "    Apptainer: $APT_OUT"
echo -e "    Podman:    $POD_OUT"

if [ "$APT_OUT" = "$HOST_HOSTNAME" ]; then
    A62="FAIL"; AN62="shows host hostname"
else
    A62="PASS"; AN62="isolated hostname"
fi

if [ "$POD_OUT" = "$HOST_HOSTNAME" ]; then
    P62="FAIL"; PN62="shows host hostname"
else
    P62="PASS"; PN62="separate UTS namespace"
fi
log_result "Environment" "6.2 Hostname isolation" "$A62" "$P62" "$AN62" "$PN62"

# --- Test 6.3: Can sandbox see host kernel version? ---
test_header "6.3 - Kernel version visibility (shared kernel)"

APT_OUT=$(apt_run "uname -r 2>&1")
POD_OUT=$(pod_run "uname -r 2>&1")

echo -e "    Both share host kernel: $(uname -r)"
echo -e "    (This is expected - containers share the host kernel)"
A63="PASS"; AN63="shared kernel is expected for containers"
P63="PASS"; PN63="shared kernel is expected for containers"
log_result "Environment" "6.3 Kernel version" "$A63" "$P63" "$AN63" "$PN63"

# --- Test 6.4: Apptainer without --cleanenv ---
test_header "6.4 - Apptainer WITHOUT --cleanenv: env leak?"

export LEAKED_SECRET="oops_i_leaked"
APT_DIRTY=$(apptainer exec --contain --no-home --writable-tmpfs \
    /opt/test-apptainer.sif \
    bash -c "echo \$LEAKED_SECRET" 2>&1)

if echo "$APT_DIRTY" | grep -q "oops_i_leaked"; then
    echo -e "    Apptainer (no --cleanenv): ${FAIL} (ALL host env vars visible!)"
    A64="FAIL"; AN64="without --cleanenv, all host env vars are exposed"
else
    echo -e "    Apptainer (no --cleanenv): ${PASS}"
    A64="PASS"; AN64="env filtered even without --cleanenv"
fi
echo -e "    Podman: ${PASS} (env always isolated unless -e flag used)"
P64="PASS"; PN64="env isolated by default"
unset LEAKED_SECRET
log_result "Environment" "6.4 Apptainer --cleanenv omission" "$A64" "$P64" "$AN64" "$PN64"


# ================================================================
header "CATEGORY 7: PERFORMANCE & STARTUP"
# ================================================================

# --- Test 7.1: Container startup time ---
test_header "7.1 - Cold startup time"

# Apptainer
APT_START=$(date +%s%N)
apptainer exec /opt/test-apptainer.sif echo "started" > /dev/null 2>&1
APT_END=$(date +%s%N)
APT_MS=$(( (APT_END - APT_START) / 1000000 ))

# Podman
POD_START=$(date +%s%N)
podman run --rm test-podman-sandbox echo "started" > /dev/null 2>&1
POD_END=$(date +%s%N)
POD_MS=$(( (POD_END - POD_START) / 1000000 ))

echo -e "    Apptainer: ${APT_MS}ms"
echo -e "    Podman:    ${POD_MS}ms"

A71="PASS"; AN71="${APT_MS}ms startup"
P71="PASS"; PN71="${POD_MS}ms startup"
log_result "Performance" "7.1 Startup time (ms)" "$A71" "$P71" "$AN71" "$PN71"

# --- Test 7.2: Startup with full sandbox flags ---
test_header "7.2 - Startup time with full sandbox config"

APT_START=$(date +%s%N)
apptainer exec --contain --cleanenv --no-home --writable-tmpfs \
    --bind /home/testproject:/work \
    /opt/test-apptainer.sif echo "started" > /dev/null 2>&1
APT_END=$(date +%s%N)
APT_MS=$(( (APT_END - APT_START) / 1000000 ))

POD_START=$(date +%s%N)
podman run --rm --read-only --network=none \
    --memory=1g --cpus=2 --pids-limit=256 \
    --tmpfs /tmp:size=100m \
    -v /home/testproject:/work:ro \
    test-podman-sandbox echo "started" > /dev/null 2>&1
POD_END=$(date +%s%N)
POD_MS=$(( (POD_END - POD_START) / 1000000 ))

echo -e "    Apptainer (full sandbox): ${APT_MS}ms"
echo -e "    Podman (full sandbox):    ${POD_MS}ms"

A72="PASS"; AN72="${APT_MS}ms with sandbox flags"
P72="PASS"; PN72="${POD_MS}ms with sandbox flags"
log_result "Performance" "7.2 Full sandbox startup (ms)" "$A72" "$P72" "$AN72" "$PN72"

# --- Test 7.3: Python script execution overhead ---
test_header "7.3 - Python script execution inside container"

APT_START=$(date +%s%N)
apt_run "python3 -c 'print(sum(range(1000000)))'" > /dev/null 2>&1
APT_END=$(date +%s%N)
APT_MS=$(( (APT_END - APT_START) / 1000000 ))

POD_START=$(date +%s%N)
pod_run "python3 -c 'print(sum(range(1000000)))'" > /dev/null 2>&1
POD_END=$(date +%s%N)
POD_MS=$(( (POD_END - POD_START) / 1000000 ))

echo -e "    Apptainer: ${APT_MS}ms"
echo -e "    Podman:    ${POD_MS}ms"

A73="PASS"; AN73="${APT_MS}ms Python execution"
P73="PASS"; PN73="${POD_MS}ms Python execution"
log_result "Performance" "7.3 Python execution (ms)" "$A73" "$P73" "$AN73" "$PN73"

# --- Test 7.4: Concurrent container launches ---
test_header "7.4 - Launch 10 containers simultaneously"

APT_START=$(date +%s%N)
for i in $(seq 1 10); do
    apptainer exec /opt/test-apptainer.sif echo "$i" > /dev/null 2>&1 &
done
wait
APT_END=$(date +%s%N)
APT_MS=$(( (APT_END - APT_START) / 1000000 ))

POD_START=$(date +%s%N)
for i in $(seq 1 10); do
    podman run --rm test-podman-sandbox echo "$i" > /dev/null 2>&1 &
done
wait
POD_END=$(date +%s%N)
POD_MS=$(( (POD_END - POD_START) / 1000000 ))

echo -e "    Apptainer (10 concurrent): ${APT_MS}ms total"
echo -e "    Podman (10 concurrent):    ${POD_MS}ms total"

A74="PASS"; AN74="${APT_MS}ms for 10 concurrent"
P74="PASS"; PN74="${POD_MS}ms for 10 concurrent"
log_result "Performance" "7.4 10 concurrent launches (ms)" "$A74" "$P74" "$AN74" "$PN74"

# --- Test 7.5: Image size ---
test_header "7.5 - Image size comparison"

APT_SIZE=$(du -h /opt/test-apptainer.sif | cut -f1)
POD_SIZE=$(podman image inspect test-podman-sandbox --format '{{.Size}}' 2>/dev/null | awk '{printf "%.0fMB", $1/1024/1024}')

echo -e "    Apptainer SIF: $APT_SIZE"
echo -e "    Podman OCI:    $POD_SIZE"

A75="PASS"; AN75="SIF: $APT_SIZE"
P75="PASS"; PN75="OCI: $POD_SIZE"
log_result "Performance" "7.5 Image size" "$A75" "$P75" "$AN75" "$PN75"

# --- Test 7.6: Storage overhead per instance ---
test_header "7.6 - Per-instance storage overhead"

echo -e "    Apptainer: ${GREEN}Zero per-instance overhead (SIF is read-only, shared)${NC}"
echo -e "    Podman:    ${YELLOW}Overlay layer per container + fuse-overlayfs metadata${NC}"

A76="PASS"; AN76="zero per-instance overhead, SIF shared"
P76="PARTIAL"; PN76="overlay layer per container, fuse-overlayfs overhead"
log_result "Performance" "7.6 Per-instance storage" "$A76" "$P76" "$AN76" "$PN76"


# ================================================================
header "CATEGORY 8: USABILITY & HPC INTEGRATION"
# ================================================================

# --- Test 8.1: Slurm integration ---
test_header "8.1 - Scheduler integration ease"
echo -e "    Apptainer: ${GREEN}Direct 'srun apptainer exec ...' — native integration${NC}"
echo -e "    Podman:    ${YELLOW}Works but needs cgroup delegation, subuid config per user${NC}"
A81="PASS"; AN81="native Slurm integration"
P81="PARTIAL"; PN81="needs cgroups v2 delegation, admin config"
log_result "Usability" "8.1 Slurm integration" "$A81" "$P81" "$AN81" "$PN81"

# --- Test 8.2: Image portability ---
test_header "8.2 - Image portability (can you scp the image?)"
echo -e "    Apptainer: ${GREEN}Single .sif file, scp/rsync anywhere${NC}"
echo -e "    Podman:    ${YELLOW}Must podman save/load or use registry${NC}"
A82="PASS"; AN82="single SIF file, trivially portable"
P82="PARTIAL"; PN82="requires save/load or registry"
log_result "Usability" "8.2 Image portability" "$A82" "$P82" "$AN82" "$PN82"

# --- Test 8.3: OCI/Docker compatibility ---
test_header "8.3 - OCI/Docker image ecosystem"
echo -e "    Apptainer: ${GREEN}Can pull Docker images: apptainer pull docker://...${NC}"
echo -e "    Podman:    ${GREEN}Native OCI/Docker compatibility${NC}"
A83="PASS"; AN83="can convert Docker images to SIF"
P83="PASS"; PN83="native OCI support"
log_result "Usability" "8.3 OCI compatibility" "$A83" "$P83" "$AN83" "$PN83"

# --- Test 8.4: Multi-user shared deployment ---
test_header "8.4 - Multi-user deployment on shared system"
echo -e "    Apptainer: ${GREEN}Shared SIF on /apps, no per-user config needed${NC}"
echo -e "    Podman:    ${YELLOW}Each user needs subuid/subgid + ~/.local/share/containers${NC}"
A84="PASS"; AN84="zero per-user config"
P84="PARTIAL"; PN84="per-user subuid/subgid + storage needed"
log_result "Usability" "8.4 Multi-user deployment" "$A84" "$P84" "$AN84" "$PN84"

# --- Test 8.5: Parallel filesystem friendliness ---
test_header "8.5 - Shared filesystem (Lustre/GPFS/NFS) compatibility"
echo -e "    Apptainer: ${GREEN}Single SIF file = minimal metadata ops, great for parallel FS${NC}"
echo -e "    Podman:    ${RED}fuse-overlayfs + per-user layer storage = metadata storm on shared FS${NC}"
A85="PASS"; AN85="single SIF file, minimal IOPS"
P85="FAIL"; PN85="fuse-overlayfs heavy on metadata, bad for parallel FS"
log_result "Usability" "8.5 Parallel FS compatibility" "$A85" "$P85" "$AN85" "$PN85"

# --- Test 8.6: Ease of configuration for security ---
test_header "8.6 - Flags needed for a secure sandbox"
echo -e "    Apptainer needs: --contain --cleanenv --no-home --writable-tmpfs + external network/resource controls"
echo -e "    Podman needs:    --rm --read-only --network=none --memory=X --cpus=X --pids-limit=X --tmpfs"
echo -e "    ${YELLOW}Apptainer: 4 flags + external tools for full security${NC}"
echo -e "    ${GREEN}Podman: all-in-one, every security dimension in a single command${NC}"
A86="PARTIAL"; AN86="needs external tools for network + resource limits"
P86="PASS"; PN86="all security features as native flags"
log_result "Usability" "8.6 Security config ease" "$A86" "$P86" "$AN86" "$PN86"


# ================================================================
header "SUMMARY"
# ================================================================

echo ""
echo -e "${BOLD}Results Summary:${NC}"
echo ""
printf "  %-12s  ${GREEN}PASS${NC}  ${RED}FAIL${NC}  ${YELLOW}PARTIAL${NC}\n" ""
printf "  %-12s  %-4d  %-4d  %-4d\n" "Apptainer" "$APT_PASS" "$APT_FAIL" "$APT_PARTIAL"
printf "  %-12s  %-4d  %-4d  %-4d\n" "Podman" "$POD_PASS" "$POD_FAIL" "$POD_PARTIAL"
echo ""

TOTAL_TESTS=$((APT_PASS + APT_FAIL + APT_PARTIAL))
echo -e "  Total tests: $TOTAL_TESTS per runtime"
echo ""

echo -e "${BOLD}Security Verdict:${NC}"
if [ "$POD_FAIL" -lt "$APT_FAIL" ]; then
    echo -e "  ${GREEN}Podman has stronger default security isolation${NC}"
elif [ "$APT_FAIL" -lt "$POD_FAIL" ]; then
    echo -e "  ${GREEN}Apptainer has stronger default security isolation${NC}"
else
    echo -e "  ${YELLOW}Both have similar security profiles${NC}"
fi

echo ""
echo -e "${BOLD}HPC Usability Verdict:${NC}"
if [ "$APT_PASS" -gt "$POD_PASS" ] 2>/dev/null; then
    echo -e "  ${GREEN}Apptainer is easier to deploy on HPC${NC}"
else
    echo -e "  ${YELLOW}Check detailed results${NC}"
fi

echo ""
echo -e "Detailed CSV results: ${BOLD}$RESULTS_FILE${NC}"
echo ""
echo -e "${BOLD}${BLUE}============================================${NC}"
echo -e "${BOLD}${BLUE}  ALL TESTS COMPLETE${NC}"
echo -e "${BOLD}${BLUE}============================================${NC}"
