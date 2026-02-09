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

# Configure CPU frequency governor for performance (disable power saving)
# This ensures consistent CPU performance for predictable benchmark workloads
echo "Configuring CPU governor for maximum performance..."
for cpu_governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
	if [ -f "$cpu_governor" ]; then
		echo "performance" >"$cpu_governor"
	fi
done

# Make CPU governor settings persistent
cat >/etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > $gov 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cpu-performance.service
systemctl start cpu-performance.service

# Set GPU persistence mode for consistent performance
nvidia-smi -pm 1 || true

# Lock GPU clocks to maximum for consistent performance (optional, may increase power usage)
# Uncomment if you need absolute maximum GPU performance consistency
# nvidia-smi -lgc $(nvidia-smi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits | head -1) || true

# Test GPU
nvidia-smi || echo "WARNING: nvidia-smi failed"

echo "Post-bootstrap GPU configuration completed at $(date)"
echo "CPU governor: performance mode enabled for predictable performance"
echo "GPU persistence mode: enabled for consistent GPU performance"
