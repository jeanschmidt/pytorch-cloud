#!/usr/bin/env bash
# EKS GPU Node Bootstrap Script (AL2023)
# This script runs AFTER the EKS bootstrap process
# It is called from the Terraform launch template

set -euo pipefail

# The EKS bootstrap script must be called FIRST by the launch template
# This script contains post-bootstrap GPU configuration only

echo "Starting GPU node post-bootstrap at $(date)"
echo "Amazon Linux 2023 detected"

# AL2023 uses containerd with nvidia-container-runtime
# Configure containerd for NVIDIA runtime
if systemctl is-active --quiet containerd; then
    echo "Configuring containerd for NVIDIA runtime..."
    # The nvidia-container-runtime is pre-installed in AL2023 EKS GPU AMIs
    # Containerd is already configured to use it via /etc/containerd/config.toml
fi

# Install useful tools (AL2023 uses dnf)
dnf install -y \
	htop \
	iotop \
	sysstat \
	vim \
	wget \
	curl \
	git \
	ccache

# Try to install nvtop if available (may not be in default repos)
dnf install -y nvtop || echo "nvtop not available, skipping..."

# Configure node for CI workloads
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >>/etc/sysctl.conf

# Set up ccache directory
mkdir -p /var/cache/ccache
chmod 777 /var/cache/ccache

# Set GPU persistence mode
nvidia-smi -pm 1 || true

# Test GPU
nvidia-smi || echo "WARNING: nvidia-smi failed"

echo "Post-bootstrap GPU configuration completed at $(date)"
