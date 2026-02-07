#!/usr/bin/env bash
# EKS Base Infrastructure Node Bootstrap Script (AL2023)
# This script runs AFTER the EKS bootstrap process
# It is called from the Terraform launch template

set -euo pipefail

# The EKS bootstrap script must be called FIRST by the launch template
# This script contains post-bootstrap configuration only

echo "Starting base infrastructure node post-bootstrap at $(date)"
echo "Amazon Linux 2023 detected"

# AL2023 uses containerd by default (not Docker)
# Configure containerd if needed
if systemctl is-active --quiet containerd; then
    echo "Containerd is running"
    # Add any containerd-specific configuration here if needed
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

# Configure node for infrastructure workloads
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >>/etc/sysctl.conf

# Set up ccache directory
mkdir -p /var/cache/ccache
chmod 777 /var/cache/ccache

echo "Base infrastructure node post-bootstrap completed at $(date)"
echo "Node taint: CriticalAddonsOnly=true:NoSchedule"
echo "This node will only run system components with matching tolerations"
