#!/bin/bash
# EKS Base Infrastructure Node User Data Template
# This template calls the EKS bootstrap script, then runs post-bootstrap configuration

set -o xtrace

# Call EKS bootstrap script with base node configuration (REQUIRED)
/etc/eks/bootstrap.sh ${cluster_name} \
  --kubelet-extra-args '--max-pods=110 --register-with-taints=CriticalAddonsOnly=true:NoSchedule'

# Run post-bootstrap configuration script
# Script is passed as a template variable from Terraform
${post_bootstrap_script}
