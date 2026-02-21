#!/bin/bash
# ============================================================
# setup-test-environment.sh
# Installs Apptainer + Podman, builds sandbox images,
# creates test fixtures on an Ubuntu 24.04 Oblivus VM
# ============================================================
set -euo pipefail

echo "=========================================="
echo "  Apptainer vs Podman Test Environment"
echo "=========================================="

# ----------------------------------------------------------
# 1. INSTALL APPTAINER
# ----------------------------------------------------------
echo ""
echo "[1/6] Installing Apptainer..."
sudo apt-get update -qq
sudo apt-get install -y -qq software-properties-common
sudo add-apt-repository -y ppa:apptainer/ppa
sudo apt-get update -qq
sudo apt-get install -y -qq apptainer
echo "  Apptainer version: $(apptainer --version)"

# ----------------------------------------------------------
# 2. INSTALL PODMAN (rootless)
# ----------------------------------------------------------
echo ""
echo "[2/6] Installing Podman..."
sudo apt-get install -y -qq podman slirp4netns fuse-overlayfs uidmap
echo "  Podman version: $(podman --version)"

# Configure rootless podman for current user
# subuid/subgid mapping
if ! grep -q "^$(whoami):" /etc/subuid 2>/dev/null; then
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami)
fi

# Ensure cgroups v2 delegation
if [ -d /sys/fs/cgroup/user.slice ]; then
    echo "  cgroups v2 detected"
else
    echo "  WARNING: cgroups v2 not fully available, some resource limit tests may fail"
fi

# ----------------------------------------------------------
# 3. CREATE TEST FIXTURES
# ----------------------------------------------------------
echo ""
echo "[3/6] Creating test fixtures..."

# Test project directory (what we'll mount into containers)
mkdir -p /home/testproject
cat > /home/testproject/README.md << 'HEREDOC'
# Test Project
This is the project directory that gets mounted into the sandbox.
HEREDOC

cat > /home/testproject/data.csv << 'HEREDOC'
name,score,department
Alice,92,Engineering
Bob,78,Marketing
Charlie,95,Engineering
Diana,64,Sales
Eve,88,Marketing
HEREDOC

cat > /home/testproject/analyze.py << 'HEREDOC'
#!/usr/bin/env python3
import csv, sys
with open('/work/data.csv') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
print(f"Records: {len(rows)}")
print(f"Avg score: {sum(int(r['score']) for r in rows)/len(rows):.1f}")
HEREDOC

# Sensitive files on the host (should NOT be visible from containers)
echo "HOST_SECRET=supersecretpassword123" > /root/.secret_env
echo "confidential host data" > /root/sensitive_file.txt
mkdir -p /etc/fake-secrets
echo "database_password=hunter2" > /etc/fake-secrets/db.conf

# A file outside the project dir (should be hidden)
mkdir -p /home/otheruser
echo "I belong to another user" > /home/otheruser/private.txt

# ----------------------------------------------------------
# 4. BUILD APPTAINER IMAGE
# ----------------------------------------------------------
echo ""
echo "[4/6] Building Apptainer sandbox image..."

cat > /tmp/apptainer-sandbox.def << 'DEFEOF'
Bootstrap: docker
From: ubuntu:24.04

%post
    apt-get update && apt-get install -y \
        curl git python3 python3-pip python3-venv \
        build-essential wget unzip jq iproute2 \
        procps net-tools dnsutils iputils-ping \
        stress-ng bc
    
    # Install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs

    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

%environment
    export PATH=/usr/local/bin:/usr/bin:/bin
    export HOME=/work

%runscript
    cd /work && exec "$@"
DEFEOF

apptainer build /opt/test-apptainer.sif /tmp/apptainer-sandbox.def

echo "  Image size: $(du -h /opt/test-apptainer.sif | cut -f1)"

# ----------------------------------------------------------
# 5. BUILD PODMAN IMAGE
# ----------------------------------------------------------
echo ""
echo "[5/6] Building Podman sandbox image..."

cat > /tmp/Containerfile << 'DOCKEOF'
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl git python3 python3-pip python3-venv \
    build-essential wget unzip jq iproute2 \
    procps net-tools dnsutils iputils-ping \
    stress-ng bc \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/bin:/usr/bin:/bin
WORKDIR /work
DOCKEOF

podman build -t test-podman-sandbox -f /tmp/Containerfile /tmp/

echo "  Image built successfully"

# ----------------------------------------------------------
# 6. VERIFY SETUP
# ----------------------------------------------------------
echo ""
echo "[6/6] Verifying setup..."
echo ""
echo "  Apptainer: $(apptainer --version)"
echo "  Podman:    $(podman --version)"
echo "  Apptainer image: /opt/test-apptainer.sif ($(du -h /opt/test-apptainer.sif | cut -f1))"
echo "  Podman image:    test-podman-sandbox"
echo "  Test project:    /home/testproject/"
echo ""
echo "=========================================="
echo "  Setup complete! Run test scripts next."
echo "=========================================="
