#!/usr/bin/env bash
# EKS GPU Node Bootstrap Script
# This script runs AFTER the EKS bootstrap process
# It is called from the Terraform launch template

set -euo pipefail

# The EKS bootstrap script must be called FIRST by the launch template
# This script contains post-bootstrap GPU configuration only

# Configure Docker daemon with NVIDIA runtime
cat > /etc/docker/daemon.json <<'EOF'
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "mtu": 1500
}
EOF

systemctl restart docker

# Install nvidia-docker2 if not present
if ! command -v nvidia-container-runtime &> /dev/null; then
    yum install -y nvidia-docker2
    systemctl restart docker
fi

# Install useful tools
yum install -y \
    htop \
    iotop \
    sysstat \
    vim \
    wget \
    curl \
    git \
    ccache \
    nvtop || true

# Configure node for CI workloads
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Set up ccache directory
mkdir -p /var/cache/ccache
chmod 777 /var/cache/ccache

# Set GPU persistence mode
nvidia-smi -pm 1 || true

# Test GPU
nvidia-smi || echo "WARNING: nvidia-smi failed"

echo "Post-bootstrap GPU configuration completed at $(date)"

