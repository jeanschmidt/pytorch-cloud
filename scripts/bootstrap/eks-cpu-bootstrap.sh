#!/usr/bin/env bash
# EKS CPU Node Bootstrap Script
# This script runs AFTER the EKS bootstrap process
# It is called from the Terraform launch template

set -euo pipefail

# The EKS bootstrap script must be called FIRST by the launch template
# This script contains post-bootstrap configuration only

# Configure Docker daemon
cat > /etc/docker/daemon.json <<'EOF'
{
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

# Install useful tools
yum install -y \
    htop \
    iotop \
    sysstat \
    vim \
    wget \
    curl \
    git \
    ccache

# Configure node for CI workloads
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Set up ccache directory
mkdir -p /var/cache/ccache
chmod 777 /var/cache/ccache

echo "Post-bootstrap configuration completed at $(date)"

